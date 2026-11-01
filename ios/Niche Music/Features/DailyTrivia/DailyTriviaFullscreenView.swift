//
//  DailyTriviaFullscreenView.swift
//  Niche Music
//

import SwiftUI
import Kingfisher

struct DailyTriviaFullscreenView: View {
    @ObservedObject var store: TriviaStore
    var onDismiss: (() -> Void)?

    @State private var payload: DailyTriviaTodayResponse?
    @State private var phase: TriviaPhase = .loading
    @State private var loadError: String?
    @State private var submitError: String?

    var body: some View {
        ZStack {
            background

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if phase == .loading {
                        loadingContent
                    } else if let loadError {
                        errorContent(loadError)
                    } else if let payload {
                        questionHeader(payload.question)
                        if showsResult(payload) {
                            outcomeBanner(payload)
                        }
                        if let submitError {
                            submitErrorBanner(submitError)
                        }
                        choicesSection(payload)
                        resultSection(payload)
                        scrollFooter(payload)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
        }
        .interactiveDismissDisabled(true)
        .task {
            await loadToday()
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            Circle()
                .fill(Theme.accentColor.opacity(0.24))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: -130, y: -280)

            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 150, y: 260)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.82),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                haptic(.light)
                onDismiss?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            if let payload {
                Text(payload.question.formattedDate)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08), in: Capsule())
            }
        }
    }

    // MARK: - Content

    private var loadingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.1)

            Text("Loading today's question...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondaryColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))

            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textSecondaryColor)
                .multilineTextAlignment(.center)

            Button {
                Task { await loadToday() }
            } label: {
                Text("Try again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Theme.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func questionHeader(_ question: DailyTriviaQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)

                Text("Daily Trivia")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accentColor)
            }

            if let imageUrl = question.questionImageUrl {
                triviaImage(
                    urlString: imageUrl,
                    height: 180,
                    cornerRadius: 18,
                    fallbackIcon: "opticaldisc"
                )
            }

            Text(question.question)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submitErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFF6B6B))

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x3D1A1A).opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func outcomeBanner(_ payload: DailyTriviaTodayResponse) -> some View {
        let isCorrect = resolvedIsCorrect(payload)

        HStack(spacing: 10) {
            Image(systemName: isCorrect ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isCorrect ? Color(hex: 0x3DDC97) : Color(hex: 0xFF6B6B))

            Text(isCorrect ? "You got it!" : "Not this time")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isCorrect ? Color(hex: 0x1A3D2E) : Color(hex: 0x3D1A1A)).opacity(0.7),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    (isCorrect ? Color(hex: 0x3DDC97) : Color(hex: 0xFF6B6B)).opacity(0.35),
                    lineWidth: 1
                )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    @ViewBuilder
    private func choicesSection(_ payload: DailyTriviaTodayResponse) -> some View {
        VStack(spacing: 10) {
            ForEach(payload.question.choices) { choice in
                choiceRow(choice, payload: payload)
            }
        }
    }

    @ViewBuilder
    private func choiceRow(_ choice: DailyTriviaChoice, payload: DailyTriviaTodayResponse) -> some View {
        let style = choiceStyle(for: choice, payload: payload)
        let isSubmittingThis = if case .submitting(let id) = phase { id == choice.id } else { false }
        let isInteractive = canSelectChoice(payload)

        Button {
            guard isInteractive else { return }
            Task { await selectChoice(choice.id, payload: payload) }
        } label: {
            HStack(spacing: 14) {
                choiceArtwork(choice, style: style)

                Text(choice.text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(style.textColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSubmittingThis {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else if let icon = style.trailingIcon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(style.iconColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(style.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style.borderColor, lineWidth: style.borderWidth)
            }
        }
        .buttonStyle(TriviaChoiceButtonStyle())
        .disabled(!isInteractive || store.isSubmitting)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: phase)
    }

    @ViewBuilder
    private func choiceArtwork(_ choice: DailyTriviaChoice, style: TriviaChoiceStyle) -> some View {
        triviaImage(
            urlString: choice.imageUrl,
            width: 52,
            height: 52,
            cornerRadius: 12,
            fallbackIcon: "music.mic"
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style.artworkBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func triviaImage(
        urlString: String?,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        cornerRadius: CGFloat,
        fallbackIcon: String
    ) -> some View {
        let resolvedWidth = width ?? .infinity
        let resolvedHeight = height ?? 120

        Group {
            if let urlString, let url = URL(string: urlString) {
                KFImage(url)
                    .placeholder {
                        imagePlaceholder(
                            width: resolvedWidth,
                            height: resolvedHeight,
                            cornerRadius: cornerRadius,
                            showSpinner: true
                        )
                    }
                    .onFailureView {
                        imagePlaceholder(
                            width: resolvedWidth,
                            height: resolvedHeight,
                            cornerRadius: cornerRadius,
                            icon: fallbackIcon
                        )
                    }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
            } else {
                imagePlaceholder(
                    width: resolvedWidth,
                    height: resolvedHeight,
                    cornerRadius: cornerRadius,
                    icon: fallbackIcon
                )
            }
        }
        .frame(
            maxWidth: width == nil ? .infinity : resolvedWidth,
            minHeight: resolvedHeight,
            maxHeight: resolvedHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func imagePlaceholder(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        showSpinner: Bool = false,
        icon: String = "photo"
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.white.opacity(0.08))
            .frame(maxWidth: width == .infinity ? .infinity : width, minHeight: height, maxHeight: height)
            .overlay {
                if showSpinner {
                    ProgressView()
                        .tint(.white.opacity(0.55))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: min(height * 0.28, 28), weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
    }

    @ViewBuilder
    private func resultSection(_ payload: DailyTriviaTodayResponse) -> some View {
        if showsResult(payload) {
            VStack(alignment: .leading, spacing: 14) {
                if let imageUrl = payload.explanationImageUrl {
                    triviaImage(
                        urlString: imageUrl,
                        height: 160,
                        cornerRadius: 16,
                        fallbackIcon: "photo.on.rectangle"
                    )
                }

                if let explanation = resolvedExplanation(payload), !explanation.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("The answer")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                            .textCase(.uppercase)
                            .tracking(0.6)

                        Text(explanation)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    private func scrollFooter(_ payload: DailyTriviaTodayResponse) -> some View {
        if showsResult(payload) || payload.hasAnswered {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Next question drops tomorrow")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.52))
                .frame(maxWidth: .infinity)

                Button {
                    haptic(.light)
                    onDismiss?()
                } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Theme.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        } else if phase != .loading && loadError == nil {
            Text("Pick one — no takebacks")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    // MARK: - Logic

    private func loadToday() async {
        phase = .loading
        loadError = nil
        submitError = nil

        guard let response = await store.fetchToday() else {
            loadError = store.lastError ?? "Couldn't load today's trivia"
            return
        }

        payload = response

        if response.hasAnswered,
           let userResponse = response.userResponse,
           let correctChoiceId = response.correctChoiceId {
            phase = .revealed(
                correct: userResponse.isCorrect,
                selectedId: userResponse.selectedChoiceId,
                correctId: correctChoiceId
            )
        } else {
            phase = .answering
        }
    }

    private func selectChoice(_ choiceId: Int, payload: DailyTriviaTodayResponse) async {
        haptic(.light)
        submitError = nil
        phase = .submitting(choiceId)

        guard let result = await store.submitAnswer(questionId: payload.question.id, answerId: choiceId) else {
            phase = .answering
            submitError = store.lastError ?? "Couldn't submit your answer. Try again."
            haptic(.error)
            return
        }

        if result.correct {
            haptic(.success)
        } else {
            haptic(.error)
        }

        self.payload = DailyTriviaTodayResponse(
            question: payload.question,
            hasAnswered: true,
            userResponse: result.response,
            correctChoiceId: result.correctChoiceId,
            explanation: result.explanation,
            explanationImageUrl: result.explanationImageUrl
        )

        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            phase = .revealed(
                correct: result.correct,
                selectedId: result.response.selectedChoiceId,
                correctId: result.correctChoiceId
            )
        }
    }

    private func canSelectChoice(_ payload: DailyTriviaTodayResponse) -> Bool {
        guard !payload.hasAnswered else { return false }
        if case .answering = phase { return true }
        return false
    }

    private func showsResult(_ payload: DailyTriviaTodayResponse?) -> Bool {
        guard payload != nil else { return false }
        if case .revealed = phase { return true }
        return payload?.hasAnswered == true
    }

    private func resolvedExplanation(_ payload: DailyTriviaTodayResponse) -> String? {
        payload.explanation
    }

    private func resolvedIsCorrect(_ payload: DailyTriviaTodayResponse) -> Bool {
        if case .revealed(let correct, _, _) = phase {
            return correct
        }
        return payload.userResponse?.isCorrect ?? false
    }

    private func choiceStyle(for choice: DailyTriviaChoice, payload: DailyTriviaTodayResponse) -> TriviaChoiceStyle {
        switch phase {
        case .revealed(let correct, let selectedId, let correctId):
            if choice.id == correctId {
                return .correct
            }
            if choice.id == selectedId, !correct {
                return .incorrect
            }
            return .dimmed
        default:
            if payload.hasAnswered,
               let userResponse = payload.userResponse,
               let correctChoiceId = payload.correctChoiceId {
                if choice.id == correctChoiceId {
                    return .correct
                }
                if choice.id == userResponse.selectedChoiceId, !userResponse.isCorrect {
                    return .incorrect
                }
                return .dimmed
            }
            return .neutral
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Supporting Types

private enum TriviaPhase: Equatable {
    case loading
    case answering
    case submitting(Int)
    case revealed(correct: Bool, selectedId: Int, correctId: Int)
}

private struct TriviaChoiceStyle: Equatable {
    let background: Color
    let borderColor: Color
    let borderWidth: CGFloat
    let textColor: Color
    let artworkBorder: Color
    let trailingIcon: String?
    let iconColor: Color

    static let neutral = TriviaChoiceStyle(
        background: .white.opacity(0.06),
        borderColor: .white.opacity(0.08),
        borderWidth: 1,
        textColor: .white,
        artworkBorder: .white.opacity(0.1),
        trailingIcon: nil,
        iconColor: .clear
    )

    static let correct = TriviaChoiceStyle(
        background: Color(hex: 0x1A3D2E).opacity(0.85),
        borderColor: Color(hex: 0x3DDC97).opacity(0.55),
        borderWidth: 1.5,
        textColor: .white,
        artworkBorder: Color(hex: 0x3DDC97).opacity(0.4),
        trailingIcon: "checkmark.circle.fill",
        iconColor: Color(hex: 0x3DDC97)
    )

    static let incorrect = TriviaChoiceStyle(
        background: Color(hex: 0x3D1A1A).opacity(0.85),
        borderColor: Color(hex: 0xFF6B6B).opacity(0.55),
        borderWidth: 1.5,
        textColor: .white,
        artworkBorder: Color(hex: 0xFF6B6B).opacity(0.4),
        trailingIcon: "xmark.circle.fill",
        iconColor: Color(hex: 0xFF6B6B)
    )

    static let dimmed = TriviaChoiceStyle(
        background: .white.opacity(0.03),
        borderColor: .white.opacity(0.05),
        borderWidth: 1,
        textColor: .white.opacity(0.42),
        artworkBorder: .white.opacity(0.06),
        trailingIcon: nil,
        iconColor: .clear
    )
}

private struct TriviaChoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("Daily Trivia") {
    DailyTriviaFullscreenView(store: TriviaStore())
}
#endif
