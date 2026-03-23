# frame_1.txt 研究文档

## 场景与职责

`frame_1.txt` 是 Codex TUI (Terminal User Interface) 中 `hash` 动画变体的第 1 帧。该文件属于欢迎界面（Welcome Screen）的 ASCII 艺术动画系统，用于在用户启动 Codex CLI 时展示动态的视觉效果。

### 所属系统
- **动画系统**: TUI 的 ASCII 动画子系统
- **动画变体**: `hash` - 一种以井号/哈希符号为主要元素的动画风格
- **帧序列**: 共 36 帧 (frame_1.txt ~ frame_36.txt)
- **使用位置**: `onboarding/welcome.rs` 中的 `WelcomeWidget`

## 功能点目的

### 视觉设计目的
该帧展示了一个由以下字符构成的抽象几何图案：
- `█` (完整块) - 主要视觉元素
- `#` (井号) - 构成图案轮廓
- `*` (星号) - 装饰性细节
- `-` (连字符) - 连接线/过渡
- `.` (点) - 点缀元素
- `A` (字母) - 特殊标记点

### 动画序列中的角色
作为第 1 帧，它是动画循环的起点，展示了一个向外扩散的哈希图案，暗示着"计算"、"加密"或"处理"的概念，与 Codex 作为 AI 编程助手的定位相呼应。

## 具体技术实现

### 文件规格
```
尺寸: 17 行 × 约 40 列
编码: UTF-8
大小: 712 bytes
```

### 帧数据结构
```rust
// 在 frames.rs 中定义
pub(crate) const FRAMES_HASH: [&str; 36] = frames_for!("hash");

// 宏展开后，frame_1.txt 被编译为字符串常量
include_str!("../frames/hash/frame_1.txt")
```

### 渲染流程
```rust
// ascii_animation.rs
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]  // 返回 frame_1.txt 等内容
}
```

### 动画控制参数
```rust
// 默认帧间隔: 80ms
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);

// 对于 36 帧，完整循环约 2.88 秒
```

## 关键代码路径与文件引用

### 编译时嵌入
| 文件 | 作用 |
|------|------|
| `frames.rs` | 定义 `frames_for!` 宏，编译时嵌入所有帧文件 |
| `frame_1.txt` | 本文件，作为 `FRAMES_HASH[0]` 被嵌入 |

### 运行时渲染链
```
frame_1.txt
    ↓ (编译时嵌入)
frames.rs:FRAMES_HASH[0]
    ↓ (被引用)
ascii_animation.rs:current_frame()
    ↓ (渲染)
onboarding/welcome.rs:WelcomeWidget.render_ref()
    ↓ (显示)
终端输出
```

### 关键代码引用

**frames.rs** (第 4-45 行):
```rust
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            // ... frame_2.txt 到 frame_36.txt
        ]
    };
}
```

**frames.rs** (第 52 行):
```rust
pub(crate) const FRAMES_HASH: [&str; 36] = frames_for!("hash");
```

**frames.rs** (第 64 行):
```rust
&FRAMES_HASH,  // 包含在 ALL_VARIANTS 中
```

**onboarding/welcome.rs** (第 82-83 行):
```rust
let frame = self.animation.current_frame();
lines.extend(frame.lines().map(Into::into));
```

## 依赖与外部交互

### 编译依赖
- **Rust 编译器**: 使用 `include_str!` 宏在编译时将文件内容嵌入二进制
- **UTF-8 支持**: 文件包含 Unicode 字符（如 `█`）

### 运行时依赖
| 组件 | 依赖方式 | 说明 |
|------|----------|------|
| `FrameRequester` | 构造时注入 | 用于调度下一帧渲染 |
| `ratatui` | 库依赖 | 终端 UI 渲染框架 |
| `tokio` | 运行时 | 异步调度帧更新 |

### 尺寸约束
```rust
// onboarding/welcome.rs
const MIN_ANIMATION_HEIGHT: u16 = 37;
const MIN_ANIMATION_WIDTH: u16 = 60;
```

如果终端尺寸小于上述约束，动画将被跳过。

## 风险、边界与改进建议

### 当前风险

1. **硬编码帧数**
   - `frames_for!` 宏期望恰好 36 帧
   - 如果添加或删除帧，需要同步修改宏定义

2. **文件缺失风险**
   - 编译时如果文件缺失，`include_str!` 会导致编译失败
   - 无运行时文件 I/O 错误（已嵌入二进制）

3. **尺寸一致性**
   - 各帧应保持相同尺寸以避免动画"跳动"
   - 当前帧: 17 行，但不同帧可能有细微差异

### 边界情况

| 场景 | 行为 |
|------|------|
| 终端高度 < 37 | 跳过动画，仅显示文字 |
| 终端宽度 < 60 | 跳过动画，仅显示文字 |
| 动画被禁用 | 不调用 `schedule_next_frame()` |
| Ctrl+. 按键 | 随机切换到其他动画变体 |

### 改进建议

1. **帧验证工具**
   ```rust
   // 建议添加编译时断言
   const _: () = assert!(
       FRAMES_HASH[0].lines().count() == 17,
       "frame_1.txt must have exactly 17 lines"
   );
   ```

2. **元数据标注**
   - 在文件头部添加注释说明帧的用途和序列位置
   - 例如：`# Frame 1/36 - Hash animation start`

3. **动态帧率**
   - 当前固定 80ms，可考虑根据终端性能动态调整

4. **可访问性**
   - 考虑为屏幕阅读器用户提供动画关闭选项
   - 当前已有 `animations_enabled` 标志控制

### 相关文件
- 同系列帧: `frame_2.txt` ~ `frame_36.txt`
- 其他动画变体: `default/`, `codex/`, `openai/`, `blocks/`, `dots/`, `hbars/`, `vbars/`, `shapes/`, `slug/`
