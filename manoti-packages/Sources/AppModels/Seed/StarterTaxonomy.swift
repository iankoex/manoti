//
//  StarterTaxonomy.swift
//  AppModels
//

import Foundation

nonisolated public struct SeedCategory: Sendable {
    public let name: String
    public let symbolName: String
    public let isFixed: Bool
    public let keywords: String

    public init(name: String, symbolName: String, isFixed: Bool = false, keywords: String = "") {
        self.name = name
        self.symbolName = symbolName
        self.isFixed = isFixed
        self.keywords = keywords
    }
}

nonisolated public struct SeedCategoryGroup: Sendable {
    public let name: String
    public let symbolName: String
    public let colorHex: String
    public let kind: CategoryKind
    public let categories: [SeedCategory]
    /// Stable identity for seeding. Never derive this from `name`: a copy-edit of a
    /// display name would otherwise seed a second group on the next launch.
    public let seedKey: String

    public init(
        name: String,
        symbolName: String,
        colorHex: String,
        kind: CategoryKind = .expense,
        categories: [SeedCategory],
        seedKey: String = ""
    ) {
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.kind = kind
        self.categories = categories
        self.seedKey = seedKey
    }

    public var key: String {
        seedKey.isEmpty ? name.lowercased() : seedKey
    }
}

