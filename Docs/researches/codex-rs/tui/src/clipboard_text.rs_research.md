# clipboard_text.rs 深度研究文档

## 场景与职责

`clipboard_text.rs` 是 Codex TUI 的文本剪贴板复制模块，负责将 Codex 生成的文本内容复制到用户的系统剪贴板。与 `clipboard_paste.rs`（处理图片粘贴）形成互补，该模块专注于文本复制功能，并针对不同的运行环境实现了智能的回退策略。

### 核心职责

1. **文本复制**: 将用户可见的文本复制到系统剪贴板
2. **环境适配**: 根据运行环境选择最合适的复制策略
3. **SSH 支持**: 在 SSH 会话中使用 OSC 52 序列实现远程到本地的剪贴板传输
4. **WSL 支持**: 在 WSL 环境中使用 PowerShell 回退访问 Windows 剪贴板
5. **错误处理**: 提供用户友好的错误信息

### 设计哲学

模块文档明确说明其设计原则：
- **范围明确**: 仅处理文本复制，不尝试创建可复用的剪贴板抽象
- **用户友好**: 返回适合在聊天 UI 中显示的错误字符串
- **策略集中**: 原生复制、OSC 52、WSL 回退的选择逻辑集中在此模块

## 功能点目的

### 1. 主入口函数

```rust
pub fn copy_text_to_clipboard(text: &str) -> Result<(), String>
```

这是模块的唯一公共 API，根据环境自动选择复制策略：
- 普通桌面会话 -> `arboard` 直接访问
- SSH 会话 -> OSC 52 终端序列
- WSL 环境（当 `arboard` 失败）-> PowerShell 回退

### 2. 环境检测

```rust
if std::env::var_os("SSH_CONNECTION").is_some() 
    || std::env::var_os("SSH_TTY").is_some() 
{
    return copy_via_osc52(text);
}
```

通过环境变量检测 SSH 会话，确保在远程机器上也能正确复制到本地剪贴板。

### 3. OSC 52 终端序列

```rust
fn osc52_sequence(text: &str, tmux: bool) -> String
```

生成 OSC 52 剪贴板控制序列：
- 基础格式: `\x1b]52;c;{base64_payload}\x07`
- Tmux 包装: `\x1bPtmux;\x1b\x1b]52;c;{base64_payload}\x07\x1b\\`

### 4. WSL PowerShell 回退

```rust
#[cfg(all(not(target_os = "android"), target_os = "linux"))]
fn copy_via_wsl_clipboard(text: &str) -> Result<(), String>
```

通过 `powershell.exe` 调用 `Set-Clipboard` cmdlet 实现 Windows 剪贴板访问。

## 具体技术实现

### 主复制逻辑

```rust
#[cfg(not(target_os = "android"))]
pub fn copy_text_to_clipboard(text: &str) -> Result<(), String> {
    // 1. 检测 SSH 环境
    if std::env::var_os("SSH_CONNECTION").is_some() 
        || std::env::var_os("SSH_TTY").is_some() 
    {
        return copy_via_osc52(text);
    }

    // 2. 尝试原生剪贴板访问
    let error = match arboard::Clipboard::new() {
        Ok(mut clipboard) => match clipboard.set_text(text.to_string()) {
            Ok(()) => return Ok(()),
            Err(err) => format!("clipboard unavailable: {err}"),
        },
        Err(err) => format!("clipboard unavailable: {err}"),
    };

    // 3. WSL 回退（Linux 平台）
    #[cfg(target_os = "linux")]
    let error = if is_probably_wsl() {
        match copy_via_wsl_clipboard(text) {
            Ok(()) => return Ok(()),
            Err(wsl_err) => format!("{error}; WSL fallback failed: {wsl_err}"),
        }
    } else {
        error
    };

    Err(error)
}
```

### OSC 52 实现

```rust
#[cfg(not(target_os = "android"))]
fn copy_via_osc52(text: &str) -> Result<(), String> {
    let sequence = osc52_sequence(text, std::env::var_os("TMUX").is_some());
    
    #[cfg(unix)]
    {
        // Unix: 直接写入 /dev/tty
        let mut tty = OpenOptions::new()
            .write(true)
            .open("/dev/tty")
            .map_err(|e| format!("clipboard unavailable: failed to open /dev/tty: {e}"))?;
        tty.write_all(sequence.as_bytes())?;
        tty.flush()?;
    }
    
    #[cfg(windows)]
    {
        // Windows: 写入 stdout
        stdout().write_all(sequence.as_bytes())?;
        stdout().flush()?;
    }
    
    Ok(())
}
```

### OSC 52 序列生成

```rust
#[cfg(not(target_os = "android"))]
fn osc52_sequence(text: &str, tmux: bool) -> String {
    let payload = base64::engine::general_purpose::STANDARD.encode(text);
    if tmux {
        // Tmux 需要特殊的包装序列
        format!("\x1bPtmux;\x1b\x1b]52;c;{payload}\x07\x1b\\")
    } else {
        format!("\x1b]52;c;{payload}\x07")
    }
}
```

### WSL PowerShell 回退

