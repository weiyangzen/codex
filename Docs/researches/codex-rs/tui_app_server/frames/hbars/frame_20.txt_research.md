# Frame 20 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 20 是 HBARS 动画序列的第二十帧，位于第二阶段的中期。此帧继续展示波浪形态的演变，条块分布更加分散，是整个 36 帧循环中第二阶段发展的重要帧。

在 36 帧循环中，Frame 20 代表了约 55.6% 的进度（20/36），标志着第二阶段进入中期发展阶段。

## 功能点目的

1. **中期深化**：深化第二阶段的波形发展
2. **分散增强**：增强条块的分散程度
3. **视觉动态**：提供更动态的视觉体验
4. **节奏维持**：维持动画的整体节奏

## 具体技术实现

### Unicode 字符集
- `▁` (U+2581) - Lower one eighth block
- `▂` (U+2582) - Lower one quarter block
- `▃` (U+2583) - Lower three eighths block
- `▄` (U+2584) - Lower half block
- `▅` (U+2585) - Lower five eighths block
- `▆` (U+2586) - Lower three quarters block
- `▇` (U+2587) - Lower seven eighths block
- `█` (U+2588) - Full block

### 帧规格
- **行数**：17 行（包含首尾空行）
- **宽度**：约 40 字符
- **帧索引**：19（在 FRAMES_HBARS 数组中）
- **显示时序**：第 1520-1600ms

### 视觉模式
Frame 20 展示了分散状态：
- 条块分布非常分散
- 波浪形态更加开放
- 整体视觉效果更加轻盈

## 关键代码路径与文件引用

### 帧数组访问
```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");
// Frame 20: FRAMES_HBARS[19]
```

### 变体切换
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) fn pick_random_variant(&mut self) -> bool {
    if self.variants.len() <= 1 {
        return false;
    }
    let mut rng = rand::rng();
    let mut next = self.variant_idx;
    while next == self.variant_idx {
        next = rng.random_range(0..self.variants.len());
    }
    self.variant_idx = next;
    self.request_frame.schedule_frame();
    true
}
```

### 欢迎组件
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
pub(crate) struct WelcomeWidget {
    pub is_logged_in: bool,
    animation: AsciiAnimation,
    animations_enabled: bool,
    layout_area: Cell<Option<Rect>>,
}
```

## 依赖与外部交互

### 变体列表
| 索引 | 变体 | 描述 |
|------|------|------|
| 0 | DEFAULT | 默认动画 |
| 1 | CODEX | Codex 主题 |
| 2 | OPENAI | OpenAI 主题 |
| 3 | BLOCKS | 方块动画 |
| 4 | DOTS | 点阵动画 |
| 5 | HASH | 哈希图案 |
| 6 | HBARS | 水平条（当前） |
| 7 | VBARS | 垂直条 |
| 8 | SHAPES | 几何形状 |
| 9 | SLUG | 蛞蝓图案 |

## 风险、边界与改进建议

### 风险与边界

1. **变体切换闪烁**
   - 切换变体时可能出现视觉跳跃
   - 不同变体的 Frame 20 可能差异很大

2. **索引越界风险**
   - `variant_idx.min(variants.len() - 1)` 防止越界
   - 但可能导致意外的变体选择

3. **测试覆盖**
   - 当前测试主要覆盖基本功能
   - 缺少对特定帧的视觉测试

### 改进建议

1. **变体预览**
   - 添加变体缩略图预览
   - 帮助用户选择喜欢的动画

2. **帧快照测试**
   - 使用 insta 进行帧内容快照测试
   - 防止意外的帧修改

3. **用户偏好**
   - 保存用户偏好的变体到配置文件
   - 下次启动时自动选择

### 测试示例

```rust
#[test]
fn frame_20_not_empty() {
    assert!(!FRAMES_HBARS[19].is_empty());
}

#[test]
fn frame_20_valid_chars() {
    let valid_chars: HashSet<char> = "▁▂▃▄▅▆▇█ \n".chars().collect();
    for ch in FRAMES_HBARS[19].chars() {
        assert!(valid_chars.contains(&ch), "Invalid char: {}", ch);
    }
}
```
