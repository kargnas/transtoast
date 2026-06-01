use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
#[cfg(target_os = "macos")]
use std::ffi::CString;
use std::fs;
#[cfg(target_os = "macos")]
use std::os::raw::{c_char, c_void};
use std::path::{Path, PathBuf};
use std::process::Command;
use tauri::{AppHandle, Manager, Monitor, PhysicalPosition, WebviewUrl, WebviewWindowBuilder};

const TRANSLATION_WINDOW_WIDTH: f64 = 356.0;
const TRANSLATION_WINDOW_HEIGHT: f64 = 150.0;
const TRANSLATION_TALL_WINDOW_HEIGHT: f64 = 176.0;
const TRANSLATION_DEBUG_WINDOW_HEIGHT: f64 = 230.0;
const TRANSLATION_WINDOW_MARGIN: f64 = 24.0;
const TRANSLATION_CARET_GAP: f64 = 8.0;

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
struct Settings {
    provider: TranslationProvider,
    #[serde(rename = "localModelID")]
    local_model_id: String,
    #[serde(rename = "localHyMT2BackendPath")]
    local_hy_mt2_backend_path: Option<String>,
    #[serde(rename = "customLocalModelsPath")]
    custom_local_models_path: Option<String>,
    #[serde(rename = "openRouterTextModel")]
    open_router_text_model: String,
    #[serde(rename = "openRouterVisionModel")]
    open_router_vision_model: String,
    #[serde(rename = "sourceLanguage")]
    source_language: String,
    #[serde(rename = "targetLanguage")]
    target_language: String,
    #[serde(rename = "toastPosition")]
    toast_position: ToastPosition,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
enum TranslationProvider {
    #[serde(rename = "localHyMT2")]
    LocalHyMT2,
    #[serde(rename = "openRouter")]
    OpenRouter,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
enum ToastPosition {
    #[serde(rename = "bottomRight")]
    BottomRight,
    #[serde(rename = "bottomLeft")]
    BottomLeft,
    #[serde(rename = "topRight")]
    TopRight,
    #[serde(rename = "topLeft")]
    TopLeft,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
enum LegacyHyMT2Model {
    #[serde(rename = "tencent/Hy-MT2-30B-A3B")]
    HyMT230B,
    #[serde(rename = "tencent/Hy-MT2-1.8B")]
    HyMT218B,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
struct StoredSettings {
    provider: Option<TranslationProvider>,
    #[serde(rename = "hyMT2Model")]
    hy_mt2_model: Option<LegacyHyMT2Model>,
    #[serde(rename = "localModelID")]
    local_model_id: Option<String>,
    #[serde(rename = "localHyMT2BackendPath")]
    local_hy_mt2_backend_path: Option<String>,
    #[serde(rename = "customLocalModelsPath")]
    custom_local_models_path: Option<String>,
    #[serde(rename = "openRouterTextModel")]
    open_router_text_model: Option<String>,
    #[serde(rename = "openRouterVisionModel")]
    open_router_vision_model: Option<String>,
    #[serde(rename = "sourceLanguage")]
    source_language: Option<String>,
    #[serde(rename = "targetLanguage")]
    target_language: Option<String>,
    #[serde(rename = "toastPosition")]
    toast_position: Option<ToastPosition>,
}

#[derive(Clone, Debug, Serialize)]
struct SettingsState {
    settings: Settings,
    defaults: Settings,
    overrides: BTreeMap<String, bool>,
    options: SettingsOptions,
    permissions: PermissionStatus,
    #[serde(rename = "storagePath")]
    storage_path: String,
}

#[derive(Clone, Debug, Serialize)]
struct SettingsOptions {
    providers: Vec<SettingOption>,
    #[serde(rename = "localModels")]
    local_models: Vec<SettingOption>,
    #[serde(rename = "sourceLanguages")]
    source_languages: Vec<SettingOption>,
    #[serde(rename = "targetLanguages")]
    target_languages: Vec<SettingOption>,
    #[serde(rename = "toastPositions")]
    toast_positions: Vec<SettingOption>,
}

#[derive(Clone, Debug, Serialize)]
struct SettingOption {
    label: String,
    value: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    note: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
struct PermissionStatus {
    keyboard: bool,
    screen: bool,
}

#[derive(Clone, Debug, Serialize)]
struct ActionResult {
    title: String,
    message: String,
    ok: bool,
}

#[derive(Clone, Debug, Serialize)]
struct TranslationPreviewState {
    mode: String,
    #[serde(rename = "sourceLanguage")]
    source_language: String,
    #[serde(rename = "targetLanguage")]
    target_language: String,
    #[serde(rename = "originalText")]
    original_text: String,
    #[serde(rename = "translatedText")]
    translated_text: String,
    #[serde(rename = "errorText")]
    error_text: Option<String>,
    #[serde(rename = "providerTitle")]
    provider_title: String,
    model: String,
}

#[derive(Clone, Debug)]
struct TranslationPreviewRequest {
    mode: String,
    debug: bool,
    caret_override: Option<ScreenRect>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct ScreenRect {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct WorkArea {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    scale: f64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum TranslationArrowPlacement {
    BelowCaret,
    AboveCaret,
    Fallback,
}

impl TranslationArrowPlacement {
    fn as_query_value(self) -> &'static str {
        match self {
            Self::BelowCaret | Self::Fallback => "below",
            Self::AboveCaret => "above",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct TranslationWindowPlacement {
    position: PhysicalPosition<i32>,
    arrow: TranslationArrowPlacement,
}

#[tauri::command]
fn load_settings(app: AppHandle) -> Result<SettingsState, String> {
    state_from_disk(&app)
}

#[tauri::command]
fn save_settings(app: AppHandle, settings: Settings) -> Result<SettingsState, String> {
    write_settings(&app, normalize_settings(settings))?;
    state_from_disk(&app)
}

#[tauri::command]
fn reset_setting(app: AppHandle, field: String) -> Result<SettingsState, String> {
    let mut settings = load_effective_settings(&app)?;
    let defaults = default_settings();

    match field.as_str() {
        "provider" => settings.provider = defaults.provider,
        "localModelID" => settings.local_model_id = defaults.local_model_id,
        "sourceLanguage" => settings.source_language = defaults.source_language,
        "targetLanguage" => settings.target_language = defaults.target_language,
        "toastPosition" => settings.toast_position = defaults.toast_position,
        "localHyMT2BackendPath" => {
            settings.local_hy_mt2_backend_path = defaults.local_hy_mt2_backend_path
        }
        "customLocalModelsPath" => {
            settings.custom_local_models_path = defaults.custom_local_models_path
        }
        "openRouterTextModel" => settings.open_router_text_model = defaults.open_router_text_model,
        "openRouterVisionModel" => {
            settings.open_router_vision_model = defaults.open_router_vision_model
        }
        _ => return Err(format!("Unknown setting field: {field}")),
    }

    write_settings(&app, settings)?;
    state_from_disk(&app)
}

#[tauri::command]
fn perform_settings_action(
    app: AppHandle,
    action: String,
    settings: Settings,
) -> Result<ActionResult, String> {
    let settings = normalize_settings(settings);
    match action.as_str() {
        "runTextTest" => run_legacy_cli(
            &app,
            legacy_cli_args(
                &settings,
                &[
                    "--translate-text-once",
                    "The quick brown fox jumps over the lazy dog.",
                ],
            ),
            "Text Test",
        ),
        "translateScreenshot" => run_legacy_cli(
            &app,
            legacy_cli_args(&settings, &["--screenshot-once"]),
            "Screenshot Translation",
        ),
        "showRequestLogs" => Ok(action_result(
            "Request Logs",
            &spawn_legacy_window(&app, &["--show-request-logs"])?,
            true,
        )),
        "showStackedToasts" => Ok(action_result(
            "Stacked Toasts",
            &spawn_legacy_window(&app, &["--show-stacked-toasts"])?,
            true,
        )),
        "showLocalModelSetup" => Ok(action_result(
            "Model Setup",
            &spawn_legacy_window(&app, &["--show-local-model-setup"])?,
            true,
        )),
        "openPermissionHelper" => Ok(action_result(
            "Permission Helper",
            &spawn_legacy_window(&app, &["--show-permission-helper"])?,
            true,
        )),
        "openInputMonitoring" => open_privacy_url(
            "Input Monitoring",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        ),
        "openAccessibility" => open_privacy_url(
            "Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ),
        "openScreenRecording" => open_privacy_url(
            "Screen Recording",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ),
        "requestKeyboardPrompt" => request_keyboard_prompt(),
        _ => Err(format!("Unknown settings action: {action}")),
    }
}

#[tauri::command]
fn load_translation_preview(app: AppHandle) -> Result<TranslationPreviewState, String> {
    let settings = load_effective_settings(&app).unwrap_or_else(|_| default_settings());
    Ok(sample_translation_preview(&settings))
}

pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            if let Some(request) = translation_preview_request() {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.hide();
                }
                let settings =
                    load_effective_settings(app.handle()).unwrap_or_else(|_| default_settings());
                let height = if request.debug {
                    TRANSLATION_DEBUG_WINDOW_HEIGHT
                } else if request.mode == "loading" || request.mode == "error" {
                    TRANSLATION_TALL_WINDOW_HEIGHT
                } else {
                    TRANSLATION_WINDOW_HEIGHT
                };
                let placement = translation_window_placement(
                    app.handle(),
                    &settings,
                    TRANSLATION_WINDOW_WIDTH,
                    height,
                    request.caret_override,
                );
                let url = format!(
                    "index.html?surface=translation&mode={}&debug={}&placement={}",
                    request.mode,
                    if request.debug { "1" } else { "0" },
                    placement.arrow.as_query_value()
                );
                WebviewWindowBuilder::new(app, "translation", WebviewUrl::App(url.into()))
                    .title("CopyTranslator Translation")
                    .inner_size(TRANSLATION_WINDOW_WIDTH, height)
                    .min_inner_size(TRANSLATION_WINDOW_WIDTH, height)
                    .resizable(false)
                    .decorations(false)
                    .transparent(true)
                    .always_on_top(true)
                    .focused(true)
                    .build()
                    .map(|window| {
                        let _ = window.set_position(placement.position);
                    })?;
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            load_settings,
            save_settings,
            reset_setting,
            perform_settings_action,
            load_translation_preview
        ])
        .run(tauri::generate_context!())
        .expect("error while running CopyTranslator Tauri app");
}

fn translation_preview_request() -> Option<TranslationPreviewRequest> {
    let mut enabled = false;
    let mut mode = "translated".to_string();
    let mut debug = false;
    let mut caret_override = None;

    for arg in std::env::args().skip(1) {
        if arg == "--translation-preview" {
            enabled = true;
        } else if arg == "--translation-preview-debug" {
            enabled = true;
            debug = true;
        } else if let Some(value) = arg.strip_prefix("--translation-preview-state=") {
            enabled = true;
            mode = normalized_translation_mode(value).to_string();
        } else if let Some(value) = arg.strip_prefix("--translation-preview-caret=") {
            enabled = true;
            caret_override = parse_screen_rect(value);
        }
    }

    enabled.then_some(TranslationPreviewRequest {
        mode,
        debug,
        caret_override,
    })
}

fn normalized_translation_mode(value: &str) -> &'static str {
    match value {
        "loading" => "loading",
        "original" => "original",
        "error" => "error",
        _ => "translated",
    }
}

fn parse_screen_rect(value: &str) -> Option<ScreenRect> {
    let numbers = value
        .split(',')
        .map(str::trim)
        .map(str::parse::<f64>)
        .collect::<Result<Vec<_>, _>>()
        .ok()?;
    if numbers.len() != 4 {
        return None;
    }
    ScreenRect::new(numbers[0], numbers[1], numbers[2], numbers[3])
}

fn translation_window_placement(
    app: &AppHandle,
    settings: &Settings,
    logical_width: f64,
    logical_height: f64,
    caret_override: Option<ScreenRect>,
) -> TranslationWindowPlacement {
    let monitors = app.available_monitors().unwrap_or_default();
    let fallback_monitor = app.primary_monitor().ok().flatten();
    let caret = caret_override.or_else(focused_text_caret_bounds);

    if let Some(caret) = caret {
        if let Some(work_area) = work_area_for_caret(&monitors, &caret)
            .or_else(|| fallback_monitor.as_ref().map(work_area_from_monitor))
        {
            return placement_near_caret(caret, work_area, logical_width, logical_height);
        }
    }

    let work_area = fallback_monitor
        .as_ref()
        .map(work_area_from_monitor)
        .or_else(|| monitors.first().map(work_area_from_monitor))
        .unwrap_or(WorkArea {
            x: 0.0,
            y: 0.0,
            width: 1440.0,
            height: 900.0,
            scale: 1.0,
        });
    fallback_placement(settings, work_area, logical_width, logical_height)
}

fn work_area_for_caret(monitors: &[Monitor], caret: &ScreenRect) -> Option<WorkArea> {
    monitors
        .iter()
        .map(work_area_from_monitor)
        .find(|work_area| {
            let center_x = caret.mid_x();
            let center_y = caret.mid_y();
            center_x >= work_area.x
                && center_x <= work_area.max_x()
                && center_y >= work_area.y
                && center_y <= work_area.max_y()
        })
}

fn work_area_from_monitor(monitor: &Monitor) -> WorkArea {
    let scale = monitor.scale_factor();
    let area = monitor.work_area();
    WorkArea {
        x: area.position.x as f64 / scale,
        y: area.position.y as f64 / scale,
        width: area.size.width as f64 / scale,
        height: area.size.height as f64 / scale,
        scale,
    }
}

fn placement_near_caret(
    caret: ScreenRect,
    work_area: WorkArea,
    logical_width: f64,
    logical_height: f64,
) -> TranslationWindowPlacement {
    let x = clamp(
        caret.mid_x() - logical_width / 2.0,
        work_area.x + TRANSLATION_WINDOW_MARGIN,
        work_area.max_x() - logical_width - TRANSLATION_WINDOW_MARGIN,
    );

    let below_y = caret.max_y() + TRANSLATION_CARET_GAP;
    if below_y + logical_height <= work_area.max_y() - TRANSLATION_WINDOW_MARGIN {
        return TranslationWindowPlacement {
            position: physical_position(x, below_y, work_area.scale),
            arrow: TranslationArrowPlacement::BelowCaret,
        };
    }

    let above_y = caret.y - logical_height - TRANSLATION_CARET_GAP;
    if above_y >= work_area.y + TRANSLATION_WINDOW_MARGIN {
        return TranslationWindowPlacement {
            position: physical_position(x, above_y, work_area.scale),
            arrow: TranslationArrowPlacement::AboveCaret,
        };
    }

    let y = clamp(
        below_y,
        work_area.y + TRANSLATION_WINDOW_MARGIN,
        work_area.max_y() - logical_height - TRANSLATION_WINDOW_MARGIN,
    );
    TranslationWindowPlacement {
        position: physical_position(x, y, work_area.scale),
        arrow: TranslationArrowPlacement::BelowCaret,
    }
}

fn fallback_placement(
    settings: &Settings,
    work_area: WorkArea,
    logical_width: f64,
    logical_height: f64,
) -> TranslationWindowPlacement {
    let margin = TRANSLATION_WINDOW_MARGIN;
    let left = work_area.x + margin;
    let right = work_area.max_x() - logical_width - margin;
    let top = work_area.y + margin;
    let bottom = work_area.max_y() - logical_height - margin;

    let (x, y) = match settings.toast_position {
        ToastPosition::BottomRight => (right, bottom),
        ToastPosition::BottomLeft => (left, bottom),
        ToastPosition::TopRight => (right, top),
        ToastPosition::TopLeft => (left, top),
    };

    TranslationWindowPlacement {
        position: physical_position(x, y, work_area.scale),
        arrow: TranslationArrowPlacement::Fallback,
    }
}

fn physical_position(x: f64, y: f64, scale: f64) -> PhysicalPosition<i32> {
    PhysicalPosition::new((x * scale).round() as i32, (y * scale).round() as i32)
}

fn clamp(value: f64, min: f64, max: f64) -> f64 {
    if min > max {
        return min;
    }
    value.clamp(min, max)
}

impl ScreenRect {
    fn new(x: f64, y: f64, width: f64, height: f64) -> Option<Self> {
        if !x.is_finite() || !y.is_finite() || !width.is_finite() || !height.is_finite() {
            return None;
        }
        if width < 0.0 || height <= 0.0 {
            return None;
        }
        Some(Self {
            x,
            y,
            width: width.max(1.0),
            height,
        })
    }

    fn mid_x(self) -> f64 {
        self.x + self.width / 2.0
    }

    fn mid_y(self) -> f64 {
        self.y + self.height / 2.0
    }

    fn max_y(self) -> f64 {
        self.y + self.height
    }
}

impl WorkArea {
    fn max_x(self) -> f64 {
        self.x + self.width
    }

    fn max_y(self) -> f64 {
        self.y + self.height
    }
}

#[cfg(target_os = "macos")]
fn focused_text_caret_bounds() -> Option<ScreenRect> {
    unsafe { focused_text_caret_bounds_macos() }
}

#[cfg(not(target_os = "macos"))]
fn focused_text_caret_bounds() -> Option<ScreenRect> {
    None
}

fn sample_translation_preview(settings: &Settings) -> TranslationPreviewState {
    TranslationPreviewState {
        mode: "translated".to_string(),
        source_language: "English".to_string(),
        target_language: settings.target_language.clone(),
        original_text: "The future belongs to those who believe in the beauty of their dreams."
            .to_string(),
        translated_text: "미래는 자신의 꿈의 아름다움을 믿는 사람들의 것이다.".to_string(),
        error_text: None,
        provider_title: provider_title(&settings.provider).to_string(),
        model: model_title(&settings.local_model_id, &settings.provider).to_string(),
    }
}

fn provider_title(provider: &TranslationProvider) -> &'static str {
    match provider {
        TranslationProvider::LocalHyMT2 => "Local Model",
        TranslationProvider::OpenRouter => "OpenRouter LLM",
    }
}

fn model_title(model_id: &str, provider: &TranslationProvider) -> &'static str {
    if matches!(provider, TranslationProvider::OpenRouter) {
        return "google/gemini-2.5-flash-lite";
    }

