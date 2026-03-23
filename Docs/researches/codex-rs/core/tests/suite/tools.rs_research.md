# tools.rs 研究文档

## 场景与职责

`tools.rs` 是 Codex Core 的综合集成测试套件，专注于验证各种工具的执行、权限控制、沙箱策略和错误处理。该测试涵盖自定义工具、shell 工具、统一执行工具等多种场景，确保工具系统在各种配置和策略下正确工作。

### 核心职责
1. **自定义工具错误处理**：验证未知自定义工具返回正确错误
2. **权限升级控制**：验证权限升级请求被拒绝和降级后重试
3. **沙箱拒绝处理**：验证沙箱拒绝时返回原始输出
4. **统一执行功能切换**：验证 `exec_command` 和 `write_stdin` 工具的动态启用/禁用
5. **Shell 超时处理**：验证超时命令正确报告和元数据
6. **后台孙进程处理**：验证超时处理后台孙进程 stdout
7. **启动失败处理**：验证命令启动失败时的错误截断

## 功能点目的

### 1. 自定义工具错误 (`custom_tool_unknown_returns_custom_output_error`)
- **目的**：验证未知自定义工具调用返回正确的错误输出
- **验证点**：
  - 调用 `unsupported_tool` 返回错误
  - 输出格式为 `"unsupported custom tool call: {tool_name}"`

### 2. 权限升级拒绝 (`shell_escalated_permissions_rejected_then_ok`)
- **目的**：验证权限升级请求被拒绝，然后无升级成功
- **验证点**：
  - `SandboxPermissions::RequireEscalated` 被拒绝
  - 错误消息提示不应在 `AskForApproval::Never` 时请求升级
  - 降级后命令成功执行

### 3. 沙箱拒绝处理 (`sandbox_denied_shell_returns_original_output`)
- **目的**：验证沙箱拒绝时返回原始命令输出而非回退消息
- **验证点**：
  - 只读沙箱拒绝写操作
  - 输出包含原始的 sentinel 输出
  - 输出包含被拒绝的路径
  - 退出码非零
  - 不包含 "failed in sandbox" 回退消息

### 4. 统一执行切换 (`unified_exec_spec_toggle_end_to_end`)
- **目的**：验证 `UnifiedExec` 功能标志正确控制工具暴露
- **验证点**：
  - 禁用时工具列表不包含 `exec_command` 和 `write_stdin`
  - 启用时工具列表包含这两个工具

### 5. Shell 超时处理 (`shell_timeout_includes_timeout_prefix_and_metadata`)
- **目的**：验证超时命令正确报告和包含元数据
- **验证点**：
  - 退出码为 124（标准超时退出码）
  - 输出包含 "command timed out"
  - 支持结构化 JSON 和纯文本两种格式

### 6. 后台孙进程处理 (`shell_timeout_handles_background_grandchild_stdout`)
- **目的**：验证超时处理后台孙进程 stdout 不阻塞
- **验证点**：
  - Python 脚本生成分离的孙进程
  - 命令在超时后正确返回（< 9 秒）
  - 不会无限等待孙进程管道关闭

### 7. 启动失败截断 (`shell_spawn_failure_truncates_exec_error`)
- **目的**：验证命令启动失败时的错误消息截断
- **验证点**：
  - 使用超长路径（700 字符重复）触发启动失败
  - 输出长度不超过 10KB
  - 输出匹配预期格式（退出码、时间、输出）

## 具体技术实现

### 测试辅助函数
```rust
fn tool_names(body: &Value) -> Vec<String> {
    body.get("tools")
        .and_then(Value::as_array)
        .map(|tools| {
            tools.iter()
                .filter_map(|tool| {
                    tool.get("name")
                        .or_else(|| tool.get("type"))
                        .and_then(Value::as_str)
                        .map(str::to_string)
                })
                .collect()
        })
        .unwrap_or_default()
}
```

