# codex-rs/tui_app_server/frames/dots 研究文档

## 1. 场景与职责

### 1.1 目录定位
`codex-rs/tui_app_server/frames/dots/` 是 Codex CLI TUI 应用服务器的 ASCII 艺术动画帧资源目录，专门存储 **"dots"（点阵）风格** 的动画帧文件。该目录属于 `tui_app_server` crate 的编译时静态资源，用于在用户登录前的欢迎界面（Welcome Screen）提供视觉吸引力的动态背景动画。

### 1.2 核心职责
- **视觉装饰**：为 Codex CLI 的 onboarding 欢迎界面提供动态 ASCII 艺术背景
- **品牌展示**：展示 "CODEX" 字样（通过点阵字符 ○、●、◉、· 等构成）
- **动画效果**：通过 36 帧连续播放形成流畅的动画过渡效果
- **用户体验**：提升命令行工具的现代化感和专业度

### 1.3 使用场景
| 场景 | 描述 |
|------|------|
| 首次启动 | 用户首次运行 `codex` 命令时的欢迎界面 |
| 未登录状态 | 用户尚未完成 OpenAI 认证时的背景展示 |
| 交互反馈 | 用户按 `Ctrl+.` 可随机切换不同动画变体 |

---

## 2. 功能点目的

### 2.1 动画变体设计
`dots` 是 10 种内置动画变体之一，每种变体使用不同的字符集风格：

| 变体名称 | 字符集 | 视觉风格 |
|----------|--------|----------|
| `default` | `._:=+,*/\|` 等 | 传统 ASCII 艺术 |
| `codex` | `○◉●·` 等 Unicode 点 | 点阵风格（本文研究对象） |
| `openai` | `○◉●·` 等 | OpenAI 品牌风格 |
| `blocks` | `▒▓█░` 等 | 方块/像素风格 |
| `dots` | `○◉●·` 等 | **点阵渐变风格** |
| `hash` | `#` 等 | 哈希线条风格 |
| `hbars` | `▂▄▆█` 等 | 水平条形图风格 |
| `vbars` | `▎▋▌▉` 等 | 垂直条形图风格 |
| `shapes` | `◆△●□▲◇■○` 等 | 几何形状风格 |
| `slug` | `d,o,t,s,c,p,5` 等 | 文字拼贴风格 |

### 2.2 dots 变体的独特特征
- **字符集**：使用 `○` (白色圆)、`◉` (靶心圆)、`●` (黑色圆)、`·` (中点) 四种 Unicode 字符
- **渐变效果**：通过点的密度变化形成明暗渐变，勾勒出 "CODEX" 字样
- **视觉隐喻**：点阵设计呼应 "数字"、"像素"、"AI" 等科技概念

### 2.3 动画参数
- **帧数**：36 帧（frame_1.txt ~ frame_36.txt）
- **帧尺寸**：40 列 × 17 行（固定尺寸）
- **帧率**：80ms/帧（`FRAME_TICK_DEFAULT = Duration::from_millis(80)`）
- **循环周期**：36 × 80ms = 2.88 秒/循环

---

## 3. 具体技术实现

### 3.1 帧文件格式

每个帧文件是纯文本文件，使用 UTF-8 编码，包含固定 17 行：

```
第一行：空行（顶部边距）
第2-16行：动画内容（40字符宽）
第17行：空行（底部边距）
```

**示例**（frame_1.txt）：
```
                                     
             ○◉○◉○●●○○●●○             
         ○○●◉●○●◉●○○··○○ ○ ●○         
       ●·●·●●● ○·   · ●· ·○···●       
      ◉●○○●●●●○            ◉●·◉·●     
     ○○◉◉●○·○·○○             ◉·○○●    
    ·● ●·  ·●◉◉··●           ●◉○··●   
   ●○ ◉●    ●○·●◉ ·○            ·◉·   
   ··○··     ●◉◉·◉·●             ··   
   ·○·●·    ◉··○○· ◉·●●●●●●○●● ○  ·   
    ○·◉●  ○◉●· ◉● · ·○○○◉◉●●●·◉●◉●·   
    ○○○ ○ ○○●◉◉·   ·○●●●● ○● ◉●◉○◉    
     ●○●  ● ·              ●●◉●○·     
       ○○●·○●○          ○○○●·○●       
         ○●●○○ ●●◉◉○◉◉◉○●●○●·●        
           ·● ●···○○○●○◉●●            
                                     
```

### 3.2 编译时资源嵌入

**文件**：`codex-rs/tui_app_server/src/frames.rs`

```rust
// 宏定义：为指定目录生成帧数组
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            include_str!(concat!("../frames/", $dir, "/frame_2.txt")),
            // ... frame_3 到 frame_36
        ]
    };
}

// 导出 dots 变体的帧数组
pub(crate) const FRAMES_DOTS: [&str; 36] = frames_for!("dots");

// 所有变体的集合
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,
    &FRAMES_CODEX,
    &FRAMES_OPENAI,
    &FRAMES_BLOCKS,
    &FRAMES_DOTS,  // 本文研究对象
    &FRAMES_HASH,
    &FRAMES_HBARS,
    &FRAMES_VBARS,
    &FRAMES_SHAPES,
    &FRAMES_SLUG,
];

// 默认帧率
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
```

