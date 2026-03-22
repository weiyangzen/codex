# codex-rs/tui/frames/slug 研究文档

## 1. 场景与职责

### 1.1 目录定位
`codex-rs/tui/frames/slug/` 是 Codex TUI（终端用户界面）项目中的一个 ASCII 艺术动画帧资源目录。它包含 36 个文本文件（`frame_1.txt` 到 `frame_36.txt`），每个文件代表一个动画帧，共同组成一个名为 "slug" 的 ASCII 艺术动画变体。

### 1.2 核心职责
- **视觉资源提供**: 为 TUI 的欢迎界面（Welcome Widget）提供装饰性的 ASCII 艺术动画背景
- **动画变体**: 作为 10 种预设动画变体之一，通过随机切换为用户提供视觉新鲜感
- **品牌展示**: 以抽象艺术风格展示 Codex/OpenAI 的品牌形象

### 1.3 使用场景
该动画主要出现在以下场景：
1. **用户首次启动**: 当用户未登录或首次使用 Codex 时显示欢迎界面
2. **引导流程**: 在 `onboarding/welcome.rs` 中作为背景动画展示
3. **彩蛋交互**: 用户可通过 `Ctrl+.` 快捷键随机切换不同的动画变体（包括 slug）

---

## 2. 功能点目的

### 2.1 动画系统架构

```
frames/slug/          # ASCII 帧资源目录
    ├── frame_1.txt   # 第1帧
    ├── frame_2.txt   # 第2帧
    ...
    └── frame_36.txt  # 第36帧（循环回到第1帧）

src/frames.rs         # 编译时帧数据嵌入模块
src/ascii_animation.rs # 动画驱动引擎
src/onboarding/welcome.rs # 主要使用方
```

### 2.2 slug 变体的特点

与其他 9 个变体相比，slug 变体具有以下特征：

| 变体名称 | 视觉风格 | 字符集 | 文件大小 |
|---------|---------|--------|---------|
| `default` | 符号艺术（复杂） | `=+-_^*\|/` 等 | ~1033 bytes/帧 |
| `codex` | 符号艺术（标准） | `cedox` 等字母 | ~662 bytes/帧 |
| `openai` | 符号艺术（标准） | `aeinop` 等字母 | ~662 bytes/帧 |
| `blocks` | 方块/阴影 | `▒▓█░▓` 等 | ~1100 bytes/帧 |
| `dots` | 圆点矩阵 | `○◉●·` 等 | ~1000 bytes/帧 |
| `hash` | 哈希风格 | `-.*#A\|` 等 | ~700 bytes/帧 |
| `hbars` | 水平条 | `▂▅▇▄▁` 等 | ~1100 bytes/帧 |
| `vbars` | 垂直条 | `▎▋▌▉▊` 等 | ~1100 bytes/帧 |
| `shapes` | 几何形状 | `◆△●□◇▲■` 等 | ~1100 bytes/帧 |
| **`slug`** | **抽象字符** | **`degopstx-5`** | **~662 bytes/帧** |

### 2.3 slug 变体的视觉特征

- **字符集**: 主要使用小写字母 `d, e, g, o, p, s, t, x` 和数字 `5`、连字符 `-`
- **动画效果**: 36 帧构成一个完整的变形/呼吸动画循环
- **尺寸**: 每帧固定 17 行，每行约 40 个字符宽度
- **风格**: 抽象、流动的视觉效果，类似有机形态的变形

示例帧内容（frame_1.txt）:
```
                                       
             d-dcottoottd             
         dot5pot5tooeeod dgtd         
       tepetppgde   egpegxoxeet       
      cpdoppttd            5pecet     
     odc5pdeoeoo            g-eoot    
    xp te  ep5ceet           p-oeet   
   tdg-p    poep5ged          g e5e   
   eedee     t55ecep            gee   
   eoxpe    ceedoeg-xttttttdtt og e   
    dxcp  dcte 5p egeddd-cttte5t5te   
    oddgd dot-5e   edpppp dpg5tcd5    
     pdt gt e              tp5pde     
       doteotd          dodtedtg      
         dptodgptccocc-optdtep        
           epgpexxdddtdctpg           
                                       
```

