# terminal.rs 研究文档

## 场景与职责

`terminal.rs` 是 Codex Core 模块中负责终端检测与识别的工具模块。它通过分析环境变量识别当前运行的终端模拟器类型，生成 User-Agent 字符串用于 OpenTelemetry 遥测，并为 TUI 提供终端特定的配置决策依据。

**主要职责：**
1. **终端类型检测** - 识别 13+ 种主流终端模拟器
2. **多路复用器检测** - 检测 tmux、zellij 等终端多路复用器
3. **tmux 客户端信息** - 通过 `tmux display-message` 获取底层终端信息
4. **User-Agent 生成** - 生成规范的终端标识字符串
5. **环境抽象** - 支持测试注入的环境变量

## 功能点目的

### 1. 终端类型枚举

```rust
pub enum TerminalName {
    AppleTerminal,    // Terminal.app
    Ghostty,          // Ghostty
    Iterm2,           // iTerm2
    WarpTerminal,     // Warp
    VsCode,           // VS Code 集成终端
    WezTerm,          // WezTerm
    Kitty,            // kitty
    Alacritty,        // Alacritty
    Konsole,          // KDE Konsole
    GnomeTerminal,    // GNOME Terminal
    Vte,              // VTE 后端
    WindowsTerminal,  // Windows Terminal
    Dumb,             // TERM=dumb
    Unknown,          // 未知
}
```

### 2. 多路复用器检测

```rust
pub enum Multiplexer {
    Tmux { version: Option<String> },
    Zellij {},
}
```

### 3. 终端信息结构

```rust
pub struct TerminalInfo {
    pub name: TerminalName,           // 终端名称枚举
    pub term_program: Option<String>, // TERM_PROGRAM 值
    pub version: Option<String>,      // 版本字符串
    pub term: Option<String>,         // TERM 值
    pub multiplexer: Option<Multiplexer>,
}
```

### 4. 检测优先级

检测顺序（从高到低）：

1. **tmux 特殊处理** - 如果 `TERM_PROGRAM=tmux`，查询底层终端
2. **TERM_PROGRAM** - 最可靠的终端标识
3. **终端特定变量：**
   - `WEZTERM_VERSION` → WezTerm
   - `ITERM_SESSION_ID`/`ITERM_PROFILE` → iTerm2
   - `TERM_SESSION_ID` → Apple Terminal
   - `KITTY_WINDOW_ID`/`TERM` 包含 "kitty" → kitty
   - `ALACRITTY_SOCKET`/`TERM=alacritty` → Alacritty
   - `KONSOLE_VERSION` → Konsole
   - `GNOME_TERMINAL_SCREEN` → GNOME Terminal
   - `VTE_VERSION` → VTE
   - `WT_SESSION` → Windows Terminal
4. **TERM 回退** - 能力字符串回退
5. **Unknown** - 完全未知

### 5. tmux 客户端信息获取

```rust
fn tmux_client_info() -> TmuxClientInfo
```

通过执行 `tmux display-message` 命令获取：
- `#{client_termtype}` - 客户端终端类型（如 `ghostty 1.2.3`）
- `#{client_termname}` - 客户端 TERM 值（如 `xterm-256color`）

**用途：** 当运行在 tmux 中时，识别用户实际使用的终端而非 tmux 本身。

### 6. User-Agent 生成

```rust
pub fn user_agent() -> String
```

生成格式：
- 有版本：`{program}/{version}`（如 `iTerm.app/3.5.0`）
- 无版本：`{program}`（如 `kitty`）
- 回退到 TERM 值或硬编码名称

**字符清理：** 非 `a-zA-Z0-9-_.` 字符替换为 `_`

## 具体技术实现

### 环境抽象 trait

```rust
trait Environment {
    fn var(&self, name: &str) -> Option<String>;
    fn has(&self, name: &str) -> bool;
    fn var_non_empty(&self, name: &str) -> Option<String>;
    fn has_non_empty(&self, name: &str) -> bool;
    fn tmux_client_info(&self) -> TmuxClientInfo;
}
```

**实现：**
- `ProcessEnvironment` - 生产环境，读取真实环境变量
- `FakeEnvironment`（测试中）- 注入测试数据

### 全局缓存

```rust
static TERMINAL_INFO: OnceLock<TerminalInfo> = OnceLock::new();
```

终端信息在首次访问时检测并缓存，避免重复检测开销。

### tmux 版本提取

```rust
fn tmux_version_from_env(env: &dyn Environment) -> Option<String>
```

当 `TERM_PROGRAM=tmux` 时，从 `TERM_PROGRAM_VERSION` 提取版本。

### 终端名称规范化

```rust
fn terminal_name_from_term_program(value: &str) -> Option<TerminalName>
```

归一化处理：
1. 去除空格、连字符、下划线、点号
2. 转小写
3. 匹配枚举

示例：
- `iTerm.app` → `itermapp` → `Iterm2`
- `WarpTerminal` → `warpterminal` → `WarpTerminal`

## 关键代码路径与文件引用

### 核心函数

| 函数 | 行号 | 用途 |
|------|------|------|
| `terminal_info()` | 263-267 | 公共 API，获取终端信息 |
| `user_agent()` | 258-260 | 公共 API，获取 User-Agent |
| `detect_terminal_info_from_env()` | 283-370 | 核心检测逻辑 |
| `detect_multiplexer()` | 372-387 | 多路复用器检测 |
| `tmux_client_info()` | 433-438 | tmux 客户端信息 |