    match model_id {
        "hymt2-mlx-1.8b-4bit" => "Hy-MT2 1.8B 4-bit (MLX)",
        "hymt2-transformers-1.8b" => "Hy-MT2 1.8B (Transformers)",
        "hymt2-transformers-30b" => "Hy-MT2 30B-A3B (Transformers)",
        _ => "Selected local model",
    }
}

fn state_from_disk(app: &AppHandle) -> Result<SettingsState, String> {
    let settings = load_effective_settings(app)?;
    let defaults = default_settings();
    let storage_path = settings_path(app)?.display().to_string();

    Ok(SettingsState {
        overrides: override_map(&settings, &defaults),
        settings,
        defaults,
        options: settings_options(),
        permissions: permission_status(),
        storage_path,
    })
}

fn load_effective_settings(app: &AppHandle) -> Result<Settings, String> {
    let path = settings_path(app)?;
    if !path.exists() {
        return Ok(default_settings());
    }

    let data = fs::read_to_string(&path)
        .map_err(|error| format!("Could not read {}: {error}", path.display()))?;
    let stored: StoredSettings = serde_json::from_str(&data)
        .map_err(|error| format!("Could not parse {}: {error}", path.display()))?;
    Ok(apply_stored_settings(stored))
}

fn apply_stored_settings(stored: StoredSettings) -> Settings {
    let mut settings = default_settings();
    if let Some(provider) = stored.provider {
        settings.provider = provider;
    }
    settings.local_model_id = stored
        .local_model_id
        .or_else(|| stored.hy_mt2_model.map(legacy_model_id))
        .unwrap_or(settings.local_model_id);
    settings.local_hy_mt2_backend_path = stored.local_hy_mt2_backend_path;
    settings.custom_local_models_path = stored.custom_local_models_path;
    if let Some(value) = stored.open_router_text_model {
        settings.open_router_text_model = value;
    }
    if let Some(value) = stored.open_router_vision_model {
        settings.open_router_vision_model = value;
    }
    if let Some(value) = stored.source_language {
        settings.source_language = value;
    }
    if let Some(value) = stored.target_language {
        settings.target_language = value;
    }
    if let Some(value) = stored.toast_position {
        settings.toast_position = value;
    }
    normalize_settings(settings)
}

fn write_settings(app: &AppHandle, settings: Settings) -> Result<(), String> {
    let path = settings_path(app)?;
    let defaults = default_settings();
    let stored = StoredSettings::from_effective(&settings, &defaults);

    if stored.is_empty() {
        if path.exists() {
            fs::remove_file(&path)
                .map_err(|error| format!("Could not remove {}: {error}", path.display()))?;
        }
        return Ok(());
    }

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("Could not create {}: {error}", parent.display()))?;
    }

