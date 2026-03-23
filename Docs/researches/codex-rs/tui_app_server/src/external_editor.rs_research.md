# external_editor.rs 研究文档

## 场景与职责

`external_editor.rs` 是 Codex TUI 应用服务器中负责**外部编辑器集成**的模块。它提供了在 TUI 应用中启动外部文本编辑器（如 Vim、VS Code、Nano 等）的功能，主要用于：

1. **消息编辑**：允许用户使用熟悉的外部编辑器编写或修改消息
2. **长文本输入**：处理多行、复杂的文本输入场景
3. **临时文件管理**：创建临时文件、写入种子内容、启动编辑器、读取修改后的内容

该模块在以下场景被调用：
- 用户在聊天界面触发外部编辑器快捷键（通常是 `Ctrl+E`）
- 需要编辑复杂的多行消息时

---

## 功能点目的

### 1. 编辑器命令解析 (`resolve_editor_command`)

**目的**：从环境变量中解析用户偏好的外部编辑器命令。

**环境变量优先级**：
1. `VISUAL` - 图形环境首选
2. `EDITOR` - 通用编辑器设置

**平台差异**：
- **Windows**：使用 `winsplit::split` 解析（处理 Windows 特有的命令行格式）
- **Unix/Linux/macOS**：使用 `shlex::split` 解析（POSIX shell 风格）

**错误处理**：
- 环境变量未设置 → `EditorError::MissingEditor`
- 解析失败（仅非 Windows）→ `EditorError::ParseFailed`
- 空命令 → `EditorError::EmptyCommand`

### 2. 外部编辑器执行 (`run_editor`)

**目的**：启动外部编辑器编辑临时文件，并返回修改后的内容。

**流程**：
1. 创建带 `.md` 后缀的临时文件
2. 将种子内容写入临时文件
3. 启动编辑器进程（继承 stdin/stdout/stderr）
4. 等待编辑器进程结束
5. 读取并返回文件内容

**平台特殊处理**：
- **Windows**：使用 `which::which` 解析 `.cmd`/`.bat` shim 文件
- **Unix**：直接使用命令名，依赖 shell PATH 解析

### 3. 错误类型定义 (`EditorError`)

| 错误类型 | 描述 | 平台 |
|----------|------|------|
| `MissingEditor` | 未设置 VISUAL/EDITOR | 全平台 |
| `ParseFailed` | 命令解析失败 | 非 Windows |
| `EmptyCommand` | 解析结果为空 | 全平台 |

---

## 具体技术实现

### 数据结构

```rust
#[derive(Debug, Error)]
pub(crate) enum EditorError {
    #[error("neither VISUAL nor EDITOR is set")]
    MissingEditor,
    #[cfg(not(windows))]
    #[error("failed to parse editor command")]
    ParseFailed,
    #[error("editor command is empty")]
    EmptyCommand,
}
```

### 核心函数实现

#### Windows 程序解析

```rust
#[cfg(windows)]
fn resolve_windows_program(program: &str) -> std::path::PathBuf {
    // Windows 上 Command::new("code") 不会解析 code.cmd shim
    // 使用 which 库尊重 PATH + PATHEXT（如 code -> code.cmd）
    which::which(program).unwrap_or_else(|_| std::path::PathBuf::from(program))
}
```

#### 编辑器命令解析

```rust
pub(crate) fn resolve_editor_command() -> std::result::Result<Vec<String>, EditorError> {
    let raw = env::var("VISUAL")
        .or_else(|_| env::var("EDITOR"))
        .map_err(|_| EditorError::MissingEditor)?;
    
    let parts = {
        #[cfg(windows)]
        { winsplit::split(&raw) }
        #[cfg(not(windows))]
        { shlex::split(&raw).ok_or(EditorError::ParseFailed)? }
    };
    
    if parts.is_empty() {
        return Err(EditorError::EmptyCommand);
    }
    Ok(parts)
}
```

#### 编辑器执行

```rust
pub(crate) async fn run_editor(seed: &str, editor_cmd: &[String]) -> Result<String> {
    if editor_cmd.is_empty() {
        return Err(Report::msg("editor command is empty"));
    }

    // 立即转换为 TempPath，确保 Windows 上文件句柄不保持打开
    let temp_path = Builder::new().suffix(".md").tempfile()?.into_temp_path();
    fs::write(&temp_path, seed)?;

    let mut cmd = {
        #[cfg(windows)]
        { Command::new(resolve_windows_program(&editor_cmd[0])) }
        #[cfg(not(windows))]
        { Command::new(&editor_cmd[0]) }
    };
    
    if editor_cmd.len() > 1 {
        cmd.args(&editor_cmd[1..]);
    }
    
    let status = cmd
        .arg(&temp_path)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .await?;

    if !status.success() {
        return Err(Report::msg(format!("editor exited with status {status}")));
    }

    fs::read_to_string(&temp_path)
}
```

### 关键实现细节

