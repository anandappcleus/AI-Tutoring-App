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
| Dev LLM | NVIDIA NIM — Sarvam-M (Indian languages) + Qwen3-235B (reasoning) |
| Prod LLM | GPT-4o mini / Claude Haiku (swap via `.env` only) |
| RAG | Chroma (dev) / Pinecone (prod) + `nv-embedqa-e5-v5` embeddings |
| Speech | Bhashini API (STT + TTS, 22 Indian languages) |
| Database | PostgreSQL |
| Deployment | Railway / Render |

---

## Repository Structure

```
AI-Tutoring-App/
├── backend/                  # Python FastAPI backend
│   ├── app/
│   │   ├── main.py           # FastAPI entrypoint + APScheduler
│   │   ├── config.py         # Pydantic Settings (reads .env)
│   │   ├── models/           # SQLAlchemy models
│   │   ├── routers/          # API routes (auth, ask, plan, progress)
│   │   ├── agents/           # CrewAI crew, agents, tasks, prompts
│   │   ├── tools/            # CrewAI tools (RAG, DB, WhatsApp)
│   │   ├── rag/              # Ingest, embedder, retriever
│   │   └── scheduler.py      # Nightly crew at 02:00 IST
│   ├── alembic/              # DB migrations
│   ├── tests/
│   ├── .env.development      # NIM keys, Chroma, local DB (gitignored)
│   ├── .env.production       # OpenAI keys, Pinecone, Railway DB (gitignored)
│   ├── requirements.txt
│   └── Dockerfile
└── ios/                      # Xcode / SwiftUI app
    └── TutorApp/
        ├── Features/         # Onboarding, Study, Progress, Subscription
        ├── Core/             # Networking, Persistence, Models
        └── Resources/        # Localizable.strings (en / bn / hi)
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

| Variable | Dev (NIM) | Prod (OpenAI) |
|----------|-----------|---------------|
| `LLM_BASE_URL` | `https://integrate.api.nvidia.com/v1` | `https://api.openai.com/v1` |
| `LLM_API_KEY` | `nvapi-xxxx` | `sk-xxxx` |
| `LLM_CHAT_MODEL` | `ai21labs/sarvam-m` | `gpt-4o-mini` |
| `LLM_AGENT_MODEL` | `qwen/qwen3-235b-a22b` | `gpt-4o-mini` |
| `EMBED_MODEL` | `nvidia/nv-embedqa-e5-v5` | `text-embedding-3-small` |
| `VECTOR_DB` | `chroma` | `pinecone` |
| `DATABASE_URL` | `postgresql://localhost/tutordb` | `postgresql://railway.app/tutordb` |

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

| Sprints | Focus |
|---------|-------|
| 1-2 | Foundation, NIM integration, RAG pipeline |
| 3-4 | CrewAI agents, FastAPI routes + auth |
| 5-6 | iOS study screen, voice input, progress charts |
| 7-8 | Subscriptions (StoreKit 2), offline packs, content QA |
| 9 | Production LLM switch, Railway deploy, TestFlight |
| 10-12 | Hindi support, App Store launch, analytics |

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

