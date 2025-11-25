use std::path::PathBuf;

fn main() {
    if !std::env::var("CARGO_CFG_TARGET_OS").is_ok_and(|t| t.eq("ios")) {
        return;
    }
    if std::env::var("DOCS_RS")
        .map(|doc| &doc == "1")
        .unwrap_or_default()
    {
        return;
    }

    let out_dir = PathBuf::from("./generated");

    let bridges = vec!["src/lib.rs", "src/native.rs"];
    for path in &bridges {
        println!("cargo:rerun-if-changed={}", path);
    }

    swift_bridge_build::parse_bridges(bridges)
        .write_all_concatenated(out_dir, env!("CARGO_PKG_NAME"));
}
