# safety_check_downgrade.rs 研究文档

## 场景与职责

`safety_check_downgrade.rs` 是 Codex Core 的安全相关测试文件，专注于验证 **模型降级（Model Downgrade）检测和警告机制**。当用户请求高风险模型（如 `gpt-5.3-codex`）但服务器因安全策略返回较低能力模型（如 `gpt-5.2`）时，系统需要：

- 检测 `OpenAI-Model` 响应头与请求模型的不匹配
- 向用户发出警告通知
- 在对话历史中记录警告信息
- 确保每轮对话只发出一次警告（避免重复）

这是 Codex 安全架构的重要组成部分，确保用户知晓模型能力的变化。

## 功能点目的

### 1. 模型头不匹配警告 (`openai_model_header_mismatch_emits_warning_event_and_warning_item`)
验证当响应头的 `OpenAI-Model` 与请求模型不一致时的完整警告流程：
- 模拟请求 `gpt-5.3-codex`，服务器返回 `gpt-5.2`
- 验证 `ModelReroute` 事件（包含 `from_model`, `to_model`, `reason`）
- 验证 `Warning` 事件包含模型信息
- 验证警告作为 `RawResponseItem` 插入对话历史

### 2. 响应模型字段不匹配 (`response_model_field_mismatch_emits_warning_when_header_matches_requested`)
测试当响应体中的 `response.model` 字段与请求匹配，但 `OpenAI-Model` 头不匹配时的警告：
- 响应体声称使用请求模型，但头部显示实际使用降级模型
- 验证仍能正确检测并警告

### 3. 单轮单次警告 (`openai_model_header_mismatch_only_emits_one_warning_per_turn`)
确保每轮对话中只发出一次警告，即使涉及多个工具调用：
- 第一轮：模型调用 `shell_command` 工具
- 第二轮：模型返回完成消息
- 验证两轮中只产生一次警告

### 4. 大小写不敏感 (`openai_model_header_casing_only_mismatch_does_not_warn`)
验证模型名称大小写差异不触发警告：
- 请求 `gpt-5.3-codex`，头部返回 `GPT-5.3-CODEX`
- 验证不触发 `ModelReroute` 或 `Warning` 事件

## 具体技术实现

### 关键数据结构

```rust
// 模型重路由事件（来自 codex_protocol::protocol）
pub struct ModelRerouteEvent {
    pub from_model: String,        // 请求的模型
    pub to_model: String,          // 实际使用的模型
    pub reason: ModelRerouteReason, // 重路由原因
}

pub enum ModelRerouteReason {
    HighRiskCyberActivity,  // 高风险网络活动
    // ... 其他原因
}

// 警告事件
pub struct WarningEvent {
    pub message: String,
}
```

### 检测流程

```
OpenAI API 响应
  ├─ 检查 OpenAI-Model 响应头
  │    ├─ 与请求模型比较（不区分大小写）
  │    ├─ 不匹配 → 创建 ModelRerouteEvent
  │    │              ├─ 发送 EventMsg::ModelReroute
  │    │              ├─ 发送 EventMsg::Warning
  │    │              └─ 插入 RawResponseItem 到对话历史
  │    └─ 匹配 → 正常处理
  └─ 继续处理响应体
```

### 测试中的 Mock 响应构建

```rust
// 构建带自定义响应头的 SSE 响应
let response = sse_response(sse_completed("resp-1"))
    .insert_header("OpenAI-Model", SERVER_MODEL);
let _mock = mount_response_once(&server, response).await;

// 序列响应（多轮对话）
let first_response = sse_response(sse(vec![
    ev_response_created("resp-1"),
    ev_function_call("call-1", "shell_command", &args),
    ev_completed("resp-1"),
])).insert_header("OpenAI-Model", SERVER_MODEL);
```

### 警告消息格式

```rust
// 警告消息包含模型信息
assert!(warning.message.contains(REQUESTED_MODEL));  // "gpt-5.3-codex"
assert!(warning.message.contains(SERVER_MODEL));      // "gpt-5.2"
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_protocol::protocol::{ModelRerouteEvent, WarningEvent}` | 事件定义 |
| `codex_protocol::protocol::ModelRerouteReason` | 重路由原因枚举 |
| `core_test_support::responses::*` | Mock 响应构建 |
| `core_test_support::wait_for_event` | 异步事件等待 |

### 外部交互

| 组件 | 交互方式 |
|------|----------|
| WireMock | 模拟 OpenAI API，注入 `OpenAI-Model` 响应头 |
| OpenAI API | 实际场景中的响应头来源 |

## 风险、边界与改进建议

### 当前风险

1. **误报风险**：大小写敏感处理不当可能导致误报或漏报
2. **重复警告**：多工具调用场景下需要确保警告去重逻辑正确
3. **国际化**：警告消息为英文，未考虑本地化

### 边界情况

1. **模型别名**：同一模型的不同名称（如 `gpt-4` 和 `gpt-4-0613`）
2. **预览版本**：`gpt-5.3-codex-preview` 与 `gpt-5.3-codex` 的比较
3. **组织特定模型**：自定义模型名称的处理
4. **无响应头**：服务器未返回 `OpenAI-Model` 头时的处理

### 改进建议

1. **智能比较**：
   - 使用模型版本号解析，而非字符串比较
   - 建立模型能力层级图，检测降级而非任意差异

2. **用户体验**：
   - 添加可操作的指导（如"联系管理员升级权限"）
   - 提供模型能力差异的详细对比

3. **可观测性**：
   - 记录重路由事件到分析系统
   - 添加指标监控（重路由频率、原因分布）

4. **测试扩展**：
   - 测试模型版本号解析逻辑
   - 测试极端长的模型名称
   - 测试特殊字符在模型名中的处理

5. **配置化**：
   - 允许配置哪些模型差异需要警告
   - 支持组织自定义模型映射

### 相关文件引用

- `codex-rs/core/src/client.rs` - HTTP 客户端，处理响应头
- `codex-rs/core/src/client_common.rs` - 模型检测逻辑
- `codex-rs/protocol/src/protocol.rs` - 事件定义
- `codex-rs/core/src/safety.rs` - 安全检查相关逻辑