### 自定义工具错误测试
```rust
let call_id = "custom-unsupported";
let tool_name = "unsupported_tool";

mount_sse_once(&server, sse(vec![
    ev_response_created("resp-1"),
    ev_custom_tool_call(call_id, tool_name, "\"payload\""),
    ev_completed("resp-1"),
])).await;

// 提交并验证
let item = mock.single_request().custom_tool_call_output(call_id);
let output = item.get("output").and_then(Value::as_str).unwrap_or_default();
assert_eq!(output, format!("unsupported custom tool call: {tool_name}"));
```

### 权限升级测试
```rust
// 第一次调用：请求升级
let first_args = json!({
    "command": command,
    "timeout_ms": 1_000,
    "sandbox_permissions": SandboxPermissions::RequireEscalated,
});

// 第二次调用：无升级
let second_args = json!({
    "command": command,
    "timeout_ms": 1_000,
});

// 验证第一次被拒绝
let expected_message = format!(
    "approval policy is {policy:?}; reject command — you should not ask for escalated permissions if the approval policy is {policy:?}"
);
assert_eq!(blocked_output, expected_message);

// 验证第二次成功
assert_eq!(output_json["metadata"]["exit_code"].as_i64(), Some(0));
```

### 沙箱拒绝测试
```rust
// 使用只读沙箱策略
fixture.submit_turn_with_policy(
    "run a command that should be denied by the read-only sandbox",
    SandboxPolicy::new_read_only_policy(),
).await?;

// 验证输出包含原始输出
assert!(body.contains(sentinel), "expected sentinel output from command to reach the model");

// 验证包含被拒绝路径
assert!(body.contains(target_path_str), "expected sandbox error to mention denied path");

// 验证不包含回退消息
assert!(!body_lower.contains("failed in sandbox"), "expected original tool output, found fallback message");

// 验证非零退出码
assert_ne!(exit_code, 0, "sandbox denial should surface a non-zero exit code");
```

### 统一执行切换测试
```rust
async fn collect_tools(use_unified_exec: bool) -> Result<Vec<String>> {
    let mut builder = test_codex().with_config(move |config| {
        if use_unified_exec {
            config.features.enable(Feature::UnifiedExec).expect(...);
        } else {
            config.features.disable(Feature::UnifiedExec).expect(...);
        }
    });
    // ... 构建并获取工具列表
}

// 验证禁用状态
let tools_disabled = collect_tools(false).await?;
assert!(!tools_disabled.iter().any(|name| name == "exec_command"));
assert!(!tools_disabled.iter().any(|name| name == "write_stdin"));

// 验证启用状态
let tools_enabled = collect_tools(true).await?;
assert!(tools_enabled.iter().any(|name| name == "exec_command"));
assert!(tools_enabled.iter().any(|name| name == "write_stdin"));
```

### 超时处理测试
```rust
let args = json!({
    "command": ["/bin/sh", "-c", "yes line | head -n 400; sleep 1"],
    "timeout_ms": timeout_ms, // 50ms
});

// 验证超时输出
if let Ok(output_json) = serde_json::from_str::<Value>(output_str) {
    assert_eq!(output_json["metadata"]["exit_code"].as_i64(), Some(124));
    let stdout = output_json["output"].as_str().unwrap_or_default();
    assert!(stdout.contains("command timed out"));
} else {
    // 回退：接受信号分类路径
    let signal_pattern = r"(?is)^execution error:.*signal.*$";
    assert_regex_match(signal_pattern, output_str);
}
```

### 后台孙进程测试
```rust
// Python 脚本生成分离的孙进程
let script = format!(r#"import subprocess
import time
from pathlib import Path

# 生成分离的孙进程
proc = subprocess.Popen(["/bin/sh", "-c", "sleep 60"], start_new_session=True)
Path({pid_path:?}).write_text(str(proc.pid))
time.sleep(60)
"#);

let args = json!({
    "command": ["python3", script_path.to_string_lossy()],
    "timeout_ms": 200,
});

// 验证在 10 秒内返回（不会等待孙进程）
let output_str = tokio::time::timeout(Duration::from_secs(10), async {
    // ... 提交并获取输出
}).await.context("exec call should not hang waiting for grandchild pipes to close")??;

assert!(elapsed < Duration::from_secs(9), "command should return shortly after timeout");
```

