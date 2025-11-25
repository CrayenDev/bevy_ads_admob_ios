# Bevy AdMob Integration

This crate provides AdMob integration for Bevy applications on iOS through swift-bridge.

## Features

- Banner ads
- Interstitial ads
- Rewarded ads
- Event-driven architecture with Bevy events
- Cross-platform compatibility (iOS-specific functionality, no-ops on other platforms)

## Setup

### iOS Project Setup

**Update Info.plist:**
   ```xml
   <key>GADApplicationIdentifier</key>
   <string>YOUR_ADMOB_APP_ID</string>
   ```
