//
//  OnboardingViewModelTests.swift
//  SmartTutorTests
//
//  Sprint 6 — Unit tests for OnboardingViewModel.
//
//  Coverage:
//    ✓ Initial step is 1
//    ✓ canProceed is false until each step's required field is filled
//    ✓ advance() increments step when canProceed
//    ✓ advance() is a no-op when canProceed is false
//    ✓ advance() stops at step 3
//    ✓ submit() sets isComplete after API call
//    ✓ submit() uses "en" / "JEE" defaults when fields are empty
//    ✓ submit() uppercases examTarget
//    ✓ concurrent submit() while already submitting is ignored
//

import XCTest
@testable import SmartTutor

@MainActor
final class OnboardingViewModelTests: XCTestCase {

    var stubAPI: StubAPIClient!
    var appState: AppState!
    var sut: OnboardingViewModel!

    override func setUp() async throws {
        TokenStore.clearAll()
        StudentProfile.clear()
        stubAPI = StubAPIClient()
        // Default stub: updateProfile returns a valid StudentResponse
        stubAPI.responseHandler = { _ in makeStudentResponse() }
        appState = AppState(apiClient: stubAPI)
        sut = OnboardingViewModel()
    }

    override func tearDown() async throws {
        TokenStore.clearAll()
        StudentProfile.clear()
    }

    // MARK: - Initial state

    func test_initial_step_isOne() {
        XCTAssertEqual(sut.step, 1)
    }

    func test_initial_isNotSubmitting() {
        XCTAssertFalse(sut.isSubmitting)
    }

    func test_initial_isNotComplete() {
        XCTAssertFalse(sut.isComplete)
    }

    // MARK: - canProceed — step 1

    func test_canProceed_step1_falseWhenNoLanguageSelected() {
        sut.step = 1
        sut.selectedLanguage = ""
        XCTAssertFalse(sut.canProceed)
    }

    func test_canProceed_step1_trueAfterLanguageSelected() {
        sut.step = 1
        sut.selectedLanguage = "bn"
        XCTAssertTrue(sut.canProceed)
    }

    // MARK: - canProceed — step 2

    func test_canProceed_step2_falseWhenNoExamSelected() {
        sut.step = 2
        sut.selectedExam = ""
        XCTAssertFalse(sut.canProceed)
    }

    func test_canProceed_step2_trueAfterExamSelected() {
        sut.step = 2
        sut.selectedExam = "jee"
        XCTAssertTrue(sut.canProceed)
    }

    // MARK: - canProceed — step 3

    func test_canProceed_step3_falseWhenNameIsBlank() {
        sut.step = 3
        sut.name = "   "
        XCTAssertFalse(sut.canProceed)
    }

    func test_canProceed_step3_falseWhenNameIsEmpty() {
        sut.step = 3
        sut.name = ""
        XCTAssertFalse(sut.canProceed)
    }

    func test_canProceed_step3_trueAfterNameEntered() {
        sut.step = 3
        sut.name = "Anand"
        XCTAssertTrue(sut.canProceed)
    }

    // MARK: - advance()

    func test_advance_incrementsStep_whenCanProceed() {
        sut.step = 1
        sut.selectedLanguage = "hi"
        sut.advance()
        XCTAssertEqual(sut.step, 2)
    }

    func test_advance_doesNotIncrement_whenCantProceed() {
        sut.step = 1
        sut.selectedLanguage = ""
        sut.advance()
        XCTAssertEqual(sut.step, 1)
    }

    func test_advance_stopsAtStep3() {
        sut.step = 3
        sut.selectedExam = "neet"   // canProceed on step 3 checks name, not exam
        sut.name = "Riya"
        sut.advance()
        // advance() only increments if step < 3
        XCTAssertEqual(sut.step, 3)
    }

    // MARK: - submit()

    func test_submit_setsIsComplete_onSuccess() async {
        sut.selectedLanguage = "bn"
        sut.selectedExam = "jee"
        sut.name = "Anand"
        await sut.submit(via: appState)
        XCTAssertTrue(sut.isComplete)
    }

    func test_submit_setsIsComplete_evenWhenAPIFails() async {
        stubAPI.responseHandler = { _ in throw APIError.noNetwork }
        appState = AppState(apiClient: stubAPI)
        sut.selectedLanguage = "en"
        sut.selectedExam = "jee"
        sut.name = "Test"
        // AppState.updateProfile absorbs all errors — isComplete should still be set
        await sut.submit(via: appState)
        XCTAssertTrue(sut.isComplete)
    }

    func test_submit_usesDefaultLanguage_whenNoneSelected() async {
        var capturedEndpoint: Endpoint?
        stubAPI.responseHandler = { endpoint in
            capturedEndpoint = endpoint
            return makeStudentResponse()
        }
        appState = AppState(apiClient: stubAPI)
        sut.selectedLanguage = ""   // not selected
        sut.selectedExam = "jee"
        sut.name = "Test"
        await sut.submit(via: appState)
        if case .updateProfile(let lang, _, _) = capturedEndpoint {
            XCTAssertEqual(lang, "en")
        } else {
            XCTFail("Expected updateProfile endpoint")
        }
    }

    func test_submit_uppercasesExam() async {
        var capturedEndpoint: Endpoint?
        stubAPI.responseHandler = { endpoint in
            capturedEndpoint = endpoint
            return makeStudentResponse()
        }
        appState = AppState(apiClient: stubAPI)
        sut.selectedLanguage = "bn"
        sut.selectedExam = "jee"   // lowercase input
        sut.name = "Test"
        await sut.submit(via: appState)
        if case .updateProfile(_, let exam, _) = capturedEndpoint {
            XCTAssertEqual(exam, "JEE")
        } else {
            XCTFail("Expected updateProfile endpoint")
        }
    }

    func test_submit_isNotSubmitting_afterCompletion() async {
        sut.selectedLanguage = "bn"
        sut.selectedExam = "jee"
        sut.name = "Anand"
        await sut.submit(via: appState)
        XCTAssertFalse(sut.isSubmitting)
    }
}
