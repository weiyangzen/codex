# setup_error.rs 深度研究文档

## 场景与职责

`setup_error.rs` 是 Windows Sandbox 模块中的**设置错误管理器**，提供结构化的错误定义、报告序列化和错误提取功能。它是设置流程（包括提权设置助手和非提权编排器）之间错误通信的桥梁。

### 核心职责
1. **错误代码定义**：定义所有可能的设置错误类型
2. **错误报告序列化**：将错误序列化为 JSON 格式供跨进程传递
3. **错误提取**：从 `anyhow::Error` 中提取结构化错误信息
4. **隐私保护**：在错误消息中脱敏用户路径信息

## 功能点目的

### 1. `SetupErrorCode` 枚举
```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SetupErrorCode {
    // Orchestrator (run in CLI) failures
    OrchestratorSandboxDirCreateFailed,
    OrchestratorElevationCheckFailed,
    OrchestratorPayloadSerializeFailed,
    OrchestratorHelperLaunchFailed,
    OrchestratorHelperLaunchCanceled,
    OrchestratorHelperExitNonzero,
    OrchestratorHelperReportReadFailed,
    // Helper (elevated process) failures
    HelperRequestArgsFailed,
    HelperSandboxDirCreateFailed,
    HelperLogFailed,
    HelperUserProvisionFailed,
    HelperUsersGroupCreateFailed,
    HelperUserCreateOrUpdateFailed,
    HelperDpapiProtectFailed,
    HelperUsersFileWriteFailed,
    HelperSetupMarkerWriteFailed,
    HelperSidResolveFailed,
    HelperCapabilitySidFailed,
    HelperFirewallComInitFailed,
    HelperFirewallPolicyAccessFailed,
    HelperFirewallRuleCreateOrAddFailed,
    HelperFirewallRuleVerifyFailed,
    HelperReadAclHelperSpawnFailed,
    HelperSandboxLockFailed,
    HelperUnknownError,
}
```

**分类**：
- **Orchestrator 错误**（7个）：非提权编排器阶段的错误
- **Helper 错误**（18个）：提权设置助手阶段的错误

### 2. `SetupErrorReport` 结构
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SetupErrorReport {
    pub code: SetupErrorCode,
    pub message: String,
}
```
- 可序列化的错误报告
- 用于跨进程传递错误信息

### 3. `SetupFailure` 结构
```rust
#[derive(Debug)]
pub struct SetupFailure {
    pub code: SetupErrorCode,
    pub message: String,
}
```
- 实现 `std::error::Error` trait
- 支持 `Display` 格式化输出
- 提供 `metric_message()` 方法获取用于指标的标签值

### 4. 错误报告文件操作

#### `setup_error_path`
```rust
pub fn setup_error_path(codex_home: &Path) -> PathBuf
```
- 返回错误报告文件路径：`codex_home/.sandbox/setup_error.json`

#### `write_setup_error_report`
```rust
pub fn write_setup_error_report(codex_home: &Path, report: &SetupErrorReport) -> Result<()>
```
- 确保 `.sandbox` 目录存在
- 将错误报告序列化为 JSON
- 写入文件

#### `read_setup_error_report`
```rust
pub fn read_setup_error_report(codex_home: &Path) -> Result<Option<SetupErrorReport>>
```
- 读取并解析错误报告
- 文件不存在返回 `Ok(None)`

#### `clear_setup_error_report`
```rust
pub fn clear_setup_error_report(codex_home: &Path) -> Result<()>
```
- 删除错误报告文件
- 文件不存在视为成功

### 5. 错误创建和提取

#### `failure`
```rust
pub fn failure(code: SetupErrorCode, message: impl Into<String>) -> anyhow::Error
```
- 便捷函数创建 `SetupFailure` 并包装为 `anyhow::Error`

#### `extract_failure`
```rust
pub fn extract_failure(err: &anyhow::Error) -> Option<&SetupFailure>
```
- 从 `anyhow::Error` 中提取 `SetupFailure`
- 用于检查错误类型

### 6. 隐私保护

#### `sanitize_setup_metric_tag_value`
```rust
pub fn sanitize_setup_metric_tag_value(value: &str) -> String
```
- 脱敏用户名路径信息
- 使用 `redact_home_paths` 和 `sanitize_metric_tag_value`

#### `redact_home_paths`
```rust
fn redact_home_paths(value: &str) -> String
```
- 从环境变量获取用户名（`USERNAME`, `USER`）
- 调用 `redact_username_segments` 替换路径中的用户名为 `<user>`

#### `redact_username_segments`
```rust
fn redact_username_segments(value: &str, usernames: &[String]) -> String
```
- 按路径分隔符（`\` 和 `/`）分割路径
- 匹配用户名（Windows 不区分大小写）
- 替换为 `<user>`

**示例**：
```rust
// 输入
"failed to write C:\\Users\\Alice\\file.txt"
// 输出
"failed to write C:\\Users\\<user>\\file.txt"
```

## 具体技术实现

### 错误代码字符串转换
```rust
impl SetupErrorCode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::OrchestratorSandboxDirCreateFailed => "orchestrator_sandbox_dir_create_failed",
            // ... 其他变体
        }
    }
}
```

### 错误报告流程
```rust
// Helper 进程（提权）
if let Err(err) = some_operation() {
    let report = SetupErrorReport {
        code: SetupErrorCode::HelperUserCreateOrUpdateFailed,
        message: err.to_string(),
    };
    write_setup_error_report(codex_home, &report)?;
    return Err(failure(report.code, report.message));
}

