# SmartTutor — Sprint Progress Tracker

*Last updated: 14 May 2026*

---

## Sprint Status Overview

| Sprint | Theme | Status | Weeks |
|--------|-------|--------|-------|
| Sprint 1 | Foundation & NIM Integration | ✅ Complete | 1–2 |
| Sprint 2 | RAG Pipeline | ✅ Complete | 3–4 |
| Sprint 3 | CrewAI Agents | ✅ Complete | 5–6 |
| Sprint 4 | FastAPI Routes + Auth | ✅ Complete | 7–8 |
| Sprint 5 | iOS Core — Study Screen | ✅ Complete | 9–10 |
| Sprint 6 | iOS — Voice, Progress, Onboarding | � In Progress | 11–12 |
| Sprint 7 | Subscription + Freemium | 🔲 Not Started | 13–14 |
| Sprint 8 | Offline Packs + Content QA | 🔲 Not Started | 15–16 |
| Sprint 9 | Production LLM Switch + Deployment | 🔲 Not Started | 17–18 |
| Sprint 10 | Hindi Support + B2B Admin Panel | 🔲 Not Started | 19–20 |
| Sprint 11 | App Store Submission + Launch | 🔲 Not Started | 21–22 |
| Sprint 12 | Analytics, Crash Reporting, Retention | 🔲 Not Started | 23–24 |

---

## Sprint 1 — Foundation & NIM Integration ✅ Complete

**Goal:** NVIDIA NIM working, FastAPI skeleton up, iOS project created, Copilot configured

| # | Task | File | Status |
|---|------|------|--------|
| 1 | Monorepo structure, .gitignore, .env files | Root / `backend/.env.example` | ✅ Done |
| 2 | Python venv + `requirements.txt` | `backend/requirements.txt` | ✅ Done |
| 3 | `config.py` — Pydantic Settings reading .env | `backend/app/config.py` | ✅ Done |
| 4 | Test NVIDIA NIM — Bengali answer from Sarvam-M | `backend/scratch/test_nim.py` | ✅ Done |
| 5 | Test Qwen3 tool calling on NIM | `backend/scratch/test_qwen.py` | ✅ Done |
| 6 | FastAPI skeleton, health check route, middleware | `backend/app/main.py` | ✅ Done |
| 7 | SQLAlchemy models: Student, QuizAnswer, StudyPlan | `backend/app/models/student.py` + `progress.py` | ✅ Done |
| 8 | Alembic init + first migration | `backend/alembic/versions/20260512_*.py` | ✅ Done |
| 9 | Xcode project created (SmartTutor) | `SmartTutor/SmartTutor.xcodeproj` | ✅ Done |
| 10 | `AppConfig.swift` — dev/prod base URL switching | `SmartTutor/SmartTutor/App/AppConfig.swift` | ✅ Done |

### iOS Screens — Designed Ahead of Schedule

> The following screens were designed during Sprint 1, ahead of their planned sprint. They will be wired up with real data in their respective sprints.

| File | Planned Sprint | Status |
|------|---------------|--------|
| `Features/Onboarding/OnboardingView.swift` | Sprint 6 | ✅ UI designed |
| `Features/Dashboard/DashboardView.swift` | Sprint 5 | ✅ UI designed |
| `Features/Study/StudyView.swift` | Sprint 5 | ✅ UI designed |
| `Features/Progress/LearnerProgressView.swift` | Sprint 6 | ✅ UI designed |
| `Features/Parent/ParentDashboardView.swift` | Sprint 6 | ✅ UI designed |
| `Features/Paywall/PaywallView.swift` | Sprint 7 | ✅ UI designed |
| `Features/OfflinePacks/OfflinePacksView.swift` | Sprint 8 | ✅ UI designed |
| `Features/Settings/SettingsView.swift` | Sprint 6 | ✅ UI designed |
| `Core/Networking/APIClient.swift` | Sprint 5 | ✅ Done |
| `Core/Networking/Endpoints.swift` | Sprint 5 | ✅ Done |
| `Core/Models/StudentProfile.swift` | Sprint 5 | ✅ Done |

---

## Sprint 2 — RAG Pipeline ✅ Complete

