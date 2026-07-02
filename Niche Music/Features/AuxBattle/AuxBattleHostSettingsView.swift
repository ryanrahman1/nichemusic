//
//  AuxBattleHostSettingsView.swift
//  Niche Music
//

import SwiftUI

struct AuxBattleHostSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AuxBattleStore

    @State private var prompt: String
    @State private var maxPlayers: Int
    @State private var snippetLength: Int
    @State private var songSource: AuxSongSource

    private let snippetOptions = [5, 10, 15, 20]
    private let playerOptions = Array(4...8)

    init(store: AuxBattleStore, room: AuxBattleRoom) {
        self.store = store
        _prompt = State(initialValue: room.prompt ?? "")
        _maxPlayers = State(initialValue: room.maxPlayers)
        _snippetLength = State(initialValue: room.snippetLengthSeconds)
        _songSource = State(initialValue: room.songSource)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField("Song prompt", text: $prompt, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Players") {
                    Picker("Max players", selection: $maxPlayers) {
                        ForEach(playerOptions, id: \.self) { count in
                            Text("\(count) players").tag(count)
                        }
                    }
                }

                Section("Snippet length") {
                    Picker("Seconds", selection: $snippetLength) {
                        ForEach(snippetOptions, id: \.self) { seconds in
                            Text("\(seconds)s").tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Song source") {
                    Picker("Source", selection: $songSource) {
                        ForEach(AuxSongSource.allCases, id: \.self) { source in
                            Text(source.label).tag(source)
                        }
                    }
                }

                if let error = store.lastError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Game settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(store.isSubmitting || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        let current = store.roomState?.room
        let promptChanged = trimmedPrompt != current?.prompt
        let playersChanged = maxPlayers != current?.maxPlayers
        let snippetChanged = snippetLength != current?.snippetLengthSeconds
        let sourceChanged = songSource != current?.songSource

        guard promptChanged || playersChanged || snippetChanged || sourceChanged else {
            dismiss()
            return
        }

        let success = await store.updateSettings(
            prompt: promptChanged ? trimmedPrompt : nil,
            maxPlayers: playersChanged ? maxPlayers : nil,
            snippetLengthSeconds: snippetChanged ? snippetLength : nil,
            songSource: sourceChanged ? songSource : nil
        )

        if success {
            AuxBattleHaptics.success()
            dismiss()
        } else {
            AuxBattleHaptics.error()
        }
    }
}
