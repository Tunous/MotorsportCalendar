// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MotorsportCalendar",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .executable(name: "MotorsportCalendar", targets: ["MotorsportCalendar"]),
        .library(name: "MotorsportCalendarData", targets: ["MotorsportCalendarData"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.7.1"),
        .package(url: "https://github.com/chan614/iCalSwift", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "MotorsportCalendar",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "ICalSwift", package: "iCalSwift"),
                .target(name: "MotorsportCalendarData"),
            ]
        ),
        .target(name: "MotorsportCalendarData"),
    ]
)