    let data = serde_json::to_string_pretty(&stored)
        .map_err(|error| format!("Could not encode settings: {error}"))?;
    fs::write(&path, data).map_err(|error| format!("Could not write {}: {error}", path.display()))
}

impl StoredSettings {
    fn from_effective(settings: &Settings, defaults: &Settings) -> Self {
        Self {
            provider: (settings.provider != defaults.provider).then(|| settings.provider.clone()),
            hy_mt2_model: None,
            local_model_id: (settings.local_model_id != defaults.local_model_id)
                .then(|| settings.local_model_id.clone()),
            local_hy_mt2_backend_path: (settings.local_hy_mt2_backend_path
                != defaults.local_hy_mt2_backend_path)
                .then(|| settings.local_hy_mt2_backend_path.clone())
                .flatten(),
            custom_local_models_path: (settings.custom_local_models_path
                != defaults.custom_local_models_path)
                .then(|| settings.custom_local_models_path.clone())
                .flatten(),
            open_router_text_model: (settings.open_router_text_model
                != defaults.open_router_text_model)
                .then(|| settings.open_router_text_model.clone()),
            open_router_vision_model: (settings.open_router_vision_model
                != defaults.open_router_vision_model)
                .then(|| settings.open_router_vision_model.clone()),
            source_language: (settings.source_language != defaults.source_language)
                .then(|| settings.source_language.clone()),
            target_language: (settings.target_language != defaults.target_language)
                .then(|| settings.target_language.clone()),
            toast_position: (settings.toast_position != defaults.toast_position)
                .then(|| settings.toast_position.clone()),
        }
    }

