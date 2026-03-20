# 研究文档：codex-rs/exec/tests/fixtures

## 场景与职责

`codex-rs/exec/tests/fixtures` 是 `codex-exec` crate 的测试固件（test fixtures）目录，用于存储集成测试所需的静态数据文件。该目录包含两类测试资源：

1. **SSE 响应流固件** (`cli_responses_fixture.sse`) - 模拟 OpenAI Responses API 的 Server-Sent Events 流
2. **Patch 结果预期文件** (`apply_patch_freeform_final.txt`) - 验证 `apply_patch` 工具执行后的文件内容

这些固件文件使测试能够在离线环境下运行，无需连接真实的 OpenAI API，同时提供确定性的测试输入和预期输出。

## 功能点目的

### 1. SSE 响应流固件 (`cli_responses_fixture.sse`)

**目的**：为 `codex-exec` CLI 的集成测试提供模拟的 AI 响应流。

**使用场景**：
- `resume.rs` 中的会话恢复测试
- `ephemeral.rs` 中的临时模式测试
- `auth_env.rs` 中的环境变量认证测试
- `add_dir.rs` 中的 `--add-dir` 参数测试

**固件内容结构**：
```
event: response.created
data: {"type":"response.created","response":{"id":"resp1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"fixture hello"}]}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp1","output":[]}}
```

该固件模拟了一个完整的 OpenAI Responses API 事件流：
- `response.created` - 响应创建事件
- `response.output_item.done` - 输出项完成事件（包含助手消息）
- `response.completed` - 响应完成事件

### 2. Patch 结果预期文件 (`apply_patch_freeform_final.txt`)

**目的**：为 `test_apply_patch_freeform_tool` 测试提供预期的最终文件内容。

**使用场景**：
- `apply_patch.rs` 中的自由格式 Patch 工具测试

**固件内容**：
```python
class BaseClass:
  def method():

    return True
```

该文件表示经过两次 Patch 操作后的预期文件状态：
1. 第一次 Patch：创建 `app.py` 文件，包含 `BaseClass` 类和返回 `False` 的 `method()`
2. 第二次 Patch：更新 `method()`，将 `return False` 替换为 `return True` 并添加空行

## 具体技术实现

### 固件加载机制

#### 1. Cargo/Bazel 双模式资源定位

测试使用 `codex_utils_cargo_bin::find_resource!` 宏来定位固件文件，支持两种构建系统：

```rust
// resume.rs, ephemeral.rs
let fixture = find_resource!("tests/fixtures/cli_responses_fixture.sse")?;
```

**实现原理**（来自 `codex-rs/utils/cargo-bin/src/lib.rs`）：
- **Cargo 模式**：使用 `env!("CARGO_MANIFEST_DIR")` 拼接相对路径
- **Bazel 模式**：使用 `runfiles::rlocation!` 解析 Bazel 运行文件

```rust
#[macro_export]
macro_rules! find_resource {
    ($resource:expr) => {{
        let resource = std::path::Path::new(&$resource);
        if $crate::runfiles_available() {
            // Bazel 模式：通过 runfiles 解析
            $crate::resolve_bazel_runfile(option_env!("BAZEL_PACKAGE"), resource)
        } else {
            // Cargo 模式：基于 MANIFEST_DIR 拼接
            let manifest_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
            Ok(manifest_dir.join(resource))
        }
    }};
}
```

#### 2. SSE 固件注入机制

通过环境变量 `CODEX_RS_SSE_FIXTURE` 将固件路径传递给 `codex-core`：

```rust
// 测试代码 (resume.rs)
test.cmd()
    .env("CODEX_RS_SSE_FIXTURE", &fixture)
    .env("OPENAI_BASE_URL", "http://unused.local")
    .arg("--skip-git-repo-check")
    .arg("echo test")
    .assert()
    .success();
```

**核心实现**（`codex-rs/core/src/client.rs:1008-1017`）：

```rust
use crate::flags::CODEX_RS_SSE_FIXTURE;

// In responses_stream() method:
if let Some(path) = &*CODEX_RS_SSE_FIXTURE {
    warn!(path, "Streaming from fixture");
    let stream = codex_api::stream_from_fixture(
        path,
        self.client.state.provider.stream_idle_timeout(),
    )
    .map_err(map_api_error)?;
    let (stream, _last_request_rx) = map_response_stream(stream, session_telemetry.clone());
    return Ok(stream);
}
```

`CODEX_RS_SSE_FIXTURE` 标志定义在 `codex-rs/core/src/flags.rs`：

