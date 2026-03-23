# frame_28.txt 研究文档

## 场景与职责

`frame_28.txt` 是 Codex TUI 应用服务器启动动画的第 28 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 78% 进度点，继续展示动画最后阶段的视觉效果。

## 功能点目的

1. **最后阶段推进**：第 28 帧标志着动画进入最后约 22% 的阶段
2. **视觉收尾**：为动画循环的结束做准备
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 2.24 秒显示

## 具体技术实现

### 帧周期位置

```
36 帧动画的最后阶段：

frame_28 ──┐
frame_29   │
frame_30   ├ 最后 9 帧（约 22%）
frame_31   │
...        │
frame_36 ──┘

frame_28 参数：
- 索引：27（0-based）
- 显示时段：[2160ms, 2240ms)
- 周期位置：77.8%
- 距离结束：8 帧（640ms）
```

### 代码定义

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-26] frame_1 到 frame_27
    include_str!("../frames/default/frame_28.txt"),  // [27]
    // [28-35] frame_29 到 frame_36
];

// 变体切换时保持帧位置
impl AsciiAnimation {
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
        // 切换后立即重绘，显示新变体的对应帧
        self.request_frame.schedule_frame();
        true
    }
}
```

### 渲染时序

```
时间线（frame_27 到 frame_29）：

2080ms    2160ms    2240ms    2320ms
   │         │         │         │
   ▼         ▼         ▼         ▼
┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
│frame_27│ │frame_28│ │frame_29│ │frame_30│
│  75%  │ │  78%  │ │  81%  │ │  83%  │
└───────┘ └───────┘ └───────┘ └───────┘
            │
            ▼
        本文件位置
```

## 关键代码路径与文件引用

| 文件 | 行号 | 说明 |
|------|------|------|
| `frames/default/frame_28.txt` | 1-17 | 第 28 帧 ASCII 艺术 |
| `src/frames.rs` | 31 | `include_str!(".../frame_28.txt")` |
| `src/frames.rs` | 47 | `FRAMES_DEFAULT` 常量 |
| `src/ascii_animation.rs` | 79-91 | `pick_random_variant()` |
| `src/onboarding/welcome.rs` | 34-46 | 键盘事件处理 |

## 依赖与外部交互

### 与键盘事件的交互

```rust
impl KeyboardHandler for WelcomeWidget {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        if !self.animations_enabled {
            return;
        }
        
        // Ctrl + . 切换变体
        if key_event.kind == KeyEventKind::Press
            && key_event.code == KeyCode::Char('.')
            && key_event.modifiers.contains(KeyModifiers::CONTROL)
        {
            tracing::warn!("Welcome background to press '.'");
            let _ = self.animation.pick_random_variant();
            // 如在 frame_28 显示时切换，将显示新变体的第 28 帧
        }
    }
}
```

### 与测试的集成

```rust
#[test]
fn ctrl_dot_changes_animation_variant() {
    let mut widget = WelcomeWidget {
        is_logged_in: false,
        animation: AsciiAnimation::with_variants(
            FrameRequester::test_dummy(),
            &VARIANTS,
            0
        ),
        animations_enabled: true,
        layout_area: Cell::new(None),
    };
    
    let before = widget.animation.current_frame();
    
    // 模拟 Ctrl + .
    widget.handle_key_event(KeyEvent::new(
        KeyCode::Char('.'),
        KeyModifiers::CONTROL
    ));
    
    let after = widget.animation.current_frame();
    assert_ne!(before, after);
}
```

## 风险、边界与改进建议

### 风险
1. **随机数生成**：`rand::rng()` 可能产生可预测序列（某些平台）
2. **变体切换抖动**：快速切换可能导致视觉不适

### 边界情况
- **单变体**：若只有一个变体，`pick_random_variant` 返回 false
- **禁用动画**：键盘事件被忽略

### 改进建议
1. **切换动画**：变体切换时添加过渡动画
2. **切换历史**：记录切换历史，避免短时间内重复切换
3. **用户偏好**：记住用户最后选择的变体
4. **预览模式**：切换前预览新变体的效果
