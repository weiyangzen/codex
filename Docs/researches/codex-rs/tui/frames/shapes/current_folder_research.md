# Codex TUI Frames/shapes 目录研究报告

## 1. 场景与职责

### 1.1 目录定位
`codex-rs/tui/frames/shapes/` 是 Codex CLI TUI（终端用户界面）的 **ASCII 艺术动画帧资源目录**，存储了 36 帧几何形状主题的 ASCII 艺术动画帧文件。该目录属于 `codex-tui` crate 的静态资源的一部分，用于在用户首次启动或欢迎界面展示动态视觉效果。

### 1.2 核心职责
- **视觉呈现**：提供几何形状（◆△□●○▲◇■ 等 Unicode 几何符号）构成的 ASCII 艺术动画
- **品牌体验**：作为 Codex CLI 的 10 种内置动画变体之一，增强终端交互的视觉吸引力
- **用户引导**：在 onboarding（新用户引导）流程的欢迎界面中作为背景动画展示

### 1.3 使用场景
| 场景 | 说明 |
|------|------|
| 欢迎界面 | `onboarding/welcome.rs` 中的 `WelcomeWidget` 使用 |
| 动画切换 | 用户可通过 `Ctrl+.` 快捷键随机切换动画变体 |
| 终端尺寸适配 | 当终端尺寸 >= 60x37 时显示动画，否则自动隐藏 |
| 配置控制 | 受 `config.animations` 配置项控制，可禁用动画 |

---

## 2. 功能点目的

### 2.1 动画变体设计
`shapes` 是 10 种内置动画变体之一，每种变体使用不同的字符集和视觉风格：

| 变体名称 | 字符集 | 视觉风格 |
|---------|--------|---------|
| `default` | `_=+*/\|` 等 | 经典 ASCII 线条艺术 |
| `codex` | `codex` 字母变形 | 品牌文字艺术 |
| `openai` | `openai` 字母变形 | OpenAI 品牌文字 |
| `blocks` | `▒▓█░` 等块字符 | 块状像素风格 |
| `dots` | `○◉●·` 等圆点 | 点阵风格 |
| `hash` | `-.*#A\|` 等 | 哈希线条风格 |
| `hbars` | `▂▄▆█` 等水平条 | 水平条形图风格 |
| `vbars` | `▎▋▌▉` 等垂直条 | 垂直条形图风格 |
| `shapes` | `◆△□●○▲◇■` 等几何符号 | **几何形状风格** |
| `slug` | `slug` 字母变形 | 蛞蝓文字艺术 |

### 2.2 shapes 变体的独特特征
- **Unicode 几何符号**：使用 Unicode 几何形状块字符（U+25C6, U+25B3, U+25A1, U+25CF 等）
- **高对比度**：黑白几何形状形成强烈视觉对比
- **动态变换**：36 帧构成一个完整循环，展示形状的聚散和变换效果
- **文化中立**：纯几何图形，无语言文化依赖

---

## 3. 具体技术实现

### 3.1 文件结构
```
codex-rs/tui/frames/shapes/
├── frame_1.txt   ~ frame_36.txt  (36 帧动画文件)
```

每帧文件规格：
- **行数**：17 行（固定）
- **宽度**：约 40 个字符（含空格填充）
- **编码**：UTF-8（包含 Unicode 几何符号）
- **帧率**：默认 80ms/帧（`FRAME_TICK_DEFAULT`）

### 3.2 帧文件示例（第 1 帧）
```
                                      
             ◆△◆△●□□●●□▲◆             
         ◆●▲△□○□△□○●◇◇●◆ ◆■□◆         
       ▲◇□◇□□□■○◆   ◆■□◆■◇●◇◇◇□       
      ●□◆○□■▲▲◆            △□◇●◇▲     
     ○○●△■○◇○◆○○            ■△◇○○▲    
    ◇□ □◆  ◇□△●◇◇▲           ■△○◇◇▲   
   □○■▲□    ■○◇□△■◇◆            ◇△◇   
   ◇◇◆◇◆     ▲△△◇●◇□            ■◆◇   
   ◇●◇■◆    ●◇◇○○◇■△◇□□□□□□◆□▲ ●■ ◇   
    ◆◇●□  ◆●□◆ △□ ◇■◇◆◆◆△△▲▲▲◇△▲△▲◇   
    ○○◆■○ ○○▲△△◆   ◆○□■■□ ○□■△▲●◆△    
     □○▲ ■▲ ◆              ▲■△□◆◇     
       ○○▲◆○□◆          ◆●◆□◇◆□■      
         ○□▲○◆ □□△●●●●△●□□◆▲◇□        
           ◆□■□◇◇◇◆◆◆▲◆●□□■           
                                      
```

