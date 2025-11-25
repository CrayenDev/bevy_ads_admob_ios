use bevy_ads_common::{AdManager, AdMessage, AdType};
use bevy_app::{App, Plugin, Update};
use bevy_ecs::prelude::*;
use bevy_reflect::prelude::*;
use serde::{Deserialize, Serialize};

pub mod native;

#[cfg(target_os = "ios")]
pub use native::AdMobNative;

/// AdMob configuration
#[derive(Resource, Debug, Clone, Reflect, Serialize, Deserialize, Default)]
pub struct AdMobConfig {
    pub banner_ad_unit_id: String,
    pub interstitial_ad_unit_id: String,
    pub rewarded_ad_unit_id: String,
    pub load_ad_on_init: Option<AdType>,
}

#[allow(unused, reason = "Variables are used on some of the platforms")]
/// AdMob manager resource
#[derive(Resource)]
pub struct AdMobManager {
    initialized: bool,
    banner_width: i32,
    banner_height: i32,
}

impl Default for AdMobManager {
    fn default() -> Self {
        Self {
            initialized: false,
            banner_width: 320,
            banner_height: 50,
        }
    }
}

#[allow(
    unused_variables,
    reason = "Variables are used on some of the platforms"
)]
impl bevy_ads_common::AdManager for AdMobManager {
    fn initialize(&mut self) -> bool {
        bevy_log::info!("Initializing AdMob");
        #[cfg(target_os = "ios")]
        {
            native::ADMOB_NATIVE.with_borrow_mut(|f| f.initialize());
            true
        }
        #[cfg(not(target_os = "ios"))]
        {
            bevy_log::info!("AdMob initialization skipped - not running on iOS");
            self.initialized = true;
            true
        }
    }
    fn is_initialized(&self) -> bool {
        self.initialized
    }

    fn show_banner(&self) -> bool {
        if !self.initialized {
            bevy_log::info!("AdMob not initialized");
            return false;
        }

        #[cfg(target_os = "ios")]
        {
            native::ADMOB_NATIVE.with_borrow_mut(|f| f.show_banner_ad())
        }
        #[cfg(not(target_os = "ios"))]
        {
            bevy_log::info!("Banner ad show simulated - not running on iOS");
            true
        }
    }

    fn show_interstitial(&self) -> bool {
        if !self.initialized {
            bevy_log::info!("AdMob not initialized");
            return false;
        }

        #[cfg(target_os = "ios")]
        {
            native::ADMOB_NATIVE.with_borrow_mut(|f| f.show_interstitial_ad())
        }
        #[cfg(not(target_os = "ios"))]
        {
            bevy_log::info!("Interstitial ad show simulated - not running on iOS");
            true
        }
    }

    fn show_rewarded(&self) -> bool {
        if !self.initialized {
            bevy_log::info!("AdMob not initialized");
            return false;
        }

        #[cfg(target_os = "ios")]
        {
            native::ADMOB_NATIVE.with_borrow_mut(|f| f.show_rewarded_ad())
        }
        #[cfg(not(target_os = "ios"))]
        {
            bevy_log::info!("Rewarded ad show simulated - not running on iOS");
            true
        }
    }

    fn hide_banner(&self) -> bool {
        if !self.initialized {
            bevy_log::info!("AdMob not initialized");
            return false;
        }

        #[cfg(target_os = "ios")]
        {
            native::ADMOB_NATIVE.with_borrow_mut(|f| f.hide_banner_ad())
        }
        #[cfg(not(target_os = "ios"))]
        {
            bevy_log::info!("Banner ad hide simulated - not running on iOS");
            true
        }
    }

    fn hide_interstitial(&self) -> bool {
        todo!()
    }

    fn hide_rewarded(&self) -> bool {
        todo!()
    }

