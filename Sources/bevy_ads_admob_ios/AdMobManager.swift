import AdSupport
import AdmobXcframework
import AppTrackingTransparency
import Foundation
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

@objc public class AdMobManager: NSObject {
    var canRequestAds: Bool {
        return ConsentInformation.shared.canRequestAds
    }
    var isPrivacyOptionsRequired: Bool {
        return ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    // Helper computed property to check if ads can be loaded
    private var canLoadAds: Bool {
        return isInitialized && canRequestAds
    }

    // MARK: - Properties
    private var bannerView: BannerView?
    private var interstitialAd: InterstitialAd?
    private var rewardedAd: RewardedAd?
    private var isInitialized = false

    // MARK: - Initialization
    @objc public override init() {
        super.init()
    }

    // MARK: - Public Methods
    @objc public func initialize_admob(test_device_id: RustStr) -> Bool {
        guard !isInitialized else {
            print("AdMob already initialized")
            return true
        }

        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                switch status {
                case .authorized:
                    // Tracking authorization dialog was shown
                    // and we are authorized
                    print("Authorized to ads")

                    // Now that we are authorized we can get the IDFA
                    print(ASIdentifierManager.shared().advertisingIdentifier)
                case .denied:
                    // Tracking authorization dialog was
                    // shown and permission is denied
                    print("ads Denied")
                case .notDetermined:
                    // Tracking authorization dialog has not been shown
                    print("ADS Not Determined")
                case .restricted:
                    print("ADS Restricted")

                @unknown default:
                    print("ADS Unknown")
                }
            }
        }
        // ConsentInformation.shared.reset()
        let parameters = RequestParameters()
        let test_id = test_device_id.toString()
        print("Admob setup test device: \(test_id)")
        let debugSettings = DebugSettings()
        debugSettings.geography = .EEA
        if !test_id.isEmpty {
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
                test_id
            ]
            // For testing purposes, you can use UMPDebugGeography to simulate a location.
            debugSettings.testDeviceIdentifiers = [test_id]
            print("Admob debug setup")
        }

        parameters.debugSettings = debugSettings

        print("Called init admob, can request \(self.canRequestAds)")
        if self.canRequestAds {
            self.init_ads_system()
            return true
        }

        // Always request consent info update first
        DispatchQueue.main.async {
            // Get the root view controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let window = windowScene.windows.first,
                let rootViewController = window.rootViewController
            else {
                print("Could not get root view controller for consent ads admob")
                on_initialized(false)
                return
            }
            // [START request_consent_info_update]
            // Requesting an update to consent information should be called on every app launch.
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) {
                requestConsentError in
                // [START_EXCLUDE]
                guard requestConsentError == nil else {
                    print(
                        "Error requesting consent for ads info update: \(requestConsentError!.localizedDescription)"
                    )
                    on_initialized(false)
                    return
                }
                print(
                    "Consent for ads info updated. canRequestAds: \(self.canRequestAds), formStatus: \(ConsentInformation.shared.consentStatus.rawValue)"
                )

                // Check if we can already request ads (consent previously given)
                if self.canRequestAds {
                    print("Can request ads - initializing immediately")
                    self.init_ads_system()
                } else if ConsentInformation.shared.consentStatus == .required {
                    // Need to show consent form
                    print("Consent for ads required - loading and presenting form")

                    Task { @MainActor in
                        do {
                            try await ConsentForm.loadAndPresentIfRequired(from: rootViewController)

                            // After consent form, check if we can request ads
                            print(
                                "Consent form for ads completed. canRequestAds: \(self.canRequestAds)"
                            )

                            if self.canRequestAds {
                                print("User consent granted - initializing ads")
                                self.init_ads_system()
                            } else {
                                print("User consent not granted for ads")
                                on_initialized(false)
                            }
                        } catch {
                            print(
                                "Error loading/presenting consent form for ads: \(error.localizedDescription)"
                            )
                            on_initialized(false)
                        }
                    }
                } else {
                    // Consent not required and can't request ads - edge case
                    print(
                        "Consent not required but can't request ads - consent status: \(ConsentInformation.shared.consentStatus.rawValue)"
                    )
                    on_initialized(false)
                }
            }
        }
        return true
    }

    /// Helper method to call the UMP SDK method to present the privacy options form.
    @MainActor func presentPrivacyOptionsForm(from viewController: UIViewController? = nil)
        async throws
    {
        try await ConsentForm.presentPrivacyOptionsForm(from: viewController)
    }

    func init_ads_system() {
        // Ensure we're on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.init_ads_system()
            }
            return
        }
        print("Starting ads admob initialization...")
        MobileAds.shared.start { [weak self] status in
            self?.isInitialized = true
            print("AdMob initialized with status: \(status.adapterStatusesByClassName)")
            print("Can request ads after init: \(self?.canRequestAds ?? false)")

            on_initialized(true)
        }

    }

    @objc public func load_banner_ad(ad_unit_id: RustStr, width: Int32, height: Int32) -> Bool {
        guard canLoadAds else {
            if !isInitialized {
                print("AdMob not initialized")
            } else if !canRequestAds {
                print("Cannot request ads - consent not granted")
            }
            return false
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Create banner view
            let adSize = adSizeFor(cgSize: CGSize(width: CGFloat(width), height: CGFloat(height)))
            self.bannerView = BannerView(adSize: adSize)
            self.bannerView?.adUnitID = ad_unit_id.toString()

            // Set root view controller
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let window = windowScene.windows.first
            {
                self.bannerView?.rootViewController = window.rootViewController
            }

            // Set delegate
            self.bannerView?.delegate = self

            // Load ad
            let request = Request()
            self.bannerView?.load(request)
        }

        return true
    }

    @objc public func show_banner_ad() -> Bool {
        guard let bannerView = bannerView else {
            print("Banner ad not loaded")
            return false
        }

        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let window = windowScene.windows.first,
                let rootViewController = window.rootViewController
            {

                // Add banner to bottom of screen
                bannerView.translatesAutoresizingMaskIntoConstraints = false
                rootViewController.view.addSubview(bannerView)

                NSLayoutConstraint.activate([
                    bannerView.centerXAnchor.constraint(
                        equalTo: rootViewController.view.centerXAnchor),
                    bannerView.bottomAnchor.constraint(
                        equalTo: rootViewController.view.safeAreaLayoutGuide.bottomAnchor),
                ])
            }
        }

        return true
    }

    @objc public func hide_banner_ad() -> Bool {
        guard let bannerView = bannerView else {
            return false
        }

        DispatchQueue.main.async {
            bannerView.removeFromSuperview()
        }

        return true
    }

    @objc public func load_interstitial_ad(ad_unit_id: RustStr) -> Bool {
        guard canLoadAds else {
            if !isInitialized {
                print("AdMob not initialized")
            } else if !canRequestAds {
                print("Cannot request ads - consent not granted")
            }
            return false
        }

        let request = Request()

        InterstitialAd.load(with: ad_unit_id.toString(), request: request) {
            [weak self] ad, error in
            if let error = error {
                print("Failed to load interstitial ad: \(error.localizedDescription)")
                on_ad_failed_to_load("interstitial", error.localizedDescription)
                return
            }

            self?.interstitialAd = ad
            self?.interstitialAd?.fullScreenContentDelegate = self
            on_ad_loaded("interstitial")
        }

        return true
    }

    @objc public func show_interstitial_ad() -> Bool {
        guard let interstitialAd = interstitialAd else {
            print("Interstitial ad not loaded")
            return false
        }

        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let window = windowScene.windows.first,
                let rootViewController = window.rootViewController
            {
                interstitialAd.present(from: rootViewController)
            }
        }

        return true
    }

    @objc public func load_rewarded_ad(ad_unit_id: RustStr) -> Bool {
        guard canLoadAds else {
            if !isInitialized {
                print("AdMob not initialized")
            } else if !canRequestAds {
                print("Cannot request ads - consent not granted")
            }
            return false
        }

        let request = Request()
        let ad_unit = ad_unit_id.toString()

        RewardedAd.load(with: ad_unit, request: request) { [weak self] ad, error in
            if let error = error {
                print("Failed to load rewarded ad: \(error.localizedDescription) \(ad_unit)")
                on_ad_failed_to_load("rewarded", error.localizedDescription)
                return
            }

            self?.rewardedAd = ad
            self?.rewardedAd?.fullScreenContentDelegate = self
            print("Loaded rewarded ad: \(ad_unit)")
            on_ad_loaded("rewarded")
        }

        return true
    }

    @objc public func show_rewarded_ad() -> Bool {
        guard let rewardedAd = rewardedAd else {
            print("Rewarded ad not loaded")
            return false
        }

        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let window = windowScene.windows.first,
                let rootViewController = window.rootViewController
            {
                rewardedAd.present(from: rootViewController) { [weak self] in
                    let reward = rewardedAd.adReward
                    print("User earned reward: \(reward.amount) \(reward.type)")
                    on_rewarded_ad_earned_reward(Int32(truncating: reward.amount), reward.type)
                }
            }
        }

        return true
    }

    @objc public func is_interstitial_ready() -> Bool {
        return interstitialAd != nil
    }

    @objc public func is_rewarded_ready() -> Bool {
        return rewardedAd != nil
    }
}