### 3.3 编译时嵌入机制
在 `codex-rs/tui/src/frames.rs` 中使用宏实现编译时嵌入：

```rust
// 宏定义：为指定目录生成 36 帧的静态数组
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            include_str!(concat!("../frames/", $dir, "/frame_2.txt")),
            // ... frame_3 到 frame_36
        ]
    };
}

// shapes 变体的静态常量
pub(crate) const FRAMES_SHAPES: [&str; 36] = frames_for!("shapes");

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
    &FRAMES_SHAPES,  // shapes 变体
    &FRAMES_SLUG,
];
```

### 3.4 动画播放引擎
`AsciiAnimation` 结构体（`ascii_animation.rs`）驱动动画播放：

```rust
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,     // 帧调度请求器
    variants: &'static [&'static [&'static str]],  // 所有变体
    variant_idx: usize,                 // 当前变体索引
    frame_tick: Duration,              // 帧间隔（默认 80ms）
    start: Instant,                    // 动画开始时间
}

impl AsciiAnimation {
    // 计算当前应显示的帧
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let elapsed_ms = self.start.elapsed().as_millis();
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        frames[idx]
    }
    
    // 随机切换变体（Ctrl+. 触发）
    pub(crate) fn pick_random_variant(&mut self) -> bool {
        let mut rng = rand::rng();
        let next = rng.random_range(0..self.variants.len());
        self.variant_idx = next;
        // ...
    }
}
```

### 3.5 帧调度系统
`FrameRequester`（`tui/frame_requester.rs`）实现高效的帧调度：

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

调度特性：
- **合并请求**：多个帧请求合并为单次重绘
- **帧率限制**：最大 120 FPS（`MIN_FRAME_INTERVAL = 8.33ms`）
- **异步调度**：基于 Tokio 的 actor 模式

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件依赖图
```
frames/shapes/*.txt
    ↓ (编译时 include_str!)
src/frames.rs ─────────────────┐
    │                          │
    ↓                          │
src/ascii_animation.rs         │
    │                          │
    ↓                          │
src/onboarding/welcome.rs      │
    │                          │
    ↓                          │
src/onboarding/onboarding_screen.rs
    │                          │
    ↓                          │
src/lib.rs ←───────────────────┘
```

### 4.2 关键文件清单

| 文件路径 | 职责 | 与 shapes 的关系 |
|---------|------|----------------|
| `frames/shapes/frame_*.txt` | 36 帧 ASCII 艺术资源 | 直接存储几何形状动画帧 |
| `src/frames.rs` | 帧资源编译时嵌入 | 通过宏将 shapes 帧嵌入为 `FRAMES_SHAPES` 常量 |
| `src/ascii_animation.rs` | 动画播放引擎 | 驱动 shapes 帧的循环播放 |
| `src/onboarding/welcome.rs` | 欢迎界面组件 | 使用 AsciiAnimation 展示 shapes 动画 |
| `src/onboarding/onboarding_screen.rs` | 引导流程 orchestrator | 初始化 WelcomeWidget，传递 animations 配置 |
| `src/tui/frame_requester.rs` | 帧调度请求 | 异步调度动画帧重绘 |
| `src/tui/frame_rate_limiter.rs` | 帧率限制 | 限制最大 120 FPS |

### 4.3 配置项
```rust
// codex-core 中的配置
pub struct Config {
    pub animations: bool,  // 控制动画启用/禁用
    // ...
}
```

