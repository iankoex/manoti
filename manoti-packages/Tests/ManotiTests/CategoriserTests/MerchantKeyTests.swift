//
//  MerchantKeyTests.swift
//  ManotiTests
//

import Testing

@testable import AppModels

@Suite("MerchantKey")
struct MerchantKeyTests {
    @Test("Tokens drop corporate noise")
    func tokens() {
        #expect(
            MerchantKey.tokens("Nixomb Ltd - Shell Bellevue")
                == ["nixomb", "shell", "bellevue"]
        )
    }

    @Test("A longer payee still matches the known merchant")
    func longerPayee() {
        #expect(MerchantKey.similarity("Shell Bellevue", "Shell Bellevue Nairobi") >= 0.6)
    }

    @Test("One shared word is not enough")
    func oneSharedWord() {
        #expect(MerchantKey.similarity("Uber", "Uber Eats") == 0)
    }

    @Test("Identical keys take the exact path")
    func identical() {
        #expect(MerchantKey.similarity("Glovo", "Glovo") == 0)
    }
}
