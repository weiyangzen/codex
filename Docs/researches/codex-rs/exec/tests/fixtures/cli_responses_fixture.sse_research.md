# cli_responses_fixture.sse 研究文档

## 场景与职责

`cli_responses_fixture.sse` 是 `codex-rs/exec` crate 的测试 fixtures 文件，包含预录制的 Server-Sent Events (SSE) 响应流数据。该文件用于模拟 OpenAI Responses API 的 SSE 输出，使测试能够在离线/沙箱环境中运行，无需连接真实的 AI 服务。

此文件是多个集成测试的核心依赖，支持：
- 会话恢复（resume）功能测试
- 临时模式（ephemeral）测试
- CLI 流式响应测试
- TUI 模型可用性测试

## 功能点目的

### 1. 测试替身（Test Double）

作为 **Fake Server** 的响应数据源，提供可预测、可重复的 API 响应：

```
真实 OpenAI API → 被模拟的 SSE 流 → 测试使用 fixture 文件
```

### 2. 测试覆盖范围

| 测试文件 | 测试函数 | 用途 |
|---------|---------|------|
| `exec/tests/suite/resume.rs` | 多个 resume 测试 | 验证会话恢复功能 |
| `exec/tests/suite/ephemeral.rs` | 持久化/临时模式测试 | 验证 rollout 文件行为 |
| `core/tests/suite/cli_stream.rs` | `responses_api_stream_cli` | 验证 CLI SSE 流处理 |
| `tui/tests/suite/model_availability_nux.rs` | 模型可用性测试 | TUI 新用户体验流程 |
| `tui_app_server/tests/suite/model_availability_nux.rs` | 同上 | TUI App Server 测试 |

### 3. 文件内容结构

```sse
event: response.created
data: {"type":"response.created","response":{"id":"resp1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"fixture hello"}]}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp1","output":[]}}
```

**事件序列**：
1. `response.created` - 响应创建事件
2. `response.output_item.done` - 输出项完成（包含助手消息）
3. `response.completed` - 响应完成事件

## 具体技术实现

### SSE 协议格式

遵循标准的 Server-Sent Events 格式：

```
event: <event_type>
data: <json_payload>

```

**关键特征**：
- 每个事件由 `event:` 和 `data:` 行组成
- 事件之间以空行分隔
- 数据行包含 JSON 格式的 payload
- 文件末尾有额外的空行

### JSON Payload 结构

#### response.created
```json
{
  "type": "response.created",
  "response": {
    "id": "resp1"
  }
}
```

#### response.output_item.done
```json
{
  "type": "response.output_item.done",
  "item": {
    "type": "message",
    "role": "assistant",
    "content": [
      {
        "type": "output_text",
        "text": "fixture hello"
      }
    ]
  }
}
```

#### response.completed
```json
{
  "type": "response.completed",
  "response": {
    "id": "resp1",
    "output": []
  }
}
```

### 环境变量注入

测试通过 `CODEX_RS_SSE_FIXTURE` 环境变量指定 fixture 文件路径：

```rust
// exec/tests/suite/resume.rs:126-132
test.cmd()
    .env("CODEX_RS_SSE_FIXTURE", &fixture)
    .env("OPENAI_BASE_URL", "http://unused.local")
    .arg("--skip-git-repo-check")
    .arg("-C")
    .arg(&repo_root)
    .arg(&prompt)
```

### 资源定位

使用 `find_resource!` 宏在 Bazel/Cargo 混合环境中定位文件：

```rust
// exec/tests/suite/resume.rs:107-109
fn exec_fixture() -> anyhow::Result<std::path::PathBuf> {
    Ok(find_resource!("tests/fixtures/cli_responses_fixture.sse")?)
}
```

## 关键代码路径与文件引用

### 调用链

```
测试函数
  ├── find_resource!() -> 定位 fixture 文件
  ├── 设置 CODEX_RS_SSE_FIXTURE 环境变量
  ├── 启动 codex-exec/codex 进程
  ├── 内部 SSE 处理器读取 fixture
  │     └── 模拟 Responses API 事件流
  └── 验证输出/行为
```

