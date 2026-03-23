# frame_3.txt 研究文档

## 场景与职责

`frame_3.txt` 是 Codex TUI 应用服务器的 ASCII 艺术动画帧文件，属于 `dots` 动画变体系列中的第三帧。作为 36 帧循环动画的组成部分，它继续推进点阵图案的动态变化，维持动画的连续性和视觉吸引力。

## 功能点目的

1. **动画序列推进**：作为第三帧，延续前两帧建立的视觉节奏
2. **图案演变**：展示点阵从分散到聚集或反之的演变过程
3. **视觉连贯性**：确保观众感知到平滑、不间断的动画效果

## 具体技术实现

### 文件格式规范
- **尺寸**：17 行 × 40 列（标准尺寸）
- **字符使用统计**：
  - `○`：约 45%（背景/低密度）
  - `●`：约 30%（主要元素）
  - `◉`：约 15%（高亮焦点）
  - `·`：约 10%（过渡效果）

### 帧序列特征

frame_3 在整体动画中的位置：
```
时间轴（ms）:  0      80      160     240     ...
帧:           [1] -> [2] -> [3] -> [4] -> ...
               ↑              ↑
            frame_1       frame_3 (当前)
```

### 图案变化分析

frame_3 的独特特征：
- 顶部区域（第 2-4 行）：点阵向中心收缩
- 中部区域（第 5-12 行）：呈现不规则的"云状"分布
- 底部区域（第 14-16 行）：右侧点阵聚集形成图案

与 frame_2 的主要差异：
- 第 2 行：`○◉○◉●●○○○○●○`（frame_3）vs `○◉○◉○●○○○●●○`（frame_2）
- 第 4 行：右侧出现更多 `◉` 字符，增强视觉焦点

## 关键代码路径与文件引用

### 核心常量定义

```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_DOTS: [&str; 36] = [
    include_str!("../frames/dots/frame_1.txt"),  // [0]
    include_str!("../frames/dots/frame_2.txt"),  // [1]
    include_str!("../frames/dots/frame_3.txt"),  // [2] <- 当前
    // ... frame_4 到 frame_36
];
```

### 动画控制器访问

```rust
// codex-rs/tui_app_server/src/ascii_animation.rs
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let elapsed_ms = self.start.elapsed().as_millis();
        let idx = ((elapsed_ms / self.frame_tick.as_millis()) % frames.len() as u128) as usize;
        // 当 idx == 2 时返回 frame_3.txt 内容
        frames[idx]
    }
}
```

### 渲染集成点

| 使用场景 | 文件路径 | 调用方式 |
|---------|----------|----------|
| 欢迎界面 | `src/onboarding/welcome.rs` | `self.animation.current_frame()` |
| 状态指示 | `src/status_indicator_widget.rs` | 通过 shimmer 效果间接使用 |

## 依赖与外部交互

### 编译依赖
- `std::include_str`：编译时文件嵌入
- 文件路径：`codex-rs/tui_app_server/frames/dots/frame_3.txt`

### 运行时依赖
- `std::time::Instant`：动画时序基准
- `ratatui::text::Line`：文本渲染

### 相关组件
```
frame_3.txt
    ↑ 编译时嵌入
frames.rs (FRAMES_DOTS[2])
    ↑ 常量引用
ascii_animation.rs (AsciiAnimation)
    ↑ 实例化
welcome.rs (WelcomeWidget)
    ↑ 渲染调用
Terminal (用户屏幕)
```

## 风险、边界与改进建议

### 技术风险

1. **字符显示宽度**：
   - Unicode 圆圈字符在不同字体中宽度可能不同
   - 某些等宽字体中 `●` 和 `○` 可能不是严格等宽
   - **影响**：可能导致动画"抖动"

2. **终端颜色支持**：
   - 文件本身无颜色信息，依赖渲染代码添加样式
   - `shimmer_spans` 函数为动画添加动态颜色

### 边界条件

| 场景 | 处理策略 |
|------|----------|
| 终端不支持 Unicode | 回退到 ASCII 字符或禁用动画 |
| 终端宽度不足 | 跳过动画显示（`MIN_ANIMATION_WIDTH = 60`） |
| 终端高度不足 | 跳过动画显示（`MIN_ANIMATION_HEIGHT = 37`） |
| 动画被禁用 | 显示静态占位符 |

### 改进建议

1. **帧内容验证**：
   ```rust
   // 建议添加的单元测试
   #[test]
   fn frame_3_format_valid() {
       let frame = FRAMES_DOTS[2];
       assert_eq!(frame.lines().count(), 17);
       assert!(frame.chars().all(|c| matches!(c, '○' | '●' | '◉' | '·' | ' ' | '\n')));
   }
   ```

2. **视觉回归测试**：
   - 使用 `insta` snapshot 测试捕获帧渲染结果
   - 防止意外修改导致视觉变化

3. **性能监控**：
   - 监控动画帧率稳定性
   - 在慢速终端上自动降低帧率

### 维护指南

- 修改时需保持与相邻帧（frame_2, frame_4）的视觉连贯性
- 避免引入新的字符类型（仅限 ○ ● ◉ ·）
- 保持行尾无多余空格（符合项目规范）
