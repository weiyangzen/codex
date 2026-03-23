# frame_36.txt 研究文档

## 1. 场景与职责

本文档描述 Codex TUI (Terminal User Interface) 应用程序中 slug（蛞蝓/鼻涕虫）ASCII 动画的第 36 帧。

### 动画序列定位
- **帧序号**: 36/36
- **动画类型**: Slug（蛞蝓）ASCII 艺术动画
- **总帧数**: 36 帧循环动画
- **动画时长**: 约 2.88 秒（36 帧 × 80ms/帧）

### 使用场景
- 应用于 Codex TUI 的欢迎界面（WelcomeWidget）
- 作为用户引导流程（onboarding）的视觉元素
- 提供友好的终端动画体验，增强用户首次使用的印象

## 2. 功能点目的

### 视觉设计目标
- 展示一个风格化的 slug（蛞蝓）生物的 ASCII 艺术形象
- 通过 36 帧连续播放形成流畅的动画效果
- 为终端界面增添生动有趣的视觉元素

### 用户体验目标
- 在用户登录前显示欢迎动画
- 通过 Ctrl+. 快捷键可切换 10 种不同的动画变体
- 动画最小显示尺寸要求：37 行高 × 60 列宽

### 技术目标
- 编译时嵌入二进制文件，避免运行时文件读取
- 零依赖的纯文本资源，确保跨平台兼容性
- 高效的内存使用（每帧 17 行 ASCII 文本）

## 3. 具体技术实现

### 编译时嵌入机制

```rust
// frames.rs 中的宏定义
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            // ... frame_2.txt 到 frame_36.txt
            include_str!(concat!("../frames/", $dir, "/frame_36.txt")),
        ]
    };
}

pub(crate) const FRAMES_SLUG: [&str; 36] = frames_for!("slug");
```

### 动画帧选择逻辑

```rust
// ascii_animation.rs 中的当前帧计算
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let tick_ms = self.frame_tick.as_millis();
    let elapsed_ms = self.start.elapsed().as_millis();
    // 本帧 (36) 的显示条件：
    // ((elapsed_ms / 80) % 36) == 36
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]
}
```

### 数据结构

```rust
// 帧数组结构
pub(crate) const FRAMES_SLUG: [&str; 36] = [
    // frame_1.txt 到 frame_36.txt 的内容
    // 本文件 (36) 是第 36 个元素（索引 36-1）
];

// 所有变体数组
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,  // 索引 0
    &FRAMES_CODEX,    // 索引 1
    &FRAMES_OPENAI,   // 索引 2
    &FRAMES_BLOCKS,   // 索引 3
    &FRAMES_DOTS,     // 索引 4
    &FRAMES_HASH,     // 索引 5
    &FRAMES_HBARS,    // 索引 6
    &FRAMES_VBARS,    // 索引 7
    &FRAMES_SHAPES,   // 索引 8
    &FRAMES_SLUG,     // 索引 9（本动画）
];
```

### 动画定时配置

```rust
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
// 第 36 帧的显示时间窗口：
// 开始: (36-1) × 80ms = 35 × 80ms
// 结束: 36 × 80ms = 2880ms
```

## 4. 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/frames.rs` | 定义 `FRAMES_SLUG` 常量和 `frames_for!` 宏 |
| `codex-rs/tui_app_server/src/ascii_animation.rs` | `AsciiAnimation` 结构体，驱动动画时序 |
| `codex-rs/tui_app_server/src/onboarding/welcome.rs` | `WelcomeWidget`，实际渲染动画 |
| `codex-rs/tui_app_server/frames/slug/frame_36.txt` | **本文件**：第 36 帧的 ASCII 内容 |

### 渲染流程

```
welcome.rs:render_ref()
  ├── 调用 animation.schedule_next_frame()  // 调度下一帧
  ├── 调用 animation.current_frame()        // 获取当前帧内容
  │     └── 计算索引: (elapsed_ms / 80) % 36
  │     └── 返回 FRAMES_SLUG[36-1]（当索引匹配时）
  └── 使用 ratatui Paragraph 渲染文本
```