---

## 3. 具体技术实现

### 3.1 编译时资源嵌入

文件: `codex-rs/tui/src/frames.rs`

```rust
// 宏定义：编译时嵌入指定目录的所有 36 帧
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            include_str!(concat!("../frames/", $dir, "/frame_2.txt")),
            // ... frame_3 到 frame_36
        ]
    };
}

// 为 slug 变体生成帧数组
pub(crate) const FRAMES_SLUG: [&str; 36] = frames_for!("slug");

// 所有变体的集合
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,
    &FRAMES_CODEX,
    &FRAMES_OPENAI,
    &FRAMES_BLOCKS,
    &FRAMES_DOTS,
    &FRAMES_HASH,
    &FRAMES_HBARS,
    &FRAMES_VBARS,
    &FRAMES_SHAPES,
    &FRAMES_SLUG,  // slug 作为第10个变体
];

// 默认帧刷新间隔: 80ms
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
```

**技术要点**:
- 使用 `include_str!` 宏在编译时将文本文件内容嵌入二进制
- 使用 `concat!` 构建文件路径，确保编译期路径解析
- 每个变体固定 36 帧，类型为 `[&str; 36]`
- 帧率固定为 80ms（约 12.5 FPS）

### 3.2 动画引擎

文件: `codex-rs/tui/src/ascii_animation.rs`

```rust
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,    // 帧调度请求器
    variants: &'static [&'static [&'static str]],  // 所有变体
    variant_idx: usize,               // 当前变体索引
    frame_tick: Duration,             // 帧间隔
    start: Instant,                   // 动画开始时间
}

impl AsciiAnimation {
    // 使用所有变体创建动画（默认从第0个变体开始）
    pub(crate) fn new(request_frame: FrameRequester) -> Self {
        Self::with_variants(request_frame, ALL_VARIANTS, 0)
    }

    // 计算当前应显示的帧
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let elapsed_ms = self.start.elapsed().as_millis();
        // 根据经过时间计算帧索引，循环播放
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        frames[idx]
    }

    // 随机切换到另一个变体（Ctrl+. 触发）
    pub(crate) fn pick_random_variant(&mut self) -> bool {
        let mut rng = rand::rng();
        let mut next = self.variant_idx;
        while next == self.variant_idx {  // 确保切换到不同变体
            next = rng.random_range(0..self.variants.len());
        }
        self.variant_idx = next;
        self.request_frame.schedule_frame();
        true
    }
}
```

### 3.3 帧调度系统

文件: `codex-rs/tui/src/tui/frame_requester.rs`

```rust
#[derive(Clone, Debug)]
pub struct FrameRequester {
    frame_schedule_tx: mpsc::UnboundedSender<Instant>,
}

impl FrameRequester {
    // 立即请求重绘
    pub fn schedule_frame(&self) {
        let _ = self.frame_schedule_tx.send(Instant::now());
    }

    // 延迟指定时间后重绘
    pub fn schedule_frame_in(&self, dur: Duration) {
        let _ = self.frame_schedule_tx.send(Instant::now() + dur);
    }
}
```

帧调度器采用 Actor 模式：
1. `FrameRequester` 作为轻量级句柄，可在各处克隆使用
2. `FrameScheduler` 作为后台任务，合并多个请求为单次重绘
3. 使用广播通道通知 TUI 事件循环进行渲染
4. 限制最大帧率为 120 FPS

### 3.4 使用方集成

文件: `codex-rs/tui/src/onboarding/welcome.rs`

