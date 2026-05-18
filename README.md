# AI-Powered Tutoring App

> Bengali-first vernacular tutoring for JEE / NEET / WB Board aspirants  
> Built with SwiftUI · FastAPI · CrewAI · NVIDIA NIM · RAG

---

## What This Is

An iOS tutoring app targeting Tier-2/3 city students (Asansol, Durgapur, Bardhaman) who prepare for JEE, NEET, and WB Board exams in their native language. Students ask questions by text or voice in Bengali (or Hindi/Tamil/Telugu); a 4-agent AI crew answers using a JEE/NEET RAG corpus and generates personalised daily study plans overnight.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS App | Swift / SwiftUI / StoreKit 2 / Core Data |
| Backend | Python 3.11 / FastAPI / SQLAlchemy 2 / Alembic |
| AI Agents | CrewAI 4-agent crew |
| LLM | NVIDIA NIM — Sarvam-M (Indian languages) + Llama-3.3-70B (reasoning) |
| RAG | ChromaDB (local) + `nv-embedqa-e5-v5` embeddings |
| Speech | Sarvam Saaras v2 STT + Bulbul v2 TTS (22 Indian languages) |
| Database | PostgreSQL — Neon (cloud, serverless) |
| Cache | Upstash Redis (chat history, 24h TTL) |
| Deployment | Railway (API server, auto-deploy on push) · Neon (DB) |

---

## Repository Structure

```
AI-Tutoring-App/
├── backend/                  # Python FastAPI backend
│   ├── app/
│   │   ├── main.py           # FastAPI entrypoint + APScheduler
│   │   ├── config.py         # Pydantic Settings (reads .env)
│   │   ├── models/           # SQLAlchemy models
│   │   ├── routers/          # API routes (auth, ask, plan, progress, mock_tests)
│   │   ├── agents/           # CrewAI crew, agents, tasks, prompts
│   │   ├── tools/            # CrewAI tools (RAG, DB, SymPy, WhatsApp)
│   │   ├── rag/              # Ingest, embedder, retriever
│   │   ├── services/         # Redis client (Upstash)
│   │   └── scheduler.py      # Nightly crew at 02:00 IST
│   ├── alembic/              # DB migrations (asyncpg — no psycopg2 needed)
│   ├── tests/
│   ├── .env                  # NIM keys, Neon DB URL, Upstash Redis (gitignored)
│   ├── requirements.txt
│   └── Dockerfile
└── SmartTutor/               # Xcode / SwiftUI app
    └── SmartTutor/
        ├── Features/         # Onboarding, Study, Progress, MockTests, Dashboard…
        ├── Core/             # Networking, Persistence, Models, Logging, UI
        └── App/              # AppState, AppDelegate, AppConfig
```

---

## Getting Started

### Prerequisites

- Python 3.11+
- Node.js 20+ (only needed to regenerate the architecture `.docx`)
- Xcode 16+
- PostgreSQL running locally
- NVIDIA NIM API key — get one free at [build.nvidia.com](https://build.nvidia.com)

### Backend Setup

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Copy the dev env template and fill in your NIM key
cp .env.example .env.development
# Edit .env.development: set NVIDIA_API_KEY=nvapi-xxxx

cp .env.development .env
alembic upgrade head
uvicorn app.main:app --reload --port 8000
# → http://localhost:8000/health
```

### Ingest RAG Corpus

```bash
# Place JEE/NEET PDFs in backend/rag/corpus/ (gitignored — too large)
python -m app.rag.ingest --dir rag/corpus/
```

### Run Tests

```bash
pytest tests/ -v
```

### Run Nightly Crew Manually

```bash
python -c 'from app.scheduler import run_nightly_crew; import asyncio; asyncio.run(run_nightly_crew())'
```

---

## Environment Variables

Copy `.env.example` to `.env.development` (local) or `.env.production` (Railway).

| Variable | Description |
|----------|-------------|
| `NVIDIA_API_KEY` | NIM API key from [build.nvidia.com](https://build.nvidia.com) |
| `LLM_CHAT_MODEL` | `sarvamai/sarvam-m` (Indic) or `meta/llama-3.3-70b-instruct` (EN) |
| `DATABASE_URL` | `postgresql+asyncpg://user:pass@host/db?ssl=require` (Neon) |
| `UPSTASH_REDIS_URL` | Upstash Redis REST URL |
| `UPSTASH_REDIS_TOKEN` | Upstash Redis token |
| `SARVAM_API_KEY` | Sarvam AI key for STT + TTS |
| `ADMIN_SECRET` | Header value for `POST /admin/run-nightly-crew` |
| `JWT_SECRET` | HS256 signing secret for auth tokens |

---

## AI Agents

| Agent | Trigger | What it does |
|-------|---------|-------------|
| **Question Generator** | On-demand (student asks) | RAG search → Sarvam-M generates answer in student's language |
| **Diagnostic** | Nightly 2 AM | Reads last 24h quiz answers → maps weak topics |
| **Curriculum Planner** | After Diagnostic | SM-2 spaced repetition → writes tomorrow's study plan |
| **Progress Monitor** | Nightly 2 AM | Detects 3-day plateaus → sends WhatsApp alert |

---

## Multilingual Support

Language is a rendering preference — same RAG corpus and agents serve all languages.  
Supported: Bengali · Hindi · Tamil · Telugu · Marathi · English (more via Bhashini).

---

## Sprint Plan

24-week plan (12 × 2-week sprints) targeting App Store launch.  
Full details: [AI_Tutoring_App_Architecture_DevPlan.md](AI_Tutoring_App_Architecture_DevPlan.md)

| Sprints | Focus | Status |
|---------|-------|--------|
| 1–4 | Foundation, NIM, RAG, CrewAI agents, FastAPI + auth | ✅ Complete |
| 5–6 | iOS study screen, voice, progress charts, onboarding | ✅ Complete |
| Post-6 | SymPy verifier, vision OCR, LLM accuracy, chat history, Full Paper Mock Tests, Neon DB migration | ✅ Complete |
| 7 | Subscriptions (StoreKit 2), freemium gate | 🔲 Not Started |
| 8 | Offline packs download, content QA | 🔲 Not Started |
| 9–12 | Prod LLM switch, TestFlight, App Store launch, analytics | 🔲 Not Started |

---

## Cost Model

| Phase | Monthly (Rs) |
|-------|-------------|
| Development (NIM free) | ~500 |
| 100 users (prod) | ~12,000 |
| 500 users | ~44,000 |
| Revenue at 500 users | ~1,50,000 |

---

## Docs

- [Architecture & Dev Plan (Markdown)](AI_Tutoring_App_Architecture_DevPlan.md)
- Regenerate the Word doc: `node build_plan.js`

---

*Built with GitHub Copilot · NVIDIA NIM · CrewAI · SwiftUI · FastAPI*

