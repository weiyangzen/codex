# clipboard_text.rs 研究文档

## 场景与职责

`clipboard_text.rs` 是 Codex TUI 应用服务器的剪贴板文本复制支持模块，专门处理 `/copy` 命令的文本复制功能。与 `clipboard_paste.rs`（处理图片粘贴）形成互补，该模块专注于将文本内容从 Codex 进程复制到用户的系统剪贴板。

该模块的核心设计哲学是**环境感知**：根据当前运行环境选择最合适的剪贴板机制：
- **本地桌面会话**：直接使用 `arboard` 访问主机剪贴板
- **SSH 远程会话**：使用 OSC 52 转义序列，让终端代理复制到客户端剪贴板
- **WSL 环境**：当 `arboard` 失败时，回退到 `powershell.exe` 访问 Windows 剪贴板
- **Android/Termux**：明确声明不支持

## 功能点目的

### 1. 主入口函数 `copy_text_to_clipboard`
这是模块的唯一公共 API，提供统一的文本复制接口：
- 检测 SSH 环境（通过 `SSH_CONNECTION` 或 `SSH_TTY` 环境变量）
- 尝试使用 `arboard` 进行原生剪贴板访问
- 在 Linux/WSL 环境下，当原生访问失败时尝试 PowerShell 回退
- 返回用户友好的错误字符串（用于 TUI 显示）

### 2. SSH 环境支持（OSC 52）
当检测到 SSH 会话时，使用 OSC 52 终端转义序列：
- **Unix 系统**：直接写入 `/dev/tty`，确保即使 stdout 被重定向也能到达终端
- **Windows 系统**：写入 stdout，因为控制台是传输通道
- **tmux 支持**：检测 `TMUX` 环境变量，使用 tmux 透传格式包装序列

### 3. WSL 回退机制
当 `arboard` 在 WSL 中无法访问 Windows 剪贴板时：
- 调用 `powershell.exe` 执行 Set-Clipboard 命令
- 通过 stdin 以 UTF-8 编码流式传输文本
- 等待进程成功返回后才返回给调用方

### 4. Android 不支持声明
明确返回错误提示，说明 Android/Termux 环境不支持剪贴板文本复制。

## 具体技术实现

### 核心函数流程

```rust
pub fn copy_text_to_clipboard(text: &str) -> Result<(), String> {
    // 1. 检测 SSH 环境
    if std::env::var_os("SSH_CONNECTION").is_some() 
        || std::env::var_os("SSH_TTY").is_some() {
        return copy_via_osc52(text);
    }
    
    // 2. 尝试 arboard 原生访问
    match arboard::Clipboard::new() {
        Ok(mut clipboard) => match clipboard.set_text(text.to_string()) {
            Ok(()) => return Ok(()),
            Err(err) => format!("clipboard unavailable: {err}"),
        },
        Err(err) => format!("clipboard unavailable: {err}"),
    };
    
    // 3. WSL 回退（仅限 Linux）
    #[cfg(target_os = "linux")]
    if is_probably_wsl() {
        match copy_via_wsl_clipboard(text) {
            Ok(()) => return Ok(()),
            Err(wsl_err) => format!("{error}; WSL fallback failed: {wsl_err}"),
        }
    }
    
    Err(error)
}
```

### OSC 52 序列生成

```rust
fn osc52_sequence(text: &str, tmux: bool) -> String {
    let payload = base64::engine::general_purpose::STANDARD.encode(text);
    if tmux {
        // tmux 透传格式：ESC P tmux ; ESC OSC 52 ; c ; payload BEL ESC \
        format!("\x1bPtmux;\x1b\x1b]52;c;{payload}\x07\x1b\\")
    } else {
        // 标准格式：ESC ] 52 ; c ; payload BEL
        format!("\x1b]52;c;{payload}\x07")
    }
}
```

### WSL PowerShell 调用