**技术要点**：
- 使用 `include_str!` 宏在编译时将文本文件内容嵌入二进制
- 每个帧作为 `&'static str` 存储在只读数据段
- 无需运行时文件 I/O，启动即可用

### 3.3 动画驱动引擎

**文件**：`codex-rs/tui_app_server/src/ascii_animation.rs`

```rust
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,  // 帧调度请求器
    variants: &'static [&'static [&'static str]],  // 所有变体
    variant_idx: usize,             // 当前变体索引
    frame_tick: Duration,           // 帧间隔
    start: Instant,                 // 动画开始时间
}

impl AsciiAnimation {
    pub(crate) fn new(request_frame: FrameRequester) -> Self {
        Self::with_variants(request_frame, ALL_VARIANTS, 0)
    }

    // 计算当前应显示的帧
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let elapsed_ms = self.start.elapsed().as_millis();
        let idx = ((elapsed_ms / self.frame_tick.as_millis()) % frames.len() as u128) as usize;
        frames[idx]
    }

    // 调度下一帧渲染
    pub(crate) fn schedule_next_frame(&self) {
        let delay = self.calculate_delay();
        self.request_frame.schedule_frame_in(delay);
    }

    // 随机切换变体（Ctrl+. 触发）
    pub(crate) fn pick_random_variant(&mut self) -> bool {
        let mut rng = rand::rng();
        let next = rng.random_range(0..self.variants.len());
        self.variant_idx = next;
        self.request_frame.schedule_frame();
        true
    }
}
```

### 3.4 帧调度系统

**文件**：`codex-rs/tui_app_server/src/tui/frame_requester.rs`

```rust
#[derive(Clone, Debug)]
pub struct FrameRequester {
    frame_schedule_tx: mpsc::UnboundedSender<Instant>,
}

impl FrameRequester {
    pub fn schedule_frame(&self) {
        let _ = self.frame_schedule_tx.send(Instant::now());
    }

    pub fn schedule_frame_in(&self, dur: Duration) {
        let _ = self.frame_schedule_tx.send(Instant::now() + dur);
    }
}
```

**FrameScheduler 任务**：
- 使用 Tokio mpsc 通道接收帧请求
- 使用 `FrameRateLimiter` 限制最大 120 FPS
- 合并多个请求为单次渲染（coalescing）
- 通过 broadcast 通道通知 TUI 事件循环

### 3.5 渲染流程

**文件**：`codex-rs/tui_app_server/src/onboarding/welcome.rs`

```rust
impl WidgetRef for &WelcomeWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // 1. 调度下一帧
        if self.animations_enabled {
            self.animation.schedule_next_frame();
        }

        // 2. 检查视口尺寸（最小 60×37）
        let show_animation = self.animations_enabled
            && layout_area.height >= MIN_ANIMATION_HEIGHT
            && layout_area.width >= MIN_ANIMATION_WIDTH;

        // 3. 渲染动画帧
        let mut lines: Vec<Line> = Vec::new();
        if show_animation {
            let frame = self.animation.current_frame();
            lines.extend(frame.lines().map(Into::into));
            lines.push("".into());
        }

        // 4. 渲染欢迎文本
        lines.push(Line::from(vec![
            "  ".into(),
            "Welcome to ".into(),
            "Codex".bold(),
            ", OpenAI's command-line coding agent".into(),
        ]));

        Paragraph::new(lines).render(area, buf);
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 资源文件
```
codex-rs/tui_app_server/frames/dots/
├── frame_1.txt   # 动画第 1 帧
├── frame_2.txt   # 动画第 2 帧
├── ...
└── frame_36.txt  # 动画第 36 帧（循环回第 1 帧）
```

### 4.2 核心代码文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/tui_app_server/src/frames.rs` | 编译时帧资源嵌入，定义 `FRAMES_DOTS` |
| `codex-rs/tui_app_server/src/ascii_animation.rs` | 动画引擎，帧计算与变体切换 |
| `codex-rs/tui_app_server/src/tui/frame_requester.rs` | 帧调度系统，120 FPS 限流 |
| `codex-rs/tui_app_server/src/tui/frame_rate_limiter.rs` | 帧率限制器 |
| `codex-rs/tui_app_server/src/onboarding/welcome.rs` | 欢迎界面组件，实际渲染动画 |
| `codex-rs/tui_app_server/src/onboarding/onboarding_screen.rs` | Onboarding 流程控制器 |

### 4.3 调用链

```
main() 
  └─ run_onboarding_app()
       └─ OnboardingScreen::new()
            └─ WelcomeWidget::new(request_frame, animations_enabled)
                 └─ AsciiAnimation::new(request_frame)
                      └─ 使用 ALL_VARIANTS (包含 FRAMES_DOTS)

渲染循环:
WelcomeWidget::render_ref()
  ├─ AsciiAnimation::schedule_next_frame()
  │   └─ FrameRequester::schedule_frame_in()
  └─ AsciiAnimation::current_frame()
      └─ 计算帧索引: (elapsed_ms / 80) % 36
```

