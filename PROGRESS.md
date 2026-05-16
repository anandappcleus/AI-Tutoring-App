# SmartTutor — Sprint Progress Tracker

*Last updated: 16 May 2026 (SymPy verifier fully operational; vision + LLM accuracy hardening)*

---

## Sprint Status Overview

| Sprint | Theme | Status | Weeks |
|--------|-------|--------|-------|
| Sprint 1 | Foundation & NIM Integration | ✅ Complete | 1–2 |
| Sprint 2 | RAG Pipeline | ✅ Complete | 3–4 |
| Sprint 3 | CrewAI Agents | ✅ Complete | 5–6 |
| Sprint 4 | FastAPI Routes + Auth | ✅ Complete | 7–8 |
| Sprint 5 | iOS Core — Study Screen | ✅ Complete | 9–10 |
| Sprint 6 | iOS — Voice, Progress, Onboarding | ✅ Complete | 11–12 |
| Sprint 7 | Subscription + Freemium | 🔲 Not Started | 13–14 |
| Sprint 8 | Offline Packs + Content QA | � In Progress (4/6 tasks) | 15–16 |
| Sprint 9 | Production LLM Switch + Deployment | 🔲 Not Started | 17–18 |
| Sprint 10 | Indic Language Expansion + B2B Admin | 🔲 Not Started | 19–20 |
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

## Sprint 6 — iOS: Voice, Progress, Onboarding ✅ Complete

**Goal:** Voice input, progress charts, language onboarding, parent dashboard

> Note: All view files are already designed. Tasks focus on wiring + Sarvam speech API (Saaras v2 STT, Bulbul v2 TTS) — same vendor as NIM LLM.

| # | Task | File | Status |
|---|------|------|--------|
| 1 | Wire `OnboardingView.swift` — `OnboardingViewModel` | `Features/Onboarding/OnboardingViewModel.swift` | ✅ Done |
| 2 | `VoiceInputView.swift` — AVFoundation microphone capture | `Features/Study/VoiceInputView.swift` | ✅ Done |
| 3 | `SarvamSpeechClient.swift` — Sarvam Saaras v2 STT + Bulbul v2 TTS | `Core/Networking/SarvamSpeechClient.swift` | ✅ Done |
| 4 | Wire `LearnerProgressView.swift` — Swift Charts + `ProgressViewModel` | `Features/Progress/LearnerProgressView.swift`, `Features/Progress/ProgressViewModel.swift` | ✅ Done |
| 5 | Wire `ParentDashboardView.swift` — `/progress` API | `Features/Parent/ParentDashboardView.swift`, `Features/Parent/ParentDashboardViewModel.swift` | ✅ Done |
| 6 | `Localizable.strings` — Bengali + Hindi UI labels | `Resources/bn.lproj/`, `Resources/hi.lproj/` | 🔲 Deferred to Sprint 10 |
| 7 | Push notification registration + APNs token upload | `SmartTutorApp.swift`, `App/AppDelegate.swift`, `POST /auth/device-token` | ✅ Done |

### Sprint 6 Unit Tests

| File | Tests | Status |
|------|-------|--------|
| `Sprint6TestHelpers.swift` — `StubAPIClient`, `MockURLProtocol`, fixture builders | — | ✅ Done |
| `OnboardingViewModelTests.swift` | 14 | ✅ Done |
| `ProgressViewModelTests.swift` | 9 | ✅ Done |
| `ParentDashboardViewModelTests.swift` | 12 | ✅ Done |
| `SarvamSpeechClientTests.swift` | 9 | ✅ Done |

**Sprint 6 test total: 44 new tests** · **Cumulative: 83 tests** (39 Sprint 5 + 44 Sprint 6)

---

## Post-Sprint 6 — Production Hardening + Feature Work ✅ Complete

*14 May 2026 — done between Sprint 6 completion and Sprint 7 start.*

### Backend Fixes (all deployed to Railway)