    fn is_empty(&self) -> bool {
        self.provider.is_none()
            && self.hy_mt2_model.is_none()
            && self.local_model_id.is_none()
            && self.local_hy_mt2_backend_path.is_none()
            && self.custom_local_models_path.is_none()
            && self.open_router_text_model.is_none()
            && self.open_router_vision_model.is_none()
            && self.source_language.is_none()
            && self.target_language.is_none()
            && self.toast_position.is_none()
    }
}

fn settings_path(app: &AppHandle) -> Result<PathBuf, String> {
    app.path()
        .app_data_dir()
        .map(|dir| dir.join("settings-overrides.json"))
        .map_err(|error| format!("Could not resolve app data directory: {error}"))
}

fn default_settings() -> Settings {
    Settings {
        provider: TranslationProvider::LocalHyMT2,
        local_model_id: "hymt2-mlx-1.8b-4bit".to_string(),
        local_hy_mt2_backend_path: None,
        custom_local_models_path: None,
        open_router_text_model: "google/gemini-2.5-flash-lite".to_string(),
        open_router_vision_model: "google/gemini-2.5-flash-lite".to_string(),
        source_language: "Auto".to_string(),
        target_language: "Korean".to_string(),
        toast_position: ToastPosition::BottomRight,
    }
}

fn normalize_settings(mut settings: Settings) -> Settings {
    settings.local_hy_mt2_backend_path = normalized_optional(settings.local_hy_mt2_backend_path);
    settings.custom_local_models_path = normalized_optional(settings.custom_local_models_path);
    settings.open_router_text_model = settings.open_router_text_model.trim().to_string();
    settings.open_router_vision_model = settings.open_router_vision_model.trim().to_string();
    settings.source_language = settings.source_language.trim().to_string();
    settings.target_language = settings.target_language.trim().to_string();
    settings
}

fn normalized_optional(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn override_map(settings: &Settings, defaults: &Settings) -> BTreeMap<String, bool> {
    BTreeMap::from([
        (
            "provider".to_string(),
            settings.provider != defaults.provider,
        ),
        (
            "localModelID".to_string(),
            settings.local_model_id != defaults.local_model_id,
        ),
        (
            "sourceLanguage".to_string(),
            settings.source_language != defaults.source_language,
        ),
        (
            "targetLanguage".to_string(),
            settings.target_language != defaults.target_language,
        ),
        (
            "toastPosition".to_string(),
            settings.toast_position != defaults.toast_position,
        ),
        (
            "localHyMT2BackendPath".to_string(),
            settings.local_hy_mt2_backend_path != defaults.local_hy_mt2_backend_path,
        ),
        (
            "customLocalModelsPath".to_string(),
            settings.custom_local_models_path != defaults.custom_local_models_path,
        ),
        (
            "openRouterTextModel".to_string(),
            settings.open_router_text_model != defaults.open_router_text_model,
        ),
        (
            "openRouterVisionModel".to_string(),
            settings.open_router_vision_model != defaults.open_router_vision_model,
        ),
    ])
}

fn settings_options() -> SettingsOptions {
    SettingsOptions {
        providers: vec![
            option("Local Model", "localHyMT2", None),
            option("OpenRouter LLM", "openRouter", None),
        ],
        local_models: vec![
            option(
                "Hy-MT2 1.8B 4-bit (MLX)",
                "hymt2-mlx-1.8b-4bit",
                Some("Recommended"),
            ),
            option(
                "Hy-MT2 1.8B (Transformers)",
                "hymt2-transformers-1.8b",
                None,
            ),
            option(
                "Hy-MT2 30B-A3B (Transformers)",
                "hymt2-transformers-30b",
                None,
            ),
            option("Hy-MT2 1.8B IQ4_XS (GGUF)", "hymt2-gguf-iq4-xs", None),
            option("LFM2 Ko-En Q4_K_M (GGUF)", "lfm2-koen-q4-k-m", None),
            option("NLLB CTranslate2 int8", "nllb-ct2-int8", None),
            option("QuickMT En-Ko", "quickmt-en-ko", None),
            option("Kanana 1.5 2.1B AIHub Ko-En LoRA", "kanana-lora-koen", None),
            option("MADLAD-400 Swift int4", "madlad-swift-int4", None),
        ],
        source_languages: language_options(true),
        target_languages: language_options(false),
        toast_positions: vec![
            option("Bottom Right", "bottomRight", None),
            option("Bottom Left", "bottomLeft", None),
            option("Top Right", "topRight", None),
            option("Top Left", "topLeft", None),
        ],
    }
}

fn language_options(include_auto: bool) -> Vec<SettingOption> {
    let languages = [
        "Auto",
        "English",
        "Korean",
        "Simplified Chinese",
        "Japanese",
        "Spanish",
        "German",
        "French",
        "Indonesian",
        "Arabic",
    ];
    languages
        .into_iter()
        .filter(|language| include_auto || *language != "Auto")
        .map(|language| option(language, language, None))
        .collect()
}

fn option(label: &str, value: &str, note: Option<&str>) -> SettingOption {
    SettingOption {
        label: label.to_string(),
        value: value.to_string(),
        note: note.map(ToString::to_string),
    }
}

fn legacy_model_id(model: LegacyHyMT2Model) -> String {
    match model {
        LegacyHyMT2Model::HyMT230B => "hymt2-transformers-30b",
        LegacyHyMT2Model::HyMT218B => "hymt2-transformers-1.8b",
    }
    .to_string()
}

fn provider_arg(provider: &TranslationProvider) -> &'static str {
    match provider {
        TranslationProvider::LocalHyMT2 => "local",
        TranslationProvider::OpenRouter => "openrouter",
    }
}

fn legacy_cli_args(settings: &Settings, base: &[&str]) -> Vec<String> {
    let mut args = base
        .iter()
        .map(|value| (*value).to_string())
        .collect::<Vec<_>>();
    args.extend([
        "--provider".to_string(),
        provider_arg(&settings.provider).to_string(),
        "--local-model".to_string(),
        settings.local_model_id.clone(),
        "--source-language".to_string(),
        settings.source_language.clone(),
        "--target-language".to_string(),
        settings.target_language.clone(),
        "--openrouter-text-model".to_string(),
        settings.open_router_text_model.clone(),
        "--openrouter-vision-model".to_string(),
        settings.open_router_vision_model.clone(),
    ]);
    if let Some(path) = &settings.local_hy_mt2_backend_path {
        args.extend(["--local-backend".to_string(), path.clone()]);
    }
    if let Some(path) = &settings.custom_local_models_path {
        args.extend(["--custom-local-models".to_string(), path.clone()]);
    }
    args
}

fn run_legacy_cli(app: &AppHandle, args: Vec<String>, title: &str) -> Result<ActionResult, String> {
    let binary = legacy_binary_path(app)?;
    let output = Command::new(&binary)
        .args(&args)
        .output()
        .map_err(|error| format!("Could not run {}: {error}", binary.display()))?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let message = if output.status.success() {
        first_non_empty(&stdout, "Completed.")
    } else {
        first_non_empty(&stderr, &stdout)
    };

    Ok(action_result(title, &message, output.status.success()))
}

fn spawn_legacy_window(app: &AppHandle, args: &[&str]) -> Result<String, String> {
    let binary = legacy_binary_path(app)?;
    Command::new(&binary)
        .args(args)
        .spawn()
        .map_err(|error| format!("Could not open {}: {error}", binary.display()))?;
    Ok("Legacy app window opened for this migration step.".to_string())
}

fn legacy_binary_path(app: &AppHandle) -> Result<PathBuf, String> {
    let roots = candidate_roots(app);
    for root in roots {
        let candidates = [
            root.join(".build/debug/CopyTranslator"),
            root.join("dist/CopyTranslator.app/Contents/MacOS/CopyTranslator"),
        ];
        if let Some(path) = candidates.into_iter().find(|path| path.exists()) {
            return Ok(path);
        }
    }
    Err("CopyTranslator CLI binary not found. Build the Swift app first.".to_string())
}

fn candidate_roots(app: &AppHandle) -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Ok(current) = std::env::current_dir() {
        push_ancestors(&mut roots, &current);
    }
    if let Ok(resource_dir) = app.path().resource_dir() {
        push_ancestors(&mut roots, &resource_dir);
    }
    roots
}

fn push_ancestors(roots: &mut Vec<PathBuf>, start: &Path) {
    for ancestor in start.ancestors() {
        let root = ancestor.to_path_buf();
        if root.join("Package.swift").exists() && !roots.contains(&root) {
            roots.push(root);
        }
    }
}

fn first_non_empty(primary: &str, fallback: &str) -> String {
    if !primary.is_empty() {
        primary.to_string()
    } else if !fallback.is_empty() {
        fallback.to_string()
    } else {
        "No output.".to_string()
    }
}

fn open_privacy_url(title: &str, url: &str) -> Result<ActionResult, String> {
    Command::new("open")
        .arg(url)
        .spawn()
        .map_err(|error| format!("Could not open System Settings: {error}"))?;
    Ok(action_result(title, "System Settings opened.", true))
}

fn request_keyboard_prompt() -> Result<ActionResult, String> {
    #[cfg(target_os = "macos")]
    {
        let granted = unsafe { CGRequestListenEventAccess() };
        return Ok(action_result(
            "Keyboard Prompt",
            if granted {
                "Keyboard monitoring is available."
            } else {
                "Keyboard permission prompt requested."
            },
            true,
        ));
    }

    #[cfg(not(target_os = "macos"))]
    {
        Ok(action_result(
            "Keyboard Prompt",
            "Keyboard permission prompt is macOS-only.",
            false,
        ))
    }
}

fn permission_status() -> PermissionStatus {
    #[cfg(target_os = "macos")]
    {
        let keyboard = unsafe { CGPreflightListenEventAccess() || AXIsProcessTrusted() };
        let screen = unsafe { CGPreflightScreenCaptureAccess() };
        PermissionStatus { keyboard, screen }
    }

    #[cfg(not(target_os = "macos"))]
    {
        PermissionStatus {
            keyboard: false,
            screen: false,
        }
    }
}

#[cfg(target_os = "macos")]
unsafe fn focused_text_caret_bounds_macos() -> Option<ScreenRect> {
    let system = OwnedCfRef::new(AXUIElementCreateSystemWide())?;
    let focused_attribute = cf_string("AXFocusedUIElement")?;
    let selected_range_attribute = cf_string("AXSelectedTextRange")?;
    let bounds_attribute = cf_string("AXBoundsForRange")?;

    let mut focused_object: CFTypeRef = std::ptr::null();
    if AXUIElementCopyAttributeValue(
        system.as_ptr(),
        focused_attribute.as_ptr(),
        &mut focused_object,
    ) != K_AX_ERROR_SUCCESS
        || focused_object.is_null()
    {
        return None;
    }
    let focused_element = OwnedCfRef::new(focused_object)?;

    let mut range_object: CFTypeRef = std::ptr::null();
    if AXUIElementCopyAttributeValue(
        focused_element.as_ptr(),
        selected_range_attribute.as_ptr(),
        &mut range_object,
    ) != K_AX_ERROR_SUCCESS
        || range_object.is_null()
    {
        return None;
    }
    let selected_range = OwnedCfRef::new(range_object)?;

    let mut bounds_object: CFTypeRef = std::ptr::null();
    if AXUIElementCopyParameterizedAttributeValue(
        focused_element.as_ptr(),
        bounds_attribute.as_ptr(),
        selected_range.as_ptr(),
        &mut bounds_object,
    ) != K_AX_ERROR_SUCCESS
        || bounds_object.is_null()
    {
        return None;
    }
    let bounds_value = OwnedCfRef::new(bounds_object)?;
    if AXValueGetType(bounds_value.as_ptr()) != K_AX_VALUE_CGRECT_TYPE {
        return None;
    }

    let mut rect = CGRect::default();
    if AXValueGetValue(
        bounds_value.as_ptr(),
        K_AX_VALUE_CGRECT_TYPE,
        &mut rect as *mut CGRect as *mut c_void,
    ) == 0
    {
        return None;
    }

    ScreenRect::new(
        rect.origin.x,
        rect.origin.y,
        rect.size.width,
        rect.size.height,
    )
}

#[cfg(target_os = "macos")]
fn cf_string(value: &str) -> Option<OwnedCfRef> {
    let value = CString::new(value).ok()?;
    let string = unsafe {
        CFStringCreateWithCString(std::ptr::null(), value.as_ptr(), K_CF_STRING_ENCODING_UTF8)
    };
    OwnedCfRef::new(string)
}

#[cfg(target_os = "macos")]
struct OwnedCfRef(CFTypeRef);

#[cfg(target_os = "macos")]
impl OwnedCfRef {
    fn new(value: CFTypeRef) -> Option<Self> {
        (!value.is_null()).then_some(Self(value))
    }

