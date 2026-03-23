# codex-rs/ollama/src/parser.rs 研究文档

## 场景与职责

`parser.rs` 是 `codex-ollama` crate 的数据解析模块，负责将 Ollama API 的 JSON 响应转换为内部事件类型。它是客户端和拉取流程之间的数据转换层，主要职责包括：

1. **JSON 解析**：将 Ollama `/api/pull` 端点返回的 JSON 对象解析为结构化事件
2. **事件生成**：根据 JSON 内容生成一个或多个 `PullEvent`
3. **进度跟踪**：提取层（layer）的下载进度信息（digest、total、completed）

该模块是纯粹的函数式模块，无状态、无副作用，专注于数据转换。

## 功能点目的

### 1. pull_events_from_value 函数

```rust
pub(crate) fn pull_events_from_value(value: &JsonValue) -> Vec<PullEvent>
```

这是模块的核心函数，将单个 JSON 对象（代表 Ollama pull 流中的一行）转换为零个或多个 `PullEvent`。

### 2. 解析的字段

| JSON 字段 | 类型 | 映射到事件 |
|-----------|------|-----------|
| `status` | 字符串 | `PullEvent::Status` |
| `status: "success"` | 特殊值 | 额外生成 `PullEvent::Success` |
| `digest` | 字符串 | `PullEvent::ChunkProgress.digest` |
| `total` | 整数 | `PullEvent::ChunkProgress.total` |
| `completed` | 整数 | `PullEvent::ChunkProgress.completed` |

### 3. 多事件生成

单个 JSON 对象可能生成多个事件：
- `{"status": "success"}` → `[Status("success"), Success]`
- `{"status": "verifying", "digest": "sha256:abc", "total": 100}` → `[Status("verifying"), ChunkProgress {...}]`

## 具体技术实现

### 核心解析逻辑

```rust
pub(crate) fn pull_events_from_value(value: &JsonValue) -> Vec<PullEvent> {
    let mut events = Vec::new();
    
    // 1. 解析 status 字段
    if let Some(status) = value.get("status").and_then(|s| s.as_str()) {
        events.push(PullEvent::Status(status.to_string()));
        if status == "success" {
            events.push(PullEvent::Success);
        }
    }
    
    // 2. 解析 digest 字段
    let digest = value
        .get("digest")
        .and_then(|d| d.as_str())
        .unwrap_or("")
        .to_string();
    
    // 3. 解析进度字段
    let total = value.get("total").and_then(JsonValue::as_u64);
    let completed = value.get("completed").and_then(JsonValue::as_u64);
    
    // 4. 如果有进度信息，生成 ChunkProgress 事件
    if total.is_some() || completed.is_some() {
        events.push(PullEvent::ChunkProgress {
            digest,
            total,
            completed,
        });
    }
    
    events
}
```

### 设计决策

1. **digest 默认为空字符串**：即使 JSON 中没有 digest，也使用空字符串而非 `Option<String>`，简化调用方处理
2. **宽松解析**：`total` 和 `completed` 是独立的 `Option<u64>`，允许部分进度信息
3. **事件累积**：使用 `Vec<PullEvent>` 返回，支持单个 JSON 生成多个事件

### Ollama Pull 流格式示例

```jsonl
{"status": "pulling manifest"}
{"status": "downloading", "digest": "sha256:abc123", "total": 1073741824, "completed": 104857600}
{"status": "downloading", "digest": "sha256:abc123", "total": 1073741824, "completed": 209715200}
{"status": "verifying sha256:abc123"}
{"status": "writing manifest"}
{"status": "success"}
```

每行被独立解析为一个或多个 `PullEvent`。

## 关键代码路径与文件引用

### 模块依赖

```
parser.rs
    └── pull.rs (PullEvent)
```

`parser.rs` 仅依赖于 `pull.rs` 中的 `PullEvent` 类型定义。

### 调用方

| 调用方 | 调用函数 | 场景 |
|--------|----------|------|
| `client.rs` | `pull_events_from_value` | `pull_model_stream` 中解析流数据 |

### 调用链

```
client.rs::pull_model_stream
    └── 读取字节流，按行分割
            └── parser.rs::pull_events_from_value
                    └── 生成 PullEvent 流
                            └── pull.rs::PullProgressReporter::on_event
```

## 依赖与外部交互

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `serde_json::Value` | JSON 数据类型 |

### 内部依赖

```rust
use crate::pull::PullEvent;
```

仅依赖于 `pull.rs` 模块的 `PullEvent` 枚举。

## 风险、边界与改进建议

### 已知风险

1. **digest 为空**：当 JSON 中没有 digest 时，使用空字符串可能导致进度跟踪问题（多个层同时下载时无法区分）。

2. **整数溢出**：`as_u64` 转换在值超出 u64 范围时会返回 `None`， silently 丢失进度信息。

3. **未知字段忽略**：任何未识别的 JSON 字段都被静默忽略，可能错过重要的新字段。

### 边界情况

| 场景 | 行为 |
|------|------|
| 空 JSON `{}` | 返回空向量 `[]` |
| 只有 digest | `ChunkProgress { digest, total: None, completed: None }` |
| 只有 total/completed | `ChunkProgress { digest: "", ... }` |
| status 为 null | 不生成 Status 事件 |
| completed > total | 原样传递，不验证 |

### 改进建议

1. **结构化错误处理**：当前使用 `Option` 链，可考虑在解析失败时返回错误而非静默忽略。

2. **digest 验证**：添加 SHA256 格式验证，确保 digest 符合预期格式。

3. **进度验证**：检查 `completed <= total`，在违反时记录警告或修正。

4. **未知字段警告**：在 debug 模式下记录未识别的字段，帮助发现 API 变更。

5. **零拷贝优化**：当前使用 `to_string()` 分配新字符串，如果 `PullEvent` 支持 `Cow<str>` 可减少分配。

6. **类型安全**：考虑使用 `serde` 派生结构体替代手动解析，提高类型安全性：

```rust
#[derive(Deserialize)]
struct PullUpdate {
    status: Option<String>,
    digest: Option<String>,
    #[serde(deserialize_with = "deserialize_u64_or_null")]
    total: Option<u64>,
    #[serde(deserialize_with = "deserialize_u64_or_null")]
    completed: Option<u64>,
}
```

### 测试覆盖

测试模块包含两个测试函数：

1. `test_pull_events_decoder_status_and_success`：验证 status 解析和 Success 事件生成
2. `test_pull_events_decoder_progress`：验证 ChunkProgress 解析，包括部分字段场景

测试使用 `assert_matches` crate 进行模式匹配验证，确保类型正确性。

### 与 LM Studio 对比

LM Studio 没有对应的解析模块，因为其 API 返回的是标准 OpenAI 兼容格式，不需要自定义解析逻辑。Ollama 使用专有的 pull 流格式，因此需要此解析层。

| 特性 | Ollama | LM Studio |
|------|--------|-----------|
| 自定义解析 | 需要（`parser.rs`）| 不需要 |
| 流格式 | 自定义 JSON Lines | OpenAI 兼容 |
| 进度粒度 | 层级别（digest）| 无原生进度 |
