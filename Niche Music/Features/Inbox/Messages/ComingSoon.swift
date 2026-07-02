//
//  ComingSoon.swift
//  Niche Music
//

import SwiftUI

enum ComingSoon {
    static let title = "Coming Soon"
    static let message = "This feature isn't available yet."
}

struct ComingSoonAlertModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert(ComingSoon.title, isPresented: $isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ComingSoon.message)
        }
    }
}

extension View {
    func comingSoonAlert(isPresented: Binding<Bool>) -> some View {
        modifier(ComingSoonAlertModifier(isPresented: isPresented))
    }
}
