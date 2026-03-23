# shell_serialization.rs 研究文档

## 场景与职责

`shell_serialization.rs` 是 Codex Core 的集成测试套件，专注于验证 **Shell 工具输出序列化** 的行为。该测试文件确保在不同配置和模型输出类型下，shell 命令的执行结果能够正确地被序列化为 JSON 或结构化文本格式。

核心测试场景包括：
1. **Shell 输出格式验证** - 验证 shell 命令输出是保持原始 JSON 还是被转换为结构化文本
2. **Apply Patch 工具输出验证** - 测试 apply_patch 工具在不同调用方式下的输出格式
3. **截断处理** - 验证大输出时的截断行为和格式
4. **退出码处理** - 验证非零退出码的输出格式

## 功能点目的

### 1. ShellModelOutput 枚举

测试使用 `ShellModelOutput` 枚举来区分不同的模型输出方式：

```rust
pub enum ShellModelOutput {
    Shell,          // 通过 shell 函数调用
    ShellCommand,   // 通过 shell_command 函数调用
    LocalShell,     // 本地 shell 调用
}
```

### 2. 输出格式控制

测试验证 `include_apply_patch_tool` 配置对输出格式的影响：
- 当 `include_apply_patch_tool = false` 时，shell 输出保持 JSON 格式
- 当 `include_apply_patch_tool = true` 时，shell 输出转换为结构化文本

### 3. ApplyPatchModelOutput 枚举

```rust
pub enum ApplyPatchModelOutput {
    Freeform,           // 自由格式输出
    Function,           // 函数调用输出
    Shell,              // Shell 调用
    ShellViaHeredoc,    // 通过 heredoc 的 shell 调用
    ShellCommandViaHeredoc, // 通过 heredoc 的 shell_command 调用
}
```

## 具体技术实现

### 关键测试流程

#### 1. shell_responses 辅助函数

生成模拟的 SSE 响应序列，支持三种输出类型：

```rust
fn shell_responses(
    call_id: &str,
    command: Vec<&str>,
    output_type: ShellModelOutput,
) -> Result<Vec<String>> {
    match output_type {
        ShellModelOutput::ShellCommand => {
            // 构造 shell_command 函数调用参数
            let parameters = json!({
                "command": command,
                "timeout_ms": 2_000,
            });
            // 返回 SSE 事件序列
        }
        ShellModelOutput::Shell => { /* 类似构造 */ }
        ShellModelOutput::LocalShell => { /* 构造本地 shell 调用 */ }
    }
}
```

#### 2. configure_shell_model 辅助函数

根据输出类型和 apply_patch 配置选择合适的测试模型：

```rust
fn configure_shell_model(
    builder: TestCodexBuilder,
    output_type: ShellModelOutput,
    include_apply_patch_tool: bool,
) -> TestCodexBuilder {
    let builder = match (output_type, include_apply_patch_tool) {
        (ShellModelOutput::ShellCommand, _) => builder.with_model("test-gpt-5-codex"),
        (ShellModelOutput::LocalShell, true) => builder.with_model("gpt-5.1-codex"),
        // ... 其他组合
    };
    builder.with_config(move |config| {
        config.include_apply_patch_tool = include_apply_patch_tool;
    })
}
```

#### 3. 结构化输出格式验证

当启用 `include_apply_patch_tool` 时，输出格式为：

```
Exit code: 0
Wall time: 0.123 seconds
Output:
<command output here>
```

### 关键数据结构

#### SSE 事件构造

使用 `core_test_support::responses` 模块提供的辅助函数：

- `ev_response_created(id)` - 响应创建事件
- `ev_function_call(call_id, name, arguments)` - 函数调用事件
- `ev_local_shell_call(call_id, status, command)` - 本地 shell 调用事件
- `ev_assistant_message(id, content)` - 助手消息事件
- `ev_completed(id)` - 响应完成事件
- `sse(events)` - 将事件序列打包为 SSE 格式

#### 测试断言模式

使用正则表达式验证结构化输出：

```rust
let expected_pattern = r"(?s)^Exit code: 0
Wall time: [0-9]+(?:\.[0-9]+)? seconds
Output:
freeform shell
?$";
assert_regex_match(expected_pattern, output);
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/shell_serialization.rs` - 本测试文件
- `codex-rs/core/tests/suite/apply_patch_cli.rs` - apply_patch 相关测试辅助函数
- `codex-rs/core/tests/common/test_codex.rs` - 测试基础设施（TestCodexBuilder, ApplyPatchModelOutput, ShellModelOutput）
- `codex-rs/core/tests/common/responses.rs` - SSE 响应模拟辅助函数