**Goal:** JEE/NEET PDFs ingested into Chroma, RAG search returning relevant chunks

| # | Task | File | Status |
|---|------|------|--------|
| 1 | Download JEE Mains papers (2015–2024) + WBCHSE PDFs | `backend/rag/corpus/` | ⏳ Manual step |
| 2 | PDF ingestion: chunk into 512-token passages, 50-token overlap | `backend/app/rag/ingest.py` | ✅ Done |
| 3 | Embedder wrapper — NIM `nv-embedqa-e5-v5` | `backend/app/rag/embedder.py` | ✅ Done |
| 4 | Chroma collection setup + upsert all chunks | `backend/app/rag/ingest.py` | ✅ Done |
| 5 | `rag_search_tool` — similarity search, top-5 chunks | `backend/app/tools/rag_search_tool.py` | ✅ Done |
| 6 | Tests: RAG query returns relevant chunks | `backend/tests/test_rag.py` | ✅ Done |
| 7 | `prompts.py` — multilingual system prompts | `backend/app/agents/prompts.py` | ✅ Done |
| 8 | Manual test: Sarvam-M + RAG context → Bengali answer quality | `backend/scratch/` | ⏳ Manual step (deferred to Sprint 8 QA) |

---

## Sprint 3 — CrewAI Agents ✅ Complete

**Goal:** All 4 agents defined and running in sequence on test data

| # | Task | File | Status |
|---|------|------|--------|
| 1 | `quiz_history_tool` — last N quiz answers per student | `backend/app/tools/quiz_history_tool.py` | ✅ Done |
| 2 | `write_plan_tool` — upsert study plan | `backend/app/tools/write_plan_tool.py` | ✅ Done |
| 3 | `progress_read_tool` — detect 3-day plateau | `backend/app/tools/progress_read_tool.py` | ✅ Done |
| 4 | `whatsapp_send_tool` — WhatsApp Business API | `backend/app/tools/whatsapp_tool.py` | ✅ Done |
| 5 | `agents.py` — define all 4 agents with NIM LLMs | `backend/app/agents/agents.py` | ✅ Done |
| 6 | `tasks.py` — tasks with `expected_output` per agent | `backend/app/agents/tasks.py` | ✅ Done |
| 7 | `crew.py` — wire full crew, test with synthetic data | `backend/app/agents/crew.py` | ✅ Done |
| 8 | Tests: 40 unit tests pass (tool schemas, plateau logic, agent/task/crew wiring) | `backend/tests/test_agents.py` | ✅ Done |

---

## Sprint 4 — FastAPI Routes + Auth ✅ Complete

**Goal:** All API endpoints live, JWT auth working, iOS can call the backend

| # | Task | File | Status |
|---|------|------|--------|
| 1 | JWT auth: `POST /auth/token`, refresh, `get_current_user` | `backend/app/routers/auth.py` | ✅ Done |
| 2 | `POST /ask` — calls Question Generator agent | `backend/app/routers/ask.py` | ✅ Done |
| 3 | `GET /plan/:student_id` — today's study plan | `backend/app/routers/plan.py` | ✅ Done |
| 4 | `POST /sync-answers` — batch insert quiz answers | `backend/app/routers/progress.py` | ✅ Done |
| 5 | `GET /progress/:student_id` — weekly progress snapshot | `backend/app/routers/progress.py` | ✅ Done |
| 6 | APScheduler nightly crew job | `backend/app/scheduler.py` | ✅ Done |
| 7 | API tests with `httpx AsyncClient` | `backend/tests/test_api.py` | ✅ Done |
| 8 | Deploy to Railway (free tier) | `backend/Dockerfile`, `railway.toml` | ✅ Done — https://smarttutor-api-production.up.railway.app |

---

## Sprint 5 — iOS Core — Study Screen ✅ Complete

**Goal:** Student can ask a question in Bengali and receive an AI answer in the iOS app

> Note: `APIClient.swift`, `Endpoints.swift`, `StudentProfile.swift`, and `StudyView.swift` were already designed. Tasks below focus on wiring them to real backend + Core Data.