    fn as_ptr(&self) -> CFTypeRef {
        self.0
    }
}

#[cfg(target_os = "macos")]
impl Drop for OwnedCfRef {
    fn drop(&mut self) {
        unsafe {
            CFRelease(self.0);
        }
    }
}

fn action_result(title: &str, message: &str, ok: bool) -> ActionResult {
    ActionResult {
        title: title.to_string(),
        message: message.to_string(),
        ok,
    }
}

#[cfg(target_os = "macos")]
type CFTypeRef = *const c_void;
#[cfg(target_os = "macos")]
type CFStringRef = CFTypeRef;
#[cfg(target_os = "macos")]
type AXUIElementRef = CFTypeRef;
#[cfg(target_os = "macos")]
type AXValueRef = CFTypeRef;

#[cfg(target_os = "macos")]
const K_AX_ERROR_SUCCESS: i32 = 0;
#[cfg(target_os = "macos")]
const K_AX_VALUE_CGRECT_TYPE: u32 = 3;
#[cfg(target_os = "macos")]
const K_CF_STRING_ENCODING_UTF8: u32 = 0x0800_0100;

#[cfg(target_os = "macos")]
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
struct CGPoint {
    x: f64,
    y: f64,
}

#[cfg(target_os = "macos")]
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
struct CGSize {
    width: f64,
    height: f64,
}

#[cfg(target_os = "macos")]
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
struct CGRect {
    origin: CGPoint,
    size: CGSize,
}

#[cfg(target_os = "macos")]
#[link(name = "ApplicationServices", kind = "framework")]
extern "C" {
    fn AXIsProcessTrusted() -> bool;
    fn AXUIElementCreateSystemWide() -> AXUIElementRef;
    fn AXUIElementCopyAttributeValue(
        element: AXUIElementRef,
        attribute: CFStringRef,
        value: *mut CFTypeRef,
    ) -> i32;
    fn AXUIElementCopyParameterizedAttributeValue(
        element: AXUIElementRef,
        parameterized_attribute: CFStringRef,
        parameter: CFTypeRef,
        result: *mut CFTypeRef,
    ) -> i32;
    fn AXValueGetType(value: AXValueRef) -> u32;
    fn AXValueGetValue(value: AXValueRef, value_type: u32, value_ptr: *mut c_void) -> u8;
    fn CGPreflightListenEventAccess() -> bool;
    fn CGRequestListenEventAccess() -> bool;
    fn CGPreflightScreenCaptureAccess() -> bool;
}

#[cfg(target_os = "macos")]
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFStringCreateWithCString(
        alloc: CFTypeRef,
        c_str: *const c_char,
        encoding: u32,
    ) -> CFStringRef;
    fn CFRelease(cf: CFTypeRef);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stored_settings_omits_defaults() {
        let defaults = default_settings();
        let stored = StoredSettings::from_effective(&defaults, &defaults);
        assert!(stored.is_empty());
    }

