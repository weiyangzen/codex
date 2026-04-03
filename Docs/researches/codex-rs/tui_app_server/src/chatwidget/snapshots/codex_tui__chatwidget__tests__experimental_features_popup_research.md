# Research: Experimental Features Popup

## 1. 场景与职责 (Scene and Responsibility)

This snapshot captures the **Experimental Features Popup** UI component in the Codex TUI application. This popup is displayed when the user triggers the experimental features selection interface, typically via a slash command or menu option.

**Scene Context:**
- The user is configuring experimental features that are not yet part of the stable API
- Features can be toggled on/off and changes are persisted to `config.toml`
- This is a configuration management interface for beta/unstable functionality

**Responsibilities:**
- Display available experimental features with their current state (enabled/disabled)
- Provide descriptions for each feature to help users understand their purpose
- Allow users to toggle features via keyboard interaction (space to select, enter to save)
- Persist feature preferences to configuration file

## 2. 功能点目的 (Functional Purpose)

The experimental features popup serves several key purposes:

1. **Feature Discovery**: Exposes users to new features that are in development (e.g., "Ghost snapshots", "Shell tool")
2. **Safe Experimentation**: Allows users to opt-in to experimental functionality without affecting stable workflows
3. **Configuration Persistence**: Saves user preferences to `config.toml` for persistence across sessions
4. **Risk Communication**: Clearly labels features as experimental, setting appropriate user expectations

**Key Features Shown:**
- **Ghost snapshots**: Capture undo snapshots each turn (disabled in snapshot)
- **Shell tool**: Allow the model to run shell commands (enabled in snapshot)

## 3. 具体技术实现 (Technical Implementation)

### Key Data Structures

```rust
// From codex_core::features
pub struct Feature;  // Enum representing available experimental features

// Experimental feature item for UI rendering
pub struct ExperimentalFeatureItem {
    pub feature: Feature,
    pub name: String,
    pub description: String,
    pub enabled: bool,
}
```

### Rendering Format

The popup renders as a selection list with:
- **Title**: "Experimental features"
- **Description**: "Toggle experimental features. Changes are saved to config.toml."
- **Feature List**: Each feature shows:
  - Checkbox state: `[ ]` for disabled, `[x]` for enabled
  - Feature name (left-aligned)
  - Feature description (right-aligned, dimmed)
- **Current Selection**: Highlighted with `›` prefix
- **Footer Instructions**: "Press space to select or enter to save for next conversation"

### Key Processes

1. **Popup Creation** (`experimental_features_popup_snapshot` test):
```rust
let features = vec![
    ExperimentalFeatureItem {
        feature: Feature::GhostCommit,
        name: "Ghost snapshots".to_string(),
        description: "Capture undo snapshots each turn.".to_string(),
        enabled: false,
    },
    ExperimentalFeatureItem {
        feature: Feature::ShellTool,
        name: "Shell tool".to_string(),
        description: "Allow the model to run shell commands.".to_string(),
        enabled: true,
    },
];
let view = ExperimentalFeaturesView::new(features, chat.app_event_tx.clone());
chat.bottom_pane.show_view(Box::new(view));
```

2. **Rendering**: Uses `render_bottom_popup()` helper to capture the rendered UI state

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files

| File | Description |
|------|-------------|
| `codex-rs/tui/src/chatwidget/tests.rs` | Contains test `experimental_features_popup_snapshot` (line ~7587) |
| `codex-rs/tui/src/bottom_pane/mod.rs` | Likely contains `ExperimentalFeaturesView` implementation |
| `codex-rs/core/src/features.rs` | Defines `Feature` enum and feature metadata |

### Key Functions

```rust
// Test function
async fn experimental_features_popup_snapshot()  // tests.rs:7587

// Helper for rendering popups
fn render_bottom_popup(chat: &ChatWidget, width: u16) -> String  // tests.rs:6661

// Feature definitions
pub struct Feature;  // features.rs
```

### Related Snapshots
- `codex_tui__chatwidget__tests__experimental_features_popup.snap` (this file)

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies

- `codex_core::features::Feature`: Core feature flag definitions
- `codex_core::features::FEATURES`: Feature metadata registry
- `ChatWidget::bottom_pane`: Bottom pane for popup rendering
- `ExperimentalFeaturesView`: UI component for feature selection
- `AppEventSender`: For emitting configuration update events

### External Dependencies

- **Configuration Persistence**: Changes saved to `config.toml`
- **Feature System**: Integrates with the core feature flag system

### Event Flow

```
User Input (Space/Enter) 
    ↓
ExperimentalFeaturesView handles key event
    ↓
AppEvent::UpdateFeatureFlags emitted
    ↓
Config updated and persisted to config.toml
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks

1. **Configuration Drift**: Multiple toggles without saving could lead to confusion about current state
2. **Feature Interdependencies**: Some features may depend on others; the UI doesn't show dependencies
3. **Persistence Failures**: If config.toml write fails, user loses their selections without warning

### Edge Cases

1. **Empty Feature List**: What happens when no experimental features are available?
2. **Feature Removal**: If a feature is removed from the codebase but exists in config.toml
3. **Concurrent Modifications**: External changes to config.toml while popup is open
4. **Invalid Feature States**: Features that require other prerequisites (e.g., platform-specific features)

### Improvement Suggestions

1. **Dependency Visualization**: Show feature dependencies in the UI (e.g., "Requires Shell tool")
2. **Confirmation Dialog**: Warn users about potentially dangerous features before enabling
3. **Revert Capability**: Add ability to revert to defaults or previous state
4. **Feature Categories**: Group related features (e.g., "Safety", "Productivity", "Experimental")
5. **Search/Filter**: Allow searching features by name or description for better discoverability
6. **Tooltips**: Show extended descriptions or documentation links on hover/focus
7. **Session vs Persistent**: Distinguish between session-only and persistent changes
8. **Validation**: Validate feature combinations before saving to prevent invalid states
