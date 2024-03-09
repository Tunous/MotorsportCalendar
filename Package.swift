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
        .package(url: "https://github.com/dmail-me/iCalendarParser", from: "0.1.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.7.1"),
    ],
    targets: [
        .executableTarget(
            name: "MotorsportCalendar",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "iCalendarParser", package: "iCalendarParser"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .target(name: "MotorsportCalendarData"),
            ]
        ),
        .target(name: "MotorsportCalendarData"),
    ]
)
