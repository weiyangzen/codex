# hbars 动画帧目录研究文档

## 1. 场景与职责

### 1.1 目录定位
`codex-rs/tui/frames/hbars/` 是 Codex TUI（Terminal User Interface）项目中存储 ASCII 艺术动画帧的目录之一。该目录包含 36 帧水平条形图风格的动画帧文件（frame_1.txt 到 frame_36.txt），用于在用户登录欢迎界面（WelcomeWidget）播放动态 ASCII 艺术动画。

### 1.2 使用场景
- **欢迎界面动画**：当用户启动 Codex CLI 且未登录时，显示欢迎界面并播放动态 ASCII 艺术动画
- **动画变体切换**：用户可以通过 `Ctrl+.` 快捷键在 10 种不同的动画变体之间随机切换
- **可配置禁用**：用户可以通过配置文件 `config.toml` 中的 `animations = false` 禁用动画效果

### 1.3 职责边界
- 该目录**仅存储静态帧数据**，不包含动画逻辑
- 动画播放逻辑由 `ascii_animation.rs` 模块处理
- 帧数据在编译时通过 `include_str!` 宏嵌入到二进制文件中

---

## 2. 功能点目的

### 2.1 视觉设计意图
`hbars`（horizontal bars，水平条形）动画变体使用 Unicode 块字符（Block Elements）创建水平流动的视觉效果：

```
字符集使用：
- ▁▂▃▄▅▆▇█  : 下八分之一块到完整块（U+2581-U+2588）
- 空格       : 用于留白和动态变化
```

与 `vbars`（垂直条形）变体形成对比，`hbars` 强调水平方向的流动感，而 `vbars` 强调垂直方向的波动感。

### 2.2 动画变体对比
项目中定义了 10 种动画变体，每种都有独特的视觉风格：

| 变体名称 | 风格描述 | 字符特征 |
|---------|---------|---------|
| `default` | 复杂 ASCII 艺术 | 使用 `=+,_~^*;\|` 等字符 |
| `codex` | Codex 品牌风格 | 定制化品牌图案 |
| `openai` | OpenAI 品牌风格 | 定制化品牌图案 |
| `blocks` | 方块风格 | 使用 `▒▓█░` 等块字符 |
| `dots` | 点阵风格 | 使用 `·•∙` 等点字符 |
| `hash` | 散列风格 | 使用 `#` 等字符 |
| **hbars** | **水平条形** | **使用 `▁▂▃▄▅▆▇█`** |
| `vbars` | 垂直条形 | 使用 `▏▎▍▌▋▊▉` 等左块字符 |
| `shapes` | 几何形状 | 使用多种几何字符 |
| `slug` | 蜗牛/ slug 风格 | 定制化生物图案 |

### 2.3 帧数据结构
每帧文件遵循严格的格式规范：
- **尺寸**: 17 行 × 40 列（固定尺寸）
- **编码**: UTF-8（包含 Unicode 块字符）
- **命名**: `frame_{N}.txt`，N 从 1 到 36
- **动画周期**: 36 帧 × 80ms = 2.88 秒/循环

---

## 3. 具体技术实现

### 3.1 编译时帧嵌入

帧数据通过 Rust 宏在编译时嵌入到二进制中（`codex-rs/tui/src/frames.rs`）：

```rust
// 宏定义：为指定目录生成帧数组
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            include_str!(concat!("../frames/", $dir, "/frame_2.txt")),
            // ... 直到 frame_36.txt
        ]
    };
}

// 生成 hbars 帧数组常量
pub(crate) const FRAMES_HBARS: [&str; 36] = frames_for!("hbars");

// 所有变体的集合
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,
    &FRAMES_CODEX,
    // ...
    &FRAMES_HBARS,
    &FRAMES_VBARS,
    // ...
];

// 默认帧间隔：80ms
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
```

### 3.2 动画播放机制

动画播放由 `AsciiAnimation` 结构体管理（`codex-rs/tui/src/ascii_animation.rs`）：

```rust
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,  // 帧调度请求器
    variants: &'static [&'static [&'static str]],  // 所有变体
    variant_idx: usize,             // 当前变体索引
    frame_tick: Duration,           // 帧间隔（默认 80ms）
    start: Instant,                 // 动画开始时间
}
```

**关键方法**:
- `current_frame()`: 根据经过时间计算当前应显示的帧索引
  ```rust
  let elapsed_ms = self.start.elapsed().as_millis();
  let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
  frames[idx]
  ```
- `pick_random_variant()`: 随机切换到另一个动画变体（避免重复）
- `schedule_next_frame()`: 请求下一帧的调度

### 3.3 帧调度系统