### 相关文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/exec/tests/fixtures/cli_responses_fixture.sse` | SSE fixture 文件（本文件） |
| `codex-rs/exec/tests/suite/resume.rs` | 会话恢复测试套件 |
| `codex-rs/exec/tests/suite/ephemeral.rs` | 临时模式测试 |
| `codex-rs/core/tests/suite/cli_stream.rs` | CLI 流式响应测试 |
| `codex-rs/core/tests/cli_responses_fixture.sse` | core crate 的符号链接/副本 |
| `codex-rs/tui/tests/suite/model_availability_nux.rs` | TUI 模型可用性测试 |
| `codex-rs/tui_app_server/tests/suite/model_availability_nux.rs` | TUI App Server 测试 |

### BUILD.bazel 配置

```bazel
# codex-rs/core/BUILD.bazel:15
"tests/cli_responses_fixture.sse",
```

确保 Bazel 构建时将文件包含在测试数据中。

## 依赖与外部交互

### 内部依赖

1. **codex_utils_cargo_bin crate**：提供 `find_resource!` 宏，支持在 Cargo 和 Bazel 环境下定位资源文件
2. **codex-core crate**：SSE 处理和响应解析逻辑
3. **codex-exec crate**：CLI 执行和事件处理

### 测试基础设施

- **assert_cmd**：用于断言命令行程序的行为
- **tempfile**：创建临时目录和文件
- **wiremock**（部分测试）：用于更复杂的 HTTP 模拟场景

### 环境变量

| 变量名 | 用途 |
|-------|------|
| `CODEX_RS_SSE_FIXTURE` | 指定 SSE fixture 文件路径 |
| `OPENAI_BASE_URL` | 覆盖 API 端点（与 fixture 配合使用） |
| `CODEX_HOME` | 指定隔离的 Codex 配置目录 |

### 网络跳过机制

```rust
use core_test_support::skip_if_no_network;
skip_if_no_network!(Ok(()));
```

虽然使用 fixture 文件，但测试仍检查网络可用性，确保与真实环境测试的一致性。

## 风险、边界与改进建议

### 潜在风险

1. **fixture 过时**：
   - OpenAI API 格式变更可能导致 fixture 与实际响应不匹配
   - 新的事件类型未在 fixture 中体现

2. **测试覆盖局限**：
   - 当前 fixture 仅包含成功场景
   - 缺少错误处理、流中断、重试等边界情况

3. **多平台路径问题**：
   - `find_resource!` 在 Windows 下的行为需验证
   - 行尾符差异可能影响 SSE 解析

### 边界情况

| 场景 | 当前覆盖 | 说明 |
|-----|---------|------|
| 成功响应 | ✅ | 基础场景覆盖 |
| 错误响应 | ❌ | 无 error 事件 |
| 流中断 | ❌ | 无中断场景 |
| 多消息输出 | ❌ | 仅单条消息 |
| 工具调用 | ❌ | 无 function_call 事件 |
| Token 使用报告 | ❌ | 无 usage 事件 |

### 改进建议

1. **扩展 fixture 集合**：
   - 创建 `cli_responses_fixture_error.sse` - 测试错误处理
   - 创建 `cli_responses_fixture_tools.sse` - 测试工具调用
   - 创建 `cli_responses_fixture_streaming.sse` - 测试增量输出

2. **自动化更新机制**：
   - 添加脚本从真实 API 响应生成 fixture
   - 版本化 fixture 格式，与 API 版本对应

3. **增强验证**：
   - 添加 SSE 格式验证测试
   - 检查 JSON schema 兼容性

4. **文档完善**：
   - 在文件头部添加注释说明格式版本
   - 记录生成方法和更新历史

5. **性能优化**：
   - 考虑压缩大型 fixture 文件
   - 实现 fixture 缓存机制

### 维护建议

```bash
# 建议添加的验证脚本
# scripts/validate_fixtures.sh

cargo test --test validate_fixtures
# 验证所有 fixture 文件的 SSE 格式正确性
# 验证 JSON payload 符合预期 schema
```
