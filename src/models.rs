use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct CacheItem {
    pub path: String,
    pub name: String,
    pub category: String,
    pub group: String,
    pub file_count: u64,
    pub size_bytes: u64,
    pub size_m_b: f64,
    pub size_g_b: f64,
    pub previous_size_m_b: f64,
    pub delta_m_b: f64,
    pub increased: bool,
    pub clean_cmd: String,
    pub impact: String,
    pub scan_time: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ArtifactItem {
    pub path: String,
    pub name: String,
    pub project_name: String,
    pub artifact_type: String,
    pub category: String,
    pub group: String,
    pub file_count: u64,
    pub size_bytes: u64,
    pub size_m_b: f64,
    pub size_g_b: f64,
    pub days_idle: u64,
    pub is_stale: bool,
    pub last_modified: String,
    pub clean_cmd: String,
    pub impact: String,
    pub scan_time: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct EnvIssue {
    pub id: String,
    #[serde(rename = "Type")]
    pub issue_type: String,
    pub scope: String,
    pub var_name: String,
    pub target_value: String,
    pub status: String,
    pub group: String,
    pub impact: String,
    pub clean_cmd: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ScanPayload {
    #[serde(default)]
    pub scan_time: String,
    #[serde(default)]
    pub platform: String,
    #[serde(default)]
    pub scan_duration_ms: u128,
    #[serde(default)]
    pub caches: Vec<CacheItem>,
    #[serde(default)]
    pub artifacts: Vec<ArtifactItem>,
    #[serde(default)]
    pub env_issues: Vec<EnvIssue>,
}

pub struct TargetSpec {
    pub path: std::path::PathBuf,
    pub name: &'static str,
    pub category: &'static str,
    pub is_safe: bool,
    pub clean_cmd_win: &'static str,
    pub clean_cmd_mac: &'static str,
    pub impact: &'static str,
}
