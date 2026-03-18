import AdSupport
import AdmobXcframework
import AppTrackingTransparency
import Foundation
import GoogleMobileAds
import UIKit
import UserMessagingPlatform
import os

// MARK: - BannerPosition

/// Banner display position. Raw value is the integer passed across the Rust bridge.
private enum BannerPosition: Int32 {
    case bottom = 0
    case top = 1
}

// MARK: - Consent status helpers

/// Human-readable name for `UMPConsentStatus`.
private func consentStatusName(_ status: ConsentStatus) -> String {
    switch status {
    case .unknown: return "unknown"
    case .required: return "required"
    case .notRequired: return "notRequired"
    case .obtained: return "obtained"
    @unknown default: return "unrecognised(\(status.rawValue))"
    }
}

/// Human-readable name for `UMPFormStatus`.
private func formStatusName(_ status: FormStatus) -> String {
    switch status {
    case .unknown: return "unknown"
    case .available: return "available"
    case .unavailable: return "unavailable"
    @unknown default: return "unrecognised(\(status.rawValue))"
    }
}

/// Human-readable name for `ATTrackingManager.AuthorizationStatus`.
@available(iOS 14, *)
private func attStatusName(_ status: ATTrackingManager.AuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unrecognised(\(status.rawValue))"
    }
}

// MARK: - Timeout helper result

/// Outcome of the `withTimeout` utility.
private enum TimeoutResult {
    case completed
    case timedOut
}

// MARK: - AdMobManager

@objc public class AdMobManager: NSObject {

