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
    pub test_device_id: Option<String>,
    pub banner_width: i32,
    pub banner_height: i32,
}

impl Default for AdMobConfig {
    fn default() -> Self {
        Self {
            banner_height: 50,
            banner_width: 150,
            rewarded_ad_unit_id: "ca-app-pub-3940256099942544/1712485313".to_string(),
            banner_ad_unit_id: "ca-app-pub-3940256099942544/2435281174".to_string(),
            interstitial_ad_unit_id: "ca-app-pub-3940256099942544/4411468910".to_string(),
            load_ad_on_init: None,
            test_device_id: None,
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

    pub fn try_get_ad_to_load_on_init(&self) -> Option<(String, AdType)> {
        self.load_ad_on_init.map(|ad_type| {
            let ad_unit = self.get_ad_unit_id(ad_type);
            (ad_unit, ad_type)
        })
    }

    pub fn set_test_device_id(&mut self, device_id: impl Into<String>) {
        self.test_device_id = Some(device_id.into());
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
    pub cfg: Option<Res<'w, AdMobConfig>>,
    pub cmd: Commands<'w, 's>,
}

impl AdmobAdsSystem<'_, '_> {
    pub fn load_ad_type(&mut self, ad_type: AdType) -> bool {
        let Some(config) = &self.cfg else {
            return false;
        };
        let ad_unit = config.get_ad_unit_id(ad_type);
        self.load_ad(ad_type, &ad_unit)
    }
}

#[allow(
    unused_variables,
    reason = "Variables are used on some of the platforms"
)]
impl bevy_ads_common::AdManager for AdmobAdsSystem<'_, '_> {
    fn initialize(&mut self) -> bool {
        if self.cfg.is_none() {
            bevy_log::error!("AdMob configuration not provided");
            return false;
        }
        if self.r.init_status.eq(&InitStatus::Initializing) {
            bevy_log::info!("Initializing AdMob already in progress");
            return false;
        }
        bevy_log::info!("Initializing AdMob");

        #[cfg(target_os = "ios")]
        {
            let device_id = match &self.cfg {
                Some(cfg) => cfg.test_device_id.clone(),
                None => None,
            };
            native::ADMOB_NATIVE.with_borrow_mut(|f| f.initialize(device_id.as_deref()));
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
        match &self.cfg {
            Some(c) => c.banner_height,
            None => 100,
        }
    }
    fn get_banner_width(&self, _ad_id: &str) -> i32 {
        match &self.cfg {
            Some(c) => c.banner_width,
            None => 100,
        }
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
            bevy_log::info!("AdMob initialized, success: {}", success);
            if *success {
                let Some(config) = &manager.cfg else {
                    continue;
                };
                let Some((ad, ad_type)) = config.try_get_ad_to_load_on_init() else {
                    continue;
                };

                manager.load_ad(ad_type, &ad);
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
        // .init_resource::<AdMobConfig>();
    }
}

/// Convenience functions for common operations
pub mod prelude {
    pub use crate::{AdMobConfig, AdMobManager, AdMobPlugin};
    pub use bevy_ads_common::{AdManager, AdMessage, AdType};
}
