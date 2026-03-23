# output.rs 深度研究文档

## 场景与职责

`output.rs` 是 debug-client 的输出管理模块，负责处理所有用户可见的输出，包括提示符显示、服务器消息打印、客户端消息打印等。它解决了交互式应用中常见的输出竞争问题（如提示符与消息交错）。

**核心定位**：
- 线程安全的输出控制器（使用 `Arc<Mutex<...>>`）
- 提示符状态管理（显示/隐藏/更新）
- 颜色支持（基于 `NO_COLOR` 环境和终端检测）
- 服务器输出（stdout）与客户端输出（stderr）分离

**使用场景**：
- 显示 `(thread-id)> ` 提示符
- 打印服务器返回的 JSON 消息
- 打印客户端错误和状态信息
- 支持管道/重定向场景（自动禁用颜色）

## 功能点目的

### 1. 标签颜色枚举

```rust
#[derive(Clone, Copy, Debug)]
pub enum LabelColor {
    Assistant,  // 绿色 (32)
    Tool,       // 青色 (36)
    ToolMeta,   // 黄色 (33)
    Thread,     // 蓝色 (34)
}
```

**设计意图**：
- 为不同类型的输出提供视觉区分
- 使用 ANSI 颜色码，简单可移植
- 通过 `format_label` 方法动态应用颜色

### 2. 提示符状态

```rust
#[derive(Debug, Default)]
struct PromptState {
    thread_id: Option<String>,  // 当前线程 ID
    visible: bool,              // 是否正在显示
}
```

**状态管理**：
- `visible` 跟踪提示符是否在当前行显示
- 需要清除提示符时，先输出换行避免内容覆盖

### 3. Output 结构体

```rust
#[derive(Clone, Debug)]
pub struct Output {
    lock: Arc<Mutex<()>>,           // 全局输出锁
    prompt: Arc<Mutex<PromptState>>, // 提示符状态
    color: bool,                     // 是否启用颜色
}
```

**线程安全设计**：
- `lock`：确保输出操作原子性，避免交错
- `prompt`：独立于主锁，支持状态查询
- `color`：编译期确定，无需同步

**颜色检测**（行29-36）：
```rust
pub fn new() -> Self {
    let no_color = std::env::var_os("NO_COLOR").is_some();
    let color = !no_color && io::stdout().is_terminal() && io::stderr().is_terminal();
    Self { ... }
}
```