### 变体切换

```
用户按下 Ctrl+.
  └── welcome.rs:handle_key_event()
        └── animation.pick_random_variant()
              └── 随机选择 0-9 的变体索引
                    └── 可能选中索引 9（FRAMES_SLUG）
```

## 5. 依赖与外部交互

### 编译依赖

| 依赖项 | 用途 |
|-------|------|
| `include_str!` 宏 | 编译时将文本文件嵌入为字符串字面量 |
| `concat!` 宏 | 构建文件路径字符串 |
| `std::time::Duration` | 动画时序控制 |

### 运行时依赖

| 依赖项 | 用途 |
|-------|------|
| `ratatui` | 终端 UI 渲染库 |
| `crossterm` | 终端事件处理（键盘输入） |
| `rand` | 随机选择动画变体 |

### 构建系统

- **Cargo**: 标准 Rust 构建（开发使用）
- **Bazel**: `codex-rs/tui_app_server/BUILD.bazel` 定义生产构建
- 注意：Bazel 需要显式声明 `compile_data` 或 `build_script_data` 以包含帧文件

### 外部接口

```rust
// AsciiAnimation 公共接口
impl AsciiAnimation {
    pub(crate) fn new(request_frame: FrameRequester) -> Self;
    pub(crate) fn with_variants(...) -> Self;
    pub(crate) fn current_frame(&self) -> &'static str;  // 返回本帧内容
    pub(crate) fn schedule_next_frame(&self);
    pub(crate) fn pick_random_variant(&mut self) -> bool;
}
```

## 6. 风险、边界与改进建议

### 潜在风险

1. **内存占用**
   - 36 帧 × 17 行 × ~40 字符 ≈ 24KB 原始文本
   - 10 种变体总计约 240KB 静态数据
   - 建议：监控二进制文件大小增长

2. **终端兼容性**
   - ASCII 艺术使用扩展字符（如 `╭``╮`）
   - 某些终端可能渲染不一致
   - 建议：测试主流终端模拟器兼容性

3. **帧率同步**
   - 固定 80ms 间隔可能与显示器刷新率不同步
   - 建议：考虑自适应帧率或垂直同步

### 边界情况

1. **尺寸限制**
   - 终端小于 37×60 时动画被跳过
   - 本帧 (36) 在小型终端中不可见

2. **变体索引越界**
   - `pick_random_variant()` 使用 `min()` 钳制索引
   - 本帧始终可通过索引 36-1 访问

3. **长时间运行**
   - `elapsed_ms` 可能溢出（u128 实际上无此风险）
   - 动画循环自然处理：`% frames.len()`

### 改进建议

1. **动态帧率**
   ```rust
   // 允许配置帧间隔
   pub(crate) fn set_frame_tick(&mut self, tick: Duration);
   ```

2. **帧预加载**
   - 当前已实现编译时嵌入，无需运行时加载
   - 可考虑压缩以减小二进制体积

3. **可访问性**
   - 添加选项禁用动画（节省 CPU/电池）
   - 提供纯文本替代显示

4. **动画变体扩展**
   - 支持用户自定义帧目录
   - 运行时加载外部帧文件

5. **性能优化**
   - 当前每帧分配新字符串（`frame.lines()`）
   - 可考虑缓存解析后的行

---

## 附录：ASCII 内容预览

```
                                      
              ddtottttottd            
          doggot5c5totcttgpptd        
        topottp-pgee egpxptetpet      
      degptdddd            ppxoge     
     t5dcopeoeot-             do-p    
     5 t5e  pd ge5t            godp   
    e cge     go goo            edet  
    eeox      do d55g           oe e  
    epge     55 tpgptttdtttttd  eoxe  
     dpeo  tedd5x5 gexdddddddee o5pe  
     p peo tdt5d     gppdddddg etg5   
      ptgoc-                 t5eg5    
        o5eetxt           tttg5te     
          ptdgppodcxdtxcg-gtctp       
            ept5xdttdttttppg          
                                      
```

*本帧为 17 行 ASCII 艺术，展示 slug 生物动画序列的第 36 个姿态。*
