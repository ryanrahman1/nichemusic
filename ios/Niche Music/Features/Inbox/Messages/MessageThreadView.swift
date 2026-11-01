//
//  MessageThreadView.swift
//  Niche Music
//
//  Created by Ryan Rahman on 6/9/26.
//

import SwiftUI
import Kingfisher
import Combine
import UIKit

struct MessageThreadView: View {
    let chat: ChatPreview

    @EnvironmentObject private var messagesStore: MessagesStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    @State private var draft = ""
    @State private var showAttachMenu = false
    @State private var showChatInfo = false
    @State private var showComingSoon = false
    @State private var pendingGifPick = false
    @State private var dragOffset: CGFloat = 0
    @State private var musicShareRoute: MusicShareRoute?
    @State private var profileNavigation: ProfileNavigation?

    // Scroll state
    @State private var scrolledToBottomOnce = false
    // ID of the top-most message before loading older ones, used to restore position
    @State private var anchorBeforePaginate: String?
    @State private var typingStopTask: Task<Void, Never>?

    private var messages: [ChatMessage] {
        _ = messagesStore.threadRevision
        return messagesStore.messages(for: chat.id)
    }

    private var threadItems: [ThreadListItem] {
        MessagesFormatting.threadListItems(
            from: messages,
            isGroup: chat.kind == .group
        )
    }

    private var oldestMessageId: String? { messages.first?.id }
    private var newestMessageId: String? { messages.last?.id }

