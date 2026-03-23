# terminal_tests.rs 研究文档

## 场景与职责

`terminal_tests.rs` 是 `terminal.rs` 的全面单元测试模块，覆盖 13+ 种终端模拟器的检测逻辑。通过 `FakeEnvironment` 结构注入受控的环境变量，验证各种终端配置下的正确识别。

**测试范围：**
- 主流终端模拟器（iTerm2、VS Code、Windows Terminal 等）
- 终端多路复用器（tmux、zellij）
- tmux 客户端信息传递
- User-Agent 字符串生成
- 环境变量优先级

## 功能点目的

### 1. TERM_PROGRAM 检测测试

验证 `TERM_PROGRAM` 环境变量作为最优先检测依据。

**场景：**
- 带版本号的 TERM_PROGRAM（如 `iTerm.app/3.5.0`）
- 不带版本号的 TERM_PROGRAM
- TERM_PROGRAM 覆盖其他终端变量（如 WEZTERM_VERSION）

### 2. 终端特定变量测试

为每种终端验证其特定检测变量：

| 终端 | 检测变量 | 测试函数 |
|------|---------|---------|
| iTerm2 | `ITERM_SESSION_ID` | `detects_iterm2` |
| Apple Terminal | `TERM_SESSION_ID` | `detects_apple_terminal` |
| Ghostty | `TERM_PROGRAM=Ghostty` | `detects_ghostty` |
| VS Code | `TERM_PROGRAM=vscode` | `detects_vscode` |
| Warp | `TERM_PROGRAM=WarpTerminal` | `detects_warp_terminal` |
| WezTerm | `WEZTERM_VERSION` | `detects_wezterm` |
| kitty | `KITTY_WINDOW_ID` | `detects_kitty` |
| Alacritty | `ALACRITTY_SOCKET` | `detects_alacritty` |
| Konsole | `KONSOLE_VERSION` | `detects_konsole` |
| GNOME Terminal | `GNOME_TERMINAL_SCREEN` | `detects_gnome_terminal` |
| VTE | `VTE_VERSION` | `detects_vte` |
| Windows Terminal | `WT_SESSION` | `detects_windows_terminal` |

### 3. 多路复用器检测测试

**tmux 测试：**
- 基本 tmux 检测（`TMUX` 变量）
- 版本提取（`TERM_PROGRAM_VERSION`）
- 客户端 termtype 传递
- 客户端 termname 回退

**zellij 测试：**
- 基本 zellij 检测（`ZELLIJ` 变量）

### 4. 回退测试

验证当无明确终端标识时的行为：
- `TERM=xterm-256color` → `TerminalName::Unknown`
- `TERM=dumb` → `TerminalName::Dumb`
- 无变量 → `TerminalName::Unknown`

## 具体技术实现

### 测试基础设施

```rust
struct FakeEnvironment {
    vars: HashMap<String, String>,
    tmux_client_info: TmuxClientInfo,
}
```

**Builder 模式：**
```rust
impl FakeEnvironment {
    fn new() -> Self { ... }
    fn with_var(mut self, key: &str, value: &str) -> Self { ... }
    fn with_tmux_client_info(mut self, termtype: Option<&str>, termname: Option<&str>) -> Self { ... }
}
```

**Environment trait 实现：**
```rust
impl Environment for FakeEnvironment {
    fn var(&self, name: &str) -> Option<String> {
        self.vars.get(name).cloned()
    }
    fn tmux_client_info(&self) -> TmuxClientInfo { ... }
}
```

### 测试辅助函数

```rust
fn terminal_info(
    name: TerminalName,
    term_program: Option<&str>,
    version: Option<&str>,
    term: Option<&str>,
    multiplexer: Option<Multiplexer>,
) -> TerminalInfo
```

简化测试中断言的构造。

### 测试用例详解

#### TERM_PROGRAM 优先级测试

```rust
#[test]
fn detects_term_program()
```

验证：
1. `TERM_PROGRAM=iTerm.app` + `TERM_PROGRAM_VERSION=3.5.0` → User-Agent: `iTerm.app/3.5.0`
2. 空版本 → User-Agent: `iTerm.app`
3. `TERM_PROGRAM` 优先级高于 `WEZTERM_VERSION`

#### tmux 客户端信息测试

```rust
#[test]
fn detects_tmux_term_program_uses_client_termtype()
```

**输入：**
- `TMUX=/tmp/tmux-1000/default,123,0`
- `TERM_PROGRAM=tmux`
- `TERM_PROGRAM_VERSION=3.6a`
- tmux_client_info: `termtype=Some("ghostty 1.2.3")`, `termname=Some("xterm-ghostty")`

**预期：**
- `name: TerminalName::Ghostty`
- `term_program: Some("ghostty")`
- `version: Some("1.2.3")`
- `term: Some("xterm-ghostty")`
- `multiplexer: Some(Multiplexer::Tmux { version: Some("3.6a") })`
- User-Agent: `ghostty/1.2.3`

#### kitty 多路径检测

```rust
#[test]
fn detects_kitty()
```

验证三种检测路径：
1. `KITTY_WINDOW_ID=1` → kitty
2. `TERM_PROGRAM=kitty` + `TERM_PROGRAM_VERSION=0.30.1` → kitty/0.30.1
3. `TERM=xterm-kitty` 覆盖 `ALACRITTY_SOCKET` → kitty

