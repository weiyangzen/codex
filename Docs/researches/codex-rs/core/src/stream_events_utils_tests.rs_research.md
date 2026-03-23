# stream_events_utils_tests.rs 研究文档

## 场景与职责

`stream_events_utils_tests.rs` 是 `stream_events_utils.rs` 的单元测试模块，专注于验证：
1. 助手消息中隐藏标记（citations、plan blocks）的正确剥离
2. 图像生成结果的 Base64 解码和文件保存
3. 各种边界情况和错误处理

## 功能点目的

### 1. 隐藏标记剥离测试

验证 `handle_non_tool_response_item` 和 `last_assistant_message_from_item` 正确处理包含记忆引用的消息。

**测试场景：**
- 正常消息 + citations → 清理后保留消息内容
- 纯 citation 消息 → 返回 None
- Plan 模式下的 proposed_plan 块剥离

### 2. 图像生成保存测试

验证 `save_image_generation_result` 函数的各种场景：
- 标准 Base64 解码保存
- 文件覆盖行为
- 特殊字符清理
- 错误输入处理

## 具体技术实现

### 测试辅助函数

```rust
fn assistant_output_text(text: &str) -> ResponseItem
```

构造测试用的助手消息 ResponseItem，简化测试代码。

### 测试用例详解

#### 1. citations 剥离测试

```rust
#[tokio::test]
async fn handle_non_tool_response_item_strips_citations_from_assistant_message()
```

**输入：**
```
hello<oai-mem-citation><citation_entries>
MEMORY.md:1-2|note=[x]
</citation_entries>
<rollout_ids>
019cc2ea-1dff-7902-8d40-c8f6e5d83cc4
</rollout_ids></oai-mem-citation> world
```

**验证点：**
- 输出文本应为 `"hello world"`
- MemoryCitation 应包含 1 个 entry（path="MEMORY.md", line_start=1, line_end=2）
- rollout_ids 应包含指定 UUID

#### 2. Plan 模式标记剥离

```rust
#[test]
fn last_assistant_message_from_item_strips_citations_and_plan_blocks()
```

**输入：**
```
before<oai-mem-citation>doc1</oai-mem-citation>
<proposed_plan>
- x
</proposed_plan>
after
```

**输出：** `"before\nafter"`

#### 3. 纯隐藏标记消息

```rust
#[test]
fn last_assistant_message_from_item_returns_none_for_citation_only_message()
#[test]
fn last_assistant_message_from_item_returns_none_for_plan_only_hidden_message()
```

验证当清理后文本为空或仅空白时，返回 `None`。

#### 4. 图像生成保存

```rust
#[tokio::test]
async fn save_image_generation_result_saves_base64_to_png_in_temp_dir()
```

**流程：**
1. 构造预期路径：`temp_dir/ig_save_base64.png`
2. 调用 `save_image_generation_result("ig_save_base64", "Zm9v")`
3. 验证返回路径与预期一致
4. 验证文件内容为 `"foo"`（Zm9v 的 Base64 解码）
5. 清理测试文件

#### 5. Data URL 拒绝

```rust
#[tokio::test]
async fn save_image_generation_result_rejects_data_url_payload()
```

**输入：** `data:image/jpeg;base64,Zm9v`

**预期：** 返回 `CodexErr::InvalidRequest`

标准 Base64 解码器无法处理 Data URL 前缀，应明确拒绝。

#### 6. 文件覆盖

```rust
#[tokio::test]
async fn save_image_generation_result_overwrites_existing_file()
```

验证当目标文件已存在时，新内容会覆盖旧内容。

#### 7. Call ID 清理

```rust
#[tokio::test]
async fn save_image_generation_result_sanitizes_call_id_for_temp_dir_output_path()
```

**输入 call_id：** `../ig/..`

**预期文件名：** `___ig___.png`

验证路径遍历攻击防护：所有非 alphanumeric、`-`、`_` 字符替换为 `_`。

#### 8. 非标准 Base64 拒绝

```rust
#[tokio::test]
async fn save_image_generation_result_rejects_non_standard_base64()
```

**输入：** `_-8`（URL-safe Base64 字符）

标准 Base64 使用 `+` 和 `/`，URL-safe 变体使用 `-` 和 `_`，应被拒绝。