### 4.4 快捷键绑定
```rust
// welcome.rs 中处理 Ctrl+.
if key_event.code == KeyCode::Char('.') 
    && key_event.modifiers.contains(KeyModifiers::CONTROL) {
    self.animation.pick_random_variant();
}
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖（codex-rs 工作区）

| Crate | 用途 |
|-------|------|
| `codex-core` | 提供 `Config.animations` 配置 |
| `codex-tui` | 主 crate，包含动画渲染逻辑 |

### 5.2 外部依赖（Crates.io）

| Crate | 版本 | 用途 |
|-------|------|------|
| `ratatui` | workspace | 终端 UI 渲染框架 |
| `crossterm` | workspace | 终端事件处理（键盘输入） |
| `rand` | workspace | 随机选择动画变体 |
| `tokio` | workspace | 异步运行时（帧调度） |

### 5.3 构建系统
- **Cargo**：标准 Rust 构建，`include_str!` 宏在编译时嵌入帧文件
- **Bazel**：`BUILD.bazel` 中 `compile_data` 包含所有帧文件

### 5.4 运行时交互
```
用户操作 → crossterm 事件 → App 事件循环 → WelcomeWidget
                                      ↓
                                 AsciiAnimation
                                      ↓
                              FrameRequester::schedule_frame
                                      ↓
                              TUI 重绘 → ratatui 渲染
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 终端尺寸不足 | 动画被裁剪或隐藏 | 代码中检查 `MIN_ANIMATION_HEIGHT/WIDTH`（37x60） |
| Unicode 支持不足 | 几何符号显示为方框 | 使用标准 Unicode 几何块字符，兼容性较好 |
| 动画禁用 | 用户关闭动画时无视觉效果 | `animations_enabled` 标志控制，优雅降级 |
| 帧率过高 | CPU 占用增加 | `FrameRateLimiter` 限制 120 FPS |

### 6.2 边界条件

1. **帧数组越界**：`current_frame()` 使用取模运算确保索引安全
2. **空变体数组**：`AsciiAnimation::new` 断言检查非空
3. **时间溢出**：`elapsed_ms` 使用 `u128`，可支持数百万年运行
4. **终端颜色支持**：`shimmer.rs` 检测真彩色支持，降级使用 DIM/BOLD

### 6.3 改进建议

#### 6.3.1 短期优化
1. **延迟加载**：当前 360 帧（10 变体 × 36 帧）全部编译进二进制，可考虑按需加载
2. **帧压缩**：帧文件存在重复空格，可使用 RLE 压缩减少二进制体积
3. **配置扩展**：支持用户自定义动画变体路径

#### 6.3.2 中期增强
1. **动态帧生成**：使用算法生成无限变化的动画，而非固定 36 帧
2. **主题联动**：动画颜色与终端主题同步（当前为黑白）
3. **交互反馈**：鼠标悬停时加速动画或显示工具提示

#### 6.3.3 长期架构
1. **插件化动画**：支持 WASM 插件加载自定义动画
2. **GPU 加速**：对于复杂动画，使用终端图形协议（如 iTerm2 图像协议）
3. **AI 生成**：基于用户偏好动态生成 ASCII 艺术

### 6.4 测试覆盖
当前测试（`welcome.rs` 中的单元测试）：
- `welcome_renders_animation_on_first_draw`：首次渲染测试
- `welcome_skips_animation_below_height_breakpoint`：尺寸边界测试
- `ctrl_dot_changes_animation_variant`：变体切换测试

建议增加：
- 帧内容完整性测试（验证 36 帧文件存在且格式正确）
- Unicode 渲染兼容性测试
- 长时间运行稳定性测试（防止时间溢出）

---

## 7. 附录

### 7.1 shapes 帧字符集分析
```
◆ (U+25C6) 黑色菱形
△ (U+25B3) 白色向上三角形
□ (U+25A1) 白色正方形
● (U+25CF) 黑色圆形
○ (U+25CB) 白色圆形
▲ (U+25B2) 黑色向上三角形
◇ (U+25C7) 白色菱形
■ (U+25A0) 黑色正方形
```

### 7.2 动画循环周期
- 帧数：36 帧
- 帧间隔：80ms
- 总周期：36 × 80ms = 2.88 秒/循环

### 7.3 二进制体积影响
- 每帧约 800-1200 字节
- shapes 变体总大小：约 30-40 KB
- 所有 10 变体总大小：约 300-400 KB