    #[test]
    fn stored_settings_keeps_only_overrides() {
        let defaults = default_settings();
        let mut settings = defaults.clone();
        settings.provider = TranslationProvider::OpenRouter;
        settings.open_router_text_model = "custom/text-model".to_string();

        let stored = StoredSettings::from_effective(&settings, &defaults);
        assert_eq!(stored.provider, Some(TranslationProvider::OpenRouter));
        assert_eq!(
            stored.open_router_text_model.as_deref(),
            Some("custom/text-model")
        );
        assert!(stored.open_router_vision_model.is_none());
        assert!(stored.target_language.is_none());
    }

    #[test]
    fn legacy_hymt2_model_migrates_to_local_model_id() {
        let settings = apply_stored_settings(StoredSettings {
            provider: Some(TranslationProvider::OpenRouter),
            hy_mt2_model: Some(LegacyHyMT2Model::HyMT218B),
            ..StoredSettings::default()
        });

        assert_eq!(settings.provider, TranslationProvider::OpenRouter);
        assert_eq!(settings.local_model_id, "hymt2-transformers-1.8b");
    }

    #[test]
    fn optional_paths_trim_to_none() {
        let mut settings = default_settings();
        settings.local_hy_mt2_backend_path = Some("   ".to_string());
        settings.custom_local_models_path = Some("  ~/models.json  ".to_string());
        let settings = normalize_settings(settings);

        assert_eq!(settings.local_hy_mt2_backend_path, None);
        assert_eq!(
            settings.custom_local_models_path.as_deref(),
            Some("~/models.json")
        );
    }

