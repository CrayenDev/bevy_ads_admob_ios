use crate::AdManager;

pub struct MockupAds {
    pub initialized: bool,
    pub ad_duration_ms: u32,
}

impl AdManager for MockupAds {
    fn is_initialized(&self) -> bool {
        self.initialized
    }

    fn initialize(&mut self) -> bool {
        self.initialized = true;
        true
    }

    fn show_banner(&self) -> bool {
        false
    }

    fn show_interstitial(&self) -> bool {
        false
    }

    fn show_rewarded(&self) -> bool {
        false
    }

    fn hide_banner(&self) -> bool {
        todo!()
    }

    fn hide_interstitial(&self) -> bool {
        todo!()
    }

    fn hide_rewarded(&self) -> bool {
        todo!()
    }

    fn load_banner(&self, ad_id: &str) -> bool {
        todo!()
    }

    fn load_interstitial(&self, ad_id: &str) -> bool {
        todo!()
    }

    fn load_rewarded(&self, ad_id: &str) -> bool {
        todo!()
    }

    fn is_interstitial_ready(&self) -> bool {
        todo!()
    }

    fn is_rewarded_ready(&self) -> bool {
        todo!()
    }
}
