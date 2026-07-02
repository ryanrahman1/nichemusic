//
//  DiscoverSearchStore.swift
//  Niche Music
//

import Foundation
import Combine

@MainActor
final class DiscoverSearchStore: ObservableObject {
    @Published private(set) var suggestions: [GlobalSearchSuggestion] = []
    @Published private(set) var results: GlobalSearchResults?
    @Published private(set) var activeQuery: String = ""
    @Published private(set) var isLoadingSuggestions = false
    @Published private(set) var isLoadingResults = false
    @Published private(set) var errorMessage: String?

    private let api = APIClient.shared
    private var suggestionsTask: Task<Void, Never>?

    func reset() {
        suggestionsTask?.cancel()
        suggestions = []
        results = nil
        activeQuery = ""
        errorMessage = nil
        isLoadingSuggestions = false
        isLoadingResults = false
    }

    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestionsTask?.cancel()

        if trimmed != activeQuery {
            results = nil
        }

        guard trimmed.count >= 2 else {
            suggestions = []
            isLoadingSuggestions = false
            return
        }

        suggestionsTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await loadSuggestions(query: trimmed)
        }
    }

    func loadSuggestions(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }

        isLoadingSuggestions = true
        errorMessage = nil

        do {
            let response: GlobalSearchSuggestionsResponse = try await api.request(
                Endpoints.globalSearchSuggestions,
                method: .get,
                query: [
                    "q": trimmed,
                    "limit": "12",
                ]
            )
            suggestions = response.suggestions
        } catch {
            if !Task.isCancelled {
                suggestions = []
                errorMessage = error.localizedDescription
            }
        }

        isLoadingSuggestions = false
    }

    func loadResults(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoadingResults = true
        errorMessage = nil
        activeQuery = trimmed

        do {
            let response: GlobalSearchResponse = try await api.request(
                Endpoints.globalSearch,
                method: .get,
                query: [
                    "q": trimmed,
                    "perTypeLimit": "10",
                ]
            )
            results = response.results
            suggestions = []
        } catch {
            results = nil
            errorMessage = error.localizedDescription
        }

        isLoadingResults = false
    }
}
