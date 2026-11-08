#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod models;
mod scanner;

use models::{CacheItem, ScanPayload};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

fn load_previous_sizes(csv_path: &Path) -> HashMap<String, f64> {
    let mut map = HashMap::new();
    if !csv_path.exists() {
        return map;
    }
    if let Ok(mut rdr) = csv::Reader::from_path(csv_path) {
        for result in rdr.deserialize::<CacheItem>().flatten() {
            map.insert(result.path, result.size_m_b);
        }
    }
    map
}

fn inject_payload_into_html(html_path: &Path, json_str: &str) -> Result<(), Box<dyn std::error::Error>> {
    if !html_path.exists() {
        return Ok(());
    }
    let html_content = fs::read_to_string(html_path)?;
    let start_marker = "// === BEGIN_AUTO_DATA ===";
    let end_marker = "// === END_AUTO_DATA ===";
    if let (Some(idx_start), Some(idx_end)) =
        (html_content.find(start_marker), html_content.find(end_marker))
    {
        if idx_end > idx_start {
            let before = &html_content[..idx_start];
            let after = &html_content[idx_end + end_marker.len()..];
            let injected = format!(
                "{}\n    const scanPayload = {};\n    {}",
                start_marker, json_str, end_marker
            );
            let new_html = format!("{}{}{}", before, injected, after);
            fs::write(html_path, new_html)?;
        }
    }
    Ok(())
}

fn save_outputs(
    base_dir: &Path,
    payload: &ScanPayload,
) -> Result<(), Box<dyn std::error::Error>> {
    let csv_path = base_dir.join("sizes.csv");
    let json_path = base_dir.join("report-data.json");
    let html_path = base_dir.join("disk-report.html");
    let ui_html_path = base_dir.join("ui").join("index.html");

    // 1. Ghi sizes.csv
    let mut wtr = csv::Writer::from_path(&csv_path)?;
    for item in &payload.caches {
        wtr.serialize(item)?;
    }
    wtr.flush()?;

    // 2. Ghi report-data.json
    let json_str = serde_json::to_string_pretty(payload)?;
    fs::write(&json_path, &json_str)?;

    // 3. Nhung truc tiep vao disk-report.html va ui/index.html
    let _ = inject_payload_into_html(&html_path, &json_str);
    let _ = inject_payload_into_html(&ui_html_path, &json_str);

    Ok(())
}

fn resolve_base_dir() -> PathBuf {
    let cwd = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    if cwd.join("disk-report.html").exists() || cwd.join("sizes.csv").exists() {
        return cwd;
    }
    if let Some(home) = dirs::home_dir() {
        let candidate = home.join("disk-report");
        if candidate.exists() {
            return candidate;
        }
    }
    cwd
}

#[tauri::command]
async fn scan_now() -> Result<ScanPayload, String> {
    tauri::async_runtime::spawn_blocking(|| {
        let base_dir = resolve_base_dir();
        let csv_path = base_dir.join("sizes.csv");
        let prev_map = load_previous_sizes(&csv_path);
        let payload = scanner::run_full_scan(&prev_map);
        let _ = save_outputs(&base_dir, &payload);
        payload
    })
    .await
    .map_err(|e| e.to_string())
}

#[tauri::command]
fn get_initial_data() -> Option<ScanPayload> {
    let base_dir = resolve_base_dir();
    let json_path = base_dir.join("report-data.json");
    if let Ok(content) = fs::read_to_string(&json_path) {
        if let Ok(payload) = serde_json::from_str::<ScanPayload>(&content) {
            return Some(payload);
        }
    }
    None
}

#[tauri::command]
fn open_path(path: String) -> bool {
    let p = Path::new(&path);
    let dir_to_open = if p.exists() {
        Some(p)
    } else {
        p.parent().filter(|parent| parent.exists())
    };
    if let Some(d) = dir_to_open {
        open::that(d).is_ok()
    } else {
        false
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let cli_only = args.iter().any(|a| a == "--cli" || a == "--once");

    if cli_only {
        let base_dir = resolve_base_dir();
        let csv_path = base_dir.join("sizes.csv");
        let prev_map = load_previous_sizes(&csv_path);
        let payload = scanner::run_full_scan(&prev_map);
        let _ = save_outputs(&base_dir, &payload);
        println!(
            "[OK] Hoan tat quet trong {} ms ({} Caches, {} Artifacts, {} Env Issues)",
            payload.scan_duration_ms,
            payload.caches.len(),
            payload.artifacts.len(),
            payload.env_issues.len()
        );
        return;
    }

    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            scan_now,
            get_initial_data,
            open_path
        ])
        .run(tauri::generate_context!())
        .expect("Loi khi khoi chay ung dung Tauri v2 DevDiskReport");
}
