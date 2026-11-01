// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Barycenter",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0"),
        .package(url: "https://github.com/raspu/Highlightr.git", exact: "2.3.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Barycenter",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Highlightr", package: "Highlightr"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .copy("Resources/marked.min.js"),
                .copy("Resources/github-markdown-dark.min.css"),
            ],
            linkerSettings: [
                // Find embedded frameworks (Sparkle) in the app bundle's Frameworks dir.
                // SwiftPM executables don't get this app-bundle rpath by default.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "BarycenterTests",
            dependencies: ["Barycenter"]
        ),
    ]
)
