//
//  CompanyAccountTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Company accounts")
struct CompanyAccountTests {
    private func makeServices() throws -> (AccountService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return (AccountService(context: context), context)
    }

    @Test("An account can be created as a company account")
    func createCompany() throws {
        let (accounts, _) = try makeServices()

        let personal = try accounts.create(name: "Everyday", kind: .bank)
        let company = try accounts.create(name: "Acme Ltd", kind: .bank, ownership: .company)

        #expect(personal.ownership == .personal)
        #expect(company.ownership == .company)
        #expect(company.isCompany)
    }

    @Test("Changing ownership updates the account and leaves the rest alone")
    func updateOwnership() throws {
        let (accounts, _) = try makeServices()
        let account = try accounts.create(name: "Acme", kind: .bank)
        let originalKind = account.kind
        let originalCurrency = account.currencyCode

        try accounts.updateDetails(
            account,
            name: "Acme Ltd",
            kind: originalKind,
            colorHex: account.colorHex,
            symbolName: account.symbolName,
            institution: "Bank",
            ownership: .company
        )

        #expect(account.ownership == .company)
        #expect(account.name == "Acme Ltd")
        #expect(account.kind == originalKind)
        #expect(account.currencyCode == originalCurrency)
    }

    @Test("Omitting ownership keeps the existing one")
    func omittedOwnershipIsPreserved() throws {
        let (accounts, _) = try makeServices()
        let account = try accounts.create(name: "Acme", kind: .bank, ownership: .company)

        try accounts.updateDetails(
            account,
            name: "Acme Holdings",
            kind: .bank,
            colorHex: account.colorHex,
            symbolName: account.symbolName,
            institution: ""
        )

        #expect(account.ownership == .company)
    }
}
