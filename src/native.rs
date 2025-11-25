// swift_bridge import will be used by the generated bridge code

use bevy_ads_common::AdMessage;
use std::cell::RefCell;

thread_local! {
    /// Temporary storage of WinitWindows data to replace usage of `!Send` resources. This will be replaced with proper
    /// storage of `!Send` data after issue #17667 is complete.
    pub static ADMOB_NATIVE: RefCell<AdMobNative> = RefCell::new(AdMobNative::new());
}

#[swift_bridge::bridge]
mod ffi {
    extern "Swift" {
        type AdMobManager;

        #[swift_bridge(init)]
        fn new() -> AdMobManager;

        fn initialize_admob(self: &AdMobManager) -> bool;
        fn load_banner_ad(self: &AdMobManager, ad_unit_id: &str, width: i32, height: i32) -> bool;
        fn show_banner_ad(self: &AdMobManager) -> bool;
        fn hide_banner_ad(self: &AdMobManager) -> bool;
        fn load_interstitial_ad(self: &AdMobManager, ad_unit_id: &str) -> bool;
        fn show_interstitial_ad(self: &AdMobManager) -> bool;
        fn load_rewarded_ad(self: &AdMobManager, ad_unit_id: &str) -> bool;
        fn show_rewarded_ad(self: &AdMobManager) -> bool;
        fn is_interstitial_ready(self: &AdMobManager) -> bool;
        fn is_rewarded_ready(self: &AdMobManager) -> bool;
    }

    extern "Rust" {
        fn on_initialized(success: bool);
        fn on_ad_loaded(ad_type: String);
        fn on_ad_failed_to_load(ad_type: String, error: String);
        fn on_ad_opened(ad_type: String);
        fn on_ad_closed(ad_type: String);
        fn on_rewarded_ad_earned_reward(amount: i32, type_name: String);
        fn on_consent_gathered(error: String);
    }
}

pub fn on_initialized(success: bool) {
    bevy_log::info!("AdMob initialized: {}", success);
    bevy_ads_common::write_event_to_queue(AdMessage::Initialized { success });
}

// Callback functions that Swift can call back into Rust
pub fn on_ad_loaded(ad_type: String) {
    bevy_log::info!("Ad loaded: {}", ad_type);
    bevy_ads_common::write_event_to_queue(AdMessage::AdLoaded { ad_type });
}

pub fn on_ad_failed_to_load(ad_type: String, error: String) {
    bevy_log::info!("Ad failed to load: {} - {}", ad_type, error);
    bevy_ads_common::write_event_to_queue(AdMessage::AdFailedToLoad { ad_type, error });
}

pub fn on_ad_opened(ad_type: String) {
    bevy_log::info!("Ad opened: {}", ad_type);
    bevy_ads_common::write_event_to_queue(AdMessage::AdLoaded { ad_type });
}

pub fn on_ad_closed(ad_type: String) {
    bevy_log::info!("Ad closed: {}", ad_type);
    bevy_ads_common::write_event_to_queue(AdMessage::AdClosed { ad_type });
}

pub fn on_rewarded_ad_earned_reward(amount: i32, reward_type: String) {
    bevy_log::info!("Rewarded ad earned reward: {} {}", amount, reward_type);
    bevy_ads_common::write_event_to_queue(AdMessage::RewardedAdEarnedReward {
        amount,
        reward_type,
    });
}

pub fn on_consent_gathered(error: String) {
    let success = error.is_empty();
    bevy_log::info!("Consent gathered: {}", error);
    bevy_ads_common::write_event_to_queue(AdMessage::ConsentGathered { error, success });
}

// Rust interface for AdMob
pub struct AdMobNative {
    manager: ffi::AdMobManager,
    // This marker indicates that this type is not thread-safe and will be `!Send` and `!Sync`.
    _not_send_sync: core::marker::PhantomData<*const ()>,
}

impl Default for AdMobNative {
    fn default() -> Self {
        Self::new()
    }
}

impl AdMobNative {
    pub fn new() -> Self {
        Self {
            manager: ffi::AdMobManager::new(),
            _not_send_sync: core::marker::PhantomData,
        }
    }

    pub fn initialize(&self) -> bool {
        self.manager.initialize_admob()
    }

    pub fn load_banner_ad(&self, ad_unit_id: &str, width: i32, height: i32) -> bool {
        self.manager.load_banner_ad(ad_unit_id, width, height)
    }

    pub fn show_banner_ad(&self) -> bool {
        self.manager.show_banner_ad()
    }

    pub fn hide_banner_ad(&self) -> bool {
        self.manager.hide_banner_ad()
    }

    pub fn load_interstitial_ad(&self, ad_unit_id: &str) -> bool {
        self.manager.load_interstitial_ad(ad_unit_id)
    }

    pub fn show_interstitial_ad(&self) -> bool {
        self.manager.show_interstitial_ad()
    }

    pub fn load_rewarded_ad(&self, ad_unit_id: &str) -> bool {
        self.manager.load_rewarded_ad(ad_unit_id)
    }

    pub fn show_rewarded_ad(&self) -> bool {
        self.manager.show_rewarded_ad()
    }

    pub fn is_interstitial_ready(&self) -> bool {
        self.manager.is_interstitial_ready()
    }

    pub fn is_rewarded_ready(&self) -> bool {
        self.manager.is_rewarded_ready()
    }
}