```rust
pub(crate) struct WelcomeWidget {
    pub is_logged_in: bool,
    animation: AsciiAnimation,
    animations_enabled: bool,
    layout_area: Cell<Option<Rect>>,
}

impl WelcomeWidget {
    pub(crate) fn new(
        is_logged_in: bool,
        request_frame: FrameRequester,
        animations_enabled: bool,
    ) -> Self {
        Self {
            is_logged_in,
            animation: AsciiAnimation::new(request_frame),  // 使用所有变体
            animations_enabled,
            layout_area: Cell::new(None),
        }
    }
}

impl WidgetRef for &WelcomeWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // 调度下一帧
        if self.animations_enabled {
            self.animation.schedule_next_frame();
        }

        // 视口太小则跳过动画
        let show_animation = self.animations_enabled
            && layout_area.height >= MIN_ANIMATION_HEIGHT  // 37
            && layout_area.width >= MIN_ANIMATION_WIDTH;   // 60

        if show_animation {
            let frame = self.animation.current_frame();
            lines.extend(frame.lines().map(Into::into));
        }
        // ... 渲染欢迎文本
    }
}

// Ctrl+. 切换变体
impl KeyboardHandler for WelcomeWidget {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        if key_event.code == KeyCode::Char('.')
            && key_event.modifiers.contains(KeyModifiers::CONTROL)
        {
            let _ = self.animation.pick_random_variant();  // 可能切换到 slug
        }
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 资源文件

```
codex-rs/tui/frames/slug/
├── frame_1.txt      # 动画第1帧
├── frame_2.txt      # 动画第2帧
...
├── frame_36.txt     # 动画第36帧（循环点）
```

### 4.2 核心代码文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/frames.rs` | 编译时嵌入所有帧数据，定义 `FRAMES_SLUG` 常量 |
| `codex-rs/tui/src/ascii_animation.rs` | 动画引擎，处理帧计算、变体切换 |
| `codex-rs/tui/src/tui/frame_requester.rs` | 帧调度系统，控制重绘时机 |
| `codex-rs/tui/src/onboarding/welcome.rs` | 主要使用方，欢迎界面组件 |

### 4.3 调用链

```
用户启动 Codex
    ↓
run_onboarding_app() [lib.rs]
    ↓
WelcomeWidget::new(request_frame, animations_enabled)
    ↓
AsciiAnimation::new(request_frame)
    ↓
AsciiAnimation::with_variants(request_frame, ALL_VARIANTS, 0)
    ↓
FRAMES_SLUG 通过 ALL_VARIANTS 被包含

渲染时:
    ↓
WelcomeWidget::render_ref()
    ↓
AsciiAnimation::current_frame() → 计算当前帧索引
    ↓
frames::FRAMES_SLUG[idx] → 返回帧字符串
    ↓
渲染到终端缓冲区

用户按 Ctrl+.
    ↓
WelcomeWidget::handle_key_event()
    ↓
AsciiAnimation::pick_random_variant()
    ↓
随机选择新变体索引（可能选中 slug）
    ↓
FrameRequester::schedule_frame() → 触发重绘
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```rust
// frames.rs 无外部依赖（仅标准库）

// ascii_animation.rs 依赖
use rand::Rng as _;                    // 随机数生成（变体切换）
use crate::frames::ALL_VARIANTS;       // 帧数据
use crate::frames::FRAME_TICK_DEFAULT; // 默认帧间隔
use crate::tui::FrameRequester;        // 帧调度

// welcome.rs 依赖
use crate::ascii_animation::AsciiAnimation;
use crate::tui::FrameRequester;
use ratatui::...                       // UI 渲染
use crossterm::event::...              // 键盘事件
```

### 5.2 编译依赖

在 `Cargo.toml` 中：
- 无特殊依赖要求
- 资源文件通过 `include_str!` 编译时嵌入，运行时无文件 I/O

### 5.3 Bazel 构建

文件: `codex-rs/tui/BUILD.bazel`

```bazel
# 帧文件作为编译数据
filegroup(
    name = "frame_files",
    srcs = glob(["frames/**/*.txt"]),
)

rust_library(
    name = "codex_tui",
    srcs = glob(["src/**/*.rs"]),
    compile_data = [":frame_files"],  # 确保帧文件对 include_str! 可用
    ...
)
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 影响 | 缓解措施 |
|-----|------|---------|
| 帧文件缺失 | 编译失败 | 所有 36 个文件必须存在，由 `frames_for!` 宏保证 |
| 帧格式不一致 | 渲染错位 | 所有帧应保持 17 行、相同列宽 |
| 字符编码问题 | 显示乱码 | 使用 UTF-8 编码的特殊字符 |
| 终端不支持 Unicode | 显示异常 | 最小尺寸检查（37x60）跳过动画 |

