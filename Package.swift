// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WthaiqSigning",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "WthaiqSigning", targets: ["WthaiqSigning"])
    ],
    targets: [
        .target(
            name: "WthaiqSigning",
            path: "Sources/WthaiqSigning",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "WthaiqSigningTests",
            dependencies: ["WthaiqSigning"],
            path: "Tests/WthaiqSigningTests"
        )
    ]
)