| # | Task | File | Status |
|---|------|------|--------|
| 1 | Wire `APIClient.swift` — JWT + token refresh | `Core/Networking/APIClient.swift` | ✅ Done — fully implemented |
| 2 | Wire `Endpoints.swift` — all endpoint definitions | `Core/Networking/Endpoints.swift` | ✅ Done — fully implemented |
| 3 | `StudentProfile.swift` — Keychain storage | `Core/Models/StudentProfile.swift` | ✅ Done — fully implemented |
| 4 | `StudyViewModel.swift` — calls `/ask`, publishes answer | `Features/Study/StudyViewModel.swift` | ✅ Done |
| 5 | Wire `StudyView.swift` to `StudyViewModel` | `Features/Study/StudyView.swift` | ✅ Done |
| 6 | Core Data stack + `QuizAnswerEntity` | `Core/Persistence/CoreDataStack.swift` | ✅ Done |
| 7 | `OfflineSyncManager.swift` — queue + sync on reconnect | `Core/Persistence/OfflineSyncManager.swift` | ✅ Done |
| 8 | `AppState.swift` + `SmartTutorApp` root wiring | `App/AppState.swift` | ✅ Done |
| + | Unit tests: `StudyViewModelTests`, `CoreDataStackTests`, `AppStateTests`, `OfflineSyncManagerTests` | `SmartTutorTests/` | ✅ Done |
| + | Railway production URL wired into `AppConfig.swift` | `App/AppConfig.swift` | ✅ Done |

---

## Sprint 6 — iOS: Voice, Progress, Onboarding � In Progress

**Goal:** Voice input, progress charts, language onboarding, parent dashboard

> Note: All view files are already designed. Tasks focus on wiring + Sarvam speech API (Saaras v2 STT, Bulbul v2 TTS) — same vendor as NIM LLM.

| # | Task | File | Status |
|---|------|------|--------|
| 1 | Wire `OnboardingView.swift` — `OnboardingViewModel` | `Features/Onboarding/OnboardingViewModel.swift` | ✅ Done |
| 2 | `VoiceInputView.swift` — AVFoundation microphone capture | `Features/Study/VoiceInputView.swift` | ✅ Done |
| 3 | `SarvamSpeechClient.swift` — Sarvam Saaras v2 STT + Bulbul v2 TTS | `Core/Networking/SarvamSpeechClient.swift` | ✅ Done |
| 4 | Wire `LearnerProgressView.swift` — Swift Charts + `ProgressViewModel` | `Features/Progress/LearnerProgressView.swift`, `Features/Progress/ProgressViewModel.swift` | ✅ Done |
| 5 | Wire `ParentDashboardView.swift` — `/progress` API | `Features/Parent/ParentDashboardView.swift`, `Features/Parent/ParentDashboardViewModel.swift` | ✅ Done |
| 6 | `Localizable.strings` — Bengali + Hindi UI labels | `Resources/bn.lproj/`, `Resources/hi.lproj/` | 🔲 |
| 7 | Push notification registration + APNs token upload | `SmartTutorApp.swift` | 🔲 |

---

## Sprint 7 — Subscription + Freemium 🔲 Not Started

**Goal:** StoreKit 2 subscriptions working, freemium gate at 10 questions/day

> Note: `PaywallView.swift` is already designed. Tasks focus on StoreKit wiring.

| # | Task | File | Status |
|---|------|------|--------|
| 1 | App Store Connect: create subscription products | App Store Connect | 🔲 |
| 2 | `StoreKitManager.swift` — purchase + restore + entitlements | `Features/Subscription/StoreKitManager.swift` | 🔲 |
| 3 | Wire `PaywallView.swift` to `StoreKitManager` | `Features/Paywall/PaywallView.swift` | 🔲 |
| 4 | Freemium gate in `StudyViewModel` — 10 q/day limit | `Features/Study/StudyViewModel.swift` | 🔲 |
| 5 | Backend: `POST /subscription/validate` — StoreKit JWS | `backend/app/routers/subscription.py` | 🔲 |
| 6 | Sandbox purchase flow test | — | 🔲 |

---

## Sprint 8 — Offline Packs + Content QA 🔲 Not Started

**Goal:** Offline question packs downloadable, Bengali/Hindi output QA reviewed