    #[test]
    fn caret_placement_prefers_below_cursor() {
        let placement = placement_near_caret(
            ScreenRect::new(500.0, 300.0, 2.0, 18.0).unwrap(),
            test_work_area(),
            356.0,
            150.0,
        );

        assert_eq!(placement.arrow, TranslationArrowPlacement::BelowCaret);
        assert_eq!(placement.position.x, 646);
        assert_eq!(placement.position.y, 652);
    }

    #[test]
    fn caret_placement_flips_above_near_bottom() {
        let placement = placement_near_caret(
            ScreenRect::new(500.0, 760.0, 2.0, 18.0).unwrap(),
            test_work_area(),
            356.0,
            150.0,
        );

        assert_eq!(placement.arrow, TranslationArrowPlacement::AboveCaret);
        assert_eq!(placement.position.x, 646);
        assert_eq!(placement.position.y, 1204);
    }

    #[test]
    fn caret_placement_clamps_to_work_area_edges() {
        let placement = placement_near_caret(
            ScreenRect::new(10.0, 20.0, 2.0, 18.0).unwrap(),
            test_work_area(),
            356.0,
            150.0,
        );

        assert_eq!(placement.arrow, TranslationArrowPlacement::BelowCaret);
        assert_eq!(placement.position.x, 48);
        assert_eq!(placement.position.y, 92);
    }

    #[test]
    fn fallback_placement_uses_toast_position_only_without_caret() {
        let mut settings = default_settings();
        settings.toast_position = ToastPosition::TopLeft;
        let placement = fallback_placement(&settings, test_work_area(), 356.0, 150.0);

        assert_eq!(placement.arrow, TranslationArrowPlacement::Fallback);
        assert_eq!(placement.position.x, 48);
        assert_eq!(placement.position.y, 48);
    }

    fn test_work_area() -> WorkArea {
        WorkArea {
            x: 0.0,
            y: 0.0,
            width: 1200.0,
            height: 800.0,
            scale: 2.0,
        }
    }
}