    private var typingLabel: String? {
        _ = messagesStore.typingRevision
        return messagesStore.typingLabel(for: chat)
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesScroll
            if let typingLabel {
                TypingIndicatorRow(label: typingLabel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            inputBar
        }
        .animation(.easeOut(duration: 0.18), value: typingLabel)
        // Background stays full-bleed; VStack respects keyboard safe area so the
        // layout slides up when the keyboard appears (iMessage-style).
        .background(Theme.backgroundColor.ignoresSafeArea())
        .background(NavigationInteractivePopGuard(disablePop: inputFocused || showAttachMenu))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if chat.kind == .dm {
                    ProfileUsernameLink(username: chat.otherUsername ?? "") {
                        VStack(spacing: 2) {
                            Text(chat.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(chat.subtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { showChatInfo = true } label: {
                        VStack(spacing: 2) {
                            Text(chat.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(chat.subtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Mute notifications") { showComingSoon = true }
                    Button("Search in conversation") { showComingSoon = true }
                    Button("Report chat", role: .destructive) { showComingSoon = true }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.white)
                }
            }
        }
        .tint(.white)
        .toolbarBackground(.hidden)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await messagesStore.loadThread(for: chat) }
        .onDisappear {
            typingStopTask?.cancel()
            messagesStore.stopLocalTyping(in: chat.id)
        }
        .onChange(of: draft) { _, newValue in
            handleDraftTypingChange(newValue)
        }
        .navigationDestination(item: $musicShareRoute) { route in
            musicShareDestination(for: route)
        }
        .navigationDestination(item: $profileNavigation) { nav in
            OtherProfileView(username: nav.username)
                .toolbarVisibility(.hidden, for: .tabBar)
        }
        .comingSoonAlert(isPresented: $showComingSoon)
        .sheet(isPresented: $showAttachMenu) {
            AttachmentMenuSheet(chat: chat, onGifTapped: { pendingGifPick = true })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .environmentObject(messagesStore)
        }
        .onChange(of: pendingGifPick) { _, triggered in
            guard triggered else { return }
            pendingGifPick = false
            Task { await pickGIF() }
        }
        .sheet(isPresented: $showChatInfo) {
            if chat.kind == .dm {
                DMInfoView(chat: chat)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            } else {
                GroupChatInfoView(chat: chat)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: – Scroll

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 7) {
                    // Pagination trigger at top
                    if messagesStore.hasMoreMessages(chat.id) {
                        Color.clear
                            .frame(height: 1)
                            .id("top-trigger")
                            .onAppear {
                                guard !messagesStore.isLoadingOlderMessages(chat.id),
                                      !messagesStore.isLoadingThread(chat.id),
                                      anchorBeforePaginate == nil else { return }
                                anchorBeforePaginate = oldestMessageId
                                Task { await messagesStore.loadOlderMessages(for: chat) }
                            }

                        if messagesStore.isLoadingOlderMessages(chat.id) {
                            ProgressView()
                                .tint(.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                    }

                    ForEach(threadItems) { item in
                        switch item {
                        case .separator(_, let label):
                            MessageTimeSeparator(label: label)

                        case .message(let message, let showSenderLabel):
                            MessageBubbleRow(
                                message: message,
                                showSenderLabel: showSenderLabel,
                                revealTimestamps: dragOffset < -28,
                                onMusicShare: { musicShareRoute = $0 },
                                onProfileShare: { profileNavigation = ProfileNavigation(username: $0) }
                            )
                            .id(message.id)
                        }
                    }

                    // Bottom anchor — always present so scrollTo works even before messages load
                    Color.clear
                        .frame(height: 1)
                        .id("bottom-anchor")
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .offset(x: dragOffset)
            }
            .background(Theme.backgroundColor)
            .scrollDismissesKeyboard(.interactively)
            // Keep scroll pinned at bottom as new messages arrive
            .defaultScrollAnchor(.bottom)
            .onTapGesture { dismissKeyboard() }
            // Fallback: if messages were already in the store when the view
            // appeared, onChange(of: count) never fires — catch it here.
            .onAppear {
                guard !scrolledToBottomOnce, !messages.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
                    scrolledToBottomOnce = true
                }
            }
            .onChange(of: messages.count) { oldCount, newCount in
                guard newCount > 0 else { return }

                if !scrolledToBottomOnce {
                    // First load: jump instantly to bottom with no visible scroll animation
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
                    scrolledToBottomOnce = true
                    return
                }

                // After pagination finishes: instantly restore scroll position so
                // the user never sees the viewport jump.
                if let anchor = anchorBeforePaginate, newCount > oldCount {
                    let capturedAnchor = anchor
                    // Brief delay lets SwiftUI finish inserting & measuring the new rows,
                    // then teleport with zero animation so there is no visible jump.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) {
                            proxy.scrollTo(capturedAnchor, anchor: .top)
                        }
                        anchorBeforePaginate = nil
                    }
                    return
                }

                // New message arrived (sent or received): scroll to bottom
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            // Also scroll to bottom when keyboard appears
            .onChange(of: inputFocused) { _, focused in
                guard focused, let last = messages.last else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: – Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                dismissKeyboard()
                showAttachMenu = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 36, height: 36)
                    .modifier(LiquidCircleGlass())
            }
            .buttonStyle(.plain)

            TextField("Message...", text: $draft, axis: .vertical)
                .focused($inputFocused)
                .lineLimit(1...5)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .modifier(LiquidRoundedGlass(cornerRadius: 20))
                .overlay {
                    if #unavailable(iOS 26.0) {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white.opacity(inputFocused ? 0.22 : 0.10), lineWidth: 1)
                    }
                }

            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(canSend ? Theme.accentColor : .white.opacity(0.28))
                    .frame(width: 36, height: 36)
                    .modifier(LiquidCircleGlass())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(Theme.backgroundColor.opacity(0))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: – Helpers

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var timestampRevealGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      value.translation.width < 0 else { return }
                dismissKeyboard()
                dragOffset = max(value.translation.width, -76)
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    dragOffset = 0
                }
            }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        typingStopTask?.cancel()
        messagesStore.stopLocalTyping(in: chat.id)
        Task { await messagesStore.sendText(in: chat, text: text) }
    }

    private func handleDraftTypingChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        typingStopTask?.cancel()

        guard !trimmed.isEmpty else {
            messagesStore.stopLocalTyping(in: chat.id)
            return
        }

        messagesStore.setLocalTyping(in: chat.id, isTyping: true)

        typingStopTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                messagesStore.stopLocalTyping(in: chat.id)
            }
        }
    }

    private func pickGIF() async {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        // Walk to the top-most presented VC so we don't double-present on top of a sheet
        var presenter = root
        while let next = presenter.presentedViewController { presenter = next }
        guard let result = await GiphyMediaPicker.pickGIF(from: presenter) else { return }
        await messagesStore.sendGif(in: chat, url: result.url, width: result.width, height: result.height)
    }

    private func dismissKeyboard() {
        inputFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    @ViewBuilder
    private func musicShareDestination(for route: MusicShareRoute) -> some View {
        switch route {
        case .appleSong(let sourceId):
            AppleMusicDetailView(sourceId: sourceId).toolbarVisibility(.hidden, for: .tabBar)
        case .nicheSong(let trackId):
            NicheTrackDetailView(trackId: trackId).toolbarVisibility(.hidden, for: .tabBar)
        case .appleAlbum(let sourceId):
            AppleAlbumDetailView(sourceId: sourceId).toolbarVisibility(.hidden, for: .tabBar)
        case .appleArtist(let sourceId):
            AppleArtistDetailView(sourceId: sourceId).toolbarVisibility(.hidden, for: .tabBar)
        }
    }
}