动画帧的调度通过 `FrameRequester` 实现（`codex-rs/tui/src/tui/frame_requester.rs`）：

```rust
pub struct FrameRequester {
    frame_schedule_tx: mpsc::UnboundedSender<Instant>,
}

impl FrameRequester {
    pub fn schedule_frame(&self) { /* 立即调度 */ }
    pub fn schedule_frame_in(&self, dur: Duration) { /* 延迟调度 */ }
}
```

调度器采用 Actor 模式：
- 多个帧请求被合并（coalescing）为单个绘制通知
- 帧率限制在 120 FPS 以内（`MIN_FRAME_INTERVAL = 8.33ms`）
- 通过广播通道通知主 TUI 事件循环进行重绘

### 3.4 欢迎界面集成

`WelcomeWidget` 使用 `AsciiAnimation` 显示动画（`codex-rs/tui/src/onboarding/welcome.rs`）：

```rust
pub(crate) struct WelcomeWidget {
    animation: AsciiAnimation,
    animations_enabled: bool,
    // ...
}

impl WidgetRef for &WelcomeWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // 调度下一帧
        if self.animations_enabled {
            self.animation.schedule_next_frame();
        }
        
        // 视口大小检查（最小 37×60）
        let show_animation = self.animations_enabled
            && layout_area.height >= MIN_ANIMATION_HEIGHT
            && layout_area.width >= MIN_ANIMATION_WIDTH;
        
        if show_animation {
            let frame = self.animation.current_frame();
            lines.extend(frame.lines().map(Into::into));
        }
        // ...
    }
}
```

**快捷键支持**:
- `Ctrl+.` : 切换到随机动画变体（包括 hbars）

### 3.5 配置控制

动画可通过配置文件禁用（`codex-rs/core/src/config/types.rs`）：

```rust
pub struct TuiConfig {
    /// Enable animations (welcome screen, shimmer effects, spinners).
    /// Defaults to `true`.
    #[serde(default = "default_true")]
    pub animations: bool,
    // ...
}
```

配置传播路径：
1. `config.toml` → `TuiConfig.animations`
2. `ChatWidgetConfig` → `WelcomeWidget`
3. `animations_enabled` 参数控制动画渲染

---

## 4. 关键代码路径与文件引用

### 4.1 帧数据文件
```
codex-rs/tui/frames/hbars/
├── frame_1.txt   # 帧 1（17×40 UTF-8 文本）
├── frame_2.txt   # 帧 2
├── ...
└── frame_36.txt  # 帧 36
```

### 4.2 核心代码文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/frames.rs` | 帧数据嵌入宏、常量定义 |
| `codex-rs/tui/src/ascii_animation.rs` | 动画播放逻辑 |
| `codex-rs/tui/src/tui/frame_requester.rs` | 帧调度系统 |
| `codex-rs/tui/src/onboarding/welcome.rs` | 欢迎界面组件 |
| `codex-rs/tui/src/onboarding/onboarding_screen.rs` | 引导屏幕集成 |

### 4.3 并行实现
`tui_app_server` crate 包含与 `tui` crate 平行的实现：
- `codex-rs/tui_app_server/src/frames.rs`（相同内容）
- `codex-rs/tui_app_server/src/ascii_animation.rs`
- `codex-rs/tui_app_server/src/onboarding/welcome.rs`

根据 AGENTS.md 规范，当 `tui` 中的实现变更时，需要同步更新 `tui_app_server` 中的对应实现。

### 4.4 构建配置

**Cargo 构建** (`codex-rs/tui/Cargo.toml`):
- 帧文件作为编译数据通过 `include_str!` 嵌入
- 无需特殊的构建时配置

**Bazel 构建** (`codex-rs/tui/BUILD.bazel`):
```starlark
codex_rust_crate(
    name = "tui",
    compile_data = glob(
        include = ["**"],  # 包含 frames/ 目录下的所有文件
        exclude = ["**/* *", "BUILD.bazel", "Cargo.toml"],
    ),
    # ...
)
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
hbars 帧数据
    ↑ include_str! (编译时)
frames.rs (FRAMES_HBARS 常量)
    ↑ 引用
ascii_animation.rs (AsciiAnimation)
    ↑ 使用
welcome.rs (WelcomeWidget)
    ↑ 集成
onboarding_screen.rs (OnboardingScreen)
```

### 5.2 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | 终端 UI 渲染框架 |
| `crossterm` | 终端事件处理（键盘快捷键） |
| `tokio` | 异步运行时（帧调度任务） |
| `rand` | 随机变体选择 |

### 5.3 配置依赖

- `codex-rs/core/src/config/types.rs`: `TuiConfig.animations` 字段
- `codex-rs/core/config.schema.json`: JSON Schema 定义

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