```rust
use env_flags::env_flags;

env_flags! {
    /// Fixture path for offline tests (see client.rs).
    pub CODEX_RS_SSE_FIXTURE: Option<&str> = None;
}
```

#### 3. Patch 结果验证

`apply_patch_freeform_final.txt` 通过 `include_str!` 宏在编译时嵌入测试代码：

```rust
// apply_patch.rs:145-148
assert_eq!(
    contents,
    include_str!("../fixtures/apply_patch_freeform_final.txt")
);
```

### 数据结构

#### SSE 固件格式

SSE 固件遵循 Server-Sent Events 标准格式：

```
event: <event_type>
data: <json_payload>

```

每个事件包含：
- `event:` 行 - 事件类型（如 `response.created`, `response.output_item.done`）
- `data:` 行 - JSON 格式的 payload
- 空行 - 事件分隔符

#### Patch 固件格式

纯文本文件，包含预期的最终文件内容，使用 Unix 换行符（LF）。

## 关键代码路径与文件引用

### 固件定义位置

| 文件 | 类型 | 用途 |
|------|------|------|
| `codex-rs/exec/tests/fixtures/cli_responses_fixture.sse` | SSE 流 | 模拟 AI 响应 |
| `codex-rs/exec/tests/fixtures/apply_patch_freeform_final.txt` | 文本 | Patch 结果预期 |

### 固件使用位置

| 测试文件 | 使用的固件 | 测试目的 |
|----------|-----------|----------|
| `resume.rs:108` | `cli_responses_fixture.sse` | `exec_fixture()` 辅助函数 |
| `resume.rs:126` | `cli_responses_fixture.sse` | `exec_resume_last_appends_to_existing_file` |
| `resume.rs:180` | `cli_responses_fixture.sse` | `exec_resume_last_accepts_prompt_after_flag_in_json_mode` |
| `resume.rs:234` | `cli_responses_fixture.sse` | `exec_resume_last_respects_cwd_filter_and_all_flag` |
| `resume.rs:342` | `cli_responses_fixture.sse` | `exec_resume_accepts_global_flags_after_subcommand` |
| `resume.rs:380` | `cli_responses_fixture.sse` | `exec_resume_by_id_appends_to_existing_file` |
| `resume.rs:436` | `cli_responses_fixture.sse` | `exec_resume_preserves_cli_configuration_overrides` |
| `resume.rs:512` | `cli_responses_fixture.sse` | `exec_resume_accepts_images_after_subcommand` |
| `ephemeral.rs:25` | `cli_responses_fixture.sse` | `persists_rollout_file_by_default` |
| `ephemeral.rs:42` | `cli_responses_fixture.sse` | `does_not_persist_rollout_file_in_ephemeral_mode` |
| `auth_env.rs` | `cli_responses_fixture.sse` | `exec_uses_codex_api_key_env_var` |
| `apply_patch.rs:147` | `apply_patch_freeform_final.txt` | `test_apply_patch_freeform_tool` |

### 核心实现文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/flags.rs` | 定义 `CODEX_RS_SSE_FIXTURE` 环境变量标志 |
| `codex-rs/core/src/client.rs:1008-1017` | 检测固件标志并切换到固件流 |
| `codex-rs/utils/cargo-bin/src/lib.rs:119-133` | `find_resource!` 宏实现 |
| `codex-rs/core/tests/common/test_codex_exec.rs` | `TestCodexExecBuilder` 测试辅助结构 |

## 依赖与外部交互

### 内部依赖

```
codex-rs/exec/tests/fixtures/
├── 被依赖方
│   ├── codex-rs/exec/tests/suite/resume.rs
│   ├── codex-rs/exec/tests/suite/ephemeral.rs
│   ├── codex-rs/exec/tests/suite/auth_env.rs
│   ├── codex-rs/exec/tests/suite/add_dir.rs
│   └── codex-rs/exec/tests/suite/apply_patch.rs
├── 依赖方（运行时加载）
│   ├── codex-rs/core/src/client.rs（通过 CODEX_RS_SSE_FIXTURE）
│   └── codex-rs/utils/cargo-bin/src/lib.rs（资源定位）
└── 依赖 crate
    ├── codex-api（stream_from_fixture）
    └── env-flags（CODEX_RS_SSE_FIXTURE 定义）
```

### 测试框架集成

固件与以下测试框架组件集成：

