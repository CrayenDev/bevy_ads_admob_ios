use std::time::Duration;

use bevy_app::{App, Update};
use bevy_ecs::{
    bundle::Bundle,
    children,
    component::Component,
    entity::Entity,
    resource::Resource,
    spawn::SpawnRelated,
    system::{Commands, Query, Res, ResMut, SystemParam},
};
use bevy_reflect::Reflect;
use bevy_time::{Time, TimerMode};
use bevy_ui::{
    AlignItems, BackgroundColor, FlexDirection, JustifyContent, JustifyItems, Node, PositionType,
    Val, widget::Text,
};

use crate::{AdManager, AdMessage, AdType};

#[derive(Debug, Resource, Reflect)]
pub struct MockupAds {
    pub initialized: bool,
    pub ad_duration_ms: u64,
}

impl Default for MockupAds {
    fn default() -> Self {
        Self {
            initialized: false,
            ad_duration_ms: 2000,
        }
    }
}

pub(crate) fn plugin(app: &mut App) {
    app.register_type::<MockupAds>();
    app.init_resource::<MockupAds>();
    app.register_type::<MockupAdComponent>();
    app.add_systems(Update, show_ads);
}

#[derive(Component, Reflect)]
pub struct MockupAdComponent(pub bevy_time::Timer, pub AdType);

#[derive(SystemParam)]
pub struct MockupAdsSystem<'w, 's> {
    pub r: ResMut<'w, MockupAds>,
    pub cmd: Commands<'w, 's>,
}

impl AdManager for MockupAdsSystem<'_, '_> {
    fn is_initialized(&self) -> bool {
        self.r.initialized
    }

    fn initialize(&mut self) -> bool {
        self.r.initialized = true;
        true
    }

    fn show_banner(&mut self) -> bool {
        false
    }

    fn show_interstitial(&mut self) -> bool {
        false
    }

    fn show_rewarded(&mut self) -> bool {
        self.cmd
            .spawn(ad_bundle(self.r.ad_duration_ms, AdType::Rewarded));
        true
    }

    fn hide_banner(&mut self) -> bool {
        true
    }

    fn hide_interstitial(&mut self) -> bool {
        true
    }

    fn hide_rewarded(&self) -> bool {
        true
    }

    fn load_banner(&self, ad_id: &str) -> bool {
        true
    }

    fn load_interstitial(&self, ad_id: &str) -> bool {
        true
    }

    fn load_rewarded(&self, ad_id: &str) -> bool {
        true
    }

    fn is_interstitial_ready(&self) -> bool {
        true
    }

    fn is_rewarded_ready(&self) -> bool {
        true
    }
}

fn show_ads(
    mut q: Query<(Entity, &mut MockupAdComponent)>,
    time: Res<Time>,
    mut commands: Commands,
) {
    for (entity, mut component) in q.iter_mut() {
        component.0.tick(time.delta());
        if component.0.is_finished() {
            commands.entity(entity).try_despawn();
            match component.1 {
                AdType::Banner => {}
                AdType::Interstitial => {
                    crate::write_event_to_queue(AdMessage::AdClosed {
                        ad_type: "Interstitial".to_string(),
                    });
                }
                AdType::Rewarded => {
                    crate::write_event_to_queue(AdMessage::AdClosed {
                        ad_type: "Interstitial".to_string(),
                    });
                    crate::write_event_to_queue(AdMessage::RewardedAdEarnedReward {
                        amount: 1,
                        reward_type: "Reward".to_string(),
                    });
                }
            }
        }
    }
}

fn ad_bundle(duration_ms: u64, ad_type: AdType) -> impl Bundle {
    (
        Node {
            width: Val::Percent(100.0),
            height: Val::Percent(100.0),
            justify_content: JustifyContent::Center,
            justify_items: JustifyItems::Stretch,
            align_items: AlignItems::Center,
            flex_direction: FlexDirection::Column,
            row_gap: Val::Px(10.0),
            position_type: PositionType::Absolute,

            ..Default::default()
        },
        MockupAdComponent(
            bevy_time::Timer::new(Duration::from_millis(duration_ms), TimerMode::Once),
            ad_type,
        ),
        bevy_ui::ZIndex(500),
        BackgroundColor(bevy_color::palettes::tailwind::BLUE_400.into()),
        children![Text::new("Mockup Ads")],
    )
}