> Note: `OfflinePacksView.swift` is already designed.

| # | Task | File | Status |
|---|------|------|--------|
| 1 | `GET /packs` — list available topic packs | `backend/app/routers/packs.py` | 🔲 |
| 2 | `GET /packs/:id/download` — return question JSON | `backend/app/routers/packs.py` | 🔲 |
| 3 | Wire `OfflinePacksView.swift` — download + Core Data | `Features/OfflinePacks/OfflinePacksView.swift` | 🔲 |
| 4 | Core Data: `OfflinePack` + `OfflineQuestion` entities | `Core/Persistence/` | 🔲 |
| 5 | Content QA: 50 Bengali answers reviewed by native speaker | — | 🔲 |
| 6 | Prompt tuning based on QA feedback | `backend/app/agents/prompts.py` | 🔲 |

---

## Sprint 9 — Production LLM Switch + Deployment 🔲 Not Started

**Goal:** Swap NIM → OpenAI for prod, Railway live, iOS on TestFlight

| # | Task | File | Status |
|---|------|------|--------|
| 1 | `.env.production` with OpenAI keys | `backend/.env.production` | 🔲 |
| 2 | Migrate Chroma embeddings → Pinecone | `backend/rag/migrate_to_pinecone.py` | 🔲 |
| 3 | Railway: set prod env vars, deploy, verify health | `railway.toml` | 🔲 |
| 4 | Load test: 50 concurrent users with Locust | `backend/tests/locustfile.py` | 🔲 |
| 5 | Fix performance issues (caching, connection pool) | — | 🔲 |
| 6 | iOS: Archive + TestFlight upload | Xcode | 🔲 |
| 7 | TestFlight: 5 beta testers (Asansol students) | — | 🔲 |

---

## Sprints 10–12 — Polish, Launch, Growth 🔲 Not Started

| Sprint | Theme | Key Deliverables |
|--------|-------|-----------------|
| 10 | Hindi Support + B2B Admin | Hindi Localizable.strings, coaching institute admin panel |
| 11 | App Store Launch | App Review submission, marketing to school WhatsApp groups |
| 12 | Analytics + Retention | Mixpanel events, Sentry crash reporting, win-back push campaigns |

---

## iOS Screens Inventory

> All screens designed during Sprint 1. ✅ = UI shell exists · 🔲 = Not yet created

| Screen | File | UI Shell | Backend Wired | Sprint to Wire |
|--------|------|----------|---------------|---------------|
| Onboarding | `Features/Onboarding/OnboardingView.swift` | ✅ | 🔲 | 6 |
| Dashboard | `Features/Dashboard/DashboardView.swift` | ✅ | 🔲 | 5 |
| Study / Ask | `Features/Study/StudyView.swift` | ✅ | 🔲 | 5 |
| Progress | `Features/Progress/LearnerProgressView.swift` | ✅ | 🔲 | 6 |
| Parent Dashboard | `Features/Parent/ParentDashboardView.swift` | ✅ | 🔲 | 6 |
| Paywall | `Features/Paywall/PaywallView.swift` | ✅ | 🔲 | 7 |
| Offline Packs | `Features/OfflinePacks/OfflinePacksView.swift` | ✅ | 🔲 | 8 |
| Settings | `Features/Settings/SettingsView.swift` | ✅ | 🔲 | 6 |
| Voice Input | `Features/Study/VoiceInputView.swift` | 🔲 | 🔲 | 6 |
| Study ViewModel | `Features/Study/StudyViewModel.swift` | 🔲 | 🔲 | 5 |
| Onboarding ViewModel | `Features/Onboarding/OnboardingViewModel.swift` | 🔲 | 🔲 | 6 |
| StoreKit Manager | `Features/Subscription/StoreKitManager.swift` | 🔲 | 🔲 | 7 |
| Offline Sync Manager | `Core/Persistence/OfflineSyncManager.swift` | 🔲 | 🔲 | 5 |
| Core Data Stack | `Core/Persistence/CoreDataStack.swift` | 🔲 | 🔲 | 5 |
| Bhashini Client | `Core/Networking/BhashiniClient.swift` | 🔲 | 🔲 | 6 |
