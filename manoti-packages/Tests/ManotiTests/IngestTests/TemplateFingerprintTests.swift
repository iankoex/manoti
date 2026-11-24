//
//  TemplateFingerprintTests.swift
//  ManotiTests
//

import Testing

@testable import AppModels

@Suite("TemplateFingerprint")
struct TemplateFingerprintTests {
    @Test("Different figures share one fingerprint")
    func figuresMasked() {
        let first = TemplateFingerprint.make(
            sender: "M-PESA",
            text: "Your balance is KES 1,204.00 on 23/11/26"
        )
        let second = TemplateFingerprint.make(
            sender: "M-PESA",
            text: "Your balance is KES 980.00 on 24/11/26"
        )

        #expect(first == second)
    }

    @Test("Different senders do not share a fingerprint")
    func sendersDiffer() {
        let text = "Your balance is KES 10.00"

        #expect(
            TemplateFingerprint.make(sender: "M-PESA", text: text)
                != TemplateFingerprint.make(sender: "IM BANK", text: text)
        )
    }

    @Test("Different meridiems share one fingerprint")
    func meridiemMasked() {
        let morning = TemplateFingerprint.make(
            sender: "M-PESA",
            text: "Paid on 21/11/26 at 11:54 AM"
        )
        let evening = TemplateFingerprint.make(
            sender: "M-PESA",
            text: "Paid on 22/11/26 at 1:00 PM"
        )

        #expect(morning == evening)
    }

    @Test("Dotted meridiems are normalised too")
    func dottedMeridiem() {
        let compact = TemplateFingerprint.make(sender: "M-PESA", text: "Received at 3:07 PM")
        let dotted = TemplateFingerprint.make(sender: "M-PESA", text: "Received at 3:07 p.m.")

        #expect(compact == dotted)
    }

    @Test("Random letters inside a reference do not split the template")
    func referenceLettersMasked() {
        let first = TemplateFingerprint.make(
            sender: "M-PESA",
            text: "Ref UKL6H2AF65 Confirmed. Ksh1,510.00 paid to Shell."
        )
        let second = TemplateFingerprint.make(
            sender: "M-PESA",
            text: "Ref UKN7G3BG21 Confirmed. Ksh2,000.00 paid to Shell."
        )

        #expect(first == second)
    }

    @Test("Merchant words still tell templates apart")
    func merchantWordsDiffer() {
        let shell = TemplateFingerprint.make(sender: "M-PESA", text: "Ksh500.00 paid to Shell Bellevue")
        let total = TemplateFingerprint.make(sender: "M-PESA", text: "Ksh500.00 paid to Total Energies")

        #expect(shell != total)
    }

    @Test("A balance keeps its shape whatever the digit count")
    func balanceDigitCount() {
        let small = TemplateFingerprint.make(
            sender: "M-PESA",
            text: "New M-PESA balance is Ksh939.68."
        )
        let large = TemplateFingerprint.make(
            sender: "M-PESA",
            text: "New M-PESA balance is Ksh1,000.00."
        )

        #expect(small == large)
    }
}