// MARK: - GADBannerViewDelegate
extension AdMobManager: BannerViewDelegate {
    public func bannerViewDidReceiveAd(_ bannerView: BannerViewDelegate) {
        print("Banner ad loaded successfully")
        on_ad_loaded("banner")
    }

    public func bannerView(
        _ bannerView: BannerViewDelegate, didFailToReceiveAdWithError error: Error
    ) {
        print("Banner ad failed to load: \(error.localizedDescription)")
        on_ad_failed_to_load("banner", error.localizedDescription)
    }

    public func bannerViewWillPresentScreen(_ bannerView: BannerViewDelegate) {
        print("Banner ad will present screen")
        on_ad_opened("banner")
    }

    public func bannerViewWillDismissScreen(_ bannerView: BannerViewDelegate) {
        print("Banner ad will dismiss screen")
    }

    public func bannerViewDidDismissScreen(_ bannerView: BannerViewDelegate) {
        print("Banner ad did dismiss screen")
        on_ad_closed("banner")
    }
}

// MARK: - GADFullScreenContentDelegate
extension AdMobManager: FullScreenContentDelegate {
    public func ad(
        ad_f: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error
    ) {
        let adType = (ad_f is InterstitialAd) ? "interstitial" : "rewarded"
        print("\(adType) ad failed to present: \(error.localizedDescription)")
        on_ad_failed_to_load(adType, error.localizedDescription)
    }

    public func adWillPresentFullScreenContent(ad_f: FullScreenPresentingAd) {
        let adType = (ad_f is InterstitialAd) ? "interstitial" : "rewarded"
        print("\(adType) ad will present")
        on_ad_opened(adType)
    }

    public func adDidDismissFullScreenContent(ad_f: FullScreenPresentingAd) {
        let adType = (ad_f is InterstitialAd) ? "interstitial" : "rewarded"
        print("\(adType) ad did dismiss")
        on_ad_closed(adType)

        // Clear the ad reference
        if ad is InterstitialAd {
            self.interstitialAd = nil
        } else if ad is RewardedAd {
            self.rewardedAd = nil
        }
    }
}