1. **硬编码帧数量**
   - 宏 `frames_for!` 硬编码 36 帧，添加/删除帧需要修改宏
   - 风险：帧文件数量与宏定义不匹配会导致编译错误

2. **固定帧尺寸**
   - 所有帧必须是 17×40 字符，否则可能导致布局错位
   - 风险：手动编辑帧文件可能破坏格式

3. **视口大小限制**
   - 动画仅在终端高度 ≥37 且宽度 ≥60 时显示
   - 风险：小终端窗口下动画突然消失可能让用户困惑

4. **并行实现同步**
   - `tui` 和 `tui_app_server` 有重复代码
   - 风险：修改一处忘记修改另一处导致行为不一致

### 6.2 边界条件

| 边界条件 | 行为 |
|---------|------|
| `animations = false` | 显示静态欢迎文本，无动画 |
| 终端高度 < 37 | 跳过动画，仅显示文本行 |
| 终端宽度 < 60 | 跳过动画，避免裁剪 |
| 单变体模式 | `pick_random_variant()` 返回 false，无切换 |
| 高帧率请求 | 被 `FrameRateLimiter` 限制在 120 FPS |

### 6.3 改进建议

1. **帧数量动态化**
   ```rust
   // 建议：使用 build.rs 生成帧数组，支持任意数量的帧
   // 或：使用 const fn 在编译时计算帧数量
   ```

2. **帧验证测试**
   ```rust
   // 建议：添加测试验证所有帧文件格式一致
   #[test]
   fn validate_hbars_frames() {
       for frame in FRAMES_HBARS {
           assert_eq!(frame.lines().count(), 17);
           // 验证每行宽度...
       }
   }
   ```

3. **视口自适应**
   ```rust
   // 建议：支持缩放或裁剪以适应小终端
   // 而非简单的显示/隐藏切换
   ```

4. **代码去重**
   ```rust
   // 建议：将共享代码提取到单独的 crate
   // 如 codex-tui-widgets，供 tui 和 tui_app_server 共用
   ```

5. **文档完善**
   - 帧文件的视觉设计意图未文档化
   - 建议添加 README.md 说明各变体的设计概念

### 6.4 测试覆盖

现有测试（`welcome.rs` 中的单元测试）：
- `welcome_renders_animation_on_first_draw`: 验证动画渲染
- `welcome_skips_animation_below_height_breakpoint`: 验证视口边界
- `ctrl_dot_changes_animation_variant`: 验证变体切换

建议补充：
- 帧数据完整性测试（验证 36 帧都存在且格式正确）
- 动画循环周期测试（验证 36 帧 × 80ms 的循环）
- 多变体随机选择测试（验证不重复选择同一变体）

---

## 附录：帧内容示例

### hbars/frame_1.txt
```
                                     
             ▂▅▂▅▄▇▇▄▄▇▆▂             
         ▂▄▆▅▇▃▇▅▇▃▄▁▁▄▂ ▂█▇▂         
       ▆▁▇▁▇▇▇█▃▂   ▂█▇▂█▁▄▁▁▁▇       
      ▄▇▂▃▇█▆▆▂            ▅▇▁▄▁▆     
     ▃▃▄▅█▃▁▃▂▃▃            █▅▁▃▃▆    
    ▁▇ ▇▂  ▁▇▅▄▁▁▆           █▅▃▁▁▆   
   ▇▃█▆▇    █▃▁▇▅█▁▂            ▁▅▁   
   ▁▁▂▁▂     ▆▅▅▁▄▁▇            █▂▁   
   ▁▄▁█▂    ▄▁▁▃▃▁█▅▁▇▇▇▇▇▇▂▇▆ ▄█ ▁   
    ▂▁▄▇  ▂▄▇▂ ▅▇ ▁█▁▂▂▂▅▅▆▆▆▁▅▆▅▆▁   
    ▃▃▂█▃ ▃▃▆▅▅▂   ▂▃▇██▇ ▃▇█▅▆▄▂▅    
     ▇▃▆ █▆ ▂              ▆█▅▇▂▁     
       ▃▃▆▂▃▇▂          ▂▄▂▇▁▂▇█      
         ▃▇▆▃▂ ▇▇▅▄▄▄▄▅▄▇▇▂▆▁▇        
           ▂▇█▇▁▁▁▂▂▂▆▂▄▇▇█           
                                     
```

### 与 vbars 的对比
vbars 使用左对齐块字符（▏▎▍▌▋▊▉），与 hbars 的底部对齐块字符（▁▂▃▄▅▆▇█）形成垂直/水平方向的视觉对比。
