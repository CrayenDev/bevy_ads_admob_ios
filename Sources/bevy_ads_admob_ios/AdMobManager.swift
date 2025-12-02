import AdmobXcframework
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
        let test_id = test_device_id.toString()
        if !test_id.isEmpty {
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
                test_id
            ]
        }
        MobileAds.shared.start { [weak self] status in
            self?.isInitialized = true
            print("AdMob initialized with status: \(status.adapterStatusesByClassName))")

            on_initialized(true)
        }
        // DispatchQueue.main.async { [weak self] in
        //     guard let self = self else { return }
        //     // ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) {
        //     //     requestConsentError in
        //     //           guard requestConsentError == nil else {
        //     //               print("Error: \(requestConsentError!.localizedDescription)")
        //     //               on_consent_gathered(requestConsentError!.localizedDescription)
        //     //               return
        //     //           }
        //     //     Task {
        //     //       do {
        //     //         try await ConsentForm.loadAndPresentIfRequired(from: nil)
        //     //           on_consent_gathered("")
        //     //           print("Consent has been gathered")
        //     //       } catch {
        //     //           on_consent_gathered(error.localizedDescription)
        //     //           print("Error: \(error.localizedDescription)")
        //     //       }
        //     //     }
        //     // }

        // }
        return true
    }

    @objc public func load_banner_ad(ad_unit_id: RustStr, width: Int32, height: Int32) -> Bool {
        guard isInitialized else {
            print("AdMob not initialized")
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
        guard isInitialized else {
            print("AdMob not initialized")
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
        guard isInitialized else {
            print("AdMob not initialized")
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