```rust
#[cfg(all(not(target_os = "android"), target_os = "linux"))]
fn copy_via_wsl_clipboard(text: &str) -> Result<(), String> {
    let mut child = std::process::Command::new("powershell.exe")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .args([
            "-NoProfile",
            "-Command",
            "[Console]::InputEncoding = [System.Text.Encoding]::UTF8; \
             $ErrorActionPreference = 'Stop'; \
             $text = [Console]::In.ReadToEnd(); \
             Set-Clipboard -Value $text",
        ])
        .spawn()
        .map_err(|e| format!("clipboard unavailable: failed to spawn powershell.exe: {e}"))?;

    // 写入文本到 PowerShell stdin
    let Some(mut stdin) = child.stdin.take() else {
        let _ = child.kill();
        return Err("clipboard unavailable: failed to open powershell.exe stdin".to_string());
    };

    stdin.write_all(text.as_bytes())?;
    drop(stdin);  // 关闭 stdin 以触发 PowerShell 执行

    // 等待执行结果
    let output = child.wait_with_output()?;
    if output.status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("clipboard unavailable: powershell.exe failed: {stderr}"))
    }
}
```

### Android 平台处理

```rust
#[cfg(target_os = "android")]
pub fn copy_text_to_clipboard(_text: &str) -> Result<(), String> {
    Err("clipboard text copy is unsupported on Android".into())
}
```

Android/Termux 环境不支持剪贴板集成，直接返回明确的错误信息。

## 关键代码路径与文件引用

### 定义位置
- **文件**: `codex-rs/tui/src/clipboard_text.rs`
- **行数**: 215 行
- **测试**: 17 行测试代码

### 调用方

| 文件 | 用途 |
|------|------|
| `lib.rs` | 模块声明 |
| `chatwidget.rs` | 处理 `/copy` 命令 |

### 依赖模块

```rust
#[cfg(not(target_os = "android"))]
use base64::Engine as _;
#[cfg(all(not(target_os = "android"), unix))]
use std::fs::OpenOptions;
#[cfg(not(target_os = "android"))]
use std::io::Write;
#[cfg(all(not(target_os = "android"), windows))]
use std::io::stdout;
#[cfg(all(not(target_os = "android"), target_os = "linux"))]
use std::process::Stdio;

#[cfg(all(not(target_os = "android"), target_os = "linux"))]
use crate::clipboard_paste::is_probably_wsl;
```

注意：从 `clipboard_paste` 导入 `is_probably_wsl()` 函数，避免重复实现。

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `arboard` | 跨平台剪贴板访问（非 Android） |
| `base64` | OSC 52 序列的 Base64 编码 |
| `std::fs::OpenOptions` | Unix 平台打开 /dev/tty |
| `std::process::Command` | WSL 环境下调用 PowerShell |

### 平台特定代码分布

| 平台 | 代码行数 | 主要功能 |
|------|---------|---------|
| 通用（非 Android） | ~140 行 | 主逻辑、OSC 52 |
| Linux | ~50 行 | WSL 回退 |
| Windows | ~10 行 | OSC 52 stdout 写入 |
| Android | ~5 行 | 错误返回 |

### 与 TUI 的集成

```
用户在 TUI 中执行 /copy 命令
    |
    v
chatwidget.rs 处理命令
    |
    v
调用 copy_text_to_clipboard(text)
    |
    v
根据环境选择策略执行
    |
    v
返回结果（成功或错误信息）
    |
    v
在 TUI 中显示结果
```

## 风险、边界与改进建议

### 潜在风险

1. **OSC 52 兼容性**: 并非所有终端都支持 OSC 52 序列
   - 风险: 用户可能在某些终端中复制失败
   - 缓解: 提供清晰的错误信息
   - 建议: 考虑检测终端类型，对已知不支持的终端提前警告

2. **PowerShell 执行策略**: WSL 回退可能受 Windows PowerShell 执行策略限制
   - 风险: 某些企业环境可能限制 PowerShell 脚本执行
   - 缓解: 使用 `-NoProfile` 和单条命令减少触发限制的可能性

3. **并发问题**: `arboard::Clipboard::new()` 每次调用创建新实例
   - 风险: 理论上可能存在并发冲突
   - 缓解: 剪贴板操作通常由用户触发，并发概率低

4. **大文本处理**: 未对文本大小进行限制
   - 风险: 超大文本可能导致内存或性能问题
   - 建议: 添加合理的大小限制

### 边界情况

1. **空文本**: 可以正常处理（复制空字符串）
2. **包含特殊字符的文本**: Base64 编码确保 OSC 52 安全传输
3. **多行文本**: 正常支持，保留换行符
4. **二进制数据**: 虽然函数签名接受 &str，但理论上可能收到无效 UTF-8

### 改进建议

1. **终端能力检测**: 在 SSH 环境下，尝试检测终端是否支持 OSC 52

```rust
fn terminal_supports_osc52() -> bool {
    // 检查 TERM 环境变量
    // 查询 terminfo 数据库
    // 或使用 DCS 序列查询终端能力
}
```

2. **Wayland 支持**: 现代 Linux 桌面越来越多使用 Wayland，可能需要特定支持

3. **错误重试**: 对 transient 错误（如剪贴板被临时锁定）添加重试逻辑

4. **异步处理**: 剪贴板操作可能阻塞，可考虑异步化

5. **测试增强**: 当前测试仅覆盖 OSC 52 序列生成，缺少：
   - 实际剪贴板操作的集成测试
   - 错误路径的测试
   - 不同平台的模拟测试

### 代码质量建议

1. **常量定义**: 将魔法字符串提取为常量

```rust
const OSC52_PREFIX: &str = "\x1b]52;c;";
const OSC52_SUFFIX: &str = "\x07";
const TMUX_WRAP_PREFIX: &str = "\x1bPtmux;\x1b";
const TMUX_WRAP_SUFFIX: &str = "\x1b\\";
```

2. **错误类型**: 考虑使用自定义错误类型替代 `String`，便于调用方分类处理

3. **日志记录**: 添加 `tracing` 日志，便于调试剪贴板问题

4. **文档示例**: 添加更多使用示例和平台特定说明
