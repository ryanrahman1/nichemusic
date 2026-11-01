//
//  AuxBattleFullscreenView.swift
//  Niche Music
//

import SwiftUI

private enum AuxHomeStep {
    case landing
    case host
    case join
}

struct AuxBattleFullscreenView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var musicPlayer: MusicPlayer
    @EnvironmentObject private var playlistStore: PlaylistStore

    @ObservedObject var store: AuxBattleStore
    var onDismiss: (() -> Void)?

    @State private var homeStep: AuxHomeStep = .landing
    @State private var showLeaveAlert = false
    @State private var showHostSettings = false
    @State private var showSongSearch = false
    @State private var selectedPick: AuxSongPickSource?
    @State private var joinCode = ""
    @State private var createPrompt = ""
    @State private var createMaxPlayers = 8
    @State private var createSnippetLength = 15
    @State private var createSongSource: AuxSongSource = .any
    @State private var winnerIsLiked = false
    @State private var winnerLikeBusy = false
    @State private var showWinnerAddToPlaylist = false
    @State private var showHostQRCode = false
    @State private var showJoinQRScanner = false
    @State private var showRoomInfo = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuxBattleBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if let state = store.roomState {
                            inRoomContent(state)
                        } else {
                            homeContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 40)
                }

                if let toast = store.toastMessage {
                    VStack {
                        Spacer()
                        AuxToastView(message: toast)
                            .padding(.bottom, 28)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                                    if store.toastMessage == toast {
                                        store.toastMessage = nil
                                    }
                                }
                            }
                    }
                }
            }
            .navigationTitle("Aux Battle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.roomState == nil {
                        if homeStep == .landing {
                            Button {
                                AuxBattleHaptics.impact(.light)
                                exitGame()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        } else {
                            Button {
                                homeStep = .landing
                                store.clearError()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    if store.roomState != nil {
                        Button {
                            showLeaveAlert = true
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Leave")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if store.roomState != nil {
                        Button {
                            showRoomInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .accessibilityLabel("Game info")
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .interactiveDismissDisabled(true)
        .alert("Leave Aux Battle?", isPresented: $showLeaveAlert) {
            Button("Stay", role: .cancel) {}
            Button("Leave", role: .destructive) {
                Task {
                    await store.leaveRoom()
                    exitGame()
                }
            }
        } message: {
            Text("You won't be able to rejoin this game until it ends.")
        }
        .sheet(isPresented: $showHostSettings) {
            if let room = store.roomState?.room {
                AuxBattleHostSettingsView(store: store, room: room)
            }
        }
        .sheet(isPresented: $showSongSearch) {
            if let source = store.roomState?.room.songSource {
                AuxBattleSongSearchView(songSource: source) { pick in
                    selectedPick = pick
                }
            }
        }
        .fullScreenCover(item: $selectedPick) { pick in
            if let seconds = store.roomState?.room.snippetLengthSeconds {
                AuxBattleSnippetPickerView(
                    store: store,
                    snippetPlayer: store.snippetPlayer,
                    pick: pick,
                    snippetLengthSeconds: seconds,
                    onSuccess: {
                        selectedPick = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showWinnerAddToPlaylist) {
            if let trackId = store.roomState?.winnerSubmission?.nicheTrackIdForLibrary {
                AddToPlaylistSheet(trackId: trackId)
            }
        }
        .sheet(isPresented: $showHostQRCode) {
            if let code = store.roomState?.room.code {
                AuxBattleQRCodeSheet(code: code)
            }
        }
        .sheet(isPresented: $showRoomInfo) {
            AuxBattleRoomInfoSheet(
                store: store,
                currentUserId: session.currentUser?.id
            )
        }
        .fullScreenCover(isPresented: $showJoinQRScanner) {
            AuxBattleQRScannerView { code in
                joinWithScannedCode(code)
            }
        }
        .onAppear {
            store.setCurrentUserId(session.currentUser?.id)
            stopAllAppMedia()
        }
        .onDisappear {
            store.snippetPlayer.stop()
        }
    }

    // MARK: - Home

    @ViewBuilder
    private var homeContent: some View {
        switch homeStep {
        case .landing:
            landingContent
        case .host:
            hostSetupContent
        case .join:
            joinContent
        }
    }

    private var landingContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 80)

            VStack(spacing: 12) {
                Text("Pass the aux")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Battle with friends over who has the best song for the prompt.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textSecondaryColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 48)

            VStack(spacing: 12) {
                AuxPrimaryButton(title: "Host a game") {
                    homeStep = .host
                }

                AuxSecondaryButton(title: "Join with code") {
                    homeStep = .join
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var hostSetupContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Host a game")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text("Set a prompt and game rules, then share the room code.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondaryColor)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Prompt")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                TextField("e.g. song for a rainy night drive", text: $createPrompt, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 16) {
                Stepper("Max players: \(createMaxPlayers)", value: $createMaxPlayers, in: 4...8)
                    .foregroundStyle(.white.opacity(0.88))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Snippet length")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Picker("Snippet", selection: $createSnippetLength) {
                        Text("5 sec").tag(5)
                        Text("10 sec").tag(10)
                        Text("15 sec").tag(15)
                        Text("20 sec").tag(20)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Song source")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Picker("Source", selection: $createSongSource) {
                        ForEach(AuxSongSource.allCases, id: \.self) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                }
            }

            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
            }

            AuxPrimaryButton(
                title: "Create game",
                isLoading: store.isLoading,
                disabled: createPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                Task {
                    let ok = await store.createRoom(
                        prompt: createPrompt,
                        maxPlayers: createMaxPlayers,
                        snippetLengthSeconds: createSnippetLength,
                        songSource: createSongSource
                    )
                    if ok {
                        AuxBattleHaptics.success()
                        homeStep = .landing
                    } else {
                        AuxBattleHaptics.error()
                    }
                }
            }
        }
    }

    private var joinContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Join a game")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text("Enter the 6-character code from your host.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondaryColor)
            }

            TextField("Room code", text: $joinCode)
                .multilineTextAlignment(.center)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .tracking(4)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.vertical, 18)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
                .onChange(of: joinCode) { _, newValue in
                    joinCode = AuxRoomCode.normalize(newValue)
                }

            AuxSmallCodeActionButton(title: "Scan QR code", systemImage: "qrcode.viewfinder") {
                showJoinQRScanner = true
            }
            .frame(maxWidth: .infinity)

            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
            }

            AuxPrimaryButton(
                title: "Join",
                isLoading: store.isLoading,
                disabled: joinCode.count < 4
            ) {
                Task {
                    let ok = await store.joinRoom(code: joinCode)
                    if ok {
                        AuxBattleHaptics.success()
                        homeStep = .landing
                        joinCode = ""
                    } else {
                        AuxBattleHaptics.error()
                    }
                }
            }
        }
    }

    // MARK: - In room

    @ViewBuilder
    private func inRoomContent(_ state: AuxRoomState) -> some View {
        let phase = state.phase(currentUserId: session.currentUser?.id)
        let isHost = state.isHost(userId: session.currentUser?.id)

        switch phase {
        case .home:
            landingContent
        case .lobby:
            lobbyView(state, isHost: isHost)
        case .submitting:
            submittingView(state, isHost: isHost)
        case .bracket:
            bracketView(state, isHost: isHost)
        case .matchup:
            matchupView(state, isHost: isHost)
        case .voting:
            votingView(state, isHost: isHost)
        case .finished:
            finishedView(state, isHost: isHost)
        }

        if let error = store.lastError {
            Text(error)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.red.opacity(0.85))
        }
    }

    private func lobbyView(_ state: AuxRoomState, isHost: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            AuxRoomCodeDisplay(
                code: state.room.code,
                showCopy: true,
                showQR: isHost,
                onCopy: { copyRoomCode(state.room.code) },
                onShowQR: { showHostQRCode = true }
            )

            if let prompt = state.room.prompt {
                AuxPromptText(prompt: prompt)
            }

            if isHost {
                Button("Edit settings") {
                    showHostSettings = true
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentColor)
            }

            AuxSection(title: "Players · \(state.meta?.playerCount ?? state.players.count)/\(state.room.maxPlayers)") {
                VStack(spacing: 8) {
                    ForEach(state.players) { player in
                        AuxPlayerRow(player: player)
                    }
                }
            }

            if isHost {
                AuxPrimaryButton(
                    title: "Start game",
                    isLoading: store.isSubmitting,
                    disabled: (state.meta?.playerCount ?? state.players.count) < 2
                ) {
                    Task {
                        if await store.startSubmissions() { AuxBattleHaptics.success() }
                    }
                }
            } else {
                Text("Waiting for host to start…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondaryColor)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func submittingView(_ state: AuxRoomState, isHost: Bool) -> some View {
        let me = state.myPlayer(userId: session.currentUser?.id)

        return VStack(alignment: .leading, spacing: 24) {
            if let prompt = state.room.prompt {
                AuxPromptText(prompt: prompt)
            }

            AuxSection(title: "Players") {
                VStack(spacing: 8) {
                    ForEach(state.players) { player in
                        AuxPlayerRow(player: player, showSubmissionStatus: true)
                    }
                }
            }

            if me?.hasSubmitted != true {
                AuxSection(title: "Your pick") {
                    Text("Find a song and choose a \(state.room.snippetLengthSeconds)-second snippet.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondaryColor)

                    AuxPrimaryButton(title: "Search songs", isLoading: store.isSubmitting) {
                        showSongSearch = true
                    }
                }
            } else {
                AuxSection(title: "Your pick") {
                    if case .full(let submission)? = me?.submission {
                        AuxSongCard(submission: submission)
                    } else {
                        Label("Locked in", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x3DDC97))
                    }
                }
            }

            if isHost {
                AuxPrimaryButton(
                    title: "Create bracket",
                    isLoading: store.isSubmitting,
                    disabled: state.meta?.allSubmitted != true
                ) {
                    Task {
                        if await store.createBracket() { AuxBattleHaptics.success() }
                    }
                }
            } else if state.meta?.allSubmitted == true {
                Text("Everyone locked in — waiting for host…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondaryColor)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func bracketView(_ state: AuxRoomState, isHost: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if let prompt = state.room.prompt {
                AuxPromptText(prompt: prompt)
            }

            AuxSection(title: "Bracket") {
                VStack(spacing: 8) {
                    ForEach(state.bracket?.matchups ?? []) { matchup in
                        bracketRow(matchup, currentId: state.room.currentMatchupId)
                    }
                }
            }

            if isHost, state.room.currentMatchupId == nil {
                let hasPending = state.nextPendingMatchup() != nil
                AuxPrimaryButton(
                    title: hasPending ? "Start next matchup" : "Start bracket",
                    isLoading: store.isSubmitting,
                    disabled: !hasPending
                ) {
                    Task {
                        if await store.startBracket() { AuxBattleHaptics.success() }
                    }
                }
            } else if !isHost, state.room.currentMatchupId == nil {
                Text("Waiting for host…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondaryColor)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func matchupView(_ state: AuxRoomState, isHost: Bool) -> some View {
        let matchup = state.resolvedCurrentMatchup ?? state.nextPendingMatchup()
        let player = store.snippetPlayer

        return VStack(alignment: .leading, spacing: 24) {
            AuxStageTitle(title: "Matchup")

            AuxPlaybackStatusView(
                countdown: player.countdown,
                isPlaying: player.isPlaying
            )

            if let matchup {
                let displayA = matchup.displayForSide(.a)
                let displayB = matchup.displayForSide(.b)
                let showingSingleSong = matchup.status == .playingA || matchup.status == .playingB

                if showingSingleSong {
                    let display = matchup.status == .playingA ? displayA : displayB
                    AuxSongCard(
                        display: display,
                        style: .featured,
                        isActive: true
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        AuxSongCard(
                            display: displayA,
                            isActive: player.activeSide == "a"
                        )

                        Text("vs")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondaryColor)
                            .padding(.top, 72)

                        AuxSongCard(
                            display: displayB,
                            isActive: player.activeSide == "b"
                        )
                    }
                }

                Text(matchupStatusLabel(matchup.status))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondaryColor)
                    .frame(maxWidth: .infinity)

                if isHost {
                    hostMatchupControls(matchup)
                } else {
                    Text(guestMatchupStatusLabel(matchup.status))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondaryColor)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func votingView(_ state: AuxRoomState, isHost: Bool) -> some View {
        let matchup = state.resolvedCurrentMatchup

        return VStack(alignment: .leading, spacing: 24) {
            AuxStageTitle(title: "Vote")

            Text("Pick the song that fits the prompt best.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondaryColor)

            if let matchup {
                let displayA = matchup.displayForSide(.a)
                let displayB = matchup.displayForSide(.b)

                HStack(alignment: .top, spacing: 10) {
                    AuxSongCard(
                        display: displayA,
                        isActive: matchup.myVote == displayA.submissionId,
                        onTap: matchup.myVote == nil ? {
                            vote(for: matchup, submissionId: displayA.submissionId)
                        } : nil
                    )

                    Text("vs")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondaryColor)
                        .padding(.top, 72)

                    AuxSongCard(
                        display: displayB,
                        isActive: matchup.myVote == displayB.submissionId,
                        onTap: matchup.myVote == nil ? {
                            vote(for: matchup, submissionId: displayB.submissionId)
                        } : nil
                    )
                }

                if matchup.myVote != nil {
                    Label("Vote submitted", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x3DDC97))
                        .frame(maxWidth: .infinity)
                }

                if isHost {
                    AuxPrimaryButton(title: "Reveal results", isLoading: store.isSubmitting) {
                        Task {
                            if await store.revealMatchup(matchupId: matchup.id) {
                                AuxBattleHaptics.success()
                            }
                        }
                    }
                } else {
                    Text("Waiting for host to reveal…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondaryColor)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func finishedView(_ state: AuxRoomState, isHost: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 20) {
                AuxStageTitle(title: "Winner")
                    .frame(maxWidth: .infinity)

                if let winner = state.winnerSubmission {
                    AuxSongCard(submission: winner, style: .featured, isWinner: true)
                        .frame(maxWidth: .infinity)

                    if let trackId = winner.nicheTrackIdForLibrary {
                        HStack(spacing: 10) {
                            Button {
                                Task { await toggleWinnerLike(trackId: trackId) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: winnerIsLiked ? "heart.fill" : "heart")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(winnerIsLiked ? Theme.accentColor : .white.opacity(0.88))

                                    Text(winnerIsLiked ? "Liked" : "Like")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.92))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.07), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(winnerLikeBusy)

                            Button {
                                showWinnerAddToPlaylist = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "text.badge.plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.88))

                                    Text("Playlist")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.92))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.07), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if let profile = state.winnerProfile {
                        VStack(spacing: 10) {
                            Text("Submitted by")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textSecondaryColor)

                            HStack(spacing: 12) {
                                AuxAvatarView(profile: profile, size: 52)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.displayLabel)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.white)

                                    if let username = profile.username {
                                        Text("@\(username)")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Theme.textSecondaryColor)
                                    }
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            AuxSection(title: "Final bracket") {
                VStack(spacing: 8) {
                    ForEach(state.bracket?.matchups ?? []) { matchup in
                        bracketRow(matchup, currentId: nil)
                    }
                }
            }

            AuxPrimaryButton(title: "Play again", isLoading: store.isSubmitting) {
                Task {
                    if await store.playAgain() { AuxBattleHaptics.success() }
                }
            }

            if isHost {
                AuxSecondaryButton(title: "Start rematch") {
                    Task {
                        if await store.createRematch() { AuxBattleHaptics.success() }
                    }
                }
            }

            if let count = state.playAgain?.count, count > 0 {
                Text("\(count) ready for rematch")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondaryColor)
                    .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: state.winnerSubmission?.id) { _, _ in
            winnerIsLiked = false
            winnerLikeBusy = false
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func hostMatchupControls(_ matchup: AuxBattleMatchup) -> some View {
        switch matchup.status {
        case .pending:
            AuxPrimaryButton(title: "Play song A", isLoading: store.isSubmitting) {
                Task { _ = await store.startMatchupA(matchupId: matchup.id) }
            }
        case .playingA:
            AuxPrimaryButton(title: "Play song B", isLoading: store.isSubmitting) {
                Task { _ = await store.startMatchupB(matchupId: matchup.id) }
            }
        case .playingB:
            AuxPrimaryButton(title: "Start voting", isLoading: store.isSubmitting) {
                Task { _ = await store.startVoting(matchupId: matchup.id) }
            }
        default:
            EmptyView()
        }
    }

    private func bracketRow(_ matchup: AuxBattleMatchup, currentId: String?) -> some View {
        let label: String
        if matchup.status == .finished {
            let a = matchup.submissionA?.trackName ?? "—"
            let b = matchup.submissionB?.trackName ?? "—"
            label = "\(a) vs \(b)"
        } else {
            label = matchup.bracketLabel
        }
        let isCurrent = matchup.id == currentId

        return HStack {
            Text("R\(matchup.roundNumber) · \(label)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.72))
                .lineLimit(1)
            Spacer()
            Text(matchup.status.rawValue.replacingOccurrences(of: "_", with: " "))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondaryColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.accentColor.opacity(0.5), lineWidth: 1)
            }
        }
    }

    private func vote(for matchup: AuxBattleMatchup, submissionId: String?) {
        guard let submissionId else { return }
        AuxBattleHaptics.impact(.medium)
        Task {
            if await store.vote(matchupId: matchup.id, submissionId: submissionId) {
                AuxBattleHaptics.success()
            }
        }
    }

    private func toggleWinnerLike(trackId: String) async {
        guard !winnerLikeBusy else { return }
        winnerLikeBusy = true
        let next = !winnerIsLiked
        winnerIsLiked = next
        AuxBattleHaptics.impact(.light)

        do {
            let endpoint = next ? Endpoints.likeNicheSong(id: trackId) : Endpoints.unlikeNicheSong(id: trackId)
            let _: MusicShareResponse = try await APIClient.shared.request(endpoint, method: .post)
        } catch {
            winnerIsLiked = !next
            store.toastMessage = error.localizedDescription
        }

        winnerLikeBusy = false
    }

    private func copyRoomCode(_ code: String) {
        AuxRoomCode.copy(code)
        AuxBattleHaptics.success()
        store.toastMessage = "Code copied"
    }

    private func joinWithScannedCode(_ code: String) {
        let normalized = AuxRoomCode.normalize(code)
        guard normalized.count >= 4 else {
            store.toastMessage = "Invalid QR code"
            return
        }

        joinCode = normalized
        Task {
            let ok = await store.joinRoom(code: normalized)
            if ok {
                AuxBattleHaptics.success()
                homeStep = .landing
                joinCode = ""
            } else {
                AuxBattleHaptics.error()
            }
        }
    }

    private func guestMatchupStatusLabel(_ status: AuxMatchupStatus) -> String {
        switch status {
        case .pending: return "Waiting for host to play song A…"
        case .playingA: return "Listen to song A…"
        case .playingB: return "Listen to song B…"
        case .voting, .finished: return ""
        }
    }

    private func matchupStatusLabel(_ status: AuxMatchupStatus) -> String {
        switch status {
        case .pending: return "Ready to play song A"
        case .playingA: return "Now playing — Song A"
        case .playingB: return "Now playing — Song B"
        case .voting: return "Voting open"
        case .finished: return "Matchup finished"
        }
    }

    private func stopAllAppMedia() {
        musicPlayer.stop(clearQueue: true, clearHistory: true)
        FeedPlayerCache.shared.stopAll()
    }

    private func exitGame() {
        homeStep = .landing
        store.snippetPlayer.stop()
        onDismiss?()
    }
}

extension AuxSongPickSource: Identifiable {
    var id: String {
        switch self {
        case .niche(let track): return "niche-\(track.id)"
        case .apple(_, let appleSourceId, _, _, _, _, _): return "apple-\(appleSourceId)"
        }
    }
}