| # | Fix / Feature | File(s) | Commit | Status |
|---|---------------|---------|--------|--------|
| 1 | **NullPool fix** — `ToolSessionFactory` with `NullPool` engine eliminates `RuntimeError: attached to a different loop` in CrewAI tools running in `ThreadPoolExecutor` | `app/database.py`, `tools/*.py` | prior session | ✅ Deployed + confirmed via Railway logs |
| 2 | **Admin concurrency guard** — `_crew_running` flag returns 409 Conflict when a nightly crew run is already in progress; prevents duplicate NIM 429s | `app/routers/admin.py` | `5655786` | ✅ Deployed |
| 3 | **FREE_DAILY_LIMIT → 50** — raised from 10 for testing | `app/routers/ask.py` | `5655786` | ✅ Deployed |
| 4 | **Multi-pass JSON parser** — `_extract_last_json_object()` (brace-depth walker, handles ReAct traces), `_fix_control_chars_in_strings()`, 4-pass parse pipeline; eliminates raw thinking text / raw JSON in iOS | `app/routers/ask.py` | `72c3bca` | ✅ Deployed |
| 5 | **Stronger tutor system prompt** — "CRITICAL OUTPUT FORMAT: Final Answer MUST be a single valid JSON object and nothing else"; explicit schema in prompt | `app/agents/prompts.py` | `72c3bca` | ✅ Deployed |
| 6 | **Better parse_failed logging** — logs `extracted_preview` (first 300 chars) and `json_err` (JSONDecodeError message) for debugging | `app/routers/ask.py` | `72c3bca` | ✅ Deployed |
| 7 | **Model routing fix** — EN questions → `meta/llama-3.3-70b-instruct` (reliable JSON output); Indic languages → `sarvamai/sarvam-m` (native language support). Root-cause fix for sarvam-m outputting pure thinking with zero JSON | `app/agents/agents.py` | `798df8b` | ✅ Deployed |
| 8 | **Prose fallback** — when no JSON and no "Final Answer:" marker, shows user-friendly message instead of 1973-char raw thinking dump | `app/routers/ask.py` | `798df8b` | ✅ Deployed |
| 9 | **Exam-specific framing** — `exam_type` (JEE/NEET/WBCHSE) flows through `AskRequest → crew → task prompt`; response includes `question_type`, `marks`, `marking_scheme` per exam style | `app/routers/ask.py`, `app/agents/crew.py`, `app/agents/tasks.py` | `1329d89` | ✅ Deployed |

### iOS Changes (deployed)

| # | Change | File(s) | Commit | Status |
|---|--------|---------|--------|--------|
| 1 | **Exam framing in chat bubble** — `buildAnswerText` renders badge `🎯 JEE Mains & Advanced • MCQ • 4 marks (+4/-1)` above explanation; `examTarget` from `StudentProfile` sent automatically | `StudyViewModel.swift` | `1329d89` | ✅ Committed |
| 2 | **AskResponse / PracticeProblem** extended with `questionType`, `marks`, `markingScheme` optional fields | `Endpoints.swift` | `1329d89` | ✅ Committed |
| 3 | **Tests updated** for new `AskResponse` + `PracticeProblem` memberwise init | `StudyViewModelTests.swift`, `OfflineSyncManagerTests.swift` | `1329d89` | ✅ Committed |
| 4 | **PROGRESS.md** updated | `PROGRESS.md` | `7543850` | ✅ Committed |
| 5 | **Exam framing unit tests** — `test_ask_sendsExamType_fromStudentProfile`, `test_buildAnswerText_rendersBadge_withExamFields` | `StudyViewModelTests.swift` | `0eee69b` | ✅ Committed |
| 6 | **Offline practice session** — `OfflinePracticeView` (flashcard Q&A, 3D flip, progress bar, completion screen), `fetchQuestions(for:)` Core Data helper, `OfflinePacksView` wired to sheet | `OfflinePracticeView.swift`, `OfflinePackEntity.swift`, `OfflinePacksView.swift` | `72de625` | ✅ Committed |

### Home Tab Feature Work (14 May 2026)

| # | Feature | File(s) | Commit | Status |
|---|---------|---------|--------|--------|
| 1 | **AppLogger** — centralized `os.Logger` wrapper with category-specific loggers (Dashboard, MockTests, SyllabusMap, FormulaSheets, Camera, Voice, Study, Navigation, Network, Auth, OfflinePacks) | `Core/Logging/AppLogger.swift` | pending | ✅ Coded |
| 2 | **ImagePickerView** — `PHPickerViewController` SwiftUI wrapper; permission-safe, logs pick/cancel/error | `Core/UI/ImagePickerView.swift` | pending | ✅ Coded |
| 3 | **MockTestsView** — full test catalog (JEE/NEET/WBCHSE static + API fallback), filter chips, empty/error state, `MockTestDetailView` → "Practise with AI Tutor" bridges to Study tab via `pendingStudyTopic` | `Features/MockTests/MockTestsView.swift` | pending | ✅ Coded |
| 4 | **SyllabusMapView** — full JEE/NEET/WBCHSE syllabus (subjects → chapters → topics), progress overlay from `GET /progress`, chapter tap → auto-ask AI tutor | `Features/SyllabusMap/SyllabusMapView.swift` | pending | ✅ Coded |
| 5 | **FormulaSheetView** — 80+ formulas across Physics/Chemistry/Maths categories, searchable, expandable accordion, "Ask AI to Explain" CTA per formula | `Features/FormulaSheets/FormulaSheetView.swift` | pending | ✅ Coded |
| 6 | **DashboardView wired** — Learning Modules all navigate (not "coming soon"); camera tap → `ImagePickerView` → `PickedImageQuerySheet`; mic tap → `VoiceInputView`; "Start AI Lesson" pre-fills Study topic; search bar submit bridges to Study | `Features/Dashboard/DashboardView.swift` | pending | ✅ Coded |
| 7 | **StudyView.onAppear** — consumes `pendingStudyTopic` `@AppStorage` bridge set by Dashboard/SyllabusMap/FormulaSheets/MockTests; auto-asks with 0.2s delay for tab-switch animation | `Features/Study/StudyView.swift` | pending | ✅ Coded |
| 8 | **Endpoints.mockTests** — `GET /mock-tests` endpoint (static fallback in ViewModel on 404) | `Core/Networking/Endpoints.swift` | pending | ✅ Coded |

