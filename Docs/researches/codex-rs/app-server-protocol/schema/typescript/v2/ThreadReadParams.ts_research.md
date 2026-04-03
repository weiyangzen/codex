# ThreadReadParams 研究文档

## 场景与职责

`ThreadReadParams` 是 App-Server Protocol v2 API 中 `thread/read` RPC 方法的请求参数类型。该类型用于客户端向服务器请求获取特定线程（Thread）的详细信息。

在 Codex 应用架构中，线程是用户与 AI 助手对话的容器。客户端需要获取线程信息以：
- 显示线程元数据（预览、创建时间、状态等）
- 恢复之前的对话上下文
- 展示线程历史记录（当 `includeTurns` 为 true 时）

## 功能点目的

### 核心功能
1. **线程标识**：通过 `threadId` 字段指定要读取的线程
2. **历史控制**：通过 `includeTurns` 布尔字段控制是否包含完整的对话轮次（turns）历史

### 设计考量
- **性能优化**：`includeTurns` 默认为 `false`，避免在仅需线程元数据时传输大量历史数据
- **灵活性**：客户端可以根据需要选择是否加载完整对话历史

## 具体技术实现

### Rust 结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadReadParams {
    pub thread_id: String,
    /// When true, include turns and their items from rollout history.
    #[serde(default)]
    pub include_turns: bool,
}
```

### TypeScript 类型定义

```typescript
interface ThreadReadParams {
  threadId: string;
  includeTurns: boolean;
}
```

### 字段说明

| 字段名 | 类型 | 必填 | 默认值 | 说明 |
|--------|------|------|--------|------|
| `threadId` | `string` | 是 | - | 目标线程的唯一标识符 |
| `includeTurns` | `boolean` | 否 | `false` | 是否包含对话轮次历史 |

### 序列化行为
- 使用 `camelCase` 命名规范进行序列化（`#[serde(rename_all = "camelCase")]`）
- `include_turns` 字段使用 `#[serde(default)]`，省略时默认为 `false`

## 关键代码路径与文件引用

### 定义位置
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**：3045-3053

### 相关类型
- `ThreadReadResponse`（3055-3060行）：对应的响应类型，包含 `Thread` 对象
- `Thread`（3475-3512行）：线程数据结构，当 `includeTurns=true` 时其 `turns` 字段会被填充

### 使用场景
- **API 端点**：`thread/read` RPC 方法
- **测试文件**：`codex-rs/app-server/tests/suite/v2/thread_read.rs`
  - `thread_read_returns_summary_without_turns`：测试不包含 turns 的读取
  - `thread_read_can_include_turns`：测试包含 turns 的读取
  - `thread_read_include_turns_rejects_unmaterialized_loaded_thread`：测试未物化线程的限制

### 测试示例
```rust
let read_id = mcp
    .send_thread_read_request(ThreadReadParams {
        thread_id: conversation_id.clone(),
        include_turns: true,  // 或 false
    })
    .await?;
```

## 依赖与外部交互

### 依赖关系
- `serde`：用于序列化/反序列化
- `schemars`：用于 JSON Schema 生成
- `ts-rs`：用于 TypeScript 类型生成

### 上游依赖
- `threadId` 必须对应一个已存在的线程（无论是已加载还是未加载状态）
- 对于未物化的已加载线程（刚创建但未保存），`includeTurns=true` 会导致错误

### 下游影响
- 影响 `ThreadReadResponse` 的构造
- 影响 `Thread` 结构体中 `turns` 字段的填充

## 风险、边界与改进建议

### 已知限制
1. **未物化线程限制**：对于刚创建尚未物化到磁盘的线程，设置 `includeTurns=true` 会返回错误：
   ```
   "includeTurns is unavailable before first user message"
   ```
   （见 `thread_read.rs` 第398-405行）

2. **性能考虑**：当线程包含大量历史对话时，`includeTurns=true` 可能导致较大的响应负载

### 边界情况
- 线程 ID 不存在：返回错误
- 线程已归档：可以正常读取
- 线程处于加载状态：可以读取，但 `includeTurns` 可能受限

### 改进建议
1. **分页支持**：对于历史记录较多的线程，考虑添加分页参数（cursor/limit）替代简单的布尔开关
2. **选择性字段**：考虑支持字段选择机制，允许客户端指定需要的具体字段子集
3. **缓存策略**：在客户端实现 `Thread` 对象的本地缓存，减少重复读取

### 相关配置
- 无直接相关配置项
- 间接影响：线程存储路径由 `CODEX_HOME` 环境变量决定
