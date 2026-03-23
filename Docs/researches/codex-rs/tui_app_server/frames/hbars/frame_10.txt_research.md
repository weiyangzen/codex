# Frame 10 Research Document - HBARS Animation Sequence

## 场景与职责

Frame 10 是 HBARS 动画序列的第十帧，位于中期阶段的核心位置。此帧展现出波浪收缩后的稳定状态，条块分布达到一个局部密集点，是整个动画循环中视觉冲击力较强的帧之一。

在 36 帧循环中，Frame 10 代表了约 27.8% 的进度（10/36），是中期阶段的高潮帧。

## 功能点目的

1. **密集展示**：展示波浪的密集状态
2. **视觉冲击**：提供强烈的视觉冲击效果
3. **高潮铺垫**：为后续帧的释放做准备
4. **节奏控制**：控制动画的节奏感

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
- **帧索引**：9（在 FRAMES_HBARS 数组中）
- **显示时序**：第 720-800ms

### 视觉模式
Frame 10 展示了密集状态：
- 条块高度普遍较高
- 波峰和波谷的对比更加明显
- 整体视觉效果更加饱满

## 关键代码路径与文件引用

### 帧数组访问
```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,  // 0
    &FRAMES_CODEX,    // 1
    &FRAMES_OPENAI,   // 2
    &FRAMES_BLOCKS,   // 3
    &FRAMES_DOTS,     // 4
    &FRAMES_HASH,     // 5
    &FRAMES_HBARS,    // 6
    &FRAMES_VBARS,    // 7
    &FRAMES_SHAPES,   // 8
    &FRAMES_SLUG,     // 9
];
```

### 变体索引
```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
pub(crate) fn with_variants(
    request_frame: FrameRequester,
    variants: &'static [&'static [&'static str]],
    variant_idx: usize,
) -> Self {
    let clamped_idx = variant_idx.min(variants.len() - 1);
    // ...
}
```

### 尺寸约束
```rust
// codex-rs/tui_app_server/src/onboarding/welcome.rs
const MIN_ANIMATION_HEIGHT: u16 = 37;
const MIN_ANIMATION_WIDTH: u16 = 60;
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
   - 不同变体的 Frame 10 可能差异很大

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
fn frame_10_not_empty() {
    assert!(!FRAMES_HBARS[9].is_empty());
}

#[test]
fn frame_10_valid_chars() {
    let valid_chars: HashSet<char> = "▁▂▃▄▅▆▇█ \n".chars().collect();
    for ch in FRAMES_HBARS[9].chars() {
        assert!(valid_chars.contains(&ch), "Invalid char: {}", ch);
    }
}
```
