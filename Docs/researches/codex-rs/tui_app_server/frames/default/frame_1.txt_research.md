# frame_1.txt 研究文档

## 场景与职责

`frame_1.txt` 是 Codex TUI 应用服务器启动动画的第一帧 ASCII 艺术图像。该文件属于 `default` 动画变体（variant），在应用启动或欢迎界面时展示动态加载效果，提升用户视觉体验。

## 功能点目的

1. **视觉反馈**：在应用初始化期间提供动态视觉反馈，减少用户等待焦虑
2. **品牌展示**：通过艺术化的 OpenAI Codex 标志展示产品形象
3. **动画序列**：作为 36 帧动画序列的起始帧，构成完整的循环动画

## 具体技术实现

### 文件格式
- **格式**：纯文本 ASCII 艺术
- **尺寸**：17 行 × 39 列（固定尺寸确保渲染一致性）
- **编码**：UTF-8（包含特殊 Unicode 字符用于艺术效果）
- **帧率**：默认 80ms/帧（`FRAME_TICK_DEFAULT = Duration::from_millis(80)`）

### 动画系统集成

```rust
// 在 frames.rs 中通过宏编译时嵌入
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            // ... frame_2.txt 到 frame_36.txt
        ]
    };
}

pub(crate) const FRAMES_DEFAULT: [&str; 36] = frames_for!("default");
```

### 渲染流程

1. **编译时嵌入**：通过 `include_str!` 宏将文本文件内容嵌入二进制
2. **帧选择逻辑**：`AsciiAnimation::current_frame()` 根据时间计算当前帧索引
   ```rust
   let elapsed_ms = self.start.elapsed().as_millis();
   let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
   ```
3. **渲染触发**：`schedule_next_frame()` 安排下一帧重绘
4. **显示条件**：视口需满足最小尺寸要求（`MIN_ANIMATION_HEIGHT = 37`, `MIN_ANIMATION_WIDTH = 60`）

### 使用场景

- **欢迎界面** (`welcome.rs`)：新用户或未登录用户首次启动时展示
- **快捷键交互**：`Ctrl + .` 可随机切换动画变体（default/codex/openai/blocks/dots/hash/hbars/vbars/shapes/slug）

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/frames/default/frame_1.txt` | 本文件，ASCII 艺术帧数据 |
| `codex-rs/tui_app_server/src/frames.rs` | 帧数据编译时嵌入与常量定义 |
| `codex-rs/tui_app_server/src/ascii_animation.rs` | 动画驱动逻辑与帧切换控制 |
| `codex-rs/tui_app_server/src/onboarding/welcome.rs` | 欢迎界面渲染与动画展示 |
| `codex-rs/tui_app_server/src/tui/frame_requester.rs` | 帧绘制调度与速率限制 |

## 依赖与外部交互

### 编译依赖
- **Bazel/Cargo**：通过 `compile_data` 或 `include_str!` 确保文件被打包进二进制

### 运行时依赖
- **ratatui**：用于终端 UI 渲染
- **tokio**：异步运行时，用于帧调度
- **crossterm**：终端控制与事件处理

### 相关变体
同目录下还有其他 9 种动画变体，每种包含 36 帧：
- `codex/` - Codex 品牌动画
- `openai/` - OpenAI 标志动画
- `blocks/`, `dots/`, `hash/`, `hbars/`, `vbars/`, `shapes/`, `slug/` - 几何图形动画

## 风险、边界与改进建议

### 风险
1. **尺寸硬编码**：帧尺寸固定，若修改文件内容需同步更新 `MIN_ANIMATION_*` 常量
2. **字符兼容性**：使用 Unicode 特殊字符，在某些终端可能显示异常
3. **Bazel 构建**：需确保 `compile_data` 包含 frames 目录，否则编译失败

### 边界情况
- 终端尺寸小于 37×60 时动画自动隐藏，仅显示文字欢迎语
- 动画可在设置中禁用（`animations_enabled` 标志）

### 改进建议
1. **动态尺寸适配**：支持响应式缩放以适应不同终端尺寸
2. **主题集成**：支持根据终端主题自动调整 ASCII 艺术颜色
3. **懒加载**：考虑将帧数据改为运行时加载，减少二进制体积
4. **可配置帧率**：允许用户自定义动画速度
