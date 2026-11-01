//
//  TriviaStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class TriviaStore: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var lastError: String?

    private let api = APIClient.shared

    func fetchToday() async -> DailyTriviaTodayResponse? {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            return try await api.request(
                Endpoints.dailyTriviaToday,
                method: .get
            )
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func submitAnswer(questionId: String, answerId: Int) async -> DailyTriviaAnswerResponse? {
        isSubmitting = true
        lastError = nil
        defer { isSubmitting = false }

        do {
            return try await api.request(
                Endpoints.dailyTriviaAnswer(questionId: questionId),
                method: .post,
                body: DailyTriviaAnswerBody(answerId: answerId)
            )
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