// MARK: – Supporting types

private struct ProfileNavigation: Hashable, Identifiable {
    let username: String
    var id: String { username }
}

private enum MusicShareRoute: Hashable, Identifiable {
    case appleSong(String)
    case nicheSong(String)
    case appleAlbum(String)
    case appleArtist(String)

    var id: String {
        switch self {
        case .appleSong(let s): return "song-apple-\(s)"
        case .nicheSong(let t): return "song-niche-\(t)"
        case .appleAlbum(let s): return "album-\(s)"
        case .appleArtist(let s): return "artist-\(s)"
        }
    }
}

// MARK: – Typing indicator

private struct TypingIndicatorRow: View {
    let label: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TypingDotsView()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 19, style: .continuous))

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

private struct TypingDotsView: View {
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(phase == index ? 0.9 : 0.35))
                    .frame(width: 6, height: 6)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: – Message time separator

private struct MessageTimeSeparator: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
        }
        .padding(.vertical, 10)
    }
}

// MARK: – Message bubble row

private struct MessageBubbleRow: View {
    let message: ChatMessage
    let showSenderLabel: Bool
    let revealTimestamps: Bool
    let onMusicShare: (MusicShareRoute) -> Void
    let onProfileShare: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            if message.isMine {
                Spacer(minLength: 52)
            } else {
                avatar
            }

            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
                if showSenderLabel && !message.isMine {
                    Text(message.senderName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.leading, 4)
                }

                messageBody

