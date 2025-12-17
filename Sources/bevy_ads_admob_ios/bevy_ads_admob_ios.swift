import AdmobXcframework 
@_cdecl("__swift_bridge__$AdMobManager$new")
func __swift_bridge__AdMobManager_new () -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(AdMobManager()).toOpaque()
}

@_cdecl("__swift_bridge__$AdMobManager$initialize_admob")
func __swift_bridge__AdMobManager_initialize_admob (_ this: UnsafeMutableRawPointer, _ test_device_id: RustStr) -> Bool {
    Unmanaged<AdMobManager>.fromOpaque(this).takeUnretainedValue().initialize_admob(test_device_id: test_device_id)
}

@_cdecl("__swift_bridge__$AdMobManager$load_banner_ad")
func __swift_bridge__AdMobManager_load_banner_ad (_ this: UnsafeMutableRawPointer, _ ad_unit_id: RustStr, _ width: Int32, _ height: Int32) -> Bool {
    Unmanaged<AdMobManager>.fromOpaque(this).takeUnretainedValue().load_banner_ad(ad_unit_id: ad_unit_id, width: width, height: height)
}

@_cdecl("__swift_bridge__$AdMobManager$show_banner_ad")
func __swift_bridge__AdMobManager_show_banner_ad (_ this: UnsafeMutableRawPointer) -> Bool {
    Unmanaged<AdMobManager>.fromOpaque(this).takeUnretainedValue().show_banner_ad()
}

@_cdecl("__swift_bridge__$AdMobManager$hide_banner_ad")
func __swift_bridge__AdMobManager_hide_banner_ad (_ this: UnsafeMutableRawPointer) -> Bool {
    Unmanaged<AdMobManager>.fromOpaque(this).takeUnretainedValue().hide_banner_ad()
}

@_cdecl("__swift_bridge__$AdMobManager$load_interstitial_ad")
func __swift_bridge__AdMobManager_load_interstitial_ad (_ this: UnsafeMutableRawPointer, _ ad_unit_id: RustStr) -> Bool {
    Unmanaged<AdMobManager>.fromOpaque(this).takeUnretainedValue().load_interstitial_ad(ad_unit_id: ad_unit_id)
}

@_cdecl("__swift_bridge__$AdMobManager$show_interstitial_ad")
func __swift_bridge__AdMobManager_show_interstitial_ad (_ this: UnsafeMutableRawPointer) -> Bool {
    Unmanaged<AdMobManager>.fromOpaque(this).takeUnretainedValue().show_interstitial_ad()
}

@_cdecl("__swift_bridge__$AdMobManager$load_rewarded_ad")
func __swift_bridge__AdMobManager_load_rewarded_ad (_ this: UnsafeMutableRawPointer, _ ad_unit_id: RustStr) -> Bool {
    Unmanaged<AdMobManager>.fromOpaque(this).takeUnretainedValue().load_rewarded_ad(ad_unit_id: ad_unit_id)
}

@_cdecl("__swift_bridge__$AdMobManager$show_rewarded_ad")
func __swift_bridge__AdMobManager_show_rewarded_ad (_ this: UnsafeMutableRawPointer) -> Bool {
    Unmanaged<AdMobManager>.fromOpaque(this).takeUnretainedValue().show_rewarded_ad()
}

@_cdecl("__swift_bridge__$AdMobManager$is_interstitial_ready")
func __swift_bridge__AdMobManager_is_interstitial_ready (_ this: UnsafeMutableRawPointer) -> Bool {
    Unmanaged<AdMobManager>.fromOpaque(this).takeUnretainedValue().is_interstitial_ready()
}

@_cdecl("__swift_bridge__$AdMobManager$is_rewarded_ready")
func __swift_bridge__AdMobManager_is_rewarded_ready (_ this: UnsafeMutableRawPointer) -> Bool {
    Unmanaged<AdMobManager>.fromOpaque(this).takeUnretainedValue().is_rewarded_ready()
}

public func on_initialized(_ success: Bool) {
    __swift_bridge__$on_initialized(success)
}
public func on_ad_loaded<GenericIntoRustString: IntoRustString>(_ ad_type: GenericIntoRustString) {
    __swift_bridge__$on_ad_loaded({ let rustString = ad_type.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
}
public func on_ad_failed_to_load<GenericIntoRustString: IntoRustString>(_ ad_type: GenericIntoRustString, _ error: GenericIntoRustString) {
    __swift_bridge__$on_ad_failed_to_load({ let rustString = ad_type.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = error.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
}
public func on_ad_opened<GenericIntoRustString: IntoRustString>(_ ad_type: GenericIntoRustString) {
    __swift_bridge__$on_ad_opened({ let rustString = ad_type.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
}
public func on_ad_closed<GenericIntoRustString: IntoRustString>(_ ad_type: GenericIntoRustString) {
    __swift_bridge__$on_ad_closed({ let rustString = ad_type.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
}
public func on_rewarded_ad_earned_reward<GenericIntoRustString: IntoRustString>(_ amount: Int32, _ type_name: GenericIntoRustString) {
    __swift_bridge__$on_rewarded_ad_earned_reward(amount, { let rustString = type_name.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
}
public func on_consent_gathered<GenericIntoRustString: IntoRustString>(_ error: GenericIntoRustString) {
    __swift_bridge__$on_consent_gathered({ let rustString = error.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
}

@_cdecl("__swift_bridge__$AdMobManager$_free")
func __swift_bridge__AdMobManager__free (ptr: UnsafeMutableRawPointer) {
    let _ = Unmanaged<AdMobManager>.fromOpaque(ptr).takeRetainedValue()
}