### Production Verification (Railway logs, 14 May 2026)

```
15:14:43 → POST /ask  lang=en  ← status=200  46.8s  (cold start — Chroma init)
15:17:07 → POST /ask  lang=en  ← status=200  13.5s  model=meta/llama-3.3-70b-instruct
15:18:14 → POST /ask  lang=en  ← status=200  12.2s  model=meta/llama-3.3-70b-instruct
```
No `ask.parse_failed` in any of the above. All 200s. ✅

---

## Post-Sprint 6 (cont.) — Camera / Image-to-AI Pipeline ✅ Complete

*15 May 2026 — image pipeline, OCR, chat thumbnail, irrelevant-image guard. Commit `30df8ef`.*

| # | Change | File(s) | Status |
|---|--------|---------|--------|
| 1 | **`sheet(item:)` blank-screen fix** — replaced `sheet(isPresented:) { if let img }` (stale closure nil-race) with `sheet(item: $pickedImageItem)` + `IdentifiableImage: Identifiable` wrapper; image always non-nil when sheet renders | `DashboardView.swift` | ✅ |
| 2 | **On-device Vision OCR** — `VNRecognizeTextRequest` (`.accurate`, language correction on) runs when user taps *Ask AI Tutor*; extracted text appended as `[Text from image: …]` in the query sent to `/ask`; backend unchanged (text-only LLM) | `DashboardView.swift` | ✅ |
| 3 | **OCR loading state** — button shows `ProgressView` spinner and is disabled while OCR runs (~0.3–0.8s); prevents double-tap | `DashboardView.swift` | ✅ |
| 4 | **Irrelevant-image guard** — hard block (alert, OK only) when OCR finds no text AND user typed nothing; soft block (alert + *Ask Anyway*) when OCR fails but user typed a question (handles genuine OCR failures on valid images); `PendingImageStore` cleared in both block paths | `DashboardView.swift` | ✅ |
| 5 | **`PendingImageStore` singleton** — carries `UIImage` from `PickedImageQuerySheet` across the Dashboard→Study tab boundary; claimed and cleared immediately in `StudyViewModel.ask()` | `StudyViewModel.swift` | ✅ |
| 6 | **`StudyMessage.image: UIImage?`** — user messages now carry an optional image; custom `Equatable` (id-based, since `UIImage` isn't `Equatable`); `ask()` strips the `[Text from image:]` annotation from the display text so the chat bubble stays clean | `StudyViewModel.swift` | ✅ |
| 7 | **Image thumbnail in chat** — `ChatMessage` and `ChatBubble` updated; user question bubbles show a 160 pt rounded thumbnail above the message text when an image was attached | `StudyView.swift` | ✅ |
| 8 | **`ImagePickerView` logging** — added `didFinishPicking` count + dismiss log, asset-load size log, main-dispatch log | `ImagePickerView.swift` | ✅ |

---

## Post-Sprint 6 (cont.) — LLM Accuracy & SymPy Verifier ✅ Complete

*16 May 2026 — end-to-end fix of SymPy sandbox, vision extraction, and LLM reliability.*

### Root Cause: SymPy Sandbox Never Worked

The `sympy_verifier.py` module was introduced to give the 70B a verified numerical answer before it writes its explanation. It was silently broken from day one: Python's `from X import Y` syntax compiles to `__import__('X', ...)` bytecode, and the sandbox had `__import__` stripped from `__builtins__`. Every `from sympy import …` line raised `ImportError` silently → caught by `except Exception` → `no_output` log for every single question.

### Issues Fixed (all deployed)

| # | Issue | Root Cause | Fix | Commit |
|---|-------|-----------|-----|--------|
| 1 | `sympy_verifier.no_output` — all questions | `__import__` stripped from sandbox `__builtins__`; `from sympy import …` always raised `ImportError` silently | Added `_restricted_import` to `safe_builtins['__import__']` — allows whitelisted modules, blocks all others | `867d368` |
| 2 | `sympy_verifier.no_output` — exponential eqs (`3^x = 4^(x-1)`) | 8B generated `solve(3**x - 4**(x-1), x)` — SymPy cannot solve transcendental equations; returned empty list → `IndexError` swallowed | Added example showing algebraic rearrangement: take ln both sides → linear eq → `solve(x*log(3)-(x-1)*log(4), x)` | `94ead88` |
| 3 | `sympy_verifier.cannot_evaluate` for image MCQ questions | `effective_question` starts with user meta-text ("Which one is correct?"); 8B saw this first and returned `CANNOT_EVALUATE` | When `body.image_b64` is set, pass only the extracted image content to SymPy — the math is in the image, not the user's framing | `c5fdf18` |
| 4 | SymPy returns unrecognisable answer `−log(2^(2/log(3/4)))` | `nsimplify()` of `log(4)/(log(4)−log(3))` produced a valid but unreadable form the 70B could not match to MCQ options | Changed exponential eq example to `round(float(sol), 4)` → `4.8202`; updated rule 3 in translation prompt to guide decimal vs symbolic choice | `82f9003` |
| 5 | Vision misread `log_{3/2}` as `log_3` | `3/2` subscript (fractional base) dropped its denominator | Added CRITICAL rule: "subscript of log is the BASE; 3/2 is base THREE-HALVES, never drop the denominator" | `e745821` |
| 6 | Vision misread infinite nested radical as finite power | `√(4 − 1/(3√2)·√(4−…))` rewritten as `(1/(3√2))^{4−1/(3√2)}` | Added CRITICAL rule: repeating sqrt pattern = INFINITE nested radical; write with `…`, do NOT rewrite as base^exponent | `e745821` |
| 7 | MCQ options (A/B/C/D) not extracted from images | Vision prompt only said "extract options" when multiple questions present | Added explicit CRITICAL rule: extract every labeled choice with full math content for ANY single MCQ question | `4df6b78` |
| 8 | 8B token-spinning loop (repeated LaTeX 20+ times) | 8B fallback on hard algebra enters infinite repetition until `max_tokens` hit | `_dedup_repetition()`: finds any 35/60/100-char substring appearing ≥5 times, truncates after 3rd occurrence; 8B `max_tokens` 3500→1500 | `a1c4eb2` |
| 9 | Generated SymPy code not visible when `no_output` fires | `log.debug(...)` not shown at INFO level in Railway | Changed to `log.info(...)` for generated code and exec exceptions | `94ead88` |
| 10 | `StudentProfile.load()` (Keychain read) on every `StudyView` render | `isPremium` and `langCode` were computed properties calling `StudentProfile.load()` directly; `StudyView.body` evaluates 30+ times during image sheet animations | Added `@Environment(AppState.self)` to `StudyView`; read from `appState.currentProfile` (already in memory) | `64ce60a` |

### SymPy Coverage After Fixes

| Problem Type | Before | After |
|---|---|---|
| Log-exponent identity `((log₂9)²)^(1/log₂(log₂9))` | ❌ `ImportError` | ✅ Returns `4` |
| Infinite nested radical `6 + log_{3/2}(…)` | ❌ `ImportError` | ✅ Returns `4` |
| Exponential equation `3^x = 4^(x-1)` | ❌ `ImportError` then wrong code | ✅ Returns `4.8202` |
| Conceptual questions | ❌ `ImportError` | ✅ `CANNOT_EVALUATE` (correct) |
| Image MCQ with meta-question | ❌ `CANNOT_EVALUATE` (saw user text) | ✅ Evaluates image math |

### Vision Extraction Accuracy After Fixes

| Pattern | Before | After |
|---|---|---|
| `log_{3/2}` (fractional base) | Misread as `log_3` | Correctly `log_{3/2}` |
| Infinite nested radical `√(4−…)` | Misread as `(base)^(exp)` | Correctly `sqrt(4 - … )` |
| MCQ options A/B/C/D | Silently dropped | Fully extracted verbatim |
| Multi-level exponents `(log₂9)²` | Outer `²` dropped | Correctly captured |

### Production Log Sequence (healthy request, 16 May 2026)

```
ask.vision_extracted  chars=137
sympy_verifier.code   chars=150  preview=from sympy import symbols, log, solve...
ask.sympy_verified    answer=4.8202
ask.direct_done       21s
← POST /ask  status=200
```

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

## Sprint 8 — Offline Packs + Content QA � In Progress

**Goal:** Offline question packs downloadable, Bengali/Hindi output QA reviewed

> Note: `OfflinePacksView.swift` is already designed.

| # | Task | File | Status |
|---|------|------|--------|
| 1 | `GET /packs` — list available topic packs | `backend/app/routers/packs.py` | ✅ Done — 6 JEE packs (Physics, Chemistry, Maths) |
| 2 | `GET /packs/:id/download` — return question JSON | `backend/app/routers/packs.py` | ✅ Done — 5 questions/pack (30 total, English placeholders) |
| 3 | Wire `OfflinePacksView.swift` — download + Core Data | `Features/OfflinePacks/OfflinePacksView.swift`, `OfflinePacksViewModel.swift` | ✅ Done |
| 4 | Core Data: `OfflinePack` + `OfflineQuestion` entities | `Core/Persistence/OfflinePackEntity.swift` | ✅ Done |
| 5 | Content QA: 50 Bengali answers reviewed by native speaker | — | 🔲 Manual step |
| 6 | Prompt tuning based on QA feedback | `backend/app/agents/prompts.py` | 🔲 Deferred to Sprint 8 QA round |

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
| 10 | Indic Language Expansion + B2B Admin | Bengali, Tamil, Telugu, Marathi Localizable.strings + coaching institute admin panel |
| 11 | App Store Launch | App Review submission, marketing to school WhatsApp groups |
| 12 | Analytics + Retention | Mixpanel events, Sentry crash reporting, win-back push campaigns |

---

## iOS Screens Inventory

> All screens designed during Sprint 1. ✅ = UI shell exists · 🔲 = Not yet created

| Screen | File | UI Shell | Backend Wired | Sprint to Wire |
|--------|------|----------|---------------|---------------|
| Onboarding | `Features/Onboarding/OnboardingView.swift` | ✅ | ✅ | 6 |
| Dashboard | `Features/Dashboard/DashboardView.swift` | ✅ | ✅ | 5+7+ |
| Study / Ask | `Features/Study/StudyView.swift` | ✅ | ✅ | 5 |
| Progress | `Features/Progress/LearnerProgressView.swift` | ✅ | ✅ | 6 |
| Parent Dashboard | `Features/Parent/ParentDashboardView.swift` | ✅ | ✅ | 6 |
| Paywall | `Features/Paywall/PaywallView.swift` | ✅ | 🔲 | 7 |
| Offline Packs | `Features/OfflinePacks/OfflinePacksView.swift` | ✅ | ✅ | 8 |
| Offline Practice | `Features/OfflinePacks/OfflinePracticeView.swift` | ✅ | ✅ | 8+ |
| Mock Tests | `Features/MockTests/MockTestsView.swift` | ✅ | ✅ (static+API) | 7+ |
| Syllabus Map | `Features/SyllabusMap/SyllabusMapView.swift` | ✅ | ✅ (progress overlay) | 7+ |
| Formula Sheets | `Features/FormulaSheets/FormulaSheetView.swift` | ✅ | ✅ | 7+ |
| Settings | `Features/Settings/SettingsView.swift` | ✅ | ✅ | 6 |
| Voice Input | `Features/Study/VoiceInputView.swift` | ✅ | ✅ | 6 |
| Study ViewModel | `Features/Study/StudyViewModel.swift` | ✅ | ✅ | 5 |
| Onboarding ViewModel | `Features/Onboarding/OnboardingViewModel.swift` | ✅ | ✅ | 6 |
| StoreKit Manager | `Features/Subscription/StoreKitManager.swift` | 🔲 | 🔲 | 7 |
| Offline Sync Manager | `Core/Persistence/OfflineSyncManager.swift` | ✅ | ✅ | 5 |
| Core Data Stack | `Core/Persistence/CoreDataStack.swift` | ✅ | ✅ | 5 |
| Sarvam Speech Client | `Core/Networking/SarvamSpeechClient.swift` | ✅ | ✅ | 6 |
| Parent Dashboard ViewModel | `Features/Parent/ParentDashboardViewModel.swift` | ✅ | ✅ | 6 |
| Progress ViewModel | `Features/Progress/ProgressViewModel.swift` | ✅ | ✅ | 6 |
| AppLogger | `Core/Logging/AppLogger.swift` | ✅ | — | 7+ |
| ImagePickerView | `Core/UI/ImagePickerView.swift` | ✅ | — | 7+ |
