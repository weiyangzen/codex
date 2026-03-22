# codex-rs/tui/frames/hash 目录研究文档

## 1. 场景与职责

### 1.1 目录定位
`codex-rs/tui/frames/hash/` 是 Codex TUI（Terminal User Interface）项目的 ASCII 艺术动画资源目录，专门存储名为 "hash" 的动画变体的帧数据。该目录属于 TUI 的视觉呈现层，用于在用户登录前的欢迎界面（Welcome Screen）提供视觉吸引力强的动态背景效果。

### 1.2 使用场景
- **欢迎界面背景动画**：当用户启动 Codex CLI 且未登录时，显示在欢迎界面的背景
- **动画变体切换**：用户可通过 `Ctrl+.` 快捷键在多个动画变体间随机切换
- **终端尺寸适配**：当终端尺寸大于最小阈值（60列 x 37行）时才显示动画

### 1.3 目录结构
```
codex-rs/tui/frames/hash/
├── frame_1.txt   ~ frame_36.txt   # 36 帧 ASCII 艺术动画
```

---

## 2. 功能点目的

### 2.1 动画效果设计
"hash" 动画变体呈现一个**旋转的哈希符号/散列图案**效果：
- 使用 Unicode 字符（包括 `█`, `*`, `#`, `-`, `.`, `A` 等）构建
- 每帧 17 行，宽度约 40-50 字符
- 通过 36 帧的连续播放形成平滑的旋转动画

### 2.2 视觉风格
- **主题**：抽象的哈希/散列符号，带有几何对称性
- **色彩**：依赖终端的默认前景色，通过字符密度变化产生明暗对比
- **动态**：图案中心旋转，外围字符流动变化

### 2.3 与其他变体的关系
`frames/` 目录包含 10 个动画变体，hash 是其中之一：
| 变体 | 描述 |
|------|------|
| `default` | 默认动画 |
| `codex` | Codex 品牌相关 |
| `openai` | OpenAI 品牌相关 |
| `blocks` | 方块图案 |
| `dots` | 点阵图案 |
| **`hash`** | **散列/哈希图案（本研究对象）** |
| `hbars` | 水平条 |
| `vbars` | 垂直条 |
| `shapes` | 几何形状 |
| `slug` | 鼻涕虫/流动效果 |

---

## 3. 具体技术实现

### 3.1 帧数据格式

每帧是一个纯文本文件，包含：
- **固定 17 行**，每行以换行符结尾
- 使用空格进行对齐
- 混合使用 ASCII 字符和 Unicode 块字符（`█` U+2588）

示例（frame_1.txt）：
```
                                     
             -.-A*##**##-             
         -*#A**#A#**..*- -█#-         
       #.*.#**█--   -█*-█.*...#       
      **-**█##-            A*.*.#     
     *-*A█-.*-**            █..**#    
    .* #-  .*A*..#           █.*..#   
   #-█-*    █*.*A█.-            .A.   
   ..-.-     #AA.*.*            █-.   
   .*.█-    *..-*.█..######-## *█ .   
    -.**  -*#- A* .█.---.A###.A#A#.   
    *--█- -*#.A-   --*██* -*█A#*-A    
     *-# █# -              #█A*-.     
       -*#-*#-          -*-#.-#█      
         -*#*- *#A****.**#-#.*        
           -*█*...---#-*#*█           
                                     
```

### 3.2 编译时嵌入

帧数据通过 Rust 的 `include_str!` 宏在编译时嵌入二进制：

```rust
// codex-rs/tui/src/frames.rs
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            // ... frame_2 到 frame_36
            include_str!(concat!("../frames/", $dir, "/frame_36.txt")),
        ]
    };
}

pub(crate) const FRAMES_HASH: [&str; 36] = frames_for!("hash");
```

### 3.3 动画播放机制