### 6.2 边界条件

1. **尺寸限制**:
   - 最小高度: 37 行 (`MIN_ANIMATION_HEIGHT`)
   - 最小宽度: 60 列 (`MIN_ANIMATION_WIDTH`)
   - 不满足时跳过动画，仅显示文本

2. **性能边界**:
   - 帧率: 80ms/帧（约 12.5 FPS）
   - 最大调度帧率: 120 FPS（由 `FrameRateLimiter` 限制）

3. **变体切换**:
   - 仅当 `animations_enabled` 为 true 时可用
   - 随机切换确保不重复选择同一变体

### 6.3 改进建议

#### 6.3.1 可配置性
```rust
// 建议：允许用户通过配置选择默认变体
pub(crate) fn new_with_variant(
    request_frame: FrameRequester,
    variant: AnimationVariant,  // 新增枚举
) -> Self
```

#### 6.3.2 动态帧率
```rust
// 建议：根据终端性能动态调整帧率
pub(crate) fn set_frame_tick(&mut self, tick: Duration) {
    self.frame_tick = tick;
}
```

#### 6.3.3 帧数据压缩
- 当前 36 帧 × 662 字节 ≈ 24 KB/变体
- 10 个变体总计约 240 KB 二进制体积
- 可考虑使用压缩算法减少嵌入式资源体积

#### 6.3.4 可访问性
- 当前动画无法被屏幕阅读器感知
- 建议添加 `aria-label` 等元数据（终端可访问性标准）

#### 6.3.5 测试覆盖
当前测试仅覆盖：
- `frame_tick_must_be_nonzero` - 帧间隔非零检查
- `welcome_renders_animation_on_first_draw` - 首次渲染
- `welcome_skips_animation_below_height_breakpoint` - 尺寸边界
- `ctrl_dot_changes_animation_variant` - 变体切换

建议增加：
- 帧数据完整性测试（验证所有 36 帧存在且非空）
- 帧尺寸一致性测试
- 变体随机分布测试

### 6.4 维护注意事项

1. **帧文件修改**: 修改任何 `frame_*.txt` 后需重新编译
2. **新增变体**: 需修改 `frames.rs` 添加新的 `frames_for!` 调用和常量
3. **删除变体**: 需同步更新 `ALL_VARIANTS` 数组
4. **AGENTS.md 合规**: 遵循 `codex-rs/tui/styles.md` 中的样式规范

---

## 7. 附录

### 7.1 帧文件清单

```
codex-rs/tui/frames/slug/
├── frame_1.txt   ├── frame_10.txt  ├── frame_19.txt  ├── frame_28.txt
├── frame_2.txt   ├── frame_11.txt  ├── frame_20.txt  ├── frame_29.txt
├── frame_3.txt   ├── frame_12.txt  ├── frame_21.txt  ├── frame_30.txt
├── frame_4.txt   ├── frame_13.txt  ├── frame_22.txt  ├── frame_31.txt
├── frame_5.txt   ├── frame_14.txt  ├── frame_23.txt  ├── frame_32.txt
├── frame_6.txt   ├── frame_15.txt  ├── frame_24.txt  ├── frame_33.txt
├── frame_7.txt   ├── frame_16.txt  ├── frame_25.txt  ├── frame_34.txt
├── frame_8.txt   ├── frame_17.txt  ├── frame_26.txt  ├── frame_35.txt
├── frame_9.txt   ├── frame_18.txt  ├── frame_27.txt  └── frame_36.txt
```

### 7.2 相关文档引用

- `codex-rs/tui/styles.md` - TUI 样式规范
- `codex-rs/AGENTS.md` - 项目级代理开发规范
- `codex-rs/tui/src/onboarding/onboarding_screen.rs` - 引导流程主入口

---

*文档生成时间: 2026-03-22*
*研究范围: codex-rs/tui/frames/slug/ 及其直接依赖*
