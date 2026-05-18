"""
Question extraction pipeline — PDF → structured MockTestQuestion rows

Supports two PDF formats found in rag/corpus/:

1. Mathongo chapter-wise (JEE Mains 2019)
   Filename pattern: cqb_{subject}_jee_main_{year}_{chapter}.pdf
   Structure:
     • Questions section: Q1 … Q2 … each with (1)(2)(3)(4) options + shift label
     • Answers section:   Q1 (answer_num) solution …  + shift label
   Each question is tagged to a shift (e.g. "10 Jan Morning") → paper_id.

2. NEET full-paper PDFs
   Filename contains "NEET {year}"
   Structure: numbered MCQ questions 1. … 2. … with (A)(B)(C)(D) options.
   Answer key section at the end.

Usage (from backend/ directory):
    python -m app.rag.extract_questions --dir rag/corpus/JEE_Mains_2019_Physics
    python -m app.rag.extract_questions --dir rag/corpus/NEET --exam NEET
    python -m app.rag.extract_questions --dir rag/corpus/ --dry-run
    python -m app.rag.extract_questions --dir rag/corpus/ --reset   # wipe + re-import
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import re
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

from pypdf import PdfReader
from sqlalchemy import delete, select, text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.config import get_settings
from app.logging_config import configure_logging
from app.models.mock_test import MockTestQuestion

log = logging.getLogger(__name__)

# ── JEE 2019 shift → paper_id mapping ────────────────────────────────
_JEE_SHIFT_MAP: dict[str, str] = {
    "9 jan morning":   "jee-2019-0109-am",
    "9 jan evening":   "jee-2019-0109-pm",
    "10 jan morning":  "jee-2019-0110-am",
    "10 jan evening":  "jee-2019-0110-pm",
    "11 jan morning":  "jee-2019-0111-am",
    "11 jan evening":  "jee-2019-0111-pm",
    "12 jan morning":  "jee-2019-0112-am",
    "12 jan evening":  "jee-2019-0112-pm",
    "8 april morning":  "jee-2019-0408-am",
    "8 april evening":  "jee-2019-0408-pm",
    "9 april morning":  "jee-2019-0409-am",
    "9 april evening":  "jee-2019-0409-pm",
    "10 april morning": "jee-2019-0410-am",
    "10 april evening": "jee-2019-0410-pm",
    "12 april morning": "jee-2019-0412-am",
    "12 april evening": "jee-2019-0412-pm",
}

# NEET year → paper_id (full paper, all subjects)
_NEET_YEAR_MAP: dict[int, str] = {
    2016: "neet-2016",
    2018: "neet-2018",
    2019: "neet-2019",
    2020: "neet-2020",
    2021: "neet-2021",
    2022: "neet-2022",
    2023: "neet-2023",
    2025: "neet-2025",
}

# Subject normalisation for Mathongo filenames
_SUBJECT_MAP = {
    "physics":     "physics",
    "chemistry":   "chemistry",
    "math":        "mathematics",
    "maths":       "mathematics",
    "mathematics": "mathematics",
    "biology":     "biology",
    "botany":      "biology",
    "zoology":     "biology",
}


# ── PDF text extraction ───────────────────────────────────────────────

def _pdf_text(pdf_path: Path) -> str:
    """Extract all text from a PDF as a single string."""
    try:
        reader = PdfReader(str(pdf_path))
    except Exception:
        log.error("Cannot open %s", pdf_path.name, exc_info=True)
        return ""
    parts: list[str] = []
    for i, page in enumerate(reader.pages, 1):
        try:
            t = page.extract_text() or ""
        except Exception:
            log.warning("Page %d extract failed in %s", i, pdf_path.name)
            continue
        parts.append(t)
    return "\n".join(parts)


def _split_questions_answers(text: str) -> tuple[str, str]:
    """
    Split PDF text into (questions_block, answers_block).
    Looks for common Mathongo section headers.
    """
    patterns = [
        r"[-–—]\s*Answers?\s*\n",
        r"\n\s*Answers?\s+Key\b",
        r"\n\s*ANSWERS?\s*\n",
        r"\bChapter\s+wise\s+Question\s+Bank\b.*?\bAnswers?\b",
    ]
    for pat in patterns:
        m = re.search(pat, text, re.IGNORECASE | re.DOTALL)
        if m:
            return text[: m.start()], text[m.start():]
    # Fallback: if no divider found treat entire text as questions (no solutions)
    return text, ""


# ── Mathongo format parsing ───────────────────────────────────────────

# Matches shift labels printed after each question/answer in Mathongo PDFs
# e.g. "10 Jan Morning", "8 April Evening", "12 April Morning"
_SHIFT_RE = re.compile(
    r"\b(\d{1,2})\s+(Jan|January|April)\s+(Morning|Evening)\b",
    re.IGNORECASE,
)

# Question block: starts with Q followed by digits on its own line/token
_Q_BLOCK_RE = re.compile(
    r"(?:^|\n)\s*(Q\s*(\d+))\s*\n(.*?)(?=\n\s*Q\s*\d+\s*\n|\Z)",
    re.DOTALL | re.IGNORECASE,
)

# Options line: (1) text (2) text  OR  (1) text\n(2) text
_OPTIONS_RE = re.compile(
    r"\(\s*([1-4])\s*\)\s*(.*?)(?=\s*\(\s*[1-4]\s*\)|\n\s*\n|\Z)",
    re.DOTALL,
)

# Answer block: Q<n> opening line then (digit) solution
_ANS_BLOCK_RE = re.compile(
    r"(?:^|\n)\s*Q\s*(\d+)\s*\n(.*?)(?=\n\s*Q\s*\d+\s*\n|\Z)",
    re.DOTALL | re.IGNORECASE,
)

_ANS_OPTION_RE = re.compile(r"^\s*\(\s*([1-4])\s*\)", re.MULTILINE)


def _normalise_shift(raw: str) -> str:
    """Normalise a raw shift string to the key used in _JEE_SHIFT_MAP."""
    return raw.strip().lower().replace("january", "jan")


def _parse_mathongo(text: str, subject: str, topic: str, year: int, source_file: str) -> list[MockTestQuestion]:
    """
    Parse a Mathongo chapter-wise PDF text into MockTestQuestion objects.
    Returns a list (may be empty if parsing yields nothing useful).
    """
    q_text, a_text = _split_questions_answers(text)

    # --- Build answer map: question_number → (correct_option, solution_text) ---
    answer_map: dict[int, tuple[str, str]] = {}
    for m in _ANS_BLOCK_RE.finditer(a_text):
        q_num = int(m.group(1))
        block = m.group(2)
        opt_m = _ANS_OPTION_RE.search(block)
        if opt_m:
            correct = opt_m.group(1)
            solution = block[opt_m.end():].strip()
            # Remove trailing shift label from solution
            solution = _SHIFT_RE.sub("", solution).strip()
            answer_map[q_num] = (correct, solution)

    # --- Parse question blocks ---
    questions: list[MockTestQuestion] = []
    # Track question numbers per paper_id to assign sequential position
    paper_q_counter: dict[str, int] = {}

    for m in _Q_BLOCK_RE.finditer(q_text):
        q_num = int(m.group(2))
        block = m.group(3)

        # Extract shift label
        shift_m = _SHIFT_RE.search(block)
        if shift_m:
            raw_shift = shift_m.group(0)
            paper_id = _JEE_SHIFT_MAP.get(_normalise_shift(raw_shift))
            # Remove shift label from block text
            block_clean = block[: shift_m.start()] + block[shift_m.end():]
        else:
            paper_id = None
            block_clean = block

        if not paper_id:
            log.debug("No shift label for Q%d in %s — skipping", q_num, source_file)
            continue

        # Extract options
        options_raw: dict[str, str] = {}
        for opt_m in _OPTIONS_RE.finditer(block_clean):
            opt_num = opt_m.group(1)
            opt_text = opt_m.group(2).strip()
            # Clean up internal whitespace/newlines in option text
            opt_text = re.sub(r"\s+", " ", opt_text)
            options_raw[opt_num] = opt_text

        # Question text = block before first option
        first_opt = _OPTIONS_RE.search(block_clean)
        q_text_raw = block_clean[: first_opt.start()].strip() if first_opt else block_clean.strip()
        q_text_raw = re.sub(r"\s+", " ", q_text_raw)

        if not q_text_raw:
            log.debug("Empty question text for Q%d in %s — skipping", q_num, source_file)
            continue

        # Answer + solution
        correct_ans, solution = answer_map.get(q_num, ("", ""))
        if not correct_ans:
            log.debug("No answer for Q%d in %s", q_num, source_file)

        # Sequential position within this paper_id
        paper_q_counter[paper_id] = paper_q_counter.get(paper_id, 0) + 1
        position = paper_q_counter[paper_id]

        # Detect if question likely references a diagram (heuristic)
        has_image = bool(re.search(r"\bfigure\b|\bdiagram\b|\bshown\b", q_text_raw, re.IGNORECASE))

        questions.append(
            MockTestQuestion(
                id=uuid.uuid4(),
                paper_id=paper_id,
                exam_type="JEE",
                year=year,
                subject=subject,
                topic=topic,
                question_number=position,
                question_text=q_text_raw,
                options=[options_raw.get(str(i), "") for i in range(1, 5)] if options_raw else None,
                question_type="MCQ" if options_raw else "integer",
                correct_answer=correct_ans or "0",
                solution_text=solution or None,
                has_image=has_image,
                source_file=source_file,
                created_at=datetime.now(timezone.utc),
            )
        )

    return questions


# ── NEET full-paper parsing ───────────────────────────────────────────

# NEET question: starts with a number followed by a dot/period
_NEET_Q_RE = re.compile(
    r"(?:^|\n)\s*(\d{1,3})\s*[.)]\s+(.*?)(?=\n\s*\d{1,3}\s*[.)]\s|\Z)",
    re.DOTALL,
)

# NEET options: (A) ... (B) ... (C) ... (D) ...
_NEET_OPT_RE = re.compile(
    r"\(\s*([A-D])\s*\)\s*(.*?)(?=\s*\(\s*[A-D]\s*\)|\n\s*\n|\Z)",
    re.DOTALL,
)

# NEET answer key: "1. (A)" or "1 A" or "1. A"
_NEET_ANS_KEY_RE = re.compile(
    r"(?:^|\n)\s*(\d{1,3})\s*[.)]\s*\(?\s*([A-Da-d])\s*\)?",
    re.MULTILINE,
)

_NEET_OPT_LETTER = {"A": "1", "B": "2", "C": "3", "D": "4",
                    "a": "1", "b": "2", "c": "3", "d": "4"}

# Rough subject boundaries in NEET (questions 1-45 Physics, 46-90 Chemistry, 91-180 Biology)
def _neet_subject(q_num: int) -> str:
    if q_num <= 45:
        return "physics"
    if q_num <= 90:
        return "chemistry"
    return "biology"


def _parse_neet(text: str, paper_id: str, year: int, source_file: str) -> list[MockTestQuestion]:
    """Parse a NEET full-paper PDF into MockTestQuestion objects."""
    # Split off answer key section
    ans_split = re.search(r"\bAnswer\s+Key\b|\bAnswers?\s*:\s*\n", text, re.IGNORECASE)
    if ans_split:
        q_text = text[: ans_split.start()]
        a_text = text[ans_split.start():]
    else:
        q_text, a_text = text, ""

    # Build answer map
    answer_map: dict[int, str] = {}
    for m in _NEET_ANS_KEY_RE.finditer(a_text):
        answer_map[int(m.group(1))] = _NEET_OPT_LETTER.get(m.group(2), m.group(2))

    questions: list[MockTestQuestion] = []
    for m in _NEET_Q_RE.finditer(q_text):
        q_num = int(m.group(1))
        if q_num > 180:
            continue
        block = m.group(2)

        opts: dict[str, str] = {}
        for opt_m in _NEET_OPT_RE.finditer(block):
            letter = opt_m.group(1).upper()
            opts[_NEET_OPT_LETTER[letter]] = re.sub(r"\s+", " ", opt_m.group(2).strip())

        first_opt = _NEET_OPT_RE.search(block)
        q_text_raw = block[: first_opt.start()].strip() if first_opt else block.strip()
        q_text_raw = re.sub(r"\s+", " ", q_text_raw)
        if not q_text_raw:
            continue

        correct = answer_map.get(q_num, "")
        subject = _neet_subject(q_num)
        has_image = bool(re.search(r"\bfigure\b|\bdiagram\b|\bshown\b", q_text_raw, re.IGNORECASE))

        questions.append(
            MockTestQuestion(
                id=uuid.uuid4(),
                paper_id=paper_id,
                exam_type="NEET",
                year=year,
                subject=subject,
                topic=None,
                question_number=q_num,
                question_text=q_text_raw,
                options=[opts.get(str(i), "") for i in range(1, 5)] if opts else None,
                question_type="MCQ",
                correct_answer=correct or "0",
                solution_text=None,
                has_image=has_image,
                source_file=source_file,
                created_at=datetime.now(timezone.utc),
            )
        )
    return questions


# ── File routing ──────────────────────────────────────────────────────

def _infer_from_mathongo_filename(pdf_path: Path) -> tuple[str, str, int] | None:
    """
    Returns (subject, topic, year) for a Mathongo filename or None if not recognised.
    Pattern: cqb_{subject}_jee_main_{year}_{chapter}.pdf
    """
    stem = pdf_path.stem.lower()
    # Strip duplicate-file suffixes like " (1)", " (2)"
    stem = re.sub(r"\s*\(\d+\)\s*$", "", stem).strip()

    m = re.match(
        r"cqb_(physics|chemistry|math|maths|mathematics)_jee_main_(\d{4})_(.+)",
        stem,
    )
    if not m:
        return None
    raw_subj, year_str, chapter = m.group(1), m.group(2), m.group(3)
    subject = _SUBJECT_MAP.get(raw_subj, raw_subj)
    topic = chapter.replace("_", " ").title()
    return subject, topic, int(year_str)


def _infer_neet_year(pdf_path: Path) -> int | None:
    m = re.search(r"NEET\s+(\d{4})", pdf_path.name, re.IGNORECASE)
    return int(m.group(1)) if m else None


def process_pdf(pdf_path: Path, dry_run: bool = False) -> list[MockTestQuestion]:
    """
    Determine PDF type, parse, and return extracted question objects.
    Returns [] if the file is not a recognised question-bank PDF.
    """
    name_lower = pdf_path.name.lower()

    # --- Mathongo JEE chapter-wise ---
    meta = _infer_from_mathongo_filename(pdf_path)
    if meta:
        subject, topic, year = meta
        log.info("Mathongo  %s  subject=%s  topic=%s  year=%d", pdf_path.name, subject, topic, year)
        text = _pdf_text(pdf_path)
        qs = _parse_mathongo(text, subject, topic, year, pdf_path.name)
        log.info("  → %d questions extracted", len(qs))
        return qs if not dry_run else []

    # --- NEET full paper ---
    if "neet" in name_lower:
        year = _infer_neet_year(pdf_path)
        if not year:
            log.warning("Cannot infer NEET year from %s — skipping", pdf_path.name)
            return []
        paper_id = _NEET_YEAR_MAP.get(year)
        if not paper_id:
            log.warning("No paper_id mapping for NEET %d — skipping", year)
            return []
        # Skip answer-key-only or analysis PDFs (they don't have question text)
        if re.search(r"analysis|answer\s*key|chapter.?wise", name_lower):
            log.info("Skipping analysis/answer-key file %s", pdf_path.name)
            return []
        log.info("NEET  %s  year=%d  paper_id=%s", pdf_path.name, year, paper_id)
        text = _pdf_text(pdf_path)
        qs = _parse_neet(text, paper_id, year, pdf_path.name)
        log.info("  → %d questions extracted", len(qs))
        return qs if not dry_run else []

    log.debug("Skipping unrecognised file: %s", pdf_path.name)
    return []


# ── Database persistence ──────────────────────────────────────────────

async def _save_questions(
    questions: list[MockTestQuestion],
    session: AsyncSession,
    reset_paper_ids: set[str],
) -> int:
    """
    Upsert questions into DB.  Papers in reset_paper_ids are wiped first.
    Returns number of rows inserted.
    """
    if not questions:
        return 0

    # Wipe papers we're about to re-import
    for pid in reset_paper_ids:
        await session.execute(
            delete(MockTestQuestion).where(MockTestQuestion.paper_id == pid)
        )

    # Insert (skip duplicates via unique constraint — attempt plain insert)
    inserted = 0
    for q in questions:
        # Check if already exists
        exists = await session.scalar(
            select(MockTestQuestion.id).where(
                MockTestQuestion.paper_id == q.paper_id,
                MockTestQuestion.subject == q.subject,
                MockTestQuestion.question_number == q.question_number,
            )
        )
        if exists is None:
            session.add(q)
            inserted += 1
    await session.commit()
    return inserted


# ── CLI entry point ───────────────────────────────────────────────────

async def _main(args: argparse.Namespace) -> None:
    configure_logging()
    settings = get_settings()

    engine = create_async_engine(settings.DATABASE_URL, echo=False)
    AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    root = Path(args.dir)
    if not root.exists():
        log.error("Directory not found: %s", root)
        sys.exit(1)

    pdf_files = sorted(root.rglob("*.pdf"))
    log.info("Found %d PDF files under %s", len(pdf_files), root)

    total_extracted = 0
    total_saved = 0
    all_paper_ids: set[str] = set()
    all_questions: list[MockTestQuestion] = []

    for pdf_path in pdf_files:
        qs = process_pdf(pdf_path, dry_run=args.dry_run)
        total_extracted += len(qs)
        all_questions.extend(qs)
        for q in qs:
            all_paper_ids.add(q.paper_id)

    log.info("Total questions extracted: %d  (papers: %s)", total_extracted, sorted(all_paper_ids))

    if args.dry_run:
        log.info("Dry-run mode — no DB writes")
        return

    reset_ids = all_paper_ids if args.reset else set()

    async with AsyncSessionLocal() as session:
        total_saved = await _save_questions(all_questions, session, reset_ids)

    log.info("Saved %d new questions to DB  (skipped %d duplicates)",
             total_saved, total_extracted - total_saved)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract questions from JEE/NEET PDFs into mock_test_questions table"
    )
    parser.add_argument("--dir", required=True, help="Root directory to scan for PDFs")
    parser.add_argument("--dry-run", action="store_true", help="Parse only, do not write to DB")
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Delete existing rows for all affected paper_ids before re-inserting",
    )
    args = parser.parse_args()
    asyncio.run(_main(args))


if __name__ == "__main__":
    main()