### 启动失败截断测试
```rust
// 生成超长路径触发启动失败
let bogus_component = "missing-bin-".repeat(700);
let bogus_exe = test.cwd.path().join(bogus_component);

let args = json!({
    "command": [bogus_exe],
    "timeout_ms": 1_000,
});

// 验证输出长度限制
assert!(output.len() <= 10 * 1024);

// 验证格式
let spawn_error_pattern = r#"(?s)^Exit code: -?\d+
Wall time: [0-9]+(?:\.[0-9]+)? seconds
Output:
execution error: .*$"#;
```

## 关键代码路径与文件引用

### 被测代码路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/tools/mod.rs` | 工具注册和调度 |
| `codex-rs/core/src/tools/handlers/shell.rs` | Shell 工具实现 |
| `codex-rs/core/src/tools/handlers/exec.rs` | 统一执行工具实现 |
| `codex-rs/core/src/sandboxing/mod.rs` | 沙箱策略实现 |
| `codex-rs/core/src/features.rs` | `Feature::UnifiedExec` 功能标志 |
| `codex-rs/core/src/exec.rs` | 命令执行和超时处理 |

### 测试依赖路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/common/responses.rs` | SSE 事件构造器 |
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodex` 测试辅助 |
| `codex-rs/core/tests/common/lib.rs` | `assert_regex_match` 和 `skip_if_no_network!` |

### 关键类型引用
```rust
// codex_core::sandboxing
pub enum SandboxPermissions {
    Default,
    RequireEscalated,
}

// codex_protocol::protocol
pub struct SandboxPolicy {
    pub file_system: FileSystemSandboxPolicy,
    pub network: NetworkSandboxPolicy,
}

impl SandboxPolicy {
    pub fn new_read_only_policy() -> Self;
    pub fn danger_full_access() -> Self;
}

pub enum AskForApproval {
    Always,
    Never,
    OnSandboxEscape,
}

// codex_core::features
pub enum Feature {
    UnifiedExec,
    ShellTool,
    ...
}
```

## 依赖与外部交互

### 外部依赖
1. **wiremock**: HTTP Mock 服务器
2. **tokio**: 异步运行时
3. **serde_json**: JSON 处理
4. **regex_lite**: 正则表达式匹配
5. **tempfile**: 临时文件创建

### 内部依赖
1. **codex_core**: 核心库
2. **codex_protocol**: 协议定义
3. **core_test_support**: 测试支持库

### 环境要求
- 网络访问（通过 `skip_if_no_network!` 宏在沙箱中跳过）
- 非 Windows 平台（`#![cfg(not(target_os = "windows"))]`）
- Python 3（后台孙进程测试）
- Perl（某些测试）

## 风险、边界与改进建议

### 已知风险
1. **平台限制**：排除 Windows，可能遗漏平台特定问题
2. **外部依赖**：依赖 Python 和 Perl 进行某些测试
3. **时序敏感**：超时测试依赖系统定时器精度

### 边界情况
1. **信号处理**：超时可能由信号或定时器触发，两种路径都需验证
2. **资源泄漏**：后台孙进程需要显式清理（使用 `libc::kill`）
3. **路径长度**：启动失败测试依赖文件系统对长路径的处理

### 改进建议
1. **Windows 支持**：调查并添加 Windows 平台支持
2. **纯 Rust 测试**：将 Python/Perl 依赖替换为纯 Rust 实现
3. **更多超时场景**：添加不同超时值和命令类型的测试
4. **资源监控**：添加测试验证无资源泄漏（进程、文件描述符）
5. **并发压力**：添加高并发工具调用的压力测试

### 潜在缺陷
1. **硬编码外部命令**：依赖 `/bin/sh`、`python3` 等系统命令
2. **信号竞争**：超时和信号处理可能存在竞态条件
3. **有限的错误码覆盖**：仅测试了部分退出码场景

### 相关测试
- `tool_harness.rs`: 工具事件和基本功能测试
- `tool_parallelism.rs`: 工具并行执行测试
- `shell_command.rs`: Shell 命令专门测试
- `sandbox.rs`: 沙箱功能专门测试
