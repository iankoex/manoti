//
//  LedgerEntry.swift
//  AppModels
//

import Foundation
import SwiftData

@Model
public final class LedgerEntry {
    public var id: UUID = UUID()
    public var occurredAt: Date = Date()
    public var createdAt: Date = Date()
    public var kindRaw: String = LedgerEntryKind.expense.rawValue
    public var amountMinor: Int64 = 0
    public var feeMinor: Int64 = 0
    public var currencyCode: String = CurrencyCatalog.defaultCurrency.code
    public var account: Account?
    public var payee: String = ""
    public var note: String = ""
    public var sourceRaw: String = LedgerEntrySource.manual.rawValue
    public var externalRef: String = ""
    public var counterpartRef: String = ""
    public var rawMessage: String = ""
    public var messageSender: String = ""
    public var balanceAfterMinor: Int64?
    public var statusRaw: String = LedgerEntryStatus.confirmed.rawValue
    public var confidence: Double = 1
    public var dedupeHash: String = ""
    /// Sender + digit-masked template, computed at ingest so a message can still be
    /// learned from when raw text is not kept.
    public var ingestFingerprint: String = ""
    public var isSoftDeleted: Bool = false

    /// The payee exactly as parsed, never edited. A late confirmation may replace `payee`
    /// only while it still equals this value, so a manual rename is never stomped.
    public var ingestPayee: String = ""
    /// The biller or aggregator behind a payment, e.g. "Family Bank Pesa Pap".
    public var channelName: String = ""
    public var confirmationRef: String = ""
    public var confirmationSender: String = ""
    public var confirmedAt: Date?
    /// Kept only when raw messages are retained.
    public var confirmationText: String = ""
    /// True when this entry was created from a bank receipt before its transaction message.
    public var isConfirmationOnly: Bool = false

    public var transfer: Transfer?
    public var loan: Loan?

    @Relationship(deleteRule: .cascade, inverse: \LedgerEntryLine.entry)
    public var lines: [LedgerEntryLine]?

    @Relationship(deleteRule: .nullify, inverse: \InvestmentCashFlow.ledgerEntry)
    public var investmentCashFlow: InvestmentCashFlow?

    /// Lines in display order. Every expense and income has at least one; other kinds have none.
    public var orderedLines: [LedgerEntryLine] {
        (lines ?? []).sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }

            return lhs.createdAt < rhs.createdAt
        }
    }

    /// The line that represents the entry in lists, icons and titles.
    public var primaryCategory: SpendingCategory? {
        orderedLines.first?.category
    }

    /// Every distinct tag across the entry's lines, ordered by name.
    public var tagList: [Tag] {
        var seen: Set<UUID> = []
        var tags: [Tag] = []

        for tag in orderedLines.flatMap(\.tagList) where seen.insert(tag.id).inserted {
            tags.append(tag)
        }

        return tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public init(
        kind: LedgerEntryKind,
        amountMinor: Int64,
        feeMinor: Int64 = 0,
        currencyCode: String = CurrencyCatalog.defaultCurrency.code,
        occurredAt: Date = Date(),
        payee: String = "",
        note: String = "",
        source: LedgerEntrySource = .manual
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.amountMinor = amountMinor
        self.feeMinor = feeMinor
        self.currencyCode = currencyCode
        self.occurredAt = occurredAt
        self.payee = payee
        self.note = note
        self.sourceRaw = source.rawValue
        self.createdAt = Date()
    }

    public var kind: LedgerEntryKind {
        get { LedgerEntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public var status: LedgerEntryStatus {
        get { LedgerEntryStatus(rawValue: statusRaw) ?? .confirmed }
        set { statusRaw = newValue.rawValue }
    }

    public var source: LedgerEntrySource {
        get { LedgerEntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var currency: Currency {
        CurrencyCatalog.currency(for: currencyCode)
    }

    public var amount: Money {
        Money(minorUnits: amountMinor, currency: currency)
    }

    public var fee: Money {
        Money(minorUnits: feeMinor, currency: currency)
    }

    /// The signed effect this entry has on its account's balance.
    ///
    /// `.openingBalance` and `.adjustment` store their own sign in `amountMinor`, so they
    /// are added as-is; every other kind is normalised from its direction and fee.
    public var signedAmountMinor: Int64 {
        switch kind {
            case .expense, .transferOut, .loanOut, .loanRepaymentOut, .investmentOut:
                -(amountMinor + feeMinor)
            case .income, .transferIn, .loanIn, .loanRepaymentIn, .investmentIn, .investmentIncome:
                amountMinor - feeMinor
            case .openingBalance, .adjustment:
                amountMinor
        }
    }

    public var isPosted: Bool {
        !isSoftDeleted && status != .ignored
    }

    /// True while the payee still reflects what the message said, so a later message may
    /// replace it with a better name. False once the user has renamed the entry.
    public var payeeIsUnedited: Bool {
        payee.isEmpty || (!ingestPayee.isEmpty && payee == ingestPayee)
    }
}
