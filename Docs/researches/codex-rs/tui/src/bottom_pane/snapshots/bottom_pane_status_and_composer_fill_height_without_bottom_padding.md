# bottom_pane_status_and_composer_fill_height_without_bottom_padding

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/mod.rs
- **Snapshot File**: codex_tui__bottom_pane__tests__status_and_composer_fill_height_without_bottom_padding.snap
- **Test Function**: status_and_composer_fill_height_without_bottom_padding

## Purpose
Tests that the BottomPane status indicator and composer fill the available height without adding unnecessary bottom padding. This snapshot validates the compact layout when a task is running and the status is displayed above the composer.

## Source Code Context
```rust
// From mod.rs - as_renderable()
fn as_renderable(&'_ self) -> RenderableItem<'_> {
    let mut flex = FlexRenderable::new();
    if let Some(status) = &self.status {
        flex.push(/*flex*/ 0, RenderableItem::Borrowed(status));
    }
    // ... pending previews ...
    let mut flex2 = FlexRenderable::new();
    flex2.push(/*flex*/ 1, RenderableItem::Owned(flex.into()));
    flex2.push(/*flex*/ 0, RenderableItem::Borrowed(&self.composer));
    RenderableItem::Owned(Box::new(flex2))
}

// From test
let height = pane.desired_height(30);
assert!(
    height >= 3,
    "expected at least 3 rows to render spacer, status, and composer; got {height}"
);
let area = Rect::new(0, 0, 30, height);
```

## UI Components Involved
- `BottomPane`: Main container
- `StatusIndicatorWidget`: Working status with spinner
- `ChatComposer`: Input composer
- `FlexRenderable`: Two-level flex layout

## Key Rendering Logic
The layout renders:
1. **Status indicator**:
   - "• Working (0s • esc to interr…" (truncated due to narrow width)
2. **Empty lines** (spacers for layout)
3. **Composer**:
   - "› Ask Codex to do anything"
4. **Footer**:
   - "100% context left" (right-aligned)

The layout uses minimal height - no extra padding is added at the bottom. The status and composer are packed efficiently.

## Test Setup Details
```rust
#[test]
fn status_and_composer_fill_height_without_bottom_padding() {
    let mut pane = BottomPane::new(BottomPaneParams { /* ... */ });
    pane.set_task_running(true);  // Activate spinner
    let height = pane.desired_height(30);
    let area = Rect::new(0, 0, 30, height);
    assert_snapshot!("status_and_composer_fill_height_without_bottom_padding", 
                     render_snapshot(&pane, area));
}
```

## Dependencies
- `StatusIndicatorWidget`: Animated status display
- `ChatComposer`: Input with placeholder
- `FlexRenderable`: Layout with flex weights (0 = fixed, 1 = expand)

## Notes
- The test verifies no trailing padding rows
- Status indicator shows "Working" with elapsed time
- "esc to interrupt" hint is shown in status
- Width is narrow (30 chars) to test truncation
- Height is dynamically calculated via `desired_height()`
