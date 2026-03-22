# codex-rs/tui_app_server/frames 目录研究文档

## 1. 场景与职责

### 1.1 目录定位

`codex-rs/tui_app_server/frames/` 目录是 Codex CLI TUI 应用的 ASCII 艺术动画帧资源库。它存储了 10 种不同风格的动画变体，每种变体包含 36 帧静态 ASCII 艺术图，用于在应用启动时的欢迎界面（Welcome Screen）展示动态视觉效果。

### 1.2 核心职责

- **视觉呈现**：为 TUI 欢迎界面提供美观的 ASCII 艺术动画背景
- **品牌展示**：包含 OpenAI/Codex 品牌相关的艺术图案
- **用户体验**：通过动画效果提升 CLI 应用的视觉吸引力
- **可配置性**：支持多种动画风格，用户可通过快捷键切换

### 1.3 使用场景

1. **首次启动欢迎**：用户首次运行 `codex` 命令时显示欢迎动画
2. **登录流程**：在 OAuth/登录流程中作为背景装饰
3. **交互反馈**：用户按 `Ctrl+.` 可随机切换动画变体

---

## 2. 功能点目的

### 2.1 动画变体列表

| 变体目录 | 风格描述 | 字符特征 |
|---------|---------|---------|
| `default/` | 默认风格，使用符号字符 | `._:=+*^|,;/~!` 等 ASCII 符号 |
| `codex/` | Codex 品牌风格，小写字母 | 使用 `eodc` 等字母构成图案 |
| `openai/` | OpenAI 品牌风格 | 使用 `openai` 字母构成图案 |
| `blocks/` | 方块风格 | 使用 `▒▓░█` 等 Unicode 方块字符 |
| `dots/` | 点阵风格 | 使用 `○◉●·` 等圆形点阵符号 |
| `hash/` | 哈希/井号风格 | 使用 `-.*#A` 等字符 |
| `hbars/` | 水平条风格 | 使用 `▂▄▆▇█` 等水平渐变条 |
| `vbars/` | 垂直条风格 | 使用 `▎▋▌▊▉█` 等垂直渐变条 |
| `shapes/` | 几何形状风格 | 使用 `◆△●□▲○■◇` 等几何符号 |
| `slug/` | Slug 风格，数字字母混合 | 使用 `dctp5oxge` 等字符 |

### 2.2 动画参数

- **帧数**：每变体 36 帧（`frame_1.txt` 到 `frame_36.txt`）
- **帧尺寸**：每帧 17 行 x 39 列（固定尺寸）
- **帧率**：默认 80ms 每帧（`FRAME_TICK_DEFAULT = Duration::from_millis(80)`）
- **动画周期**：约 2.88 秒完成一个完整循环（36 × 80ms）

### 2.3 用户交互

- **快捷键**：`Ctrl+.` 随机切换动画变体
- **动画开关**：受配置项 `config.animations` 控制
- **响应式**：当终端尺寸小于 60×37 时自动隐藏动画

---

## 3. 具体技术实现

### 3.1 文件组织结构

```
frames/
├── blocks/frame_*.txt    # 36 帧方块风格
├── codex/frame_*.txt     # 36 帧 Codex 品牌风格
├── default/frame_*.txt   # 36 帧默认符号风格
├── dots/frame_*.txt      # 36 帧点阵风格
├── hash/frame_*.txt      # 36 帧哈希风格
├── hbars/frame_*.txt     # 36 帧水平条风格
├── openai/frame_*.txt    # 36 帧 OpenAI 品牌风格
├── shapes/frame_*.txt    # 36 帧几何形状风格
├── slug/frame_*.txt      # 36 帧 Slug 风格
└── vbars/frame_*.txt     # 36 帧垂直条风格
```

### 3.2 编译时嵌入（frames.rs）

```rust
// 使用宏在编译时嵌入所有帧数据
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            include_str!(concat!("../frames/", $dir, "/frame_2.txt")),
            // ... frame_3 到 frame_36
        ]
    };
}

// 导出各变体帧数组
pub(crate) const FRAMES_DEFAULT: [&str; 36] = frames_for!("default");
pub(crate) const FRAMES_CODEX: [&str; 36] = frames_for!("codex");
// ... 其他变体

// 所有变体的集合引用
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT, &FRAMES_CODEX, &FRAMES_OPENAI,
    &FRAMES_BLOCKS, &FRAMES_DOTS, &FRAMES_HASH,
    &FRAMES_HBARS, &FRAMES_VBARS, &FRAMES_SHAPES, &FRAMES_SLUG,
];

// 默认帧间隔
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
```

### 3.3 动画驱动器（ascii_animation.rs）

