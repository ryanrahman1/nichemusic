//
//  ProfileUsernameLink.swift
//  Niche Music
//

import SwiftUI

struct ProfileUsernameLink<Label: View>: View {
    let username: String
    @ViewBuilder var label: () -> Label

    @Environment(\.sheetExternalNavigation) private var sheetExternalNavigation

    var body: some View {
        if let sheetExternalNavigation {
            Button {
                sheetExternalNavigation.dismissAndOpenProfile(username)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                OtherProfileView(username: username)
                    .toolbarVisibility(.hidden, for: .tabBar)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        }
    }
}
