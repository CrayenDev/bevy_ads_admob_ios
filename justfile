build: clean
    cargo build --target aarch64-apple-ios
    cargo build --target x86_64-apple-ios
    just prepare ios-arm64
    just prepare ios-arm64_x86_64-simulator
    just copy_swift
    mkdir -p target/universal-ios/debug
    lipo -create "./target/aarch64-apple-ios/debug/libbevy_ads_admob_ios.a" \
        "./target/x86_64-apple-ios/debug/libbevy_ads_admob_ios.a" \
        -output ./target/universal-ios/debug/libbevy_ads_admob_ios.a
    cp target/aarch64-apple-ios/debug/libbevy_ads_admob_ios.a ./AdmobXcframework.xcframework/ios-arm64/
    cp target/universal-ios/debug/libbevy_ads_admob_ios.a ./AdmobXcframework.xcframework/ios-arm64_x86_64-simulator/

build-release: clean
    cargo build --target aarch64-apple-ios --release
    cargo build --target x86_64-apple-ios --release
    just prepare ios-arm64
    just prepare ios-arm64_x86_64-simulator
    just copy_swift
    mkdir -p target/universal-ios/release
    lipo -create "./target/aarch64-apple-ios/release/libbevy_ads_admob_ios.a" \
        "./target/x86_64-apple-ios/release/libbevy_ads_admob_ios.a" \
        -output ./target/universal-ios/release/libbevy_ads_admob_ios.a
    cp target/aarch64-apple-ios/release/libbevy_ads_admob_ios.a ./AdmobXcframework.xcframework/ios-arm64/
    cp target/universal-ios/release/libbevy_ads_admob_ios.a ./AdmobXcframework.xcframework/ios-arm64_x86_64-simulator/

full: clean
    just build-release
    cp target/aarch64-apple-ios/release/libbevy_ads_admob_ios.a ./AdmobXcframework.xcframework/ios-arm64/
    cp target/universal-ios/release/libbevy_ads_admob_ios.a ./AdmobXcframework.xcframework/ios-arm64_x86_64-simulator/

prepare $target:
    mkdir AdmobXcframework.xcframework/$target
    mkdir AdmobXcframework.xcframework/$target/Headers
    printf "module AdmobXcframework {\n    header \"SwiftBridgeCore.h\"\n    header \"bevy_ads_admob_ios.h\"\n    export *\n}\n" > ./AdmobXcframework.xcframework/$target/Headers/module.modulemap
    cp generated/bevy_ads_admob_ios/*.h ./AdmobXcframework.xcframework/$target/Headers/
    cp generated/*.h ./AdmobXcframework.xcframework/$target/Headers/

copy_swift:
    echo "import AdmobXcframework "|cat - ./generated/SwiftBridgeCore.swift > ./Sources/bevy_ads_admob_ios/SwiftBridgeCore.swift
    echo "import AdmobXcframework "|cat - ./generated/bevy_ads_admob_ios/bevy_ads_admob_ios.swift > ./Sources/bevy_ads_admob_ios/bevy_ads_admob_ios.swift

clean:
    rm -rf AdmobXcframework.xcframework/ios-arm64
    rm -rf AdmobXcframework.xcframework/ios-arm64_x86_64-simulator

zip:
    mkdir -p dist
    zip -r dist/AdmobXcframework.xcframework.zip ./AdmobXcframework.xcframework/
    ls -lisah dist/AdmobXcframework.xcframework.zip
    shasum -a 256 dist/AdmobXcframework.xcframework.zip
    shasum -a 256 dist/AdmobXcframework.xcframework.zip > dist/AdmobXcframework.xcframework.sha256.txt
