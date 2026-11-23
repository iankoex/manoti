//
//  IngestOutbox.swift
//  AppServices
//

import AppModels
import Foundation

/// One message durably parked before the store is opened.
nonisolated public struct OutboxMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let sender: String?
    public let receivedAt: Date
    public let dedupeHash: String
    public let enqueuedAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        sender: String?,
        receivedAt: Date,
        dedupeHash: String,
        enqueuedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.sender = sender
        self.receivedAt = receivedAt
        self.dedupeHash = dedupeHash
        self.enqueuedAt = enqueuedAt
    }
}

/// A crash-safe inbox for messages arriving from Shortcuts.
///
/// The intent writes the receipt here before touching SwiftData, so a terminated intent,
/// a store-open failure, or a timeout cannot lose the bank message. Every intent and every
/// launch drains it. Deduplication makes replay safe.
nonisolated public struct IngestOutbox: Sendable {
    public static let folderName = "ingest-outbox"

    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    public static var defaultDirectory: URL {
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.iankoex.manoti"
        ) {
            return group.appendingPathComponent(folderName, isDirectory: true)
        }

        return FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    public func enqueue(_ message: OutboxMessage) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(message)
        try data.write(to: url(for: message.id), options: .atomic)
    }

    public func pending() throws -> [OutboxMessage] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        return
            files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? JSONDecoder().decode(OutboxMessage.self, from: data)
            }
            .sorted { $0.enqueuedAt < $1.enqueuedAt }
    }

    public func remove(_ message: OutboxMessage) throws {
        try? FileManager.default.removeItem(at: url(for: message.id))
    }

    public func count() -> Int {
        (try? pending().count) ?? 0
    }

    /// Replays every parked message. A message is removed only after the ingest call
    /// returns, so a store failure leaves it for the next attempt.
    @discardableResult
    @MainActor
    public func drain(into ingest: IngestService) throws -> Int {
        var processed = 0

        for message in try pending() {
            do {
                _ = try ingest.ingest(
                    text: message.text,
                    sender: message.sender,
                    receivedAt: message.receivedAt
                )
                try remove(message)
                processed += 1
            } catch {
                // Keep it: the store may be temporarily unavailable.
                continue
            }
        }

        return processed
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
