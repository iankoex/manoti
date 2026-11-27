//
//  AccountIdentifierTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Account identifiers")
struct AccountIdentifierTests {
    private func makeService() throws -> AccountService {
        let container = try ModelContainerFactory.make(inMemory: true)
        return AccountService(context: ModelContext(container))
    }

    private func makeServiceAndContext() throws -> (AccountService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return (AccountService(context: context), context)
    }

    @Test("A card identifier must be exactly four digits")
    func cardValidation() throws {
        let accounts = try makeService()
        let account = try accounts.create(name: "Card", kind: .card)

        #expect(throws: AccountError.invalidIdentifier) {
            try accounts.addIdentifier(value: "547", type: .cardLast4, to: account)
        }
        #expect(throws: AccountError.invalidIdentifier) {
            try accounts.addIdentifier(value: "5477X", type: .cardLast4, to: account)
        }

        let added = try accounts.addIdentifier(value: "5477", type: .cardLast4, to: account)
        #expect(added.value == "5477")
    }

    @Test("The same identifier cannot be attached twice")
    func duplicates() throws {
        let accounts = try makeService()
        let bank = try accounts.create(name: "Bank", kind: .bank)
        let card = try accounts.create(name: "Card", kind: .card)

        try accounts.addIdentifier(value: "5477", type: .cardLast4, to: bank)

        #expect(throws: AccountError.duplicateIdentifier) {
            try accounts.addIdentifier(value: "5477", type: .cardLast4, to: card)
        }
    }

    @Test("Removing an identifier stops routing")
    func remove() throws {
        let accounts = try makeService()
        let account = try accounts.create(name: "Bank", kind: .bank)
        let identifier = try accounts.addIdentifier(
            value: "01234567890123",
            type: .accountNumber,
            to: account
        )

        #expect(accounts.account(forIdentifier: "01234567890123")?.id == account.id)

        try accounts.removeIdentifier(identifier)

        #expect(accounts.account(forIdentifier: "01234567890123") == nil)
    }

    @Test("Updating an identifier changes routing")
    func update() throws {
        let accounts = try makeService()
        let account = try accounts.create(name: "Card", kind: .card)
        let identifier = try accounts.addIdentifier(value: "5477", type: .cardLast4, to: account)

        try accounts.updateIdentifier(identifier, value: "9999", type: .cardLast4)

        #expect(accounts.account(forIdentifier: "5477") == nil)
        #expect(accounts.account(forIdentifier: "9999")?.id == account.id)
    }

    @Test("A sender identifier matches the sender case-insensitively, never the payee")
    func sender() throws {
        let accounts = try makeService()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        try accounts.addIdentifier(value: "M-PESA", type: .sender, to: account)

        #expect(accounts.account(forSender: "m-pesa")?.id == account.id)
        #expect(accounts.account(forSender: "  M-Pesa  ")?.id == account.id)
        #expect(accounts.account(forIdentifier: "m-pesa") == nil)
    }

    @Test("Account numbers and phones share one uniqueness namespace")
    func sharedNumberNamespace() throws {
        let accounts = try makeService()
        let bank = try accounts.create(name: "Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        try accounts.addIdentifier(value: "0712 345 678", type: .phone, to: mobile)

        #expect(throws: AccountError.duplicateIdentifier) {
            try accounts.addIdentifier(value: "0712-345-678", type: .accountNumber, to: bank)
        }

        try accounts.addIdentifier(value: "01234567890123", type: .accountNumber, to: bank)

        #expect(throws: AccountError.duplicateIdentifier) {
            try accounts.addIdentifier(value: "0123 4567 8901 23", type: .phone, to: mobile)
        }
    }

    @Test("A legacy collision across account number and phone routes nowhere")
    func legacyCollision() throws {
        let (accounts, context) = try makeServiceAndContext()
        let bank = try accounts.create(name: "Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let accountNumber = AccountIdentifier(value: "01234567890123", type: .accountNumber)
        accountNumber.account = bank
        context.insert(accountNumber)

        let phone = AccountIdentifier(value: "01234567890123", type: .phone)
        phone.account = mobile
        context.insert(phone)

        try context.save()

        #expect(accounts.account(forIdentifier: "01234567890123") == nil)
    }

    @Test("A phone routes in national and international form")
    func phoneFormats() throws {
        let accounts = try makeService()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let other = try accounts.create(name: "Other", kind: .mobileMoney)

        try accounts.addIdentifier(value: "0700 000 000", type: .phone, to: mobile)

        #expect(accounts.account(forIdentifier: "0700 000 000")?.id == mobile.id)
        #expect(accounts.account(forIdentifier: "254700000000")?.id == mobile.id)
        #expect(accounts.account(forIdentifier: "+254 700 000 000")?.id == mobile.id)
        #expect(accounts.account(forIdentifier: "0700 000 001") == nil)

        #expect(throws: AccountError.duplicateIdentifier) {
            try accounts.addIdentifier(value: "254700000000", type: .phone, to: other)
        }
    }

    @Test("A phone and an account number are not fuzzy-matched for uniqueness")
    func phoneAndAccountNumberStayDistinct() throws {
        let accounts = try makeService()
        let bank = try accounts.create(name: "Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        try accounts.addIdentifier(value: "0700 000 000", type: .phone, to: mobile)
        try accounts.addIdentifier(value: "254700000000", type: .accountNumber, to: bank)

        // They share the last nine digits, so routing cannot choose one.
        #expect(accounts.account(forIdentifier: "254700000000") == nil)
    }

    @Test("Archived accounts do not block reusing an identifier")
    func archivedAccountDoesNotBlockReuse() throws {
        let accounts = try makeService()
        let old = try accounts.create(name: "Old bank", kind: .bank)
        try accounts.addIdentifier(value: "01234567890123", type: .accountNumber, to: old)

        try accounts.archive(old)

        let new = try accounts.create(name: "New bank", kind: .bank)
        try accounts.addIdentifier(value: "01234567890123", type: .accountNumber, to: new)

        #expect(accounts.account(forIdentifier: "01234567890123")?.id == new.id)
    }

    @Test("Unarchiving cannot create an ambiguous identifier")
    func unarchiveConflict() throws {
        let accounts = try makeService()
        let old = try accounts.create(name: "Old bank", kind: .bank)
        try accounts.addIdentifier(value: "01234567890123", type: .accountNumber, to: old)
        try accounts.archive(old)

        let new = try accounts.create(name: "New bank", kind: .bank)
        try accounts.addIdentifier(value: "01234567890123", type: .accountNumber, to: new)

        #expect(throws: AccountError.duplicateIdentifier) {
            try accounts.unarchive(old)
        }
        #expect(old.isArchived)
    }

    @Test("Account numbers accept spaces and hyphens but store digits")
    func accountNumberSeparators() throws {
        let accounts = try makeService()
        let bank = try accounts.create(name: "Bank", kind: .bank)

        let identifier = try accounts.addIdentifier(
            value: "0123 4567-8901 23",
            type: .accountNumber,
            to: bank
        )

        #expect(identifier.value == "01234567890123")
        #expect(accounts.account(forIdentifier: "0123-4567-8901-23")?.id == bank.id)
    }

    @Test("Identifier length boundaries are enforced")
    func numberBoundaries() throws {
        let accounts = try makeService()
        let bank = try accounts.create(name: "Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        #expect(throws: AccountError.invalidIdentifier) {
            try accounts.addIdentifier(value: "12-3", type: .accountNumber, to: bank)
        }
        #expect(throws: AccountError.invalidIdentifier) {
            try accounts.addIdentifier(value: "AB-1234", type: .accountNumber, to: bank)
        }

        let shortestAccountNumber = try accounts.addIdentifier(value: "12-34", type: .accountNumber, to: bank)
        #expect(shortestAccountNumber.value == "1234")

        #expect(throws: AccountError.invalidIdentifier) {
            try accounts.addIdentifier(value: "54 77", type: .cardLast4, to: bank)
        }

        #expect(throws: AccountError.invalidIdentifier) {
            try accounts.addIdentifier(value: "123456", type: .phone, to: mobile)
        }

        let shortestPhone = try accounts.addIdentifier(value: "123-4567", type: .phone, to: mobile)
        #expect(shortestPhone.value == "1234567")

        #expect(throws: AccountError.invalidIdentifier) {
            try accounts.addIdentifier(value: "1234567890123456", type: .phone, to: mobile)
        }

        let longestPhone = try accounts.addIdentifier(value: "123456789012345", type: .phone, to: mobile)
        #expect(longestPhone.value == "123456789012345")
    }
}
