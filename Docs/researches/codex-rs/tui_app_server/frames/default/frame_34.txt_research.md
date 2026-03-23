# frame_34.txt 研究文档

## 场景与职责

`frame_34.txt` 是 Codex TUI 应用服务器启动动画的第 34 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 94% 进度点，是动画即将结束的关键帧。

## 功能点目的

1. **即将结束**：第 34 帧距离动画周期结束还有 3 帧
2. **最后阶段展示**：展示动画最后约 6% 阶段的视觉效果
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 2.72 秒显示

## 具体技术实现

### 帧周期位置

```
36 帧动画的最后阶段：

92%      94%      97%     100%
│        │        │        │
33       34       35       36
├────────┼────────┼────────┤
          │
          ▼
      frame_34
      (94.4%)

frame_34 参数：
- 索引：33（0-based）
- 显示时段：[2640ms, 2720ms)
- 周期位置：94.4%
- 距离结束：2 帧（160ms）
```

### 代码定义

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-32] frame_1 到 frame_33
    include_str!("../frames/default/frame_34.txt"),  // [33]
    // [34-35] frame_35 到 frame_36
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
时间线（frame_33 到 frame_36）：

2560ms    2640ms    2720ms    2800ms    2880ms
   │         │         │         │         │
   ▼         ▼         ▼         ▼         ▼
┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
│frame_33│ │frame_34│ │frame_35│ │frame_36│ │frame_1│
│  92%  │ │  94%  │ │  97%  │ │ 100%  │ │  0%   │
└───────┘ └───────┘ └───────┘ └───────┘ └───────┘
            │
            ▼
        本文件位置
```

## 关键代码路径与文件引用

| 文件 | 行号 | 说明 |
|------|------|------|
| `frames/default/frame_34.txt` | 1-17 | 第 34 帧 ASCII 艺术 |
| `src/frames.rs` | 37 | `include_str!(".../frame_34.txt")` |
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
            // 如在 frame_34 显示时切换，将显示新变体的第 34 帧
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
1. **随机数生成**：`rand::rng()` 可能产生可预测序列
2. **变体切换抖动**：快速切换可能导致视觉不适

### 边界情况
- **单变体**：若只有一个变体，`pick_random_variant` 返回 false
- **禁用动画**：键盘事件被忽略

### 改进建议
1. **切换动画**：变体切换时添加过渡动画
2. **切换历史**：记录切换历史，避免短时间内重复切换
3. **用户偏好**：记住用户最后选择的变体
4. **预览模式**：切换前预览新变体的效果
