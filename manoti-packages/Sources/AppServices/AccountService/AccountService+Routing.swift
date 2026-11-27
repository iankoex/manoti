//
//  AccountService+Routing.swift
//  AppServices
//

import AppModels
import Foundation

nonisolated extension AccountService {
    /// Routes an incoming message to one of the user's own accounts.
    ///
    /// Never guesses between several accounts: if the most specific identifier matches more
    /// than one account, the message is left unmatched (`nil`) and the caller stores it for
    /// review. Archived accounts never match.
    public func account(forIdentifier value: String) -> Account? {
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty else {
            return nil
        }

        let accounts = (try? fetchAccounts(includeArchived: false)) ?? []
        let identifiers =
            accounts
            .flatMap { account in
                (account.identifiers ?? []).map { (identifier: $0, account: account) }
            }

        // Group by how specific a match is. Account numbers and phones route identically
        // (exact digits), so they share one specificity level.
        let bySpecificity = Dictionary(grouping: identifiers) { routingSpecificity(of: $0.identifier.type) }

        for specificity in bySpecificity.keys.sorted() {
            let matches = (bySpecificity[specificity] ?? []).filter {
                matches($0.identifier, digits: digits)
            }

            guard !matches.isEmpty else {
                continue
            }

            let matchedAccountIDs = Set(matches.map { $0.account.id })
            return matchedAccountIDs.count == 1 ? matches[0].account : nil
        }

        return nil
    }

    /// Routes a message by the sender Messages reports, never by the payee.
    ///
    /// An exact sender match is required so `IM` cannot claim a message from `PRIME`.
    /// Two accounts sharing a sender are ambiguous and route nowhere.
    public func account(forSender value: String) -> Account? {
        let sender = normalisedSender(value)
        guard !sender.isEmpty else {
            return nil
        }

        let accounts = (try? fetchAccounts(includeArchived: false)) ?? []
        let matches = accounts.filter { account in
            (account.identifiers ?? []).contains {
                $0.type == .sender && normalisedSender($0.value) == sender
            }
        }

        return matches.count == 1 ? matches[0] : nil
    }

    private func routingSpecificity(of type: AccountIdentifierType) -> Int {
        switch type {
            case .cardLast4: 0
            case .accountNumber, .phone: 1
            case .sender: 2
        }
    }

    private func matches(_ identifier: AccountIdentifier, digits: String) -> Bool {
        let identifierDigits = identifier.normalisedValue
        guard !identifierDigits.isEmpty else {
            return false
        }

        if identifier.type == .cardLast4 {
            return digits.count >= 4 && digits.hasSuffix(identifierDigits)
        }

        // Sender identifiers are matched by `account(forSender:)`; free text such as a
        // payee must never satisfy one.
        guard identifier.type != .sender else {
            return false
        }

        // A phone may be written nationally (0700…) or internationally (254700…).
        // Account numbers stay an exact match: a shared suffix is not an identity.
        if identifier.type == .phone {
            return AccountService.phoneDigitsMatch(digits, identifierDigits)
        }

        return digits == identifierDigits
    }

    /// True when two phone numbers are the same in national or international form.
    ///
    /// Exact digits always match. Otherwise the last nine digits must agree: that covers
    /// `0700 000 000` and `+254 700 000 000` without rewriting already-stored identifiers.
    /// The trade-off is that two numbers from different countries sharing the last nine
    /// digits also match. A single-user, Kenya-first app accepts that; see the design.
    nonisolated public static func phoneDigitsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.filter(\.isNumber)
        let right = rhs.filter(\.isNumber)

        guard !left.isEmpty, !right.isEmpty else {
            return false
        }

        if left == right {
            return true
        }

        guard left.count >= 9, right.count >= 9 else {
            return false
        }

        return left.suffix(9) == right.suffix(9)
    }

    private func normalisedSender(_ value: String) -> String {
        value
            .uppercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