#### 9. 非 Base64 Data URL 拒绝

```rust
#[tokio::test]
async fn save_image_generation_result_rejects_non_base64_data_urls()
```

**输入：** `data:image/svg+xml,<svg/>`

非 Base64 编码的 Data URL 应被拒绝。

## 关键代码路径与文件引用

### 被测函数

| 函数 | 定义位置 | 测试覆盖 |
|------|---------|---------|
| `handle_non_tool_response_item` | `stream_events_utils.rs:295-360` | citations 剥离 |
| `last_assistant_message_from_item` | `stream_events_utils.rs:362-377` | 纯标记消息处理 |
| `save_image_generation_result` | `stream_events_utils.rs:74-96` | 图像保存全场景 |

### 测试依赖

```rust
use super::handle_non_tool_response_item;
use super::last_assistant_message_from_item;
use super::save_image_generation_result;
use crate::codex::make_session_and_context;
use codex_protocol::items::TurnItem;
use codex_protocol::models::ContentItem;
use codex_protocol::models::ResponseItem;
use pretty_assertions::assert_eq;
```

### 测试工具

- `make_session_and_context()` - 构造测试用的 Session 和 TurnContext

## 依赖与外部交互

### 测试框架

- `#[tokio::test]` - 异步测试支持
- `#[test]` - 同步测试
- `pretty_assertions::assert_eq` - 美观的差异输出

### 文件系统交互

- `std::env::temp_dir()` - 获取系统临时目录
- `std::fs::write/read/remove_file` - 文件操作
- `tokio::fs` - 异步文件操作（通过被测函数间接使用）

### 协议类型

- `ResponseItem::Message` - 助手消息结构
- `TurnItem::AgentMessage` - 内部消息表示
- `AgentMessageContent::Text` - 文本内容

## 风险、边界与改进建议

### 测试覆盖分析

| 功能 | 覆盖状态 | 备注 |
|------|---------|------|
| citations 剥离 | ✅ 完整 | 含解析验证 |
| plan blocks 剥离 | ✅ 完整 | 仅同步测试 |
| 图像保存 | ✅ 完整 | 含错误场景 |
| 工具调用处理 | ❌ 缺失 | `handle_output_item_done` 未测试 |
| 记忆模式污染 | ❌ 缺失 | `maybe_mark_thread_memory_mode_polluted` 未测试 |
| Stage1 使用统计 | ❌ 缺失 | `record_stage1_output_usage` 未测试 |

### 改进建议

1. **添加工具调用测试**
   ```rust
   #[tokio::test]
   async fn handle_output_item_done_routes_tool_call() {
       // 验证工具调用被正确识别并返回 tool_future
   }
   
   #[tokio::test]
   async fn handle_output_item_done_handles_guardrail_error() {
       // 验证 MissingLocalShellCallId 错误处理
   }
   ```

2. **添加并发测试**
   ```rust
   #[tokio::test]
   async fn concurrent_image_generation_saves_separate_files() {
       // 验证并发图像生成不冲突
   }
   ```

3. **添加大文件测试**
   ```rust
   #[tokio::test]
   async fn save_image_generation_result_handles_large_images() {
       // 测试大 Base64 负载的性能和内存使用
   }
   ```

4. **改进测试隔离**
   ```rust
   // 当前使用固定文件名，建议使用随机文件名避免冲突
   let call_id = format!("test_{}", uuid::Uuid::new_v4());
   ```

5. **添加 Windows 路径测试**
   ```rust
   #[tokio::test]
   async fn save_image_generation_result_handles_windows_paths() {
       // 验证 Windows 环境下的路径处理
   }
   ```

### 潜在问题

1. **临时文件清理**
   - 当前使用 `let _ = std::fs::remove_file(&saved_path)` 忽略清理错误
   - 建议：使用 `tempfile` crate 的自动清理功能

2. **测试顺序依赖**
   - 虽然当前测试独立，但使用固定文件名存在潜在冲突
   - 建议：使用 `NamedTempFile` 或随机文件名

3. **Base64 测试数据**
   - `"Zm9v"` 是 `"foo"` 的 Base64 编码
   - 建议：添加注释说明，或使用常量定义