// Orchestrator 进程（非提权）
let status = cmd.status()?;
if !status.success() {
    match read_setup_error_report(codex_home)? {
        Some(report) => Err(anyhow::Error::new(SetupFailure::from_report(report))),
        None => Err(failure(SetupErrorCode::OrchestratorHelperExitNonzero, "...")),
    }
}
```

### 路径脱敏算法
```rust
fn redact_username_segments(value: &str, usernames: &[String]) -> String {
    let mut segments: Vec<String> = Vec::new();
    let mut separators: Vec<char> = Vec::new();
    let mut current = String::new();

    // 分割路径
    for ch in value.chars() {
        if ch == '\\' || ch == '/' {
            segments.push(std::mem::take(&mut current));
            separators.push(ch);
        } else {
            current.push(ch);
        }
    }
    segments.push(current);

    // 替换匹配的用户名
    for segment in &mut segments {
        let matches = if cfg!(windows) {
            usernames.iter().any(|name| segment.eq_ignore_ascii_case(name))
        } else {
            usernames.iter().any(|name| segment == name)
        };
        if matches {
            *segment = "<user>".to_string();
        }
    }

    // 重新组合
    let mut out = String::new();
    for (idx, segment) in segments.iter().enumerate() {
        out.push_str(segment);
        if let Some(sep) = separators.get(idx) {
            out.push(*sep);
        }
    }
    out
}
```

## 关键代码路径与文件引用

### 内部依赖
| 函数 | 来源 | 用途 |
|------|------|------|
| `sanitize_metric_tag_value` | `codex_utils_string` | 指标标签值清理 |

### 被调用方
| 调用方 | 函数 | 场景 |
|--------|------|------|
| `setup_orchestrator.rs` | `failure`, `write_setup_error_report`, `read_setup_error_report`, `clear_setup_error_report` | 错误处理流程 |
| `sandbox_users.rs` | `SetupFailure::new` | 用户创建错误 |
| 设置助手各模块 | `failure` | 报告具体错误 |

### 导出接口
```rust
#[cfg(target_os = "windows")]
pub use setup_error::extract_failure as extract_setup_failure;
#[cfg(target_os = "windows")]
pub use setup_error::sanitize_setup_metric_tag_value;
#[cfg(target_os = "windows")]
pub use setup_error::setup_error_path;
#[cfg(target_os = "windows")]
pub use setup_error::write_setup_error_report;
#[cfg(target_os = "windows")]
pub use setup_error::SetupErrorCode;
#[cfg(target_os = "windows")]
pub use setup_error::SetupErrorReport;
#[cfg(target_os = "windows")]
pub use setup_error::SetupFailure;
```

## 依赖与外部交互

### 外部 Crate
- `anyhow`：错误处理和传播
- `serde`：错误报告序列化
- `codex_utils_string`：字符串工具（指标标签清理）

### 标准库
- `std::fmt::Display`：错误格式化
- `std::error::Error`：错误 trait 实现
- `std::fs`：文件操作
- `std::path`：路径操作

### 环境变量
- `USERNAME`：Windows 用户名
- `USER`：Unix 风格用户名（备用）

## 风险、边界与改进建议

### 已知风险

1. **错误报告竞争**
   - 问题：多个并发设置流程可能覆盖错误报告
   - 缓解：通常设置流程是顺序执行的
   - 建议：添加进程 ID 或时间戳到文件名

2. **敏感信息泄露**
   - 问题：错误消息可能包含密码或其他敏感信息
   - 缓解：用户名路径脱敏
   - 风险：其他敏感信息可能未被发现

3. **文件权限**
   - 问题：错误报告文件可能被其他用户读取
   - 缓解：存储在用户的 `codex_home` 目录
   - 建议：设置严格的文件权限

### 边界条件

1. **空用户名列表**：脱敏函数返回原字符串
2. **无效 UTF-8**：`to_string_lossy` 使用替换字符
3. **文件系统错误**：IO 错误通过 `Result` 传播
4. **JSON 解析错误**：通过 `Result` 传播

### 改进建议

1. **更多脱敏规则**
   - 当前：仅脱敏用户名
   - 建议：添加 IP 地址、邮箱、令牌等模式

2. **错误报告增强**
   - 当前：仅包含代码和消息
   - 建议：添加时间戳、堆栈跟踪、系统信息

3. **错误分类细化**
   - 当前：较粗粒度的错误代码
   - 建议：添加更具体的子错误类型

4. **国际化支持**
   - 当前：错误消息为英文
   - 建议：支持本地化错误消息

5. **错误恢复建议**
   - 建议：在错误报告中包含恢复建议

### 测试覆盖

模块包含以下单元测试：
- `sanitize_tag_value_redacts_username_segments`：验证用户名脱敏
- `sanitize_tag_value_leaves_unknown_segments`：验证非用户路径保留
- `sanitize_tag_value_redacts_multiple_occurrences`：验证多处替换

### 使用示例

```rust
// 创建错误
return Err(failure(
    SetupErrorCode::HelperUserCreateOrUpdateFailed,
    format!("failed to create user {name}")
));

// 提取错误
if let Some(failure) = extract_failure(&err) {
    println!("Error code: {}", failure.code.as_str());
    println!("Message: {}", failure.message);
}

// 写入错误报告
let report = SetupErrorReport {
    code: SetupErrorCode::HelperSandboxDirCreateFailed,
    message: "Permission denied".to_string(),
};
write_setup_error_report(codex_home, &report)?;

// 读取错误报告
if let Some(report) = read_setup_error_report(codex_home)? {
    // 处理错误报告
}
```

### 错误代码命名约定

- `Orchestrator*`：编排器（非提权 CLI）错误
- `Helper*`：设置助手（提权进程）错误
- 使用 `snake_case` 序列化
- 后缀 `Failed` 表示操作失败

### 指标集成

错误代码用于指标标签：
```rust
// 示例指标
codex_sandbox_setup_errors_total{code="helper_user_create_or_update_failed"} 1
```

`metric_message()` 方法提供脱敏后的消息，适合用于指标标签或日志。