1. **`core_test_support`** - 提供 `test_codex_exec()` 辅助函数和 `find_resource!` 宏
2. **`assert_cmd`** - 用于断言 CLI 命令的输出和退出码
3. **`tempfile`** - 创建隔离的临时目录用于测试
4. **`wiremock`** - 启动模拟服务器（虽然 SSE 固件测试不实际使用网络）

### 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_RS_SSE_FIXTURE` | 指向 SSE 固件文件的路径 |
| `OPENAI_BASE_URL` | 设置为虚拟地址（`http://unused.local`）确保不连接真实 API |
| `CODEX_HOME` | 指向临时目录，隔离测试状态 |

## 风险、边界与改进建议

### 当前风险

1. **固件与代码不同步风险**
   - `apply_patch_freeform_final.txt` 是硬编码的预期输出，如果 `apply_patch` 工具的行为或格式发生变化，测试将失败
   - 建议：在固件文件中添加版本注释，说明生成该文件的代码版本

2. **SSE 固件覆盖范围有限**
   - 当前的 `cli_responses_fixture.sse` 只包含最基本的响应流事件
   - 复杂场景（如工具调用、错误处理、流中断）缺乏固件覆盖
   - 建议：添加更多 SSE 固件文件覆盖不同场景

3. **跨平台路径问题**
   - `find_resource!` 宏虽然处理了 Cargo/Bazel 差异，但在 Windows 上可能仍有路径分隔符问题
   - 当前 `apply_patch.rs` 中的 `include_str!` 使用 Unix 风格路径 `../fixtures/...`

### 边界情况

1. **空 SSE 固件处理**
   - 如果 `cli_responses_fixture.sse` 为空或格式错误，`stream_from_fixture` 会返回错误
   - 测试应确保固件文件存在且格式正确

2. **并发测试**
   - 多个测试同时读取同一固件文件是安全的（只读访问）
   - 但每个测试应使用独立的 `CODEX_HOME` 临时目录（通过 `test_codex_exec()` 确保）

3. **Bazel 沙箱**
   - 在 Bazel 沙箱环境中，固件文件需要通过 `runfiles` 机制访问
   - `find_resource!` 宏已处理此情况，但需要确保 `BAZEL_PACKAGE` 编译时环境变量正确设置

### 改进建议

1. **固件文档化**
   ```markdown
   <!-- 建议添加 fixtures/README.md -->
   # 测试固件说明
   
   ## cli_responses_fixture.sse
   - 用途：模拟基本 AI 响应流
   - 生成方式：手动编写（基于 OpenAI Responses API 格式）
   - 更新频率：API 格式变更时
   
   ## apply_patch_freeform_final.txt
   - 用途：验证自由格式 Patch 工具输出
   - 生成方式：执行 test_apply_patch_freeform_tool 测试后复制实际输出
   - 更新频率：Patch 工具行为变更时
   ```

2. **添加更多 SSE 固件场景**
   - `cli_responses_with_tool_calls.sse` - 包含工具调用的事件流
   - `cli_responses_with_error.sse` - 包含错误响应的事件流
   - `cli_responses_streaming.sse` - 模拟流式输出（多个 `output_text` 增量）

3. **固件验证脚本**
   ```bash
   # 建议添加验证脚本
   #!/bin/bash
   # 验证 SSE 固件格式正确
   for f in tests/fixtures/*.sse; do
       if ! grep -q "event:" "$f"; then
           echo "ERROR: $f missing event lines"
           exit 1
       fi
   done
   ```

4. **考虑使用 insta snapshot 测试**
   - 对于 `apply_patch_freeform_final.txt` 这类预期输出，可以使用 `insta` snapshot 测试
   - 优势：自动管理预期输出更新，提供清晰的 diff 视图

5. **固件文件组织优化**
   ```
   tests/fixtures/
   ├── sse/
   │   ├── basic_response.sse
   │   ├── with_tool_calls.sse
   │   └── with_error.sse
   └── patch/
       └── freeform_final.txt
   ```

### 相关文件引用

- `codex-rs/exec/tests/fixtures/cli_responses_fixture.sse:1-10`
- `codex-rs/exec/tests/fixtures/apply_patch_freeform_final.txt:1-4`
- `codex-rs/exec/tests/suite/resume.rs:107-109`
- `codex-rs/exec/tests/suite/apply_patch.rs:145-148`
- `codex-rs/core/src/client.rs:1008-1017`
- `codex-rs/core/src/flags.rs:1-6`
- `codex-rs/utils/cargo-bin/src/lib.rs:119-133`
