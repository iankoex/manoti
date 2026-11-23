//
//  EmptyStateView.swift
//  Modifiers
//

import SwiftUI

public struct EmptyStateView: View {
    private let symbolName: String
    private let title: String
    private let message: String

    public init(symbolName: String, title: String, message: String) {
        self.symbolName = symbolName
        self.title = title
        self.message = message
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbolName)
        } description: {
            Text(message)
        }
    }
}