```rust
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,           // 帧调度请求器
    variants: &'static [&'static [&'static str]], // 变体集合
    variant_idx: usize,                      // 当前变体索引
    frame_tick: Duration,                    // 帧间隔
    start: Instant,                          // 动画开始时间
}

impl AsciiAnimation {
    // 创建新实例，默认使用 ALL_VARIANTS
    pub(crate) fn new(request_frame: FrameRequester) -> Self
    
    // 指定变体集合创建
    pub(crate) fn with_variants(request_frame, variants, variant_idx)
    
    // 调度下一帧（基于时间计算延迟）
    pub(crate) fn schedule_next_frame(&self)
    
    // 获取当前应显示的帧内容
    pub(crate) fn current_frame(&self) -> &'static str
    
    // 随机切换变体（Ctrl+. 触发）
    pub(crate) fn pick_random_variant(&mut self) -> bool
}
```

### 3.4 帧计算逻辑

当前帧索引计算：
```rust
let elapsed_ms = self.start.elapsed().as_millis();
let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
frames[idx]
```

下一帧调度计算：
```rust
let rem_ms = elapsed_ms % tick_ms;
let delay_ms = if rem_ms == 0 { tick_ms } else { tick_ms - rem_ms };
self.request_frame.schedule_frame_in(Duration::from_millis(delay_ms_u64));
```

### 3.5 帧调度系统（tui/frame_requester.rs）

```rust
/// 帧调度请求器（Cloneable，可多任务共享）
pub struct FrameRequester {
    frame_schedule_tx: mpsc::UnboundedSender<Instant>,
}

impl FrameRequester {
    pub fn schedule_frame(&self)           // 立即调度
    pub fn schedule_frame_in(&self, dur)   // 延迟调度
}

/// 内部调度器任务（FrameScheduler）
struct FrameScheduler {
    receiver: mpsc::UnboundedReceiver<Instant>,
    draw_tx: broadcast::Sender<()>,        // 通知 TUI 事件循环
    rate_limiter: FrameRateLimiter,        // 限制最大 120 FPS
}
```

### 3.6 帧率限制器（tui/frame_rate_limiter.rs）

```rust
/// 120 FPS 最小帧间隔（≈8.33ms）
pub(super) const MIN_FRAME_INTERVAL: Duration = Duration::from_nanos(8_333_334);

pub(super) struct FrameRateLimiter {
    last_emitted_at: Option<Instant>,
}

impl FrameRateLimiter {
    // 将请求时间限制在最小间隔之后
    pub(super) fn clamp_deadline(&self, requested: Instant) -> Instant
    
    // 记录已发送的绘制通知
    pub(super) fn mark_emitted(&mut self, emitted_at: Instant)
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件关系图

```
frames/
├── blocks/, codex/, default/, ...    # 360 个帧文件 (10 × 36)
│
src/
├── frames.rs                          # 编译时嵌入宏，导出帧常量
├── ascii_animation.rs                 # AsciiAnimation 驱动器
├── tui/
│   ├── frame_requester.rs             # FrameRequester / FrameScheduler
│   └── frame_rate_limiter.rs          # FrameRateLimiter (120 FPS 限制)
├── onboarding/
│   ├── welcome.rs                     # WelcomeWidget 使用动画
│   └── onboarding_screen.rs           # 引导流程集成
└── lib.rs                             # mod frames, mod ascii_animation
```

### 4.2 调用链

```
1. 应用启动
   └── lib.rs::run_main()
       └── run_ratatui_app()
           └── run_onboarding_app()
               └── OnboardingScreen::new()
                   └── WelcomeWidget::new(request_frame, animations_enabled)
                       └── AsciiAnimation::new(request_frame)

2. 渲染循环
   └── OnboardingScreen::render_ref()
       └── WelcomeWidget::render_ref()
           ├── animation.schedule_next_frame()  // 调度下一帧
           └── animation.current_frame()        // 获取当前帧内容
               └── Paragraph::new(frame).render()

3. 帧调度
   └── AsciiAnimation::schedule_next_frame()
       └── FrameRequester::schedule_frame_in(delay)
           └── FrameScheduler::run()  // 异步任务
               └── draw_tx.send(())   // 通知 TUI 重绘

4. 用户交互
   └── OnboardingScreen::handle_key_event()
       └── WelcomeWidget::handle_key_event(KeyEvent { code: Char('.'), modifiers: CONTROL })
           └── animation.pick_random_variant()
               └── 随机选择新变体索引
```

### 4.3 关键代码引用

| 文件路径 | 行号范围 | 功能描述 |
|---------|---------|---------|
| `src/frames.rs` | 1-71 | 编译时宏定义，帧数据嵌入 |
| `src/ascii_animation.rs` | 1-111 | AsciiAnimation 结构及实现 |
| `src/tui/frame_requester.rs` | 1-354 | 帧调度请求器与调度器 |
| `src/tui/frame_rate_limiter.rs` | 1-62 | 帧率限制（120 FPS） |
| `src/onboarding/welcome.rs` | 1-170 | WelcomeWidget 使用动画 |
| `src/onboarding/onboarding_screen.rs` | 94-98 | 创建 WelcomeWidget |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 模块 | 依赖类型 | 说明 |
|-----|---------|-----|
| `frames.rs` | 数据提供 | 被 `ascii_animation.rs` 引用 |
| `ascii_animation.rs` | 业务逻辑 | 被 `welcome.rs` 引用 |
| `tui/frame_requester.rs` | 基础设施 | 被 `ascii_animation.rs` 和 `welcome.rs` 引用 |
| `tui/frame_rate_limiter.rs` | 基础设施 | 被 `frame_requester.rs` 内部使用 |

### 5.2 外部 crate 依赖

| Crate | 用途 |
|-------|-----|
| `rand` | `pick_random_variant()` 随机数生成 |
| `tokio` | `FrameScheduler` 异步任务运行 |
| `ratatui` | 帧内容渲染为 Widget |
| `crossterm` | 键盘事件处理（Ctrl+.） |

### 5.3 配置交互

```rust
// config.animations 控制动画开关
WelcomeWidget::new(is_logged_in, request_frame, config.animations)

