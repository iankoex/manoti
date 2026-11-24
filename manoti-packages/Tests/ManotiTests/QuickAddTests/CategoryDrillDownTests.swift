//
//  CategoryDrillDownTests.swift
//  ManotiTests
//

import Testing

@testable import EntryFormFeature

@Test("A group row says how many matching categories it holds")
func groupRowText() {
    #expect(CategoryDrillDownText.groupCount(1) == "1 category")
    #expect(CategoryDrillDownText.groupCount(4) == "4 categories")
}

@Test("A single group skips the group step")
func singleGroupSkipsStep() {
    #expect(!CategoryDrillDownText.usesGroupStep(groupCount: 1))
    #expect(CategoryDrillDownText.usesGroupStep(groupCount: 2))
}