#### 3.3.1 核心结构
```rust
// ascii_animation.rs
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,     // 帧调度请求器
    variants: &'static [&'static [&'static str]], // 所有变体
    variant_idx: usize,                // 当前变体索引
    frame_tick: Duration,              // 帧间隔（默认 80ms）
    start: Instant,                    // 动画开始时间
}
```

#### 3.3.2 帧计算逻辑
```rust
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let elapsed_ms = self.start.elapsed().as_millis();
    let tick_ms = self.frame_tick.as_millis();
    // 根据经过时间计算当前帧索引
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]
}
```

#### 3.3.3 帧调度
- 默认帧间隔：`FRAME_TICK_DEFAULT = Duration::from_millis(80)`
- 36 帧 × 80ms = 约 2.88 秒完成一个循环
- 使用 `FrameRequester` 协调多个动画源的绘制请求，限制最高 120 FPS

### 3.4 配置与控制

#### 3.4.1 动画开关
通过 `config.animations`（布尔值）控制：
```rust
// onboarding_screen.rs
WelcomeWidget::new(
    !matches!(login_status, LoginStatus::NotAuthenticated),
    tui.frame_requester(),
    config.animations,  // 控制是否启用动画
)
```

#### 3.4.2 变体切换
用户可通过 `Ctrl+.` 快捷键随机切换变体：
```rust
// welcome.rs
fn handle_key_event(&mut self, key_event: KeyEvent) {
    if key_event.kind == KeyEventKind::Press
        && key_event.code == KeyCode::Char('.')
        && key_event.modifiers.contains(KeyModifiers::CONTROL)
    {
        let _ = self.animation.pick_random_variant();
    }
}
```

### 3.5 渲染流程

```
WelcomeWidget::render_ref
├── 检查 animations_enabled
├── 检查终端尺寸 >= MIN_ANIMATION_HEIGHT (37) 和 MIN_ANIMATION_WIDTH (60)
├── 调用 animation.current_frame() 获取当前帧
├── 将帧文本按行分割并转换为 ratatui::Line
└── 使用 Paragraph 渲染到缓冲区
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/frames/hash/frame_*.txt` | **动画帧数据（36 帧）** |
| `codex-rs/tui/src/frames.rs` | 帧数据编译时嵌入宏定义 |
| `codex-rs/tui/src/ascii_animation.rs` | 动画播放控制逻辑 |
| `codex-rs/tui/src/onboarding/welcome.rs` | 欢迎界面组件，使用动画 |
| `codex-rs/tui/src/tui/frame_requester.rs` | 帧调度与速率限制 |

### 4.2 关键代码引用

#### 帧定义（frames.rs）
```rust
pub(crate) const FRAMES_HASH: [&str; 36] = frames_for!("hash");
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT, &FRAMES_CODEX, &FRAMES_OPENAI,
    &FRAMES_BLOCKS, &FRAMES_DOTS, &FRAMES_HASH,  // <-- hash 变体
    &FRAMES_HBARS, &FRAMES_VBARS, &FRAMES_SHAPES, &FRAMES_SLUG,
];
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
```

#### 动画初始化（welcome.rs）
```rust
impl WelcomeWidget {
    pub(crate) fn new(
        is_logged_in: bool,
        request_frame: FrameRequester,
        animations_enabled: bool,
    ) -> Self {
        Self {
            is_logged_in,
            animation: AsciiAnimation::new(request_frame),  // 使用 ALL_VARIANTS
            animations_enabled,
            layout_area: Cell::new(None),
        }
    }
}
```

#### 渲染检查（welcome.rs）
```rust
const MIN_ANIMATION_HEIGHT: u16 = 37;
const MIN_ANIMATION_WIDTH: u16 = 60;

let show_animation = self.animations_enabled
    && layout_area.height >= MIN_ANIMATION_HEIGHT
    && layout_area.width >= MIN_ANIMATION_WIDTH;
```

### 4.3 测试覆盖

