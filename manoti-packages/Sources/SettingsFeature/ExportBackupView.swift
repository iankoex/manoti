//
//  ExportBackupView.swift
//  SettingsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI
import UniformTypeIdentifiers

/// Writes a JSON backup or CSV, and merges a backup back in by UUID.
struct ExportBackupView: View {
    @Environment(ExportService.self) private var exportService
    @Environment(PrivacyService.self) private var privacyService

    @State private var isExportingBackup = false
    @State private var isExportingCSV = false
    @State private var isImporting = false
    @State private var isImportingReplace = false
    @State private var isConfirmingReplace = false
    @State private var exportDocument: ManotiExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = "manoti-backup"
    @State private var pendingRestoreData: Data?
    @State private var pendingReplaceData: Data?
    @State private var restorePreview = ""
    @State private var replacePreview = ""
    @State private var isConfirmingRestore = false
    @State private var restoreMessage: String?
    @State private var errorMessage: String?
    @State private var lastBackupAt: Date?

    var body: some View {
        Form {
            Section {
                LabeledContent("Last backup") {
                    Text(lastBackupText)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    exportBackup()
                } label: {
                    Label("Export JSON backup", systemImage: "doc.badge.arrow.up")
                }

                Button {
                    exportCSV()
                } label: {
                    Label("Export transactions CSV", systemImage: "tablecells")
                }
            } header: {
                Text("Export")
            } footer: {
                Text(
                    "A backup contains all of your Manoti data, including amounts, names and messages. Store it somewhere private; Manoti does not upload it."
                )
            }

            Section {
                Button {
                    isImporting = true
                } label: {
                    Label("Restore from backup", systemImage: "arrow.down.doc")
                }
            } header: {
                Text("Restore")
            } footer: {
                Text(
                    "Restoring merges rows by ID: existing rows are updated, missing rows are added, and nothing is deleted. A backup from another schema version is refused."
                )
            }

            Section {
                Button(role: .destructive) {
                    isImportingReplace = true
                } label: {
                    Label("Replace everything from a backup", systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text("Replace")
            } footer: {
                Text(
                    "This deletes the current accounts, entries, categories, budgets, loans and investments, then restores the chosen file. Settings and the last-backup date stay on this device. This cannot be undone."
                )
            }
        }
        .navigationTitle("Export & backup")
        .fileExporter(
            isPresented: $isExportingBackup,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename,
            onCompletion: finishedBackupExport
        )
        .fileExporter(
            isPresented: $isExportingCSV,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename,
            onCompletion: finishedCSVExport
        )
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importedBackup
        )
        .fileImporter(
            isPresented: $isImportingReplace,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importedReplaceBackup
        )
        .alert("Restore this backup?", isPresented: $isConfirmingRestore) {
            Button("Cancel", role: .cancel) {
                pendingRestoreData = nil
            }
            Button("Restore", action: restore)
        } message: {
            Text("\(restorePreview)\n\nExisting rows are updated by ID; nothing is deleted.")
        }
        .alert("Replace everything?", isPresented: $isConfirmingReplace) {
            Button("Cancel", role: .cancel) {
                pendingReplaceData = nil
            }
            Button("Replace", role: .destructive, action: replace)
        } message: {
            Text(
                "\(replacePreview)\n\nThis deletes the current data and cannot be undone. Settings and the last-backup date stay."
            )
        }
        .alert(
            "Restore complete",
            isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
        .alert(
            "Could not export or restore",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onManotiDataChange { lastBackupAt = exportService.lastBackupAt() }
    }

    private var lastBackupText: String {
        guard let lastBackupAt else {
            return "Never"
        }

        return lastBackupAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func exportBackup() {
        do {
            exportDocument = ManotiExportDocument(data: try exportService.backupData())
            exportContentType = .json
            exportFilename = exportService.suggestedBackupFilename()
            isExportingBackup = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportCSV() {
        do {
            let data = try exportService.transactionsCSVData()
            exportDocument = ManotiExportDocument(data: data)
            exportContentType = .commaSeparatedText
            exportFilename = exportService.suggestedCSVFilename()
            isExportingCSV = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishedBackupExport(_ result: Result<URL, Error>) {
        switch result {
            case .success:
                do {
                    try exportService.markBackupCompleted()
                    lastBackupAt = exportService.lastBackupAt()
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                if !isUserCancellation(error) {
                    errorMessage = error.localizedDescription
                }
        }
    }

    private func finishedCSVExport(_ result: Result<URL, Error>) {
        if case .failure(let error) = result, !isUserCancellation(error) {
            errorMessage = error.localizedDescription
        }
    }

    private func importedBackup(_ result: Result<[URL], Error>) {
        switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }

                readBackup(at: url) { data, preview in
                    pendingRestoreData = data
                    restorePreview = preview
                    isConfirmingRestore = true
                }

            case .failure(let error):
                if !isUserCancellation(error) {
                    errorMessage = error.localizedDescription
                }
        }
    }

    private func importedReplaceBackup(_ result: Result<[URL], Error>) {
        switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }

                readBackup(at: url) { data, preview in
                    pendingReplaceData = data
                    replacePreview = preview
                    isConfirmingReplace = true
                }

            case .failure(let error):
                if !isUserCancellation(error) {
                    errorMessage = error.localizedDescription
                }
        }
    }

    private func readBackup(
        at url: URL,
        completion: (Data, String) -> Void
    ) {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            completion(data, try exportService.backupSummary(data: data))
        } catch {
            errorMessage = restoreErrorText(error)
        }
    }

    private func restore() {
        guard let data = pendingRestoreData else {
            return
        }

        do {
            let summary = try exportService.restore(data: data)
            restoreMessage =
                "\(summary.inserted) added · \(summary.updated) updated"
                + (summary.skipped > 0 ? " · \(summary.skipped) links skipped" : "")
            pendingRestoreData = nil
            privacyService.applyLaunchState()
        } catch {
            errorMessage = restoreErrorText(error)
        }
    }

    private func replace() {
        guard let data = pendingReplaceData else {
            return
        }

        do {
            let summary = try exportService.restore(data: data, mode: .replace)
            restoreMessage =
                "Replaced · \(summary.inserted) restored"
                + (summary.skipped > 0 ? " · \(summary.skipped) links skipped" : "")
            pendingReplaceData = nil
            privacyService.applyLaunchState()
        } catch {
            errorMessage = restoreErrorText(error)
        }
    }

    private func restoreErrorText(_ error: Error) -> String {
        guard let exportError = error as? ExportError else {
            return error.localizedDescription
        }

        switch exportError {
            case .unsupportedVersion(let version):
                return "This backup uses schema version \(version), which this version of Manoti cannot read."
            case .decodeFailed:
                return "This file is not a Manoti JSON backup."
            case .checksumMismatch:
                return "This backup is damaged or was edited. Restore a fresh export."
            case .invalidCSV:
                return "The backup could not be converted."
        }
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        (error as? CocoaError)?.code == .userCancelled
    }
}

/// A plain data document used for both JSON and CSV exports.
struct ManotiExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json, .commaSeparatedText]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
