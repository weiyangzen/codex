# FeedbackUploadParams 研究报告

## 1. 场景与职责

### 使用场景
`FeedbackUploadParams` 是 Codex App-Server Protocol v2 API 中用于**用户反馈上传**功能的请求参数结构。该结构定义了客户端向服务器提交用户反馈时所需携带的完整信息。

### 主要职责
- **反馈分类收集**：允许用户对 AI 生成的内容或交互体验进行分类标记（如"有帮助"、"不准确"、"有害内容"等）
- **上下文信息关联**：支持将反馈与特定会话（thread）关联，便于问题追踪和分析
- **日志收集控制**：提供是否包含系统日志的选项，帮助开发者诊断问题
- **扩展日志支持**：允许附加额外的日志文件路径，用于更详细的调试场景

### 典型使用流程
1. 用户在客户端界面完成一次交互后，点击"反馈"按钮
2. 客户端弹出反馈表单，用户选择分类并填写原因
3. 客户端构造 `FeedbackUploadParams` 并通过 `feedback/upload` RPC 方法发送给服务器
4. 服务器接收反馈数据，可选择性地收集相关日志并存储到分析系统

---

## 2. 功能点目的

### 核心功能目标

| 功能 | 目的说明 |
|------|----------|
| **classification** | 对反馈进行标准化分类，支持数据统计和趋势分析 |
| **reason** | 提供自由文本字段，让用户详细描述问题或建议 |
| **threadId** | 将会话上下文与反馈关联，便于复现和调查问题 |
| **includeLogs** | 控制是否自动包含系统运行日志，平衡隐私与调试需求 |
| **extraLogFiles** | 支持上传额外的自定义日志文件，用于特定场景的深度诊断 |

### 业务价值
1. **产品质量改进**：通过结构化反馈收集，识别模型输出的系统性问题
2. **用户体验优化**：了解用户在使用过程中遇到的具体障碍
3. **问题快速定位**：通过日志关联，缩短从反馈到修复的时间周期
4. **合规与安全**：及时发现并处理有害内容或安全漏洞

---

## 3. 具体技术实现

### 3.1 数据结构定义

#### JSON Schema 定义
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "classification": { "type": "string" },
    "extraLogFiles": {
      "items": { "type": "string" },
      "type": ["array", "null"]
    },
    "includeLogs": { "type": "boolean" },
    "reason": { "type": ["string", "null"] },
    "threadId": { "type": ["string", "null"] }
  },
  "required": ["classification", "includeLogs"],
  "title": "FeedbackUploadParams",
  "type": "object"
}
```

#### Rust 结构体定义
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FeedbackUploadParams {
    pub classification: String,
    #[ts(optional = nullable)]
    pub reason: Option<String>,
    #[ts(optional = nullable)]
    pub thread_id: Option<String>,
    pub include_logs: bool,
    #[ts(optional = nullable)]
    pub extra_log_files: Option<Vec<PathBuf>>,
}
```

### 3.2 字段详细说明

| 字段名 | 类型 | 必需 | 序列化名称 | 说明 |
|--------|------|------|------------|------|
| `classification` | `String` | ✅ | `classification` | 反馈分类标签，如 "thumbs_up", "thumbs_down", "inaccurate" 等 |
| `reason` | `Option<String>` | ❌ | `reason` | 用户填写的详细反馈原因，可为空 |
| `thread_id` | `Option<String>` | ❌ | `threadId` | 关联的会话 ID，用于上下文追溯 |
| `include_logs` | `bool` | ✅ | `includeLogs` | 是否包含系统自动收集的日志 |
| `extra_log_files` | `Option<Vec<PathBuf>>` | ❌ | `extraLogFiles` | 额外日志文件路径列表 |

### 3.3 序列化特性

- **命名规范**：使用 `camelCase` 进行 JSON 序列化（`#[serde(rename_all = "camelCase")]`）
- **TypeScript 导出**：通过 `ts-rs` 库自动生成 TypeScript 类型定义，导出到 `v2/` 目录
- **可选字段处理**：可选字段使用 `#[ts(optional = nullable)]` 注解，在 TypeScript 中表现为 `T | null` 类型
- **JSON Schema 生成**：通过 `schemars` 库自动生成 JSON Schema，用于客户端验证和文档生成

### 3.4 在协议中的位置

```
ClientRequest::FeedbackUpload => "feedback/upload" {
    params: v2::FeedbackUploadParams,
    response: v2::FeedbackUploadResponse,
}
```

该定义位于 `common.rs` 的 `client_request_definitions!` 宏中，表示这是一个**客户端发起的服务器请求**。

---

## 4. 关键代码路径与文件引用

### 4.1 核心定义文件

| 文件路径 | 作用 |
|----------|------|
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（约第 2100-2109 行） |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求定义宏，注册 `feedback/upload` 方法（约第 451-454 行） |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/FeedbackUploadParams.json` | 自动生成的 JSON Schema |

### 4.2 代码生成流程

```
v2.rs (Rust 结构体)
    ↓ (ts-rs 宏展开)
