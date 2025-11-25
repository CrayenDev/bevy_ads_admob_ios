// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "bevy_ads_admob",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "bevy_ads_admob",
            targets: ["bevy_ads_admob"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git",
            from: "12.14.0"
        )
    ],
    targets: [
        .binaryTarget(
            name: "AdmobXcframework",
            path: "AdmobXcframework.xcframework"),

        .target(
            name: "bevy_ads_admob",
            dependencies: [
                "AdmobXcframework",
                .product(
                    name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
            ],
        ),
    ]
)
