//
//  SplitTemplateTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels

@Suite("Split templates")
struct SplitTemplateTests {
    private let household = UUID()
    private let groceries = UUID()

    @Test("Shares are normalised to basis points and add up to 10,000")
    func normalisation() throws {
        let template = try #require(
            SplitTemplate(
                lines: [
                    SplitTemplateLine(categoryID: household, weightBasisPoints: 300),
                    SplitTemplateLine(categoryID: groceries, weightBasisPoints: 200),
                ]
            )
        )

        #expect(template.lines.map(\.weightBasisPoints) == [6_000, 4_000])
        #expect(template.lines.first?.categoryID == household)
    }

    @Test("Fewer than two categories is not a template")
    func needsTwoCategories() {
        #expect(
            SplitTemplate(
                lines: [SplitTemplateLine(categoryID: household, weightBasisPoints: 100)]
            ) == nil
        )
        #expect(
            SplitTemplate(
                lines: [
                    SplitTemplateLine(categoryID: household, weightBasisPoints: 100),
                    SplitTemplateLine(categoryID: household, weightBasisPoints: 100),
                ]
            ) == nil
        )
    }

    @Test("Allocation keeps the proportions and the exact total")
    func allocation() throws {
        let template = try #require(
            SplitTemplate(
                lines: [
                    SplitTemplateLine(categoryID: household, weightBasisPoints: 6_000),
                    SplitTemplateLine(categoryID: groceries, weightBasisPoints: 4_000),
                ]
            )
        )

        let parts = try #require(template.allocations(totalMinor: 50_000))

        #expect(parts.map(\.amountMinor) == [30_000, 20_000])
        #expect(parts.reduce(0) { $0 + $1.amountMinor } == 50_000)
    }

    @Test("A tiny total still gives every line at least one minor unit")
    func tinyTotal() throws {
        let template = try #require(
            SplitTemplate(
                lines: [
                    SplitTemplateLine(categoryID: household, weightBasisPoints: 5_000),
                    SplitTemplateLine(categoryID: groceries, weightBasisPoints: 5_000),
                ]
            )
        )

        let parts = try #require(template.allocations(totalMinor: 3))

        #expect(parts.allSatisfy { $0.amountMinor >= 1 })
        #expect(parts.reduce(0) { $0 + $1.amountMinor } == 3)
        #expect(template.allocations(totalMinor: 1) == nil)
    }

    @Test("A template survives its JSON encoding")
    func encoding() throws {
        let template = try #require(
            SplitTemplate(
                lines: [
                    SplitTemplateLine(categoryID: household, weightBasisPoints: 7_000),
                    SplitTemplateLine(categoryID: groceries, weightBasisPoints: 3_000),
                ]
            )
        )

        #expect(SplitTemplate(encoded: template.encoded) == template)
        #expect(SplitTemplate(encoded: "") == nil)
    }

    @Test("The summary names the categories and their shares")
    func summary() throws {
        let template = try #require(
            SplitTemplate(
                lines: [
                    SplitTemplateLine(categoryID: household, weightBasisPoints: 6_000),
                    SplitTemplateLine(categoryID: groceries, weightBasisPoints: 4_000),
                ]
            )
        )

        let text = template.summary(categoryNames: [household: "Household", groceries: "Groceries"])
        #expect(text == "Household 60% · Groceries 40%")
        #expect(template.summary(categoryNames: [household: "Household"]) == nil)
    }
}