    // MARK: - Logging

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "bevy_ads", category: "AdMob")

    // MARK: - Consent timeout

    /// Maximum time to wait for the UMP consent info update before giving up.
    private let consentTimeoutSeconds: Duration = .seconds(10)

    // MARK: - Main-actor state
    // All mutable UI-bound state lives here. It is written exclusively from @MainActor
    // tasks and read from @objc entry points via the nonisolated(unsafe) mirrors below.

    @MainActor private var bannerView: BannerView?
    @MainActor private var bannerPosition: BannerPosition = .bottom
    @MainActor private var interstitialAd: InterstitialAd?
    @MainActor private var rewardedAd: RewardedAd?
    /// A transparent UIWindow placed above the game's Metal window, used to present
    /// UIKit content (consent forms, fullscreen ads, banner ads) above the CAMetalLayer.
    @MainActor private var overlayWindow: UIWindow?

    // Ad unit IDs are stored alongside their ad references for logging.
    @MainActor private var lastInterstitialUnitID: String?
    @MainActor private var lastRewardedUnitID: String?

    // Nonisolated mirrors so `adUnitID(for:)` can be called from nonisolated
    // delegate methods without requiring an async hop.
    nonisolated(unsafe) private var _lastInterstitialUnitID: String?
    nonisolated(unsafe) private var _lastRewardedUnitID: String?

    // MARK: - Synchronous state mirrors
    // Written only from @MainActor (always paired with the actor-isolated property),
    // read from nonisolated @objc entry points where an async hop would be unsound.
    // The nonisolated(unsafe) annotation acknowledges the compiler cannot verify
    // the invariant; it is enforced by convention via the setter helpers below.

    nonisolated(unsafe) private var _isInitialized = false
    nonisolated(unsafe) private var _isInitializing = false
    nonisolated(unsafe) private var _isBannerLoaded = false
    nonisolated(unsafe) private var _hasBannerView = false
    nonisolated(unsafe) private var _hasInterstitial = false
    nonisolated(unsafe) private var _hasRewarded = false
    nonisolated(unsafe) private var _canRequestAds = false
    nonisolated(unsafe) private var _isPrivacyOptionsRequired = false

    // MARK: - Mirror setter helpers
    // Centralise the dual-write so callers cannot forget to update one side.

    @MainActor private func setInitialized(_ value: Bool) {
        _isInitialized = value
    }

    @MainActor private func setInitializing(_ value: Bool) {
        _isInitializing = value
    }

    @MainActor private func setBannerLoaded(_ value: Bool) {
        _isBannerLoaded = value
    }

    @MainActor private func setHasBannerView(_ value: Bool) {
        _hasBannerView = value
    }

    @MainActor private func setHasInterstitial(_ value: Bool) {
        _hasInterstitial = value
    }

    @MainActor private func setHasRewarded(_ value: Bool) {
        _hasRewarded = value
    }

    /// Refreshes the synchronous mirrors for consent-related state from UMP.
    /// Call this after any operation that may change consent (init, form dismiss, etc.).
    @MainActor private func refreshConsentMirrors() {
        _canRequestAds = ConsentInformation.shared.canRequestAds
        _isPrivacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    // Derived mirror used by load_* guards — reads only nonisolated(unsafe) mirrors.
    private var _canLoadAds: Bool { _isInitialized && _canRequestAds }

    // MARK: - Initialization

    @objc public override init() {
        super.init()
    }

    // MARK: - Public API

    @objc public func is_privacy_options_required() -> Bool {
        return _isPrivacyOptionsRequired
    }

    /// Present the UMP privacy-options form in response to a user action (e.g. a
    /// "Manage Privacy" button). After the form is dismissed, `on_consent_gathered`
    /// is called so the Rust side can react to any consent change.
    @objc public func show_privacy_options_form() -> Bool {
        guard _isPrivacyOptionsRequired else {
            logger.debug("Privacy options form is not required — skipping.")
            return false
        }

        Task { @MainActor in
            guard let rootViewController = self.getOrCreateOverlayViewController() else {
                self.logger.error(
                    "show_privacy_options_form: could not obtain overlay view controller.")
                on_consent_gathered("Could not obtain root view controller")
                return
            }
            do {
                let formStatus = ConsentInformation.shared.formStatus
                self.logger.debug(
                    "Presenting privacy options form. formStatus=\(formStatusName(formStatus), privacy: .public)"
                )

                try await ConsentForm.presentPrivacyOptionsForm(from: rootViewController)

                self.refreshConsentMirrors()
                self.logger.debug("Privacy options form dismissed.")
                self.dismissOverlayWindow()

                if self._canRequestAds {
                    on_consent_gathered("")
                } else {
                    self.logger.warning("Consent withdrawn via privacy options form.")
                    on_consent_gathered("User withdrew consent")
                }
                self.logIABTCFConsentStrings()
            } catch {
                self.logger.error(
                    "Privacy options form error: \(error.localizedDescription, privacy: .public)")
                self.dismissOverlayWindow()
                on_consent_gathered(error.localizedDescription)
            }
        }

        return true
    }

    @objc public func initialize_admob(test_device_id: RustStr) -> Bool {
        // Guard against duplicate calls — both fully initialised and mid-flight.
        guard !_isInitialized && !_isInitializing else {
            logger.debug(
                "AdMob already initialised or initialising — ignoring duplicate call.")
            return true
        }

        let testID = test_device_id.toString()

        // Build UMP request parameters.
        let parameters = RequestParameters()

        if !testID.isEmpty {
            // Debug settings only apply when a test device ID is provided
            // (i.e. development / QA builds). Never simulate EEA in production.
            let debugSettings = DebugSettings()
            debugSettings.geography = .EEA
            debugSettings.testDeviceIdentifiers = [testID]
            parameters.debugSettings = debugSettings

            // Register the test device with the Mobile Ads SDK as well.
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [testID]

            logger.debug(
                "AdMob debug mode — test device: \(testID, privacy: .public), geography: EEA")
        }

        logger.debug(
            "[init step 1/4] Starting consent info update. canRequestAds=\(ConsentInformation.shared.canRequestAds)"
        )

        // Mark as in-flight before the async work begins.
        Task { @MainActor in
            self.setInitializing(true)
        }

        // Consent information must be refreshed on every app launch.
        Task { @MainActor in
            let startTime = ContinuousClock.now

            guard let rootViewController = self.getOrCreateOverlayViewController() else {
                self.logger.error("initialize_admob: could not obtain overlay view controller.")
                self.finishInitializing()
                on_consent_gathered("Could not obtain root view controller")
                return
            }

            await self.runConsentFlow(
                parameters: parameters, from: rootViewController, startTime: startTime)
        }

        return true
    }

    // MARK: - Banner ads

    @objc public func load_banner_ad(ad_unit_id: RustStr, width: Int32, height: Int32) -> Bool {
        let unitID = ad_unit_id.toString()
        guard _canLoadAds else {
            logNotReady(context: "load_banner_ad(\(unitID))")
            return false
        }

        Task { @MainActor in
            // `adSizeFor(cgSize:)` is a GoogleMobileAds SDK top-level function
            // (re-exported via the SPM `GoogleMobileAds` module). It converts a
            // CGSize into the nearest supported GADAdSize.
            let adSize = adSizeFor(cgSize: CGSize(width: CGFloat(width), height: CGFloat(height)))
            let banner = BannerView(adSize: adSize)
            banner.adUnitID = unitID
            banner.rootViewController = self.getOrCreateOverlayViewController()
            banner.delegate = self
            self.bannerView = banner
            self.setBannerLoaded(false)
            self.setHasBannerView(true)

            self.logger.debug(
                "Loading banner ad — unit: \(unitID, privacy: .public) size: \(width)x\(height)")
            banner.load(Request())
        }

        return true
    }

    /// Shows the loaded banner at the given position.
    /// - Parameter position: 0 = bottom (default), 1 = top.
    @objc public func show_banner_ad(position: Int32) -> Bool {
        guard _hasBannerView && _isBannerLoaded else {
            logger.warning(
                "show_banner_ad called but banner is not ready (hasBannerView=\(self._hasBannerView) loaded=\(self._isBannerLoaded))"
            )
            return false
        }

        Task { @MainActor in
            guard
                let banner = self.bannerView,
                let overlayVC = self.getOrCreateOverlayViewController()
            else { return }

            let resolvedPosition = BannerPosition(rawValue: position) ?? .bottom
            self.bannerPosition = resolvedPosition

            // Idempotent — skip if already in the view hierarchy.
            guard banner.superview == nil else {
                self.logger.debug(
                    "show_banner_ad: banner already in view hierarchy — updating position only.")
                self.applyBannerConstraints(
                    banner: banner, in: overlayVC.view,
                    position: resolvedPosition)
                return
            }

            banner.translatesAutoresizingMaskIntoConstraints = false
            overlayVC.view.addSubview(banner)
            self.applyBannerConstraints(
                banner: banner, in: overlayVC.view,
                position: resolvedPosition)

            self.logger.debug(
                "Banner ad shown at \(resolvedPosition == .top ? "top" : "bottom", privacy: .public)."
            )
        }

        return true
    }

    @objc public func hide_banner_ad() -> Bool {
        guard _hasBannerView else { return false }

        Task { @MainActor in
            self.bannerView?.removeFromSuperview()
            self.logger.debug("Banner ad hidden.")
            // Release the overlay window now that the banner is gone. It will be
            // re-created on demand if another banner or fullscreen ad is shown.
            self.dismissOverlayWindow()
        }

        return true
    }

    // MARK: - Interstitial ads

    @objc public func load_interstitial_ad(ad_unit_id: RustStr) -> Bool {
        let unitID = ad_unit_id.toString()
        guard _canLoadAds else {
            logNotReady(context: "load_interstitial_ad(\(unitID))")
            return false
        }

        logger.debug("Loading interstitial ad — unit: \(unitID, privacy: .public)")
        InterstitialAd.load(with: unitID, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            if let error {
                self.logger.error(
                    "Interstitial load failed (\(unitID, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                )
                on_ad_failed_to_load("interstitial", error.localizedDescription)
                return
            }
            Task { @MainActor in
                self.interstitialAd = ad
                self.interstitialAd?.fullScreenContentDelegate = self
                self.lastInterstitialUnitID = unitID
                self._lastInterstitialUnitID = unitID
                self.setHasInterstitial(true)
                self.logger.debug("Interstitial ad loaded — unit: \(unitID, privacy: .public)")
                on_ad_loaded("interstitial")
            }
        }

        return true
    }

    @objc public func show_interstitial_ad() -> Bool {
        guard _hasInterstitial else {
            logger.warning("show_interstitial_ad called but no interstitial is loaded.")
            return false
        }

        Task { @MainActor in
            guard
                let ad = self.interstitialAd,
                let overlayVC = self.getOrCreateOverlayViewController()
            else { return }
            ad.present(from: overlayVC)
            self.logger.debug(
                "Interstitial ad presented — unit: \(self.lastInterstitialUnitID ?? "?", privacy: .public)."
            )
        }

        return true
    }

    // MARK: - Rewarded ads

    @objc public func load_rewarded_ad(ad_unit_id: RustStr) -> Bool {
        let unitID = ad_unit_id.toString()
        guard _canLoadAds else {
            logNotReady(context: "load_rewarded_ad(\(unitID))")
            return false
        }

        logger.debug("Loading rewarded ad — unit: \(unitID, privacy: .public)")
        RewardedAd.load(with: unitID, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            if let error {
                self.logger.error(
                    "Rewarded load failed (\(unitID, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                )
                on_ad_failed_to_load("rewarded", error.localizedDescription)
                return
            }
            Task { @MainActor in
                self.rewardedAd = ad
                self.rewardedAd?.fullScreenContentDelegate = self
                self.lastRewardedUnitID = unitID
                self._lastRewardedUnitID = unitID
                self.setHasRewarded(true)
                self.logger.debug("Rewarded ad loaded — unit: \(unitID, privacy: .public)")
                on_ad_loaded("rewarded")
            }
        }

        return true
    }

    @objc public func show_rewarded_ad() -> Bool {
        guard _hasRewarded else {
            logger.warning("show_rewarded_ad called but no rewarded ad is loaded.")
            return false
        }

        Task { @MainActor in
            guard
                let ad = self.rewardedAd,
                let overlayVC = self.getOrCreateOverlayViewController()
            else { return }

            ad.present(from: overlayVC) { [weak self] in
                let reward = ad.adReward
                self?.logger.debug(
                    "User earned reward: \(reward.amount) \(reward.type, privacy: .public)")
                on_rewarded_ad_earned_reward(Int32(truncating: reward.amount), reward.type)
            }
            self.logger.debug(
                "Rewarded ad presented — unit: \(self.lastRewardedUnitID ?? "?", privacy: .public)."
            )
        }

        return true
    }

    // MARK: - Ready state queries

    @objc public func is_banner_ready() -> Bool {
        return _hasBannerView && _isBannerLoaded
    }

    @objc public func is_interstitial_ready() -> Bool {
        return _hasInterstitial
    }

    @objc public func is_rewarded_ready() -> Bool {
        return _hasRewarded
    }

    // MARK: - Private helpers

    /// Applies the banner's position constraints inside `superview`, removing any
    /// previously installed banner constraints first.
    @MainActor private func applyBannerConstraints(
        banner: BannerView, in superview: UIView, position: BannerPosition
    ) {
        // Remove any existing constraints that involve the banner.
        superview.constraints
            .filter { $0.firstItem === banner || $0.secondItem === banner }
            .forEach { $0.isActive = false }

        let anchor: NSLayoutConstraint
        switch position {
        case .top:
            anchor = banner.topAnchor.constraint(
                equalTo: superview.safeAreaLayoutGuide.topAnchor)
        case .bottom:
            anchor = banner.bottomAnchor.constraint(
                equalTo: superview.safeAreaLayoutGuide.bottomAnchor)
        }

        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: superview.centerXAnchor),
            anchor,
        ])
    }

    /// Returns the key window's root view controller for the first connected scene.
    @MainActor private func keyRootViewController() -> UIViewController? {
        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.keyWindow ?? windowScene.windows.first
        else {
            logger.error("keyRootViewController: no UIWindowScene / window available.")
            return nil
        }
        return window.rootViewController
    }

    /// Returns the root view controller of a transparent overlay UIWindow that sits above
    /// the game's Metal rendering window. All UIKit content that must appear over the
    /// CAMetalLayer (consent forms, fullscreen ads, banner ads) should be presented from
    /// this view controller.
    ///
    /// The overlay window is created lazily on first call and reused until
    /// `dismissOverlayWindow()` is called. It uses `.alert + 1` window level so it
    /// appears above every other window, including the game's winit UIWindow.
    @MainActor private func getOrCreateOverlayViewController() -> UIViewController? {
        if let existing = overlayWindow {
            return existing.rootViewController
        }

        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        else {
            logger.error("getOrCreateOverlayViewController: no UIWindowScene available.")
            return nil
        }

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isOpaque = false

        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.isOpaque = false
        window.rootViewController = vc
        window.makeKeyAndVisible()

        overlayWindow = window
        logger.debug("Overlay window created (windowLevel=\(window.windowLevel.rawValue)).")
        return vc
    }

    /// Hides and releases the overlay window. Call this once the content presented from
    /// `getOrCreateOverlayViewController()` has been fully dismissed.
    ///
    /// - Important: Do **not** call this while a banner ad is still visible, since the
    ///   banner lives as a subview of the overlay window's root view.
    @MainActor private func dismissOverlayWindow() {
        guard overlayWindow != nil else { return }
        overlayWindow?.isHidden = true
        overlayWindow = nil
        logger.debug("Overlay window dismissed.")
    }

    /// Resets the initialising flag on both the actor-isolated and mirror copies.
    @MainActor private func finishInitializing() {
        setInitializing(false)
    }

    /// Runs the full consent info update + form presentation flow with a timeout.
    @MainActor private func runConsentFlow(
        parameters: RequestParameters, from rootViewController: UIViewController,
        startTime: ContinuousClock.Instant
    ) async {
        let result = await withTimeout(consentTimeoutSeconds) { [weak self] in
            guard let self else { return }
            await self.requestConsentInfoUpdate(
                parameters: parameters, from: rootViewController, startTime: startTime)
        }

        if result == .timedOut {
            logger.error(
                "Consent info update timed out after \(self.consentTimeoutSeconds) — proceeding without consent."
            )
            finishInitializing()
            on_consent_gathered("Timeout")
        }
    }

    /// Wraps `ConsentInformation.requestConsentInfoUpdate` in a checked continuation
    /// so the caller can `await` its completion.
    private func requestConsentInfoUpdate(
        parameters: RequestParameters, from rootViewController: UIViewController,
        startTime: ContinuousClock.Instant
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
                guard let self else { continuation.resume(); return }

                if let error {
                    self.logger.error(
                        "Consent info update failed: \(error.localizedDescription, privacy: .public)"
                    )
                    Task { @MainActor in
                        self.finishInitializing()
                        on_consent_gathered(error.localizedDescription)
                    }
                    continuation.resume()
                    return
                }

                Task { @MainActor in
                    self.refreshConsentMirrors()

                    let status = ConsentInformation.shared.consentStatus
                    let formStatus = ConsentInformation.shared.formStatus
                    let elapsed = ContinuousClock.now - startTime

                    self.logger.debug(
                        "[init step 2/4] Consent info updated (\(elapsed)). consentStatus=\(consentStatusName(status), privacy: .public) formStatus=\(formStatusName(formStatus), privacy: .public) canRequestAds=\(self._canRequestAds)"
                    )

                    await self.handleConsentResult(from: rootViewController, startTime: startTime)
                    continuation.resume()
                }
            }
        }
    }

    /// After the UMP info update completes, decide whether to show the consent form,
    /// skip it, and when to proceed to MobileAds initialisation.
    @MainActor private func handleConsentResult(
        from rootViewController: UIViewController,
        startTime: ContinuousClock.Instant
    ) async {
        let status = ConsentInformation.shared.consentStatus

        if _canRequestAds {
            // Consent was previously granted (or not required). Skip the form.
            logger.debug(
                "Consent already granted (status=\(consentStatusName(status), privacy: .public)) — proceeding to SDK init."
            )
            dismissOverlayWindow()
            on_consent_gathered("")
            logIABTCFConsentStrings()
            await startMobileAdsSdk(startTime: startTime)
            return
        }

        switch status {
        case .required:
            // First-run or stale consent: load and present the form if needed.
            let formStatus = ConsentInformation.shared.formStatus
            logger.debug(
                "[init step 3/4] Consent required — loading UMP form. formStatus=\(formStatusName(formStatus), privacy: .public)"
            )
            do {
                try await ConsentForm.loadAndPresentIfRequired(from: rootViewController)
                refreshConsentMirrors()
                logger.debug(
                    "UMP form dismissed. canRequestAds=\(self._canRequestAds)")
                logIABTCFConsentStrings()
                // The consent form has been dismissed; release the overlay window now.
                // startMobileAdsSdk may trigger the ATT prompt (presented from a fresh
                // overlay) so we dismiss here before that step.
                dismissOverlayWindow()

                if _canRequestAds {
                    on_consent_gathered("")
                    await startMobileAdsSdk(startTime: startTime)
                } else {
                    logger.warning("User did not grant consent.")
                    finishInitializing()
                    on_consent_gathered("User did not grant consent")
                }
            } catch {
                logger.error("UMP form error: \(error.localizedDescription, privacy: .public)")
                dismissOverlayWindow()
                finishInitializing()
                on_consent_gathered(error.localizedDescription)
            }

        case .notRequired:
            // Outside a region that requires explicit consent — ads are allowed.
            logger.debug("Consent not required in this region — proceeding to SDK init.")
            dismissOverlayWindow()
            on_consent_gathered("")
            logIABTCFConsentStrings()
            await startMobileAdsSdk(startTime: startTime)

        case .obtained:
            // canRequestAds was false even though consent is obtained. This means the
            // user gave limited consent (e.g. rejected personalised ads). The SDK will
            // serve non-personalised ads only. Report the limitation to the Rust side
            // so it can react (e.g. hide personalisation-dependent features).
            logger.warning(
                "Consent obtained but canRequestAds=false — ads will be limited. Proceeding to SDK init."
            )
            dismissOverlayWindow()
            logIABTCFConsentStrings()
            on_consent_gathered("limited")
            await startMobileAdsSdk(startTime: startTime)

        case .unknown:
            fallthrough
        @unknown default:
            logger.error(
                "Unexpected consent status (\(consentStatusName(status), privacy: .public)) — cannot initialise ads."
            )
            dismissOverlayWindow()
            finishInitializing()
            on_consent_gathered("Unexpected consent status: \(consentStatusName(status))")
        }
    }

    /// Requests ATT authorisation (iOS 14+) then starts the Google Mobile Ads SDK.
    /// ATT is requested *after* the UMP consent flow as recommended by Google/Apple.
    @MainActor private func startMobileAdsSdk(startTime: ContinuousClock.Instant) async {
        let attStatus = await requestTrackingAuthorizationIfNeeded()

        let elapsed = ContinuousClock.now - startTime
        logger.debug("[init step 4/4] Starting MobileAds SDK… (\(elapsed) since init start)")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            MobileAds.shared.start { [weak self] initStatus in
                guard let self else { continuation.resume(); return }
                Task { @MainActor in
                    await self.finishMobileAdsStart(
                        initStatus: initStatus,
                        attStatus: attStatus,
                        startTime: startTime)
                    continuation.resume()
                }
            }
        }
    }

    /// Called on @MainActor once `MobileAds.shared.start` completes.
    @MainActor private func finishMobileAdsStart(
        initStatus: InitializationStatus,
        attStatus: ATTrackingManager.AuthorizationStatus?,
        startTime: ContinuousClock.Instant
    ) async {
        setInitialized(true)
        finishInitializing()
        refreshConsentMirrors()

        // Log only adapters that are not yet ready — avoid dumping
        // the full dictionary which produces an unreadable blob.
        let notReady = initStatus.adapterStatusesByClassName
            .filter { $0.value.state != .ready }
            .map { "\($0.key): \($0.value.state.rawValue)" }
        if notReady.isEmpty {
            logger.debug("MobileAds SDK started — all adapters ready.")
        } else {
            logger.warning(
                "MobileAds SDK started — adapters not ready: \(notReady.joined(separator: ", "), privacy: .public)"
            )
        }

        // Final summary log for the entire initialisation flow.
        let totalElapsed = ContinuousClock.now - startTime
        let consentStatus = ConsentInformation.shared.consentStatus
        var attSummary = "n/a"
        if #available(iOS 14, *) {
            attSummary = attStatus.map { attStatusName($0) } ?? "skipped"
        }
        logger.info(
            "AdMob init complete (\(totalElapsed)). consent=\(consentStatusName(consentStatus), privacy: .public) ATT=\(attSummary, privacy: .public) canRequestAds=\(self._canRequestAds) privacyOptionsRequired=\(self._isPrivacyOptionsRequired)"
        )

        on_initialized(true)
    }

    /// Requests ATT tracking authorisation on iOS 14+ and logs the outcome.
    /// Returns the resulting ATT status, or `nil` if ATT is unavailable.
    @MainActor private func requestTrackingAuthorizationIfNeeded()
        async -> ATTrackingManager.AuthorizationStatus?
    {
        guard #available(iOS 14, *) else { return nil }

        let status = await ATTrackingManager.requestTrackingAuthorization()
        switch status {
        case .authorized:
            logger.debug(
                "ATT: authorized. IDFA=\(ASIdentifierManager.shared().advertisingIdentifier.uuidString, privacy: .private)"
            )
        case .denied:
            logger.warning("ATT: denied — personalised ads unavailable.")
        case .restricted:
            logger.warning("ATT: restricted — personalised ads unavailable.")
        case .notDetermined:
            // .notDetermined after requestTrackingAuthorization() is anomalous —
            // the call is supposed to block until the user responds.
            logger.error(
                "ATT: returned .notDetermined after requestTrackingAuthorization — unexpected, IDFA unavailable."
            )
        @unknown default:
            logger.warning("ATT: unknown status (\(status.rawValue)).")
        }
        return status
    }

    /// Runs `operation` with a deadline. Returns `.timedOut` if the deadline was hit
    /// before `operation` completed, `.completed` otherwise.
    private func withTimeout(_ duration: Duration, operation: @escaping @Sendable () async -> Void)
        async -> TimeoutResult
    {
        await withTaskGroup(of: TimeoutResult.self) { group in
            group.addTask {
                await operation()
                return .completed
            }
            group.addTask {
                try? await Task.sleep(for: duration)
                return .timedOut
            }
            // The first task to finish wins; cancel the other.
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    /// Logs a consistent message when an ad operation is skipped because the SDK
    /// is not ready or consent has not been granted.
    private func logNotReady(context: String) {
        if !_isInitialized {
            logger.warning("\(context, privacy: .public): AdMob SDK not yet initialised.")
        } else if !_canRequestAds {
            logger.warning("\(context, privacy: .public): ads blocked — consent not granted.")
        } else {
            logger.warning(
                "\(context, privacy: .public): ads blocked — unknown reason (initialized=\(self._isInitialized), canRequestAds=\(self._canRequestAds))."
            )
        }
    }

    /// Logs the IAB TCF 2.0 consent strings stored in UserDefaults by the UMP SDK.
    /// These are essential for debugging why specific ad networks refuse to serve ads.
    private func logIABTCFConsentStrings() {
        let defaults = UserDefaults.standard
        let gdprApplies = defaults.integer(forKey: "IABTCF_gdprApplies")
        let tcString = defaults.string(forKey: "IABTCF_TCString") ?? "(not set)"
        let purposeConsents = defaults.string(forKey: "IABTCF_PurposeConsents") ?? "(not set)"
        let vendorConsents = defaults.string(forKey: "IABTCF_VendorConsents") ?? "(not set)"

        logger.debug(
            "IABTCF: gdprApplies=\(gdprApplies) TCString=\(tcString, privacy: .private) PurposeConsents=\(purposeConsents, privacy: .public) VendorConsents=\(vendorConsents, privacy: .private)"
        )
    }
}

// MARK: - BannerViewDelegate

extension AdMobManager: BannerViewDelegate {
    public func bannerViewDidReceiveAd(_ bannerView: BannerViewDelegate) {
        logger.debug("Banner ad loaded successfully.")
        Task { @MainActor in
            self.setBannerLoaded(true)
        }
        on_ad_loaded("banner")
    }

    public func bannerView(
        _ bannerView: BannerViewDelegate, didFailToReceiveAdWithError error: Error
    ) {
        logger.error("Banner ad failed to load: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
            self.setBannerLoaded(false)
        }
        on_ad_failed_to_load("banner", error.localizedDescription)
    }

    public func bannerViewWillPresentScreen(_ bannerView: BannerViewDelegate) {
        logger.debug("Banner ad will present screen.")
        on_ad_opened("banner")
    }

    public func bannerViewWillDismissScreen(_ bannerView: BannerViewDelegate) {
        logger.debug("Banner ad will dismiss screen.")
    }

    public func bannerViewDidDismissScreen(_ bannerView: BannerViewDelegate) {
        logger.debug("Banner ad did dismiss screen.")
        on_ad_closed("banner")
    }
}

// MARK: - FullScreenContentDelegate

extension AdMobManager: FullScreenContentDelegate {
    public func ad(
        ad_f: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error
    ) {
        let adType = adTypeName(ad_f)
        let unitID = adUnitID(for: ad_f)
        logger.error(
            "\(adType, privacy: .public) ad (\(unitID, privacy: .public)) failed to present: \(error.localizedDescription, privacy: .public)"
        )
        // This is a *presentation* failure, not a *load* failure. Use the distinct
        // callback so the Rust side can handle it differently (e.g. not auto-reload).
        // The overlay window is no longer needed since the ad failed to appear.
        Task { @MainActor in
            self.dismissOverlayWindow()
        }
        on_ad_failed_to_present(adType, error.localizedDescription)
    }

    public func adWillPresentFullScreenContent(ad_f: FullScreenPresentingAd) {
        let adType = adTypeName(ad_f)
        logger.debug("\(adType, privacy: .public) ad will present.")
        on_ad_opened(adType)
    }

    public func adDidDismissFullScreenContent(ad_f: FullScreenPresentingAd) {
        let adType = adTypeName(ad_f)
        let unitID = adUnitID(for: ad_f)
        logger.debug("\(adType, privacy: .public) ad (\(unitID, privacy: .public)) dismissed.")
        on_ad_closed(adType)

        // Clear the reference so is_*_ready() returns false and a new ad can be loaded.
        // Also release the overlay window — it is no longer needed until the next ad.
        Task { @MainActor in
            if ad_f is InterstitialAd {
                self.interstitialAd = nil
                self.lastInterstitialUnitID = nil
                self._lastInterstitialUnitID = nil
                self.setHasInterstitial(false)
            } else if ad_f is RewardedAd {
                self.rewardedAd = nil
                self.lastRewardedUnitID = nil
                self._lastRewardedUnitID = nil
                self.setHasRewarded(false)
            }
            self.dismissOverlayWindow()
        }
    }

    private func adTypeName(_ ad: FullScreenPresentingAd) -> String {
        return (ad is InterstitialAd) ? "interstitial" : "rewarded"
    }

    /// Returns the ad unit ID for the given fullscreen ad, if tracked.
    /// Reads from nonisolated(unsafe) mirrors so it can be called from nonisolated
    /// delegate methods without an async hop.
    private func adUnitID(for ad: FullScreenPresentingAd) -> String {
        if ad is InterstitialAd {
            return _lastInterstitialUnitID ?? "?"
        } else if ad is RewardedAd {
            return _lastRewardedUnitID ?? "?"
        }
        return "?"
    }
}
