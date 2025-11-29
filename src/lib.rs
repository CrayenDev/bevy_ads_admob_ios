use bevy_ads_common::{AdManager, AdMessage, AdType};
use bevy_app::{App, Plugin, Update};
use bevy_ecs::{prelude::*, system::SystemParam};
use bevy_reflect::prelude::*;
use serde::{Deserialize, Serialize};

pub mod native;

#[cfg(target_os = "ios")]
pub use native::AdMobNative;

/// AdMob configuration
#[derive(Resource, Debug, Clone, Reflect, Serialize, Deserialize)]
pub struct AdMobConfig {
    pub banner_ad_unit_id: String,
    pub interstitial_ad_unit_id: String,
    pub rewarded_ad_unit_id: String,
    pub load_ad_on_init: Option<AdType>,
    pub banner_width: i32,
    pub banner_height: i32,
}

impl Default for AdMobConfig {
    fn default() -> Self {
        Self {
            banner_height: 50,
            banner_width: 150,
            rewarded_ad_unit_id: "ca-app-pub-3940256099942544/5354046379".to_string(),
            banner_ad_unit_id: "ca-app-pub-3940256099942544/9214589741".to_string(),
            interstitial_ad_unit_id: "ca-app-pub-3940256099942544/1033173712".to_string(),
            load_ad_on_init: None,
        }
    }
}

impl AdMobConfig {
    /// Get the ad unit ID for the given ad type
    pub fn get_ad_unit_id(&self, ad_type: AdType) -> String {
        match ad_type {
            AdType::Banner => self.banner_ad_unit_id.clone(),
            AdType::Interstitial => self.interstitial_ad_unit_id.clone(),
            AdType::Rewarded => self.rewarded_ad_unit_id.clone(),
        }
    }
}

#[derive(Debug, Clone, Copy, Hash, PartialEq, Eq, PartialOrd, Ord, Default)]
pub enum InitStatus {
    #[default]
    NotInitialized,
    Initializing,
    Initialized,
    Failed,
}

#[allow(unused, reason = "Variables are used on some of the platforms")]
/// AdMob manager resource
#[derive(Resource)]
pub struct AdMobManager {
    init_status: InitStatus,
}

impl AdMobManager {
    pub fn is_initialized(&self) -> bool {
        self.init_status == InitStatus::Initialized
    }
}

impl Default for AdMobManager {
    fn default() -> Self {
        Self {
            init_status: InitStatus::NotInitialized,
        }
    }
}

#[derive(SystemParam)]
pub struct AdmobAdsSystem<'w, 's> {
    pub r: NonSendMut<'w, AdMobManager>,
    pub cfg: Res<'w, AdMobConfig>,
    pub cmd: Commands<'w, 's>,
}

#[allow(
    unused_variables,
    reason = "Variables are used on some of the platforms"
)]
impl bevy_ads_common::AdManager for AdmobAdsSystem<'_, '_> {
    fn initialize(&mut self) -> bool {
        if self.r.init_status.eq(&InitStatus::Initializing) {
            bevy_log::info!("Initializing AdMob already in progress");
            return false;
        }
        bevy_log::info!("Initializing AdMob");
        #[cfg(target_os = "ios")]
        {
            native::ADMOB_NATIVE.with_borrow_mut(|f| f.initialize());
            true
        }
        #[cfg(not(target_os = "ios"))]
        {
            bevy_log::info!("AdMob initialization skipped - not running on iOS");
            self.r.init_status = InitStatus::Initialized;
            true
        }
    }
    fn is_initialized(&self) -> bool {
        self.r.is_initialized()
    }

    fn show_banner(&mut self) -> bool {
        if !self.is_initialized() {
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

    fn show_interstitial(&mut self) -> bool {
        if !self.is_initialized() {
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

    fn show_rewarded(&mut self) -> bool {
        if !self.is_initialized() {
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

    fn hide_banner(&mut self) -> bool {
        if !self.is_initialized() {
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

    fn hide_interstitial(&mut self) -> bool {
        false
    }

    fn hide_rewarded(&mut self) -> bool {
        false
    }

    fn load_banner(&mut self, ad_id: &str) -> bool {
        #[cfg(target_os = "ios")]
        {
            let banner_width = self.get_banner_width(ad_id);
            let banner_height = self.get_banner_height(ad_id);
            native::ADMOB_NATIVE
                .with_borrow_mut(|f| f.load_banner_ad(ad_id, banner_width, banner_height))
        }
        #[cfg(not(target_os = "ios"))]
        {
            bevy_log::info!("Banner ad load simulated - not running on iOS");
            true
        }
    }

    fn load_interstitial(&mut self, ad_id: &str) -> bool {
        if !self.is_initialized() {
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

    fn load_rewarded(&mut self, ad_id: &str) -> bool {
        if !self.is_initialized() {
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
        if !self.is_initialized() {
            bevy_log::info!("AdMob not initialized");
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
        if !self.is_initialized() {
            bevy_log::info!("AdMob not initialized");
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
    fn get_banner_height(&self, _ad_id: &str) -> i32 {
        self.cfg.banner_height
    }
    fn get_banner_width(&self, _ad_id: &str) -> i32 {
        self.cfg.banner_width
    }
}

/// System to initialize AdMob when the plugin starts
fn initialize_admob(
    mut manager: AdmobAdsSystem,
    // _non_send_marker: bevy_ecs::system::NonSendMarker,
) {
    if !manager.is_initialized() {
        let success = manager.initialize();
        bevy_log::info!("AdMob started init {}", success);
    }
}

fn on_admob_initialized(
    mut reader: MessageReader<AdMessage>,
    mut manager: AdmobAdsSystem,
    _non_send_marker: bevy_ecs::system::NonSendMarker,
) {
    for event in reader.read() {
        if let AdMessage::Initialized { success } = event {
            manager.r.init_status = if *success {
                InitStatus::Initialized
            } else {
                InitStatus::Failed
            };
            if *success {
                if let Some(ad_type) = manager.cfg.load_ad_on_init {
                    let ad_unit = manager.cfg.get_ad_unit_id(ad_type);
                    manager.load_ad(ad_type, &ad_unit);
                }
            }
        }
    }
}

/// Bevy plugin for AdMob integration
pub struct AdMobPlugin;

impl Plugin for AdMobPlugin {
    fn build(&self, app: &mut App) {
        if !app.is_plugin_added::<bevy_ads_common::AdsCommonPlugin>() {
            app.add_plugins(bevy_ads_common::AdsCommonPlugin);
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
