//
//  TriviaModels.swift
//  Niche Music
//

import Foundation

struct DailyTriviaTodayResponse: Decodable {
    let question: DailyTriviaQuestion
    let hasAnswered: Bool
    let userResponse: DailyTriviaUserResponse?
    let correctChoiceId: Int?
    let explanation: String?
    let explanationImageUrl: String?

    init(
        question: DailyTriviaQuestion,
        hasAnswered: Bool,
        userResponse: DailyTriviaUserResponse?,
        correctChoiceId: Int?,
        explanation: String?,
        explanationImageUrl: String? = nil
    ) {
        self.question = question
        self.hasAnswered = hasAnswered
        self.userResponse = userResponse
        self.correctChoiceId = correctChoiceId
        self.explanation = explanation
        self.explanationImageUrl = explanationImageUrl
    }
}

struct DailyTriviaQuestion: Decodable, Identifiable, Equatable {
    let id: String
    let questionDate: String
    let question: String
    let choices: [DailyTriviaChoice]
    let releaseAt: String
    let questionImageUrl: String?

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: questionDate) else { return questionDate }

        let display = DateFormatter()
        display.dateFormat = "MMM d"
        display.timeZone = TimeZone.current
        return display.string(from: date)
    }
}

struct DailyTriviaChoice: Decodable, Identifiable, Equatable {
    let id: Int
    let text: String
    let imageUrl: String?
}

struct DailyTriviaUserResponse: Decodable, Equatable {
    let id: String
    let selectedChoiceId: Int
    let isCorrect: Bool
    let answeredAt: String
}

struct DailyTriviaAnswerBody: Encodable {
    let answerId: Int
}

struct DailyTriviaAnswerResponse: Decodable {
    let correct: Bool
    let correctChoiceId: Int
    let explanation: String?
    let explanationImageUrl: String?
    let response: DailyTriviaUserResponse
    let alreadyAnswered: Bool?
}

#if DEBUG
extension DailyTriviaQuestion {
    static let preview = DailyTriviaQuestion(
        id: "daily_trivia_20260702",
        questionDate: "2026-07-02",
        question: "Which artist released the album \"Blonde\"?",
        choices: [
            DailyTriviaChoice(id: 1, text: "Tyler, The Creator", imageUrl: nil),
            DailyTriviaChoice(id: 2, text: "Frank Ocean", imageUrl: nil),
            DailyTriviaChoice(id: 3, text: "Kendrick Lamar", imageUrl: nil),
            DailyTriviaChoice(id: 4, text: "Steve Lacy", imageUrl: nil),
        ],
        releaseAt: "2026-07-02T00:00:00+00:00",
        questionImageUrl: nil
    )
}
#endif