遵循 [NO_COLOR](https://no-color.org/) 标准，并检测终端类型。

### 4. 服务器输出行

```rust
pub fn server_line(&self, line: &str) -> io::Result<()>
```

**行为**（行39-46）：
1. 获取全局锁
2. 清除当前提示符（如果可见）
3. 写入 stdout 并换行
4. 重新绘制提示符

**设计目的**：
- 服务器消息输出到 stdout，支持管道/重定向
- 自动处理提示符的显示/隐藏，避免视觉混乱

### 5. 客户端输出行

```rust
pub fn client_line(&self, line: &str) -> io::Result<()>
```

**行为**（行48-54）：
1. 获取全局锁
2. 清除当前提示符
3. 写入 stderr 并换行
4. **不**重新绘制提示符（由调用者控制）

**设计目的**：
- 客户端消息（错误、状态）输出到 stderr
- 与服务器输出分离，便于日志分离

### 6. 提示符管理

**显示提示符**（行56-60）：
```rust
pub fn prompt(&self, thread_id: &str) -> io::Result<()>
```
- 更新状态并立即显示

**设置提示符**（行62-65）：
```rust
pub fn set_prompt(&self, thread_id: &str)
```
- 仅更新状态，不立即显示
- 用于异步更新（如收到 `ThreadReady` 事件）

**格式**（行110-120）：
```rust
fn write_prompt_locked(&self) -> io::Result<()> {
    write!(stderr, "({thread_id})> ")?;
    stderr.flush()?;
    prompt.visible = true;
}
```

### 7. 标签格式化

```rust
pub fn format_label(&self, label: &str, color: LabelColor) -> String
```

**颜色映射**（行72-78）：
```rust
let code = match color {
    LabelColor::Assistant => "32",  // 绿色
    LabelColor::Tool => "36",       // 青色
    LabelColor::ToolMeta => "33",   // 黄色
    LabelColor::Thread => "34",     // 蓝色
};
format!("\x1b[{code}m{label}\x1b[0m")
```

## 具体技术实现

### 关键流程

**输出服务器消息**：
```
server_line(line)
    ↓
acquire lock
    ↓
clear_prompt_line_locked()
    ↓ 如果 prompt.visible:
        writeln!(stderr)  // 换行
        prompt.visible = false
    ↓
writeln!(stdout, line)
    ↓
redraw_prompt_locked()
    ↓ 如果 prompt.thread_id 存在:
        write_prompt_locked()
    ↓
release lock
```

**输出客户端消息**：
```
client_line(line)
    ↓
acquire lock
    ↓
clear_prompt_line_locked()
    ↓
writeln!(stderr, line)  // 不重新绘制提示符
    ↓
release lock
```

### 数据结构关系

```
Output
    ├─ lock: Arc<Mutex<()>>
    ├─ prompt: Arc<Mutex<PromptState>>
    │           ├─ thread_id: Option<String>
    │           └─ visible: bool
    └─ color: bool

LabelColor
    ├─ Assistant → "\x1b[32m...\x1b[0m"
    ├─ Tool → "\x1b[36m...\x1b[0m"
    ├─ ToolMeta → "\x1b[33m...\x1b[0m"
    └─ Thread → "\x1b[34m...\x1b[0m"
```

### 锁策略

**全局输出锁**（`lock`）：
- 保护所有输出操作的原子性
- 防止多线程输出交错
- 使用 `expect("output lock poisoned")` 处理 poison

**提示符状态锁**（`prompt`）：
- 独立于全局锁，允许状态查询
- 在持有全局锁时也可能需要访问

**锁层级**：
```rust
// 安全：先获取全局锁
let _guard = self.lock.lock().expect("output lock poisoned");
self.clear_prompt_line_locked()?;  // 内部获取 prompt 锁

// 危险：死锁风险！
let _prompt_guard = self.prompt.lock().expect("...");
let _guard = self.lock.lock().expect("...");  // 如果另一个线程持有全局锁等待 prompt 锁
```

当前实现始终遵循"先全局锁，后 prompt 锁"的顺序，避免死锁。

## 关键代码路径与文件引用

### 内部依赖

无直接内部依赖。

### 外部依赖

| Crate | 用途 |
|-------|------|
| `std::io` | 标准 I/O 操作 |
| `std::io::IsTerminal` | 终端检测 |

### 调用关系

**被调用方**：

| 调用者 | 方法 | 场景 |
|--------|------|------|
| `main.rs:68` | `Output::new()` | 初始化 |
| `main.rs:97` | `client_line()` | 显示连接信息 |
| `main.rs:99` | `set_prompt()` | 设置初始提示符 |
| `main.rs:114` | `prompt()` | 显示提示符 |
| `main.rs:126,132,142...` | `client_line()` | 错误/状态信息 |
| `main.rs:160` | `print_help()` → `client_line()` | 帮助信息 |
| `main.rs:256,265...` | `client_line()` | 事件处理 |
| `client.rs:302` | `server_line()` | 打印服务器响应 |
| `reader.rs:70` | `server_line()` | 打印原始服务器输出 |
| `reader.rs:86,92,100` | `client_line()` | reader 错误 |
| `reader.rs:127,136` | `client_line()` | 审批响应日志 |
| `reader.rs:230,234...` | `server_line()` | 过滤后的通知 |
| `reader.rs:310` | `write_multiline()` → `server_line()` | 多行输出 |

## 依赖与外部交互

### 标准输出流

| 流 | 用途 | 目标受众 |
|----|------|----------|
| stdout | 服务器消息 | 用户/管道/脚本 |
| stderr | 客户端消息、提示符 | 用户（终端）|

**设计理由**：
- stdout 可管道传递给其他工具处理
- stderr 始终显示给用户，不受管道影响
- 提示符在 stderr，避免污染 stdout 数据流

### 环境变量

| 变量 | 作用 |
|------|------|
| `NO_COLOR` | 禁用所有颜色输出 |

### 终端检测

```rust
io::stdout().is_terminal() && io::stderr().is_terminal()
```

- 任一输出被重定向则禁用颜色
- 避免在管道中输出 ANSI 转义序列

## 风险、边界与改进建议

### 当前风险

**1. 锁 Poison 处理**
```rust
let _guard = self.lock.lock().expect("output lock poisoned");
```
- 使用 `expect` 可能导致 panic
- 虽然输出锁不太可能 poison，但严格来说应处理

**2. 错误忽略**
```rust
pub fn set_prompt(&self, thread_id: &str) {
    let _guard = self.lock.lock().expect("output lock poisoned");
    self.set_prompt_locked(thread_id);  // 无返回值，无法传播错误
}
```
- `set_prompt` 忽略锁错误
- 可能导致状态不一致

**3. 颜色代码硬编码**
```rust
let code = match color {
    LabelColor::Assistant => "32",
    // ...
};
```
- 不支持主题定制
- 不支持 256 色或真彩色

### 边界情况

**1. 空线程 ID**
```rust
fn write_prompt_locked(&self) -> io::Result<()> {
    let Some(thread_id) = prompt.thread_id.as_ref() else {
        return Ok(());  // 静默忽略
    };
    ...
}
```
- 无线程 ID 时不显示提示符
- 用户可能困惑为什么没有提示符

**2. 长线程 ID**
- 线程 ID 可能很长（如 `thr_1234567890abcdef`）
- 提示符可能占用过多水平空间
- 无截断或缩写机制

**3. 并发输出**
```rust
pub fn server_line(&self, line: &str) -> io::Result<()> {
    let _guard = self.lock.lock().expect("output lock poisoned");
    // ... 多个 I/O 操作
}
```
- 持有锁期间进行多次 I/O
- 如果 I/O 阻塞，其他线程无法输出

### 改进建议

**1. 使用 `parking_lot` 锁**
```rust
// 建议：parking_lot::Mutex 更轻量，且 poison-free
use parking_lot::Mutex;
```

**2. 支持主题配置**
```rust
// 建议：可配置的颜色主题
pub struct ColorTheme {
    pub assistant: Color,
    pub tool: Color,
    pub tool_meta: Color,
    pub thread: Color,
}

pub enum Color {
    Ansi(u8),
    Rgb(u8, u8, u8),
}
```

**3. 提示符模板**
```rust
// 建议：可配置的提示符格式
pub fn format_prompt(&self, thread_id: &str) -> String {
    format!(self.prompt_template, thread_id = thread_id)
    // 默认: "({thread_id})> "
    // 可配置: "[{thread_id}]$ " 或 "codex> "
}
```

**4. 异步输出**
```rust
// 建议：使用 tokio::io 支持异步
use tokio::io::{AsyncWriteExt, stderr, stdout};

pub async fn server_line(&self, line: &str) -> io::Result<()>
```

**5. 日志级别**
```rust
// 建议：支持不同详细程度
pub enum Verbosity {
    Quiet,      // 仅错误
    Normal,     // 默认
    Verbose,    // 调试信息
}
```

**6. 宽字符处理**
```rust
// 建议：处理 Unicode 宽字符
use unicode_width::UnicodeWidthStr;

fn clear_prompt_line_locked(&self) -> io::Result<()> {
    // 计算实际显示宽度，而非字节数
    let width = line.width();
    write!(stderr, "\r{}\r", " ".repeat(width))?;
}
```

### 代码质量

**优点**：
- 简单清晰，职责单一
- 线程安全设计合理
- 遵循 NO_COLOR 标准

**可改进点**：
- 硬编码的 ANSI 转义序列
- 有限的错误处理
- 无测试覆盖

### 与 AGENTS.md 规范符合度

检查项目规范：
- ✅ 模块小于 500 LoC（实际 121 行）
- ✅ 简单的结构，无过度设计

无违规项。

### 与 TUI 风格规范对比

根据 `codex-rs/tui/styles.md`（如存在）：
- 当前使用基础 ANSI 颜色
- TUI 使用 `ratatui` 的 `Stylize` trait
- 建议保持一致性，但 debug-client 的定位是简单工具，当前实现可接受