### 4.4 配置关联

**文件**：`codex-rs/tui_app_server/src/onboarding/welcome.rs`

```rust
// 最小显示尺寸要求
const MIN_ANIMATION_HEIGHT: u16 = 37;
const MIN_ANIMATION_WIDTH: u16 = 60;

// 动画使能配置（来自 config.animations）
pub(crate) fn new(
    is_logged_in: bool,
    request_frame: FrameRequester,
    animations_enabled: bool,  // 控制是否显示动画
) -> Self
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```rust
// 标准库
std::time::{Duration, Instant}
std::convert::TryFrom

// 内部模块依赖
crate::frames::{
    ALL_VARIANTS,      // 包含 FRAMES_DOTS
    FRAME_TICK_DEFAULT // 80ms
}
crate::tui::FrameRequester // 帧调度

// Onboarding 模块
crate::onboarding::welcome::WelcomeWidget // 主要使用者
```

### 5.2 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `rand` | `pick_random_variant()` 随机数生成 |
| `ratatui` | 终端 UI 渲染框架 |
| `tokio` | 异步运行时，帧调度任务 |
| `crossterm` | 终端事件处理（Ctrl+. 切换变体） |

### 5.3 Bazel 构建配置

**文件**：`codex-rs/tui_app_server/BUILD.bazel`

```starlark
codex_rust_crate(
    name = "tui_app_server",
    crate_name = "codex_tui_app_server",
    compile_data = glob(
        include = ["**"],  # 包含 frames/dots/*.txt
        exclude = [...],
    ),
    ...
)
```

**注意**：`frames/dots/*.txt` 通过 `glob(["**"])` 被包含为编译数据，确保 Bazel 构建时资源可用。

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **尺寸限制** | 终端小于 60×37 时不显示动画 | 优雅降级为纯文本欢迎语 |
| **性能** | 动画增加 CPU 使用率 | 80ms 帧率 + 120 FPS 限流 |
| **可访问性** | 动画可能干扰屏幕阅读器 | 可通过配置禁用动画 |
| **字符渲染** | 部分终端可能不支持 Unicode 点字符 | 使用通用 ASCII 变体作为备选 |

### 6.2 边界条件

1. **空变体数组**：`AsciiAnimation::with_variants` 会 panic（`assert!(!variants.is_empty())`）
2. **单变体**：`pick_random_variant()` 返回 `false`，无操作
3. **零帧率**：`current_frame()` 返回第一帧
4. **时间溢出**：`elapsed_ms` 计算使用 `u128`，理论安全

### 6.3 改进建议

#### 6.3.1 性能优化
```rust
// 当前：每次渲染都计算帧索引
let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;

// 建议：缓存当前帧，仅在必要时更新
if elapsed_ms / tick_ms != last_tick {
    current_frame_idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    last_tick = elapsed_ms / tick_ms;
}
```

#### 6.3.2 可访问性增强
```rust
// 建议：添加环境变量禁用动画
const DISABLE_ANIMATION: bool = option_env!("CODEX_DISABLE_ANIMATION").is_some();
```

#### 6.3.3 动态帧率
```rust
// 建议：根据终端性能自适应调整帧率
pub(crate) fn adaptive_frame_tick(&self) -> Duration {
    if self.detect_slow_terminal() {
        Duration::from_millis(160)  // 降速到 6.25 FPS
    } else {
        FRAME_TICK_DEFAULT  // 12.5 FPS
    }
}
```

#### 6.3.4 帧文件压缩
当前 36 帧 × 17 行 × ~40 字符 ≈ 24KB 静态数据。可考虑：
- 使用 RLE（Run-Length Encoding）压缩重复空格
- 运行时解压到堆内存

### 6.4 测试覆盖

**现有测试**：`codex-rs/tui_app_server/src/onboarding/welcome.rs`

```rust
#[test]
fn welcome_renders_animation_on_first_draw() { ... }

#[test]
fn welcome_skips_animation_below_height_breakpoint() { ... }

#[test]
fn ctrl_dot_changes_animation_variant() { ... }
```

**建议补充**：
- 帧文件完整性测试（验证 36 帧都存在且格式正确）
- Unicode 字符渲染测试
- 长时间运行内存泄漏测试

---

## 7. 总结

`codex-rs/tui_app_server/frames/dots/` 是 Codex CLI TUI 的视觉资产目录，存储 36 帧点阵风格的 ASCII 艺术动画。该动画通过编译时资源嵌入、异步帧调度、ratatui 渲染等技术实现，在用户 onboarding 流程中提供现代化的视觉体验。

**关键设计决策**：
1. 编译时嵌入避免运行时 I/O
2. 多变体设计支持用户自定义（Ctrl+. 切换）
3. 响应式降级（小终端隐藏动画）
4. 限流机制保护性能（120 FPS 上限）

**维护注意事项**：
- 修改帧文件后需重新编译
- 新增变体需同步更新 `frames.rs` 和 `ALL_VARIANTS`
- 保持 36 帧 × 17 行的统一尺寸
