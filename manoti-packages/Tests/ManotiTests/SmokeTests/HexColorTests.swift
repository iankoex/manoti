//
//  HexColorTests.swift
//  ManotiTests
//

import Testing

@testable import AppPackageExtensions

@Suite("HexColor")
struct HexColorTests {
    @Test("Parses with and without a leading hash")
    func parsing() throws {
        let plain = try #require(HexColor.rgb(from: "3366CC"))
        #expect(abs(plain.red - 0.2) < 0.001)
        #expect(abs(plain.green - 0.4) < 0.001)
        #expect(abs(plain.blue - 0.8) < 0.001)

        let hashed = try #require(HexColor.rgb(from: "#3366CC"))
        #expect(hashed == plain)
    }

    @Test("Rejects malformed values")
    func rejectsMalformed() {
        #expect(HexColor.rgb(from: "12345") == nil)
        #expect(HexColor.rgb(from: "GGGGGG") == nil)
        #expect(HexColor.rgb(from: "") == nil)
    }

    @Test("Normalises to uppercase without the hash")
    func normalising() {
        #expect(HexColor.normalised("#a1b2c3") == "A1B2C3")
        #expect(HexColor.normalised("zzzzzz") == nil)
    }
}