#### Alacritty 多路径检测

```rust
#[test]
fn detects_alacritty()
```

验证三种检测路径：
1. `ALACRITTY_SOCKET=/tmp/alacritty`
2. `TERM_PROGRAM=Alacritty` + `TERM_PROGRAM_VERSION=0.13.2`
3. `TERM=alacritty`

## 关键代码路径与文件引用

### 被测函数

| 函数 | 定义位置 | 测试覆盖 |
|------|---------|---------|
| `detect_terminal_info_from_env` | `terminal.rs:283-370` | 全部测试 |
| `detect_multiplexer` | `terminal.rs:372-387` | tmux/zellij 测试 |
| `terminal_from_tmux_client_info` | `terminal.rs:393-415` | tmux 客户端测试 |
| `user_agent_token` | `terminal.rs:174-206` | 所有断言 |
| `terminal_name_from_term_program` | `terminal.rs:466-490` | TERM_PROGRAM 测试 |

### 测试结构

```rust
// 测试分组：
detects_term_program()           // TERM_PROGRAM 基础
detects_iterm2()                 // iTerm2 特定变量
detects_apple_terminal()         // Apple Terminal
detects_ghostty()                // Ghostty
detects_vscode()                 // VS Code
detects_warp_terminal()          // Warp
detects_tmux_multiplexer()       // tmux 基础
detects_zellij_multiplexer()     // zellij
detects_tmux_client_termtype()   // tmux termtype
detects_tmux_client_termname()   // tmux termname
detects_tmux_term_program_uses_client_termtype()  // tmux 完整流程
detects_wezterm()                // WezTerm
detects_kitty()                  // kitty
detects_alacritty()              // Alacritty
detects_konsole()                // Konsole
detects_gnome_terminal()         // GNOME Terminal
detects_vte()                    // VTE
detects_windows_terminal()       // Windows Terminal
detects_term_fallbacks()         // TERM 回退
```

## 依赖与外部交互

### 测试框架

- `#[test]` - 标准测试属性
- `pretty_assertions::assert_eq` - 美观的差异输出

### 数据结构

- `TerminalInfo` - 被测结构
- `TerminalName` - 终端名称枚举
- `Multiplexer` - 多路复用器枚举
- `TmuxClientInfo` - tmux 客户端信息

### 测试数据

所有测试使用硬编码的模拟数据：
- UUID: 随机生成（测试中不涉及）
- 版本号: 真实版本格式（如 `3.5.0`、`2024.2`）
- 路径: 模拟路径（如 `/tmp/tmux-1000/default,123,0`）

## 风险、边界与改进建议

### 测试覆盖分析

| 功能 | 覆盖状态 | 备注 |
|------|---------|------|
| TERM_PROGRAM 检测 | ✅ 完整 | 含版本提取 |
| 终端特定变量 | ✅ 完整 | 13+ 终端 |
| tmux 客户端信息 | ✅ 完整 | 含 termtype/termname |
| zellij 检测 | ✅ 完整 | 基础检测 |
| User-Agent 生成 | ✅ 完整 | 所有测试验证 |
| 字符清理 | ⚠️ 部分 | 未测试特殊字符 |
| 命令执行 | ❌ 缺失 | `tmux_display_message` 未测试 |
| 缓存机制 | ❌ 缺失 | `OnceLock` 未测试 |

### 改进建议

1. **添加错误场景测试**
   ```rust
   #[test]
   fn handles_invalid_tmux_output() {
       let env = FakeEnvironment::new()
           .with_var("TMUX", "1")
           .with_tmux_client_info(Some(""), Some(""));  // 空值
       // 验证回退到 Unknown
   }
   ```

2. **添加并发测试**
   ```rust
   #[test]
   fn terminal_info_is_thread_safe() {
       // 验证 OnceLock 并发安全
       std::thread::spawn(|| terminal_info()).join();
   }
   ```

3. **添加模糊测试**
   ```rust
   #[test]
   fn handles_malformed_version_strings() {
       // 测试各种畸形版本字符串
       let versions = vec!["", "v", "1.2.3.4.5", "版本号", "1\n2"];
   }
   ```

4. **添加性能测试**
   ```rust
   #[test]
   fn detection_is_fast() {
       let start = Instant::now();
       for _ in 0..1000 {
           let _ = detect_terminal_info_from_env(&env);
       }
       assert!(start.elapsed() < Duration::from_millis(10));
   }
   ```

5. **添加新终端测试**
   ```rust
   #[test]
   fn detects_rio_terminal() {
       let env = FakeEnvironment::new()
           .with_var("RIO_VERSION", "0.2.0");
       // 验证 TerminalName::Rio
   }
   ```

### 潜在问题

1. **测试与实际行为差异**
   - 测试使用 `FakeEnvironment`，实际使用 `ProcessEnvironment`
   - `tmux_display_message` 实际执行命令，测试中完全 mock
   - 建议：添加集成测试验证真实 tmux 环境

2. **硬编码期望值**
   - User-Agent 格式变更需要更新所有测试
   - 建议：使用常量定义期望格式

3. **平台特定测试缺失**
   - Windows 路径格式（`WT_SESSION`）
   - WSL 环境检测
   - 建议：添加平台特定测试条件

4. **版本解析测试不足**
   - 未测试版本字符串中的特殊字符处理
   - 未测试多部分版本号（如 `1.2.3-beta.4`）