```rust
// welcome.rs tests
#[test]
fn welcome_renders_animation_on_first_draw() {
    let widget = WelcomeWidget::new(false, FrameRequester::test_dummy(), true);
    let area = Rect::new(0, 0, MIN_ANIMATION_WIDTH, MIN_ANIMATION_HEIGHT);
    // ... 验证动画行渲染
}

#[test]
fn ctrl_dot_changes_animation_variant() {
    // 验证 Ctrl+. 切换变体
}
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
frames/hash/*.txt
    └── frames.rs (通过 include_str! 嵌入)
        └── ascii_animation.rs (AsciiAnimation 使用)
            └── welcome.rs (WelcomeWidget 使用)
                └── onboarding_screen.rs (OnboardingScreen 使用)
                    └── lib.rs / app.rs (主应用)
```

### 5.2 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | 终端 UI 渲染框架，用于 Line/Paragraph/Buffer |
| `crossterm` | 终端事件处理（键盘输入检测） |
| `tokio` | 异步运行时，用于 FrameScheduler 任务 |
| `rand` | 随机数生成，用于变体随机切换 |

### 5.3 配置依赖

- `config.animations`（来自 `codex_core::config::Config`）
  - 类型：`bool`
  - 默认值：`true`
  - 控制整个 TUI 的动画开关

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 终端兼容性
- **Unicode 字符渲染**：`█` (U+2588) 等块字符在某些终端可能显示为方框或问号
- **颜色支持**：动画本身不依赖颜色，但与其他 shimmer 效果配合时需要真彩色支持

#### 6.1.2 性能考虑
- 每帧约 700 字节，36 帧约 25KB 内存占用（可忽略）
- 80ms 帧间隔在低速终端上可能导致 CPU 占用

#### 6.1.3 尺寸限制
- 最小显示尺寸 60×37 可能在高 DPI 小窗口中被跳过
- 无响应式适配，终端过小时直接隐藏动画

### 6.2 边界条件

| 场景 | 行为 |
|------|------|
| `animations = false` | 完全跳过动画渲染，显示静态欢迎文本 |
| 终端高度 < 37 | 跳过动画，欢迎文本从顶部开始 |
| 终端宽度 < 60 | 跳过动画 |
| 快速连续按 `Ctrl+.` | 通过 `pick_random_variant()` 随机选择，可能重复 |
| 单变体模式 | `pick_random_variant()` 返回 `false`，无变化 |

### 6.3 改进建议

#### 6.3.1 可访问性
- 考虑为视觉障碍用户提供纯文本替代描述
- 添加配置选项控制动画速度或完全禁用

#### 6.3.2 性能优化
- 可考虑将帧数据压缩（当前 25KB 可接受，但变体增多后需考虑）
- 帧率可根据终端性能动态调整

#### 6.3.3 功能扩展
- 支持用户自定义动画变体（从配置文件加载）
- 添加更多交互动画（如鼠标悬停效果）
- 考虑根据系统主题（亮色/暗色）切换动画配色

#### 6.3.4 测试增强
- 当前测试主要验证渲染行数，可添加视觉回归测试（snapshot testing）
- 验证所有 36 帧文件存在且格式正确

### 6.4 维护注意事项

1. **帧文件修改**：任何对 `frame_*.txt` 的修改都会触发二进制重新编译
2. **新增变体**：需在 `frames.rs` 中添加新的 `frames_for!` 调用和常量定义
3. **Bazel 构建**：如 AGENTS.md 所述，新增文件需更新 `BUILD.bazel` 的 `compile_data`
4. **版权与归属**：ASCII 艺术应确保无版权争议

---

## 附录：帧数据统计

```bash
$ ls -1 codex-rs/tui/frames/hash/ | wc -l
36

$ wc -l codex-rs/tui/frames/hash/*.txt | tail -1
576 total  # 36 帧 × 16 行 = 576 行

$ du -sh codex-rs/tui/frames/hash/
24K
```

---

*文档生成时间：2026-03-22*
*基于 codex-rs/tui 代码库 commit 研究*