                if message.isMine, let receipt = receiptText {
                    Text(receipt)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.trailing, 4)
                }
            }

            if revealTimestamps {
                Text(message.timestamp)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
                    .frame(width: 54, alignment: message.isMine ? .leading : .trailing)
                    .transition(.opacity)
            }

            if !message.isMine {
                Spacer(minLength: 52)
            }
        }
        .animation(.easeOut(duration: 0.14), value: revealTimestamps)
    }

    @ViewBuilder
    private var messageBody: some View {
        if let attachment = message.attachment {
            MessageAttachmentCard(
                attachment: attachment,
                isMine: message.isMine,
                onMusicShare: onMusicShare,
                onProfileShare: onProfileShare
            )
            if let caption = message.caption, !caption.isEmpty {
                textBubble(caption)
            }
        } else if let text = message.text, !text.isEmpty {
            textBubble(text)
        }
    }

    private func textBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                message.isMine ? Theme.accentColor : .white.opacity(0.13),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
    }

    private var avatar: some View {
        Group {
            if let urlString = message.senderAvatarURL, let url = URL(string: urlString) {
                KFImage(url).resizable().scaledToFill()
            } else {
                Circle()
                    .fill(.white.opacity(0.12))
                    .overlay {
                        Text(String(message.senderName.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }

    private var receiptText: String? {
        if message.isSending { return "Sending…" }
        return message.readReceiptLabel
    }
}

// MARK: – Attachment card

private struct MessageAttachmentCard: View {
    private let cardWidth: CGFloat = 280
    private let artworkAspect: CGFloat = 0.85

    let attachment: MessageAttachment
    let isMine: Bool
    let onMusicShare: (MusicShareRoute) -> Void
    let onProfileShare: (String) -> Void

    var body: some View {
        switch attachment.kind {
        case .gif:      gifCard
        case .profile:  profileCard
        case .song, .album, .artist: musicShareCard
        }
    }

    private var shellBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.white.opacity(isMine ? 0.14 : 0.09))
    }

    // MARK: GIF

    private var gifCard: some View {
        Group {
            if let urlString = attachment.gifURL, let url = URL(string: urlString) {
                KFAnimatedImage(url)
                    .scaledToFit()
                    .frame(width: 260, height: gifHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                placeholderArtwork(icon: "sparkles")
                    .frame(width: 260, height: 180)
            }
        }
    }

    private var gifHeight: CGFloat {
        let w = max(CGFloat(attachment.gifWidth ?? 260), 1)
        let h = attachment.gifHeight.map { CGFloat($0) } ?? w
        return min(280, 260 / (w / h))
    }

    // MARK: Music share

    @ViewBuilder
    private var musicShareCard: some View {
        if let route = musicShareRouteValue {
            musicContent
                .contentShape(Rectangle())
                .onTapGesture { onMusicShare(route) }
        } else {
            musicContent
        }
    }

    private var musicShareRouteValue: MusicShareRoute? {
        switch attachment.kind {
        case .song:
            if let sid = attachment.sourceId, !sid.isEmpty { return .appleSong(sid) }
            if let eid = attachment.entityId, !eid.isEmpty { return .nicheSong(eid) }
            return nil
        case .album:
            return attachment.sourceId.flatMap { $0.isEmpty ? nil : .appleAlbum($0) }
        case .artist:
            return attachment.sourceId.flatMap { $0.isEmpty ? nil : .appleArtist($0) }
        default: return nil
        }
    }

    private var musicContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            shareArtwork

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let subtitle = attachment.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(width: cardWidth, alignment: .leading)
        .background(shellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if isMine {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
        }
    }

    // MARK: Profile share

    @ViewBuilder
    private var profileCard: some View {
        let cardView = profileCardContent
        if let username = attachment.username, !username.isEmpty {
            cardView
                .contentShape(Rectangle())
                .onTapGesture { onProfileShare(username) }
        } else {
            cardView
        }
    }

    private var profileCardContent: some View {
        HStack(spacing: 12) {
            profileAvatar

            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = attachment.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: cardWidth, alignment: .leading)
        .background(shellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if isMine {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
        }
    }

    // MARK: Artwork / avatar

    @ViewBuilder
    private var shareArtwork: some View {
        let h = cardWidth * artworkAspect
        if let imageURL = attachment.imageURL,
           let resolved = resolvedAppleArtworkURL(imageURL, size: 480) ?? URL(string: imageURL) {
            KFImage(resolved)
                .resizable()
                .scaledToFill()
                .frame(width: cardWidth, height: h)
                .clipped()
        } else {
            placeholderArtwork(icon: iconName)
                .frame(width: cardWidth, height: h)
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let imageURL = attachment.imageURL, let url = URL(string: imageURL) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.white.opacity(0.45))
                }
        }
    }

    private func placeholderArtwork(icon: String) -> some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
    }

    private var iconName: String {
        switch attachment.kind {
        case .song:    return "music.note"
        case .album:   return "square.stack"
        case .artist:  return "person.crop.circle"
        case .gif:     return "sparkles"
        case .profile: return "person"
        }
    }

}

// MARK: – Glass modifiers

private struct LiquidCircleGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

private struct LiquidRoundedGlass: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

// MARK: – Navigation pop guard

private struct NavigationInteractivePopGuard: UIViewControllerRepresentable {
    var disablePop: Bool

    func makeUIViewController(context: Context) -> PopGuardViewController {
        let vc = PopGuardViewController()
        vc.view.isUserInteractionEnabled = false
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ vc: PopGuardViewController, context: Context) {
        vc.disablePop = disablePop
    }

    final class PopGuardViewController: UIViewController, UIGestureRecognizerDelegate {
        var disablePop = false { didSet { syncPopGesture() } }

        private weak var popGesture: UIGestureRecognizer?
        private weak var previousDelegate: UIGestureRecognizerDelegate?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachIfNeeded(); syncPopGesture()
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attachIfNeeded(); syncPopGesture()
        }
        deinit {
            if popGesture?.delegate === self { popGesture?.delegate = previousDelegate }
        }

        private func attachIfNeeded() {
            guard let nav = navigationController,
                  let gesture = nav.interactivePopGestureRecognizer,
                  popGesture !== gesture else { return }
            if popGesture?.delegate === self { popGesture?.delegate = previousDelegate }
            popGesture = gesture
            previousDelegate = gesture.delegate
            gesture.delegate = self
        }

        private func syncPopGesture() {
            guard let gesture = popGesture ?? navigationController?.interactivePopGestureRecognizer else { return }
            popGesture = gesture
            gesture.isEnabled = !disablePop && (navigationController?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === popGesture else {
                return previousDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
            }
            if disablePop { return false }
            guard let nav = navigationController, nav.viewControllers.count > 1 else { return false }
            // Delegate edge-detection entirely to the system — avoids the overly
            // narrow 24 pt zone that made swipe-back feel broken.
            return previousDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            previousDelegate?.gestureRecognizer?(gestureRecognizer, shouldRecognizeSimultaneouslyWith: other) ?? false
        }
    }
}
