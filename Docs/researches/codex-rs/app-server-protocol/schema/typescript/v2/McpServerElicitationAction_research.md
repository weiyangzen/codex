# McpServerElicitationAction 研究文档

## 场景与职责

`McpServerElicitationAction` 是 MCP (Model Context Protocol) 服务器交互式请求的用户响应动作枚举。它定义了用户在处理 MCP 服务器发起的 elicitation 请求时可以采取的操作类型。

当 MCP 服务器需要用户输入或确认时（例如 OAuth 授权、配置确认、选项选择等），客户端会展示相应的 UI，用户通过选择这些动作来响应服务器的请求。

## 功能点目的

1. **接受请求**: `accept` - 用户同意并继续处理 MCP 服务器的请求
2. **拒绝请求**: `decline` - 用户拒绝请求，但允许继续当前对话回合
3. **取消操作**: `cancel` - 用户取消请求，同时中断当前对话回合

这三个动作提供了完整的用户交互控制，支持不同的业务场景需求。

## 具体技术实现

### 数据类型定义

```typescript
export type McpServerElicitationAction = "accept" | "decline" | "cancel";
```

### 动作语义详解

| 动作值 | 语义 | 对对话的影响 |
|--------|------|--------------|
| `accept` | 用户接受并确认 | 继续正常处理流程 |
| `decline` | 用户拒绝但不终止 | 拒绝当前请求，但对话继续 |
| `cancel` | 用户取消并终止 | 拒绝请求并中断当前对话回合 |

### 生成信息

该文件为自动生成代码，由 [ts-rs](https://github.com/Aleph-Alpha/ts-rs) 工具从 Rust 源代码生成。

对应的 Rust 类型定义：
```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
pub enum McpServerElicitationAction {
    Accept,
    Decline,
    Cancel,
}
```

### 序列化规则
- Rust 端使用 `#[serde(rename_all = "camelCase")]` 进行序列化
- TypeScript 端接收小驼峰格式的字符串值

## 关键代码路径与文件引用

### TypeScript 定义
- **文件**: `codex-rs/app-server-protocol/schema/typescript/v2/McpServerElicitationAction.ts`
- **索引导出**: `codex-rs/app-server-protocol/schema/typescript/v2/index.ts`

### Rust 源文件
- **文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **搜索关键词**: `McpServerElicitationAction`

### 响应类型
- **文件**: `McpServerElicitationRequestResponse.ts`
- **关系**: 响应中的 `action` 字段使用此类型

### 核心使用位置

1. **App Server 事件处理**
   - 文件: `codex-rs/app-server/src/bespoke_event_handling.rs`
   - 用途: 处理 MCP 服务器 elicitation 响应

2. **TUI 应用服务器**
   - 文件: `codex-rs/tui_app_server/src/app/app_server_requests.rs`
   - 用途: 处理用户通过 TUI 的响应

3. **Exec 模块**
   - 文件: `codex-rs/exec/src/lib.rs`
   - 用途: 命令行执行时的交互处理

4. **测试套件**
   - 文件: `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs`
   - 用途: 验证 elicitation 流程

## 依赖与外部交互

### 协议流程

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  MCP Server │────▶│  App Server │────▶│ Client UI   │
│  (请求输入)  │     │ (转发请求)   │     │ (展示界面)   │
└─────────────┘     └─────────────┘     └──────┬──────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │  用户选择    │
                                        │(accept/decline│
                                        │  /cancel)    │
                                        └──────┬──────┘
                                               │
┌─────────────┐     ┌─────────────┐     ┌──────┴──────┐
│  MCP Server │◀────│  App Server │◀────│  响应处理    │
│ (接收响应)   │     │ (处理响应)   │     │             │
└─────────────┘     └─────────────┘     └─────────────┘
```

### 相关协议定义

**ServerRequest (服务器请求)**:
```typescript
{
  method: "mcpServer/elicitation/request",
  params: McpServerElicitationRequestParams
}
```

**ClientResponse (客户端响应)**:
```typescript
{
  action: McpServerElicitationAction,  // "accept" | "decline" | "cancel"
  // ... 其他响应数据
}
```

### 下游依赖

1. **UI 组件**: 需要在界面上提供对应三个动作的按钮或选项
2. **状态管理**: 根据动作值决定后续流程走向
3. **日志记录**: 记录用户选择用于审计和分析

## 风险、边界与改进建议

### 已知风险

1. **动作语义混淆**: `decline` 和 `cancel` 的区别可能让用户困惑
   - `decline`: 拒绝但继续对话
   - `cancel`: 拒绝并中断回合
   
2. **默认值缺失**: 类型定义没有指定默认值，需要调用方明确处理

3. **扩展性限制**: 当前只有三种动作，未来扩展可能需要破坏性变更

### 边界情况

1. **网络中断**: 用户选择后网络中断，需要处理重试或超时
2. **并发请求**: 多个 elicitation 请求同时到达时的处理
3. **会话过期**: 用户长时间未响应导致会话超时

### 改进建议

1. **添加说明文档**: 在 UI 上明确区分 `decline` 和 `cancel` 的行为差异
2. **默认值策略**: 考虑添加 `defaultAction` 字段到请求参数中
3. **超时处理**: 添加超时后的默认动作配置
4. **动作扩展**: 考虑预留扩展空间，如 `retry`、`skip` 等动作
5. **用户教育**: 在首次使用时提供动作选择的引导说明

### 测试建议

1. **单元测试**: 验证每种动作的序列化和反序列化
2. **集成测试**: 测试完整的 elicitation 请求-响应流程
3. **边界测试**: 测试无效动作值的处理
4. **UI 测试**: 验证三种动作在界面上的正确展示和交互

### 相关代码示例

```rust
// Rust 端处理示例 (app-server/src/bespoke_event_handling.rs)
match action {
    McpServerElicitationAction::Accept => {
        // 处理接受逻辑
    }
    McpServerElicitationAction::Decline => {
        // 处理拒绝但继续逻辑
    }
    McpServerElicitationAction::Cancel => {
        // 处理取消并中断逻辑
    }
}
```
