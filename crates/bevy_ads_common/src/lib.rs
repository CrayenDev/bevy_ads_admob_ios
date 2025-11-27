use bevy_app::{App, FixedUpdate, Plugin};
use bevy_ecs::prelude::*;
use bevy_reflect::prelude::*;
use crossbeam::queue::SegQueue;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};

#[cfg(feature = "fake_ads")]
pub mod fake_ads;

static EVENT_QUEUE: Lazy<SegQueue<AdMessage>> = Lazy::new(|| SegQueue::new());

pub fn write_event_to_queue(event: AdMessage) {
    _ = EVENT_QUEUE.push(event);
}

/// Events that can be triggered by Ad system operations
#[derive(Message, Debug, Clone, Reflect, Serialize, Deserialize)]
pub enum AdMessage {
    Initialized { success: bool },
    ConsentGathered { success: bool, error: String },
    AdLoaded { ad_type: String },
    AdFailedToLoad { ad_type: String, error: String },
    AdOpened { ad_type: String },
    AdClosed { ad_type: String },
    RewardedAdEarnedReward { amount: i32, reward_type: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Reflect, Serialize, Deserialize)]
pub enum AdType {
    Banner,
    Interstitial,
    Rewarded,
}

pub trait AdManager {
    fn initialize(&mut self) -> bool;
    fn is_initialized(&self) -> bool;
    fn load_ad(&self, ad_type: AdType, ad_id: &str) -> bool {
        match ad_type {
            AdType::Banner => self.load_banner(ad_id),
            AdType::Interstitial => self.load_interstitial(ad_id),
            AdType::Rewarded => self.load_rewarded(ad_id),
        }
    }
    fn show_ad(&mut self, ad_type: AdType) -> bool {
        if !self.is_ad_ready(ad_type) {
            return false;
        }
        match ad_type {
            AdType::Banner => self.show_banner(),
            AdType::Interstitial => self.show_interstitial(),
            AdType::Rewarded => self.show_rewarded(),
        }
    }
    fn hide_ad(&mut self, ad_type: AdType) -> bool {
        match ad_type {
            AdType::Banner => self.hide_banner(),
            AdType::Interstitial => self.hide_interstitial(),
            AdType::Rewarded => self.hide_rewarded(),
        }
    }
    fn is_ad_ready(&self, ad_type: AdType) -> bool {
        match ad_type {
            AdType::Banner => self.is_banner_ready(),
            AdType::Interstitial => self.is_interstitial_ready(),
            AdType::Rewarded => self.is_rewarded_ready(),
        }
    }
    fn show_banner(&mut self) -> bool;
    fn show_interstitial(&mut self) -> bool;
    fn show_rewarded(&mut self) -> bool;
    fn hide_banner(&mut self) -> bool;
    fn hide_interstitial(&mut self) -> bool;
    fn hide_rewarded(&self) -> bool;
    fn load_banner(&self, ad_id: &str) -> bool;
    fn load_interstitial(&self, ad_id: &str) -> bool;
    fn load_rewarded(&self, ad_id: &str) -> bool;
    fn is_banner_ready(&self) -> bool {
        true
    }
    fn is_interstitial_ready(&self) -> bool;
    fn is_rewarded_ready(&self) -> bool;
}

pub struct AdBasePlugin;

impl Plugin for AdBasePlugin {
    fn build(&self, app: &mut App) {
        app.add_message::<AdMessage>()
            .add_systems(FixedUpdate, handle_events)
            .register_type::<AdMessage>();
        #[cfg(feature = "fake_ads")]
        app.add_plugins(fake_ads::plugin);
    }
}

fn handle_events(mut writer: MessageWriter<AdMessage>) {
    while let Some(ev) = EVENT_QUEUE.pop() {
        writer.write(ev);
    }
}