### 调用关系

**被调用方（上游）：**
- 遥测系统 - 生成 User-Agent 头部
- TUI 配置 - 终端特定的行为调整
- 日志系统 - 终端类型标记

**调用方（下游）：**
- `std::env::var` - 环境变量读取
- `std::process::Command` - tmux 命令执行

### 检测逻辑代码

```rust
fn detect_terminal_info_from_env(env: &dyn Environment) -> TerminalInfo {
    let multiplexer = detect_multiplexer(env);

    // 1. tmux 特殊处理
    if let Some(term_program) = env.var_non_empty("TERM_PROGRAM") {
        if is_tmux_term_program(&term_program)
            && matches!(multiplexer, Some(Multiplexer::Tmux { .. }))
            && let Some(terminal) = terminal_from_tmux_client_info(...)
        {
            return terminal;
        }
        // ... TERM_PROGRAM 处理
    }

    // 2. 终端特定变量检查
    if env.has("WEZTERM_VERSION") { ... }
    if env.has("ITERM_SESSION_ID") { ... }
    // ... 更多检查

    // 3. TERM 回退
    if let Some(term) = env.var_non_empty("TERM") { ... }

    TerminalInfo::unknown(multiplexer)
}
```

## 依赖与外部交互

### 标准库依赖

```rust
use std::sync::OnceLock;
use std::process::Command;
```

### 外部命令

- `tmux display-message -p #{client_termtype}`
- `tmux display-message -p #{client_termname}`

**失败处理：** 命令失败或 tmux 不可用时返回 `None`，不影响整体检测。

### 环境变量清单

| 变量 | 用途 |
|------|------|
| `TERM_PROGRAM` | 主终端标识 |
| `TERM_PROGRAM_VERSION` | 版本信息 |
| `TERM` | 能力字符串回退 |
| `TMUX`/`TMUX_PANE` | tmux 检测 |
| `ZELLIJ`/`ZELLIJ_SESSION_NAME`/`ZELLIJ_VERSION` | zellij 检测 |
| `WEZTERM_VERSION` | WezTerm 检测 |
| `ITERM_SESSION_ID`/`ITERM_PROFILE` | iTerm2 检测 |
| `TERM_SESSION_ID` | Apple Terminal 检测 |
| `KITTY_WINDOW_ID` | kitty 检测 |
| `ALACRITTY_SOCKET` | Alacritty 检测 |
| `KONSOLE_VERSION` | Konsole 检测 |
| `GNOME_TERMINAL_SCREEN` | GNOME Terminal 检测 |
| `VTE_VERSION` | VTE 检测 |
| `WT_SESSION` | Windows Terminal 检测 |

## 风险、边界与改进建议

### 已知风险

1. **tmux 命令执行开销**
   - 每次检测执行 2 次 `tmux display-message`
   - 缓解：结果缓存在 `OnceLock` 中
   - 风险：首次调用有 ~10-50ms 延迟

2. **环境变量伪造**
   - 用户可以设置任意环境变量欺骗检测
   - 缓解：这是设计上的，用于测试和自定义

3. **Windows 支持局限**
   - 依赖 `WT_SESSION` 检测 Windows Terminal
   - 某些旧版本 Windows Terminal 可能未设置此变量

4. **Unicode 处理**
   - `sanitize_header_value` 仅处理 ASCII 字符
   - 非 ASCII 字符会被替换为 `_`

### 边界情况

1. **嵌套多路复用器**
   - tmux 内运行 zellij 或反之
   - 当前优先检测 tmux

2. **SSH 会话**
   - 环境变量可能来自本地或远程
   - 依赖 SSH 客户端保留或转发变量

3. **容器环境**
   - TERM 通常设置，TERM_PROGRAM 通常缺失
   - 回退到 `TerminalName::Unknown`

4. **CI/CD 环境**
   - 通常为 `TERM=dumb` 或 `Unknown`

### 改进建议

1. **添加更多终端支持**
   ```rust
   // 建议添加：
   Rio,        // Rio terminal
   Tabby,      // Tabby
   Hyper,      // Hyper
   Terminator, // Terminator
   Tilix,      // Tilix
   ```

2. **缓存策略优化**
   ```rust
   // 当前使用 OnceLock，建议添加刷新机制
   pub fn refresh_terminal_info() -> TerminalInfo
   ```

3. **检测置信度**
   ```rust
   pub struct TerminalInfo {
       // ...
       pub confidence: ConfidenceLevel,  // High/Medium/Low
   }
   ```

4. **异步检测**
   ```rust
   // 避免 tmux 命令阻塞
   pub async fn terminal_info_async() -> TerminalInfo
   ```

5. **配置覆盖**
   ```rust
   // 允许用户强制指定终端类型
   if let Ok(forced) = env::var("CODEX_TERMINAL") {
       return parse_forced_terminal(&forced);
   }
   ```

6. **版本解析增强**
   ```rust
   // 当前仅传递原始版本字符串
   // 建议解析为语义版本结构
   pub version: Option<SemVer>,
   ```

### 测试文件

- `src/terminal_tests.rs` - 全面覆盖 13+ 终端类型的检测测试