// 最小尺寸限制
const MIN_ANIMATION_HEIGHT: u16 = 37;
const MIN_ANIMATION_WIDTH: u16 = 60;
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 编译时资源膨胀
- **风险**：360 个帧文件在编译时通过 `include_str!` 嵌入二进制，增加约 200-300KB 二进制体积
- **缓解**：帧文件为纯文本，体积可控；使用 `&str` 引用避免运行时拷贝

#### 6.1.2 固定帧尺寸假设
- **风险**：所有帧假设为 17 行高，若修改帧文件尺寸需同步修改渲染逻辑
- **代码位置**：`welcome.rs:76-78` 的 `MIN_ANIMATION_HEIGHT` 检查

#### 6.1.3 硬编码帧数量
- **风险**：宏 `frames_for!` 硬编码 36 帧，新增/删除帧需修改宏
- **缓解**：36 帧是动画设计标准，变更频率极低

### 6.2 边界情况

| 场景 | 行为 |
|-----|-----|
| 终端尺寸 < 60×37 | 自动隐藏动画，仅显示文字 |
| `config.animations = false` | 完全禁用动画渲染和调度 |
| 快速连续按 Ctrl+. | 每次按键随机切换，可能重复同一变体 |
| 单变体模式 | `pick_random_variant()` 返回 false，无操作 |
| 系统时间回拨 | `Instant` 单调性保证，动画可能短暂停滞 |

### 6.3 改进建议

#### 6.3.1 配置化帧率
```rust
// 当前：硬编码 80ms
// 建议：支持 config.animation_speed 配置
pub(crate) fn with_tick_duration(mut self, tick: Duration) -> Self
```

#### 6.3.2 动态帧加载
- **现状**：编译时嵌入，无法运行时更新
- **建议**：支持从 `~/.codex/frames/` 加载自定义帧，便于用户定制

#### 6.3.3 帧缓存优化
- **现状**：每次 `current_frame()` 重新计算索引
- **建议**：缓存当前帧索引，仅在下帧时间点更新

#### 6.3.4 变体持久化
- **现状**：随机切换，重启后恢复默认
- **建议**：记录用户偏好变体到配置文件中

#### 6.3.5 测试覆盖
- **现状**：仅测试 `FRAME_TICK_DEFAULT > 0`
- **建议**：
  - 添加帧内容完整性测试（验证 36 帧存在且非空）
  - 添加变体切换测试
  - 添加边界尺寸测试

### 6.4 相关测试

```rust
// ascii_animation.rs 测试
#[test]
fn frame_tick_must_be_nonzero() {
    assert!(FRAME_TICK_DEFAULT.as_millis() > 0);
}

// welcome.rs 测试
#[test]
fn welcome_renders_animation_on_first_draw()
#[test]
fn welcome_skips_animation_below_height_breakpoint()
#[test]
fn ctrl_dot_changes_animation_variant()

// frame_requester.rs 测试（部分）
#[tokio::test]
async fn test_schedule_frame_immediate_triggers_once()
#[tokio::test]
async fn test_coalesces_multiple_requests_into_single_draw()
#[tokio::test]
async fn test_limits_draw_notifications_to_120fps()
```

---

## 7. 附录

### 7.1 帧文件示例

**default/frame_1.txt**（符号风格）：
```
                                     
             _._:=++==+,_             
         _=,/*\+/+\=||=_ "+_         
       ,|*|+**"^`    `*""~=~||+       
      ;*_\*',,_            /*|;|,     
     \^;/'^|\`\\            ".\\,    
    ~* +`  |*/;||,           '.\||,   
   +^"-*    '\|*/"|_          ! |/|   
   ||_|`     ,//|;|*            "`|   
   |=~'`    ;||^\|".~++++++_+, =" |   
    _~;*  _;+` /* |"|___.:,,,|/,/,|   
    \^_"^ ^\,./`   `^*''* ^*"/,;_/    
     *^, ", `              ,'/*_|     
       ^\,`\+_          _=_+|_+"      
         ^*,\_!*+:;=;;.=*+_,|*        
           `*"*|~~___,_;+*"           
```

### 7.2 相关文档

- `AGENTS.md`：Rust 代码风格指南
- `codex-rs/tui/styles.md`：TUI 样式规范
- `codex-rs/tui_app_server/src/onboarding/welcome.rs`：欢迎组件实现
