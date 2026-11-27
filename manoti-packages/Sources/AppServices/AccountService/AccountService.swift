//
//  AccountService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum AccountError: Error, Equatable {
    case emptyName
    case duplicateName
    case openingBalanceLocked
    case openingBalanceMissing
    case invalidIdentifier
    case duplicateIdentifier
}

@Observable
nonisolated public final class AccountService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func fetchAccounts(includeArchived: Bool = false) throws -> [Account] {
        var descriptor = FetchDescriptor<Account>(
            sortBy: [SortDescriptor(\Account.sortIndex), SortDescriptor(\Account.name)]
        )

        if !includeArchived {
            descriptor.predicate = #Predicate<Account> { !$0.isArchived }
        }

        return try context.fetch(descriptor)
    }

    @discardableResult
    public func create(
        name: String,
        kind: AccountKind,
        currencyCode: String = CurrencyCatalog.defaultCurrency.code,
        colorHex: String = "#2F80ED",
        symbolName: String = "building.columns",
        ownership: AccountOwnership = .personal,
        openingBalanceMinor: Int64 = 0,
        openedAt: Date = Date()
    ) throws -> Account {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AccountError.emptyName
        }

        let existing = try fetchAccounts(includeArchived: true)
        guard !existing.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw AccountError.duplicateName
        }

        let account = Account(
            name: trimmed,
            kind: kind,
            currencyCode: currencyCode,
            colorHex: colorHex,
            symbolName: symbolName,
            ownership: ownership,
            sortIndex: existing.count
        )
        context.insert(account)

        let opening = LedgerEntry(
            kind: .openingBalance,
            amountMinor: openingBalanceMinor,
            currencyCode: account.currencyCode,
            occurredAt: openedAt,
            note: "Opening balance"
        )
        opening.account = account
        context.insert(opening)

        try context.save()
        ManotiNotifications.postDataChanged()
        return account
    }

    public func updateOpeningBalance(_ account: Account, to minorUnits: Int64) throws {
        let posted = (account.transactions ?? []).filter(\.isPosted)
        let openings = posted.filter { $0.kind == .openingBalance }

        guard let opening = openings.min(by: { $0.occurredAt < $1.occurredAt }) else {
            throw AccountError.openingBalanceMissing
        }

        guard !posted.contains(where: { $0.id != opening.id && $0.occurredAt < opening.occurredAt }) else {
            throw AccountError.openingBalanceLocked
        }

        opening.amountMinor = minorUnits
        account.updatedAt = Date()
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func archive(_ account: Account) throws {
        account.isArchived = true
        account.updatedAt = Date()
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func updateDetails(
        _ account: Account,
        name: String,
        kind: AccountKind,
        colorHex: String,
        symbolName: String,
        institution: String,
        ownership: AccountOwnership? = nil
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AccountError.emptyName
        }

        let others = try fetchAccounts(includeArchived: true).filter { $0.id != account.id }
        guard !others.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw AccountError.duplicateName
        }

        account.name = trimmed
        account.kind = kind
        account.colorHex = HexColor.normalised(colorHex) ?? account.colorHex
        account.symbolName = symbolName
        account.institution = institution.trimmingCharacters(in: .whitespacesAndNewlines)

        if let ownership {
            account.ownership = ownership
        }

        account.updatedAt = Date()
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func unarchive(_ account: Account) throws {
        // Re-check routing identifiers: while archived, another account may have reused
        // one of them. Unarchiving must not create an ambiguous match.
        for identifier in account.identifiers ?? [] {
            try ensureIdentifierIsUnique(identifier.value, type: identifier.type, excluding: identifier)
        }

        account.isArchived = false
        account.updatedAt = Date()
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    @discardableResult
    public func addIdentifier(
        value: String,
        type: AccountIdentifierType,
        to account: Account
    ) throws -> AccountIdentifier {
        let normalised = try normalisedIdentifier(value: value, type: type)
        try ensureIdentifierIsUnique(normalised, type: type, excluding: nil)

        let identifier = AccountIdentifier(value: normalised, type: type)
        identifier.account = account
        context.insert(identifier)
        try context.save()
        ManotiNotifications.postDataChanged()
        return identifier
    }

    public func updateIdentifier(
        _ identifier: AccountIdentifier,
        value: String,
        type: AccountIdentifierType
    ) throws {
        let normalised = try normalisedIdentifier(value: value, type: type)
        try ensureIdentifierIsUnique(normalised, type: type, excluding: identifier)

        identifier.value = normalised
        identifier.type = type
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func removeIdentifier(_ identifier: AccountIdentifier) throws {
        context.delete(identifier)
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    /// Trims and validates an identifier, returning the value stored on the model.
    private func normalisedIdentifier(value: String, type: AccountIdentifierType) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        switch type {
            case .cardLast4:
                // A card suffix stays strict: exactly four digits, no separators.
                let digits = trimmed.filter(\.isNumber)
                guard digits.count == 4, digits.count == trimmed.count else {
                    throw AccountError.invalidIdentifier
                }
                return digits

            case .accountNumber:
                // Account numbers may be written with spaces or hyphens but are stored as digits.
                let allowed = CharacterSet(charactersIn: " -")
                guard
                    trimmed.unicodeScalars.allSatisfy({
                        CharacterSet.decimalDigits.contains($0) || allowed.contains($0)
                    })
                else {
                    throw AccountError.invalidIdentifier
                }

                let digits = trimmed.filter(\.isNumber)
                guard digits.count >= 4 else {
                    throw AccountError.invalidIdentifier
                }
                return digits

            case .phone:
                let allowed = CharacterSet(charactersIn: "+- ()")
                guard
                    trimmed.unicodeScalars.allSatisfy({
                        CharacterSet.decimalDigits.contains($0) || allowed.contains($0)
                    })
                else {
                    throw AccountError.invalidIdentifier
                }

                let digits = trimmed.filter(\.isNumber)
                guard (7...15).contains(digits.count) else {
                    throw AccountError.invalidIdentifier
                }
                return digits

            case .sender:
                guard trimmed.count >= 2 else {
                    throw AccountError.invalidIdentifier
                }
                return trimmed
        }
    }

    /// Routing is ambiguous if the same value points at two accounts, so keep it unique
    /// within each routing namespace. Account numbers and phones route identically, so
    /// they share one namespace; the same digits may still be a phone and a card suffix.
    private func ensureIdentifierIsUnique(
        _ value: String,
        type: AccountIdentifierType,
        excluding identifier: AccountIdentifier?
    ) throws {
        let existing = try context.fetch(FetchDescriptor<AccountIdentifier>())
        let namespace = IdentifierNamespace(type)

        let clash = existing.contains { candidate in
            guard
                candidate.id != identifier?.id,
                candidate.account?.isArchived == false,
                IdentifierNamespace(candidate.type) == namespace
            else {
                return false
            }

            if namespace == .sender {
                return candidate.value.caseInsensitiveCompare(value) == .orderedSame
            }

            let digits = value.filter(\.isNumber)
            if candidate.type == .phone, type == .phone {
                return AccountService.phoneDigitsMatch(candidate.normalisedValue, digits)
            }

            return candidate.normalisedValue == digits
        }

        guard !clash else {
            throw AccountError.duplicateIdentifier
        }
    }
}

/// Values that may point at an account, grouped by how routing compares them.
private nonisolated enum IdentifierNamespace: Equatable {
    case cardLast4
    case number
    case sender

    init(_ type: AccountIdentifierType) {
        switch type {
            case .cardLast4: self = .cardLast4
            case .accountNumber, .phone: self = .number
            case .sender: self = .sender
        }
    }
}
