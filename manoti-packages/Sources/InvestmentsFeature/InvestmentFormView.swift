//
//  InvestmentFormView.swift
//  InvestmentsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Sheet for adding a Treasury bond or bill.
///
/// Money market accounts use `MoneyMarketFormView`.
public struct InvestmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppService.self) private var appService
    @Environment(AccountService.self) private var accountService
    @Environment(InvestmentService.self) private var investmentService

    @Bindable private var state: InvestmentFormState
    @State private var errorMessage: String?

    public init(mode: InvestmentFormState.Mode = .bond) {
        _state = Bindable(InvestmentFormState(mode: mode))
    }

    public var body: some View {
        NavigationStack {
            Form {
                typeSection
                identificationSection
                amountSection

                if state.mode == .bond {
                    couponSection
                    pricingSection
                }

                datesSection
                taxSection
                accountSection
                noteSection

                if !state.validationMessages.isEmpty {
                    Section("Before you can save") {
                        ForEach(state.validationMessages, id: \.self) { message in
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(state.mode == .bond ? "Add a bond" : "Add a bill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(!state.canSave)
                }
            }
            .alert(
                "Could not save",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                state.reload(accountService: accountService)
                state.withholdingTaxText = "\(Decimal(appService.withholdingTaxBasisPoints) / 100)"
            }
        }
    }

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $state.mode) {
                Text("Treasury bond").tag(InvestmentFormState.Mode.bond)
                Text("Treasury bill").tag(InvestmentFormState.Mode.bill)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(
                state.mode == .bond
                    ? "Bonds pay a coupon every six months until maturity."
                    : "Bills are bought below nominal and repay the face value at maturity."
            )
        }
    }

    private var identificationSection: some View {
        Section("Identification") {
            if state.mode == .bond {
                TextField("Issue number, e.g. FXD1/2021/025", text: $state.issueNumber)

                TextField("ISIN", text: $state.isin)
                    .plainTextInput()
            }
        }
    }

    private var amountSection: some View {
        Section {
            LabeledContent("Nominal") {
                HStack(spacing: ManotiSpacing.small) {
                    Text(state.currency.code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("0.00", text: $state.nominalText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }

            if state.mode == .bill {
                LabeledContent("Price paid") {
                    HStack(spacing: ManotiSpacing.small) {
                        Text(state.currency.code)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField("0.00", text: $state.purchasePriceText)
                            .decimalKeyboard()
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }
            }
        } footer: {
            if let message = amountMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }

    private var couponSection: some View {
        Section {
            LabeledContent("Annual coupon") {
                HStack(spacing: ManotiSpacing.small) {
                    TextField("13.924", text: $state.couponRateText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()

                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if let rate = state.couponRateBasisPoints, rate > 10_000 {
                Text("Enter a coupon rate between 0% and 100%.")
                    .foregroundStyle(.red)
            } else if !state.couponRateText.isEmpty && state.couponRateBasisPoints == nil {
                Text("Enter a valid coupon rate.")
                    .foregroundStyle(.red)
            } else {
                Text("Coupons are paid semi-annually. Withholding tax is deducted at source.")
            }
        }
    }

    private var pricingSection: some View {
        Section {
            LabeledContent("Clean price") {
                HStack(spacing: ManotiSpacing.small) {
                    TextField("100", text: $state.cleanPriceText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()

                    Text("per 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Accrued interest") {
                HStack(spacing: ManotiSpacing.small) {
                    Text(state.currency.code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("0.00", text: $state.accruedInterestText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }

            LabeledContent("Cash invested") {
                HStack(spacing: ManotiSpacing.small) {
                    Text(state.currency.code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Dirty price", text: $state.cashInvestedText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }

            if let dirtyPrice = state.dirtyPrice {
                LabeledContent("Dirty price") {
                    AmountText(dirtyPrice, style: .subheadline.weight(.semibold))
                }
            }
        } footer: {
            Text(
                "Clean price plus accrued interest is the dirty price you actually pay. Leave cash invested empty to use it."
            )
        }
    }

    private var datesSection: some View {
        Section {
            DatePicker("Purchased", selection: $state.purchaseDate, displayedComponents: .date)

            if state.mode == .bond {
                Toggle("Issue date", isOn: issueDateToggle)

                if let issueDate = state.issueDate {
                    DatePicker("Issued", selection: issueDateBinding(issueDate), displayedComponents: .date)
                }
            }

            Toggle("Settlement date", isOn: settlementDateToggle)

            if let settlementDate = state.settlementDate {
                DatePicker("Settles", selection: settlementDateBinding(settlementDate), displayedComponents: .date)
            }

            if state.mode == .bond {
                Toggle("First coupon date", isOn: firstCouponToggle)

                if let firstCouponDate = state.firstCouponDate {
                    DatePicker(
                        "First coupon",
                        selection: firstCouponBinding(firstCouponDate),
                        displayedComponents: .date
                    )
                }
            }

            DatePicker(
                "Maturity",
                selection: maturityBinding,
                displayedComponents: .date
            )
        } footer: {
            if let message = dateMessage {
                Text(message)
                    .foregroundStyle(.red)
            } else if state.mode == .bond {
                Text("A settlement after today keeps the holding pending until that date.")
            }
        }
    }

    private var taxSection: some View {
        Section {
            LabeledContent("Withholding tax") {
                HStack(spacing: ManotiSpacing.small) {
                    TextField("10", text: $state.withholdingTaxText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()

                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Tax exempt", isOn: $state.taxExempt)

            LabeledContent("Reinvest rate") {
                HStack(spacing: ManotiSpacing.small) {
                    TextField("Default", text: $state.reinvestmentRateText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()

                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if let message = rateMessage {
                Text(message)
                    .foregroundStyle(.red)
            } else {
                Text("Leave the override empty to use the default reinvestment rate from Settings.")
            }
        }
    }

    private var accountSection: some View {
        Section {
            Picker("Account", selection: $state.selectedAccountID) {
                if state.activeAccounts.isEmpty {
                    Text("No active accounts").tag(UUID?.none)
                } else {
                    ForEach(state.activeAccounts) { account in
                        Text("\(account.displayName) · \(account.currency.code)")
                            .tag(Optional(account.id))
                    }
                }
            }
        } footer: {
            if state.activeAccounts.isEmpty {
                Text("The investment is recorded without a linked cash account.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var noteSection: some View {
        Section("Note") {
            TextField("Optional note", text: $state.note, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private var amountMessage: String? {
        if state.nominalText.isEmpty {
            return nil
        }

        guard let nominal = state.parsedNominal?.minorUnits else {
            return "Enter a valid nominal amount."
        }

        if nominal <= 0 {
            return "Enter a nominal amount greater than zero."
        }

        if state.mode == .bill, state.purchasePriceText.isEmpty {
            return nil
        }

        if state.mode == .bill, let price = state.parsedPurchasePrice?.minorUnits {
            if price <= 0 {
                return "Enter a price paid greater than zero."
            }
            if price > nominal {
                return "A Treasury bill costs less than its nominal."
            }
        }

        return nil
    }

    private var dateMessage: String? {
        if let maturity = state.maturityDate {
            if state.mode == .bond, state.purchaseDate > maturity {
                return "Maturity must be after the purchase date."
            }
            if state.mode == .bill, state.purchaseDate >= maturity {
                return "Maturity must be after the purchase date."
            }
            if let firstCoupon = state.firstCouponDate, firstCoupon > maturity {
                return "The first coupon must be on or before maturity."
            }
            if let firstCoupon = state.firstCouponDate, firstCoupon < state.purchaseDate {
                return "The first coupon cannot be before the purchase date."
            }
        }

        if let issueDate = state.issueDate, issueDate > state.purchaseDate {
            return "The issue date cannot be after the purchase date."
        }

        if let settlement = state.settlementDate, settlement < state.purchaseDate {
            return "Settlement cannot be before the purchase date."
        }

        return nil
    }

    private var rateMessage: String? {
        if state.withholdingTaxBasisPoints == nil {
            return "Enter a withholding tax between 0% and 100%."
        }

        if !state.reinvestmentRateText.isEmpty && state.reinvestmentRateOverrideBasisPoints == nil {
            return "Enter a valid reinvestment rate."
        }

        return nil
    }

    private var issueDateToggle: Binding<Bool> {
        Binding(
            get: { state.issueDate != nil },
            set: { isOn in state.issueDate = isOn ? state.purchaseDate : nil }
        )
    }

    private var settlementDateToggle: Binding<Bool> {
        Binding(
            get: { state.settlementDate != nil },
            set: { isOn in state.settlementDate = isOn ? state.purchaseDate : nil }
        )
    }

    private var firstCouponToggle: Binding<Bool> {
        Binding(
            get: { state.firstCouponDate != nil },
            set: { isOn in
                state.firstCouponDate =
                    isOn
                    ? InvestmentMath.calendar.date(byAdding: .month, value: 6, to: state.purchaseDate)
                    : nil
            }
        )
    }

    private var maturityBinding: Binding<Date> {
        Binding(
            get: {
                state.maturityDate
                    ?? InvestmentMath.calendar.date(byAdding: .year, value: 10, to: state.purchaseDate)
                    ?? state.purchaseDate
            },
            set: { state.maturityDate = $0 }
        )
    }

    private func issueDateBinding(_ date: Date) -> Binding<Date> {
        Binding(get: { date }, set: { state.issueDate = $0 })
    }

    private func settlementDateBinding(_ date: Date) -> Binding<Date> {
        Binding(get: { date }, set: { state.settlementDate = $0 })
    }

    private func firstCouponBinding(_ date: Date) -> Binding<Date> {
        Binding(get: { date }, set: { state.firstCouponDate = $0 })
    }

    private func save() {
        do {
            try state.save(investmentService: investmentService)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