TypeScript 定义文件 → codex-rs/app-server-protocol/bindings/v2/
    ↓ (schemars 宏展开)
JSON Schema 文件 → codex-rs/app-server-protocol/schema/json/v2/
```

### 4.3 相关类型

- **响应类型**：`FeedbackUploadResponse` - 包含上传后的 `thread_id` 确认
- **请求枚举**：`ClientRequest::FeedbackUpload` - 包装参数和请求 ID

### 4.4 使用示例

```rust
// 构造反馈上传请求
let params = FeedbackUploadParams {
    classification: "thumbs_down".to_string(),
    reason: Some("The code suggestion was incorrect".to_string()),
    thread_id: Some("thread-123".to_string()),
    include_logs: true,
    extra_log_files: None,
};

let request = ClientRequest::FeedbackUpload {
    request_id: RequestId::Integer(1),
    params,
};
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `serde` | 序列化/反序列化支持 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型定义生成 |
| `std::path::PathBuf` | 日志文件路径表示 |

### 5.2 协议依赖

- **请求 ID**：使用 `crate::RequestId` 进行请求追踪
- **响应类型**：与 `FeedbackUploadResponse` 配对使用

### 5.3 外部系统交互

```
┌─────────────┐     feedback/upload      ┌─────────────┐
│   Client    │ ───────────────────────→ │   Server    │
│  (TUI/CLI)  │  FeedbackUploadParams    │ (AppServer) │
└─────────────┘                          └──────┬──────┘
                                                │
                                                ↓
                                       ┌─────────────────┐
                                       │  Feedback Store │
                                       │ (Analytics DB)  │
                                       └─────────────────┘
                                                │
                                                ↓
                                       ┌─────────────────┐
                                       │  Log Collector  │
                                       │  (if enabled)   │
                                       └─────────────────┘
```

### 5.4 构建依赖

- **Bazel**：`BUILD.bazel` 文件定义了编译目标和依赖关系
- **Cargo**：`Cargo.toml` 中的 `app-server-protocol` crate

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

| 风险类别 | 具体描述 | 缓解措施 |
|----------|----------|----------|
| **隐私泄露** | `includeLogs` 可能包含敏感信息（文件路径、环境变量） | 在服务器端实现日志脱敏过滤器 |
| **文件遍历** | `extraLogFiles` 可能被恶意利用读取任意文件 | 服务器端验证路径白名单，限制可访问目录 |
| **数据滥用** | `classification` 字段自由文本可能导致分类混乱 | 提供预定义分类枚举，限制可选值 |
| **存储压力** | 大量反馈和日志可能导致存储成本激增 | 实现反馈采样策略和日志保留策略 |

### 6.2 边界情况

1. **空分类字符串**：虽然 schema 要求 `classification` 必填，但未限制非空，可能导致空字符串分类
2. **超长 reason**：自由文本字段无长度限制，可能导致存储问题或处理延迟
3. **无效 threadId**：传入不存在的 thread ID，服务器需要优雅处理
4. **不可读日志文件**：`extraLogFiles` 中的路径可能不存在或无权限读取

### 6.3 改进建议

#### 短期改进
1. **分类枚举化**：将 `classification` 从自由字符串改为枚举类型
   ```rust
   pub enum FeedbackClassification {
       ThumbsUp,
       ThumbsDown,
       Inaccurate,
       Harmful,
       Other,
   }
   ```

2. **添加长度限制**：为 `reason` 字段添加最大长度验证（如 2000 字符）

3. **增强日志控制**：细化 `includeLogs` 为更细粒度的控制选项
   ```rust
   pub struct LogInclusionOptions {
       pub system_logs: bool,
       pub conversation_history: bool,
       pub command_outputs: bool,
   }
   ```

#### 长期改进
1. **反馈附件支持**：扩展支持上传截图或其他附件类型
2. **反馈状态追踪**：添加反馈处理状态查询接口
3. **批量反馈接口**：支持一次性提交多条反馈，减少网络往返
4. **匿名反馈模式**：支持不关联 thread_id 的匿名反馈，保护用户隐私

### 6.4 测试建议

- **单元测试**：验证序列化/反序列化的正确性
- **边界测试**：测试空字符串、超长文本、特殊字符处理
- **集成测试**：验证端到端的反馈提交流程
- **安全测试**：验证路径遍历防护和敏感信息过滤

---

## 附录：相关文件引用

```
codex-rs/
├── app-server-protocol/
│   ├── src/
│   │   └── protocol/
│   │       ├── v2.rs                    # 结构体定义
│   │       └── common.rs                # 请求方法注册
│   └── schema/
│       └── json/
│           └── v2/
│               └── FeedbackUploadParams.json    # JSON Schema
└── ...
```