    fn load_banner(&self, ad_id: &str) -> bool {
        #[cfg(target_os = "ios")]
        {
            native::ADMOB_NATIVE
                .with_borrow_mut(|f| f.load_banner_ad(ad_id, self.banner_width, self.banner_height))
        }
        #[cfg(not(target_os = "ios"))]
        {
            bevy_log::info!("Banner ad load simulated - not running on iOS");
            true
        }
    }

    fn load_interstitial(&self, ad_id: &str) -> bool {
        if !self.initialized {
            bevy_log::info!("AdMob not initialized");
            return false;
        }

        #[cfg(target_os = "ios")]
        {
            native::ADMOB_NATIVE.with_borrow_mut(|f| f.load_interstitial_ad(ad_id))
        }
        #[cfg(not(target_os = "ios"))]
        {
            bevy_log::info!("Interstitial ad load simulated - not running on iOS");
            true
        }
    }

    fn load_rewarded(&self, ad_id: &str) -> bool {
        if !self.initialized {
            bevy_log::info!("AdMob not initialized");
            return false;
        }
        #[cfg(target_os = "ios")]
        {
            native::ADMOB_NATIVE.with_borrow_mut(|f| f.load_rewarded_ad(ad_id))
        }
        #[cfg(not(target_os = "ios"))]
        {
            bevy_log::info!("Rewarded ad load simulated - not running on iOS");
            true
        }
    }

    fn is_interstitial_ready(&self) -> bool {
        if !self.initialized {
            return false;
        }

        #[cfg(target_os = "ios")]
        {
            native::ADMOB_NATIVE.with_borrow_mut(|f| f.is_interstitial_ready())
        }
        #[cfg(not(target_os = "ios"))]
        {
            true
        }
    }

    fn is_rewarded_ready(&self) -> bool {
        if !self.initialized {
            return false;
        }

        #[cfg(target_os = "ios")]
        {
            native::ADMOB_NATIVE.with_borrow_mut(|f| f.is_rewarded_ready())
        }
        #[cfg(not(target_os = "ios"))]
        {
            true
        }
    }
}

/// System to initialize AdMob when the plugin starts
fn initialize_admob(
    mut manager: NonSendMut<AdMobManager>,
    // _non_send_marker: bevy_ecs::system::NonSendMarker,
) {
    if !manager.initialized {
        let success = manager.initialize();
        bevy_log::info!("AdMob started init {}", success);
    }
}

fn on_admob_initialized(
    mut reader: MessageReader<AdMessage>,
    mut manager: NonSendMut<AdMobManager>,
    cfg: Res<AdMobConfig>,
    _non_send_marker: bevy_ecs::system::NonSendMarker,
) {
    for event in reader.read() {
        if let AdMessage::Initialized { success } = event
            && *success
        {
            manager.initialized = true;
            if let Some(ad_type) = cfg.load_ad_on_init {
                match ad_type {
                    AdType::Banner => manager.load_banner(&cfg.banner_ad_unit_id),
                    AdType::Interstitial => manager.load_interstitial(&cfg.interstitial_ad_unit_id),
                    AdType::Rewarded => manager.load_rewarded(&cfg.rewarded_ad_unit_id),
                };
            }
        }
    }
}

/// Bevy plugin for AdMob integration
pub struct AdMobPlugin;

impl Plugin for AdMobPlugin {
    fn build(&self, app: &mut App) {
        if !app.is_plugin_added::<bevy_ads_common::AdBasePlugin>() {
            app.add_plugins(bevy_ads_common::AdBasePlugin);
        }
        app.init_non_send_resource::<AdMobManager>()
            .add_systems(
                Update,
                initialize_admob.run_if(resource_added::<AdMobConfig>),
            )
            .add_systems(Update, on_admob_initialized)
            .register_type::<AdMobConfig>();
    }
}

/// Convenience functions for common operations
pub mod prelude {
    pub use crate::{AdMobConfig, AdMobManager, AdMobPlugin};
    pub use bevy_ads_common::{AdManager, AdMessage, AdType};
}