1. **临时文件处理**
   - 使用 `tempfile::Builder` 创建带 `.md` 后缀的临时文件
   - 立即调用 `into_temp_path()` 释放文件句柄（Windows 兼容性）
   - 文件在 `TempPath` 被 drop 时自动删除

2. **进程 IO 继承**
   - 继承 stdin：允许编辑器接收用户输入
   - 继承 stdout/stderr：允许编辑器正常显示界面

3. **异步执行**
   - 使用 `tokio::process::Command` 进行异步进程管理
   - 不阻塞 TUI 主循环

---

## 关键代码路径与文件引用

### 本文件结构

| 函数/类型 | 行号 | 职责 |
|-----------|------|------|
| `EditorError` | 11-20 | 错误类型定义 |
| `resolve_windows_program` | 24-29 | Windows 程序解析 |
| `resolve_editor_command` | 33-51 | 编辑器命令解析 |
| `run_editor` | 54-91 | 执行外部编辑器 |

### 测试覆盖

| 测试函数 | 行号 | 测试内容 |
|----------|------|----------|
| `resolve_editor_prefers_visual` | 131-139 | VISUAL 优先级测试 |
| `resolve_editor_errors_when_unset` | 143-153 | 环境变量未设置错误 |
| `run_editor_returns_updated_content` | 155-170 | 完整编辑流程测试 |

### 测试辅助结构

```rust
struct EnvGuard {
    visual: Option<String>,
    editor: Option<String>,
}

impl Drop for EnvGuard {
    fn drop(&mut self) {
        // 恢复原始环境变量
        restore_env("VISUAL", self.visual.take());
        restore_env("EDITOR", self.editor.take());
    }
}
```

### 调用方

| 文件 | 使用场景 |
|------|----------|
| `app.rs` | 处理外部编辑器事件 |
| `chatwidget.rs` | 聊天窗口外部编辑器集成 |
| `bottom_pane/footer.rs` | 底部栏快捷键提示 |
| `bottom_pane/mod.rs` | 底部面板编辑器状态管理 |

---

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tempfile` | 创建和管理临时文件 |
| `tokio` | 异步进程执行 |
| `color-eyre` | 错误处理和报告 |
| `thiserror` | 错误类型派生宏 |
| `shlex` | Unix 命令行解析 |
| `winsplit` | Windows 命令行解析 |
| `which` | Windows 程序路径解析 |

### 内部模块依赖

无直接内部模块依赖，但被多个模块依赖。

### 模块声明

在 `lib.rs` 中声明为私有模块：
```rust
mod external_editor;
```

---

## 风险、边界与改进建议

### 已知风险

1. **编辑器兼容性**
   - 某些编辑器（如 VS Code）可能以非阻塞方式启动（返回立即）
   - 当前实现假设编辑器进程在文件关闭后才退出
   - GUI 编辑器可能需要特殊处理

2. **临时文件安全**
   - 临时文件在系统临时目录创建，可能有权限问题
   - 文件内容在编辑期间以明文存储

3. **跨平台差异**
   - Windows 和非 Windows 的解析逻辑不同，可能产生不一致行为
   - 环境变量处理在不同 shell 中可能有差异

4. **错误恢复**
   - 编辑器崩溃或异常退出时，临时文件可能残留
   - 用户取消编辑（如 Vim 的 `:cq`）被视为失败

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 编辑器返回非零退出码 | 返回错误，丢弃修改 |
| 空种子内容 | 正常创建空文件 |
| 编辑器修改后清空文件 | 返回空字符串 |
| 并发编辑请求 | 每次创建独立临时文件 |
| 环境变量包含引号 | 平台特定的解析逻辑处理 |

### 改进建议

1. **GUI 编辑器支持**
   - 检测常见 GUI 编辑器（VS Code、Sublime、Atom）
   - 使用 `--wait` 标志确保进程阻塞直到文件关闭
   - 或实现文件监视机制检测编辑完成

2. **配置增强**
   - 支持配置文件指定编辑器而非仅环境变量
   - 支持编辑器特定参数模板

3. **错误恢复**
   - 编辑器失败时保留临时文件供手动恢复
   - 添加重试机制

4. **安全性**
   - 考虑使用更安全的临时文件位置
   - 敏感内容编辑后安全擦除临时文件

5. **测试增强**
   - 添加 Windows 特定测试
   - 添加 GUI 编辑器模拟测试
   - 添加大文件编辑测试

6. **用户体验**
   - 添加编辑器启动提示（避免用户困惑）
   - 支持取消编辑操作（检测特定退出码）

---

## 代码统计

- **总行数**：171 行
- **代码行**：约 90 行
- **测试行**：约 75 行
- **函数数量**：3 个
- **单元测试**：3 个
- **错误类型**：3 个（1 个平台条件编译）

---

## 关联文件

- `codex-rs/tui_app_server/src/app.rs`：事件处理
- `codex-rs/tui_app_server/src/chatwidget.rs`：UI 集成
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`：快捷键提示