```rust
fn copy_via_wsl_clipboard(text: &str) -> Result<(), String> {
    let mut child = std::process::Command::new("powershell.exe")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .args([
            "-NoProfile",
            "-Command",
            "[Console]::InputEncoding = [System.Text.Encoding]::UTF8; 
             $ErrorActionPreference = 'Stop'; 
             $text = [Console]::In.ReadToEnd(); 
             Set-Clipboard -Value $text",
        ])
        .spawn()?;
    
    // 写入文本到 stdin，等待进程完成
}
```

### 平台特定实现

| 平台 | 实现 |
|------|------|
| 非 Android | 完整实现（arboard + OSC 52 + WSL 回退） |
| Android | 返回不支持错误 |

## 关键代码路径与文件引用

### 定义位置
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/clipboard_text.rs`

### 调用方
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/chatwidget.rs`：处理 `/copy` 命令，调用 `copy_text_to_clipboard`

### 依赖模块
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/clipboard_paste.rs`：导入 `is_probably_wsl` 函数

### 模块声明
- 在 `lib.rs` 中声明为 `mod clipboard_text;`

## 依赖与外部交互

### 外部依赖
- `arboard`：跨平台剪贴板访问
- `base64`：OSC 52 序列的 Base64 编码
- `std::fs::OpenOptions`（Unix）：打开 `/dev/tty`
- `std::process::Command`（Linux/WSL）：执行 PowerShell

### 环境变量检测
- `SSH_CONNECTION`：SSH 连接信息
- `SSH_TTY`：SSH 分配的 TTY
- `TMUX`：tmux 会话检测

### 平台特定代码
- `#[cfg(not(target_os = "android"))]`：标准实现
- `#[cfg(target_os = "android")]`：不支持声明
- `#[cfg(unix)]`：Unix 特定的 TTY 写入
- `#[cfg(windows)]`：Windows 特定的 stdout 写入
- `#[cfg(all(not(target_os = "android"), target_os = "linux"))]`：WSL 回退

## 风险、边界与改进建议

### 风险点

1. **OSC 52 终端兼容性**
   - 并非所有终端都支持 OSC 52
   - 某些终端可能需要显式启用
   - **建议**：添加终端能力检测，对不支持的终端提供明确的错误提示

2. **WSL PowerShell 可靠性**
   - 依赖 Windows 端的 PowerShell 和 .NET
   - 某些精简版 Windows 可能缺少组件
   - **建议**：添加 PowerShell 可用性预检，提供更友好的错误信息

3. **tmux 透传复杂性**
   - tmux 透传序列较为复杂，可能在嵌套 tmux 会话中出现问题
   - **建议**：测试多层嵌套 tmux 场景

### 边界情况

1. **大文本处理**
   - 当前实现将整个文本加载到内存进行 Base64 编码
   - 超大文本可能导致内存压力
   - **建议**：考虑添加文本大小限制或流式处理

2. **特殊字符处理**
   - PowerShell 通过 stdin 接收文本，需要正确处理特殊字符
   - 当前使用 UTF-8 编码，但某些旧版 Windows 可能不支持

3. **并发访问**
   - 剪贴板访问不是原子的，可能在多线程环境下出现问题
   - **建议**：考虑添加同步机制（如果需要）

### 改进建议

1. **错误信息优化**
   - 当前错误信息较为通用，建议根据失败路径提供更具体的指导
   - 例如："SSH 会话中终端不支持 OSC 52，请尝试使用..."

2. **功能扩展**
   - 支持复制富文本（HTML/RTF）
   - 支持复制到特定剪贴板（主选区/剪贴板，X11 环境）

3. **测试覆盖**
   - 当前测试仅覆盖 OSC 52 序列生成
   - 建议添加集成测试（使用模拟剪贴板）

4. **配置选项**
   - 允许用户强制使用特定复制机制（覆盖自动检测）
   - 配置 OSC 52 的目标（c=clipboard, p=primary, q=secondary, s=select, o=cut）

5. **性能优化**
   - 对于大文本，考虑分块处理
   - 添加复制进度指示（对于超大文本）