### 被测试的源代码
- `codex-rs/core/src/tools/handlers/shell.rs` - Shell 工具处理器
- `codex-rs/core/src/tools/runtimes/shell.rs` - Shell 运行时
- `codex-rs/core/src/tools/handlers/apply_patch.rs` - Apply Patch 工具处理器

### 核心测试用例

| 测试用例 | 描述 |
|---------|------|
| `shell_output_stays_json_without_freeform_apply_patch` | 验证未启用 apply_patch 时输出为 JSON |
| `shell_output_is_structured_with_freeform_apply_patch` | 验证启用 apply_patch 时输出为结构化文本 |
| `shell_output_preserves_fixture_json_without_serialization` | 验证 JSON 内容不被序列化修改 |
| `shell_output_structures_fixture_with_serialization` | 验证 JSON 内容被正确包装为结构化格式 |
| `shell_output_for_freeform_tool_records_duration` | 验证执行时间记录 |
| `shell_output_reserializes_truncated_content` | 验证截断输出的重新序列化 |
| `apply_patch_custom_tool_output_is_structured` | 验证 apply_patch 自定义工具输出格式 |
| `apply_patch_custom_tool_call_creates_file` | 验证 apply_patch 文件创建 |
| `apply_patch_custom_tool_call_updates_existing_file` | 验证 apply_patch 文件更新 |
| `apply_patch_custom_tool_call_reports_failure_output` | 验证 apply_patch 失败报告 |
| `shell_output_is_structured_for_nonzero_exit` | 验证非零退出码的输出格式 |
| `shell_command_output_is_freeform` | 验证 shell_command 的自由格式输出 |
| `shell_command_output_is_not_truncated_under_10k_bytes` | 验证 10KB 以下不截断 |
| `shell_command_output_is_not_truncated_over_10k_bytes` | 验证 10KB 以上截断行为 |
| `local_shell_call_output_is_structured` | 验证本地 shell 调用的结构化输出 |

## 依赖与外部交互

### 测试依赖

1. **core_test_support** - 测试支持库
   - `test_codex::test_codex()` - 创建测试 Codex 实例
   - `test_codex::TestCodexBuilder` - 测试配置构建器
   - `responses::start_mock_server()` - 启动模拟服务器
   - `responses::mount_sse_sequence()` - 挂载 SSE 响应序列

2. **wiremock** - HTTP 模拟服务器
   - 用于模拟 OpenAI API 响应

3. **test_case** - 参数化测试
   - 用于对多种输出类型运行相同测试

### 外部命令依赖

测试执行以下外部命令：
- `/bin/echo` - 简单输出测试
- `/usr/bin/sed` - 文件读取测试
- `/bin/sh` - shell 执行测试
- `perl` - 生成大输出测试

### 协议交互

测试通过模拟 SSE 事件流与 Codex Core 交互：
1. 模拟服务器接收 `POST /responses` 请求
2. 返回 SSE 格式的响应流
3. 验证请求体中的 `function_call_output` 格式

## 风险、边界与改进建议

### 当前风险

1. **平台限制** - 测试标记为 `#!cfg(not(target_os = "windows"))`，Windows 平台覆盖不足
2. **网络依赖** - 使用 `skip_if_no_network!` 宏，无网络时测试被跳过
3. **模型硬编码** - 测试依赖特定模型名称（如 "gpt-5.1-codex"），模型变更时可能失败

### 边界情况

1. **截断阈值** - 测试验证 200 token 限制下的截断行为，但实际阈值可能变化
2. **时间精度** - Wall time 使用正则匹配 `[0-9]+(?:\.[0-9]+)?`，可能存在浮点精度问题
3. **字符编码** - 测试涉及 UTF-8 内容（如 `naïve café`），但未明确测试编码边界

### 改进建议

1. **增加 Windows 支持** - 为 Windows 平台添加等效测试
2. **参数化模型名称** - 使用配置而非硬编码模型名称
3. **增加编码测试** - 添加多字节字符、emoji 等边界测试
4. **增加并发测试** - 验证多线程环境下的输出序列化正确性
5. **增加性能基准** - 对大输出（如 1MB）的序列化性能进行基准测试

### 相关配置项

测试涉及的关键配置：
- `config.include_apply_patch_tool` - 控制 apply_patch 工具启用
- `config.tool_output_token_limit` - 控制输出截断阈值
- `config.model` - 控制使用的模型

这些配置通过 `TestCodexBuilder::with_config` 方法在测试中动态设置。