nonisolated public enum StarterTaxonomy {
    public static let groups: [SeedCategoryGroup] = [
        SeedCategoryGroup(
            name: "Transport",
            symbolName: "bus",
            colorHex: "#0A84FF",
            categories: [
                SeedCategory(name: "Bus/Matatu", symbolName: "bus", keywords: "matatu,bus,stage,fare"),
                SeedCategory(name: "Taxi", symbolName: "car.side", keywords: "taxi,cab"),
                SeedCategory(name: "Ride-hailing", symbolName: "car.fill", keywords: "uber,bolt,little,ride"),
                SeedCategory(name: "Fuel", symbolName: "fuelpump", keywords: "shell,total,kobil,topline,petrol,diesel"),
                SeedCategory(name: "Parking", symbolName: "parkingsign", keywords: "parking"),
            ],
            seedKey: "transport"
        ),
        SeedCategoryGroup(
            name: "Food",
            symbolName: "fork.knife",
            colorHex: "#FF9F0A",
            categories: [
                SeedCategory(name: "Breakfast", symbolName: "sunrise", keywords: "breakfast,mandazi,uji,tea"),
                SeedCategory(name: "Lunch", symbolName: "takeoutbag.and.cup.and.straw", keywords: "lunch,cafe,hotel"),
                SeedCategory(name: "Dinner", symbolName: "moon.stars", keywords: "dinner,supper"),
                SeedCategory(
                    name: "Takeout", symbolName: "bag", keywords: "takeaway,takeout,delivery,glovo,bolt food,uber eats"),
                SeedCategory(
                    name: "Groceries", symbolName: "cart",
                    keywords: "market,mart,supermarket,grocery,naivas,quickmart,carrefour"),
                SeedCategory(name: "Coffee", symbolName: "cup.and.saucer", keywords: "coffee,java,cafe,latte"),
            ],
            seedKey: "food"
        ),
        SeedCategoryGroup(
            name: "Shopping",
            symbolName: "bag",
            colorHex: "#BF5AF2",
            categories: [
                SeedCategory(name: "Household", symbolName: "house", keywords: "household,cleaning"),
                SeedCategory(name: "Clothing", symbolName: "tshirt", keywords: "clothing,shoes,shirt"),
                SeedCategory(name: "Electronics", symbolName: "desktopcomputer", keywords: "electronics,phone,laptop"),
            ],
            seedKey: "shopping"
        ),
        SeedCategoryGroup(
            name: "Utilities",
            symbolName: "bolt",
            colorHex: "#FFD60A",
            categories: [
                SeedCategory(name: "Electricity", symbolName: "bolt", keywords: "kplc,electricity,tokens"),
                SeedCategory(name: "Water", symbolName: "drop", keywords: "water"),
                SeedCategory(name: "Internet", symbolName: "wifi", keywords: "internet,fibre,broadband"),
                SeedCategory(
                    name: "Airtime & Data", symbolName: "antenna.radiowaves.left.and.right",
                    keywords: "airtime,data,bundles,safaricom"),
            ],
            seedKey: "utilities"
        ),
        SeedCategoryGroup(
            name: "Housing",
            symbolName: "house",
            colorHex: "#30D158",
            categories: [
                SeedCategory(name: "Rent", symbolName: "key", isFixed: true, keywords: "rent,landlord"),
                SeedCategory(
                    name: "Service charge", symbolName: "building.2", isFixed: true,
                    keywords: "service charge,maintenance fee"),
                SeedCategory(
                    name: "Repairs", symbolName: "wrench.and.screwdriver", keywords: "repair,plumber,electrician"),
            ],
            seedKey: "housing"
        ),
        SeedCategoryGroup(
            name: "Health",
            symbolName: "heart",
            colorHex: "#FF375F",
            categories: [
                SeedCategory(name: "Pharmacy", symbolName: "cross.case", keywords: "pharmacy,chemist,medicine"),
                SeedCategory(name: "Clinic", symbolName: "stethoscope", keywords: "clinic,hospital,doctor"),
                SeedCategory(name: "Insurance", symbolName: "shield", isFixed: true, keywords: "insurance,nhic,sha"),
            ],
            seedKey: "health"
        ),
        SeedCategoryGroup(
            name: "Entertainment",
            symbolName: "sparkles",
            colorHex: "#FF2D55",
            categories: [
                SeedCategory(
                    name: "Streaming", symbolName: "play.rectangle", keywords: "netflix,spotify,showmax,youtube"),
                SeedCategory(name: "Events", symbolName: "ticket", keywords: "event,ticket,concert"),
                SeedCategory(name: "Drinks", symbolName: "wineglass", keywords: "bar,drinks,beer"),
            ],
            seedKey: "entertainment"
        ),
        SeedCategoryGroup(
            name: "Education",
            symbolName: "graduationcap",
            colorHex: "#64D2FF",
            categories: [
                SeedCategory(
                    name: "Fees", symbolName: "building.columns", isFixed: true, keywords: "school fees,tuition,college"
                ),
                SeedCategory(name: "Books", symbolName: "book", keywords: "books,stationery"),
                SeedCategory(name: "Courses", symbolName: "laptopcomputer", keywords: "course,udemy,coursera"),
            ],
            seedKey: "education"
        ),
        SeedCategoryGroup(
            name: "Fees & Charges",
            symbolName: "percent",
            colorHex: "#8E8E93",
            categories: [
                SeedCategory(
                    name: "Bank fees", symbolName: "building.columns", keywords: "bank charge,ledger fee,excise"),
                SeedCategory(name: "Mobile money fees", symbolName: "phone", keywords: "transaction cost,mpesa charge"),
                SeedCategory(name: "Transfer fees", symbolName: "arrow.left.arrow.right", keywords: "transfer fee"),
            ],
            seedKey: "fees-charges"
        ),
        SeedCategoryGroup(
            name: "Family & Giving",
            symbolName: "person.2",
            colorHex: "#AC8E68",
            categories: [
                SeedCategory(
                    name: "Family support", symbolName: "figure.2.and.child.holdinghands", keywords: "family,support"),
                SeedCategory(
                    name: "Church/Charity", symbolName: "hands.and.sparkles", keywords: "church,charity,offering,tithe"),
                SeedCategory(name: "Gifts", symbolName: "gift", keywords: "gift,present"),
            ],
            seedKey: "family-giving"
        ),
        SeedCategoryGroup(
            name: "Income",
            symbolName: "arrow.down.circle",
            colorHex: "#34C759",
            kind: .income,
            categories: [
                SeedCategory(name: "Salary", symbolName: "banknote", keywords: "salary,payroll"),
                SeedCategory(name: "Business", symbolName: "briefcase", keywords: "business,invoice"),
                SeedCategory(name: "Refund", symbolName: "arrow.uturn.backward", keywords: "refund,reversal"),
                SeedCategory(name: "Gift received", symbolName: "gift", keywords: "received,gift"),
                SeedCategory(name: "Other income", symbolName: "plus.circle", keywords: "income"),
            ],
            seedKey: "income"
        ),
        SeedCategoryGroup(
            name: "Other",
            symbolName: "square.grid.2x2",
            colorHex: "#636366",
            categories: [
                SeedCategory(name: "Uncategorised", symbolName: "questionmark.circle")
            ],
            seedKey: "other"
        ),
    ]
}
