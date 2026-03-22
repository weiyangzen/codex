# collaboration_mode_list.rs 研究文档

## 场景与职责

`collaboration_mode_list.rs` 是 Codex App Server v2 API 的集成测试文件，专注于测试**协作模式(Collaboration Mode)列表查询**功能。该文件验证：

1. **默认预设模式返回** - 确认服务器返回预定义的协作模式预设（如 plan、default 等）
2. **API 契约稳定性** - 保持协作模式列表的 API 响应格式稳定
3. **模式属性完整性** - 验证每个模式包含名称、模式类型、模型和推理努力度设置

## 功能点目的

### 1. 协作模式预设管理
协作模式(Collaboration Mode)是 Codex 的核心功能，定义了 Agent 的行为方式：

- **Plan 模式**：用于规划和设计阶段
- **Default 模式**：标准执行模式
- **Ask 模式**：询问确认模式
- **Code 模式**：代码生成模式

每个模式包含：
- `name`：模式显示名称
- `mode`：模式类型枚举（`ModeKind`）
- `model`：使用的 AI 模型
- `reasoning_effort`：推理努力度设置

### 2. 测试目标
- 验证 `collaborationMode/list` RPC 方法可用
- 确认返回的预设列表顺序稳定
- 确保模式属性完整且符合预期

## 具体技术实现

### 关键数据结构

```rust
// 请求参数（空结构体，表示无参数）
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CollaborationModeListParams {}

// 响应结构
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CollaborationModeListResponse {
    pub data: Vec<CollaborationModeMask>,
}

// 协作模式掩码
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CollaborationModeMask {
    pub name: String,
    pub mode: Option<ModeKind>,
    pub model: Option<String>,
    #[serde(rename = "reasoning_effort")]
    #[ts(rename = "reasoning_effort")]
    pub reasoning_effort: Option<Option<ReasoningEffort>>,
}
```

### 测试实现

```rust
#[tokio::test]
async fn list_collaboration_modes_returns_presets() -> Result<()> {
    // 1. 创建临时 CODEX_HOME
    let codex_home = TempDir::new()?;
    let mut mcp = McpProcess::new(codex_home.path()).await?;

    // 2. 初始化 MCP 连接
    timeout(DEFAULT_TIMEOUT, mcp.initialize()).await??;

    // 3. 发送 list 请求
    let request_id = mcp
        .send_list_collaboration_modes_request(CollaborationModeListParams::default())
        .await?;

    // 4. 读取响应
    let response: JSONRPCResponse = timeout(
        DEFAULT_TIMEOUT,
        mcp.read_stream_until_response_message(RequestId::Integer(request_id)),
    )
    .await??;

    // 5. 解析响应
    let CollaborationModeListResponse { data: items } =
        to_response::<CollaborationModeListResponse>(response)?;

    // 6. 验证结果
    let expected: Vec<CollaborationModeMask> = builtin_collaboration_mode_presets()
        .into_iter()
        .map(|preset| CollaborationModeMask { ... })
        .collect();
    assert_eq!(expected, items);
    Ok(())
}
```

### 预设数据来源

```rust
// 来自 codex_core::test_support::builtin_collaboration_mode_presets
codex_core::test_support::builtin_collaboration_mode_presets()
```

该函数返回 Codex 核心库中定义的默认协作模式预设列表。

## 关键代码路径与文件引用

### 测试文件
- `/codex-rs/app-server/tests/suite/v2/collaboration_mode_list.rs` - 本测试文件

### 协议定义
- `/codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `CollaborationModeListParams` (行 1797-1801)
  - `CollaborationModeListResponse` (行 1827-1833)
  - `CollaborationModeMask` (行 1803-1825)

### 核心库定义
- `/codex-rs/core/src/test_support/mod.rs` - `builtin_collaboration_mode_presets`
- `/codex-rs/core/src/config_types.rs` - `CollaborationModeMask` 核心定义

### 测试支持
- `/codex-rs/app-server/tests/common/mcp_process.rs`:
  - `send_list_collaboration_modes_request` (行 512-519)

## 依赖与外部交互

### 内部依赖
1. **McpProcess** - 管理 codex-app-server 子进程
2. **JSON-RPC 协议** - 请求/响应通信
3. **核心库预设** - `builtin_collaboration_mode_presets()`

### 无外部服务依赖
该测试是纯粹的本地测试，不依赖：
- 网络连接
- Mock 服务器
- 外部 API

### 测试流程
```
┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   测试代码   │────▶│  McpProcess     │────▶│ codex-app-server│
│             │     │  (子进程管理)    │     │  (被测服务)      │
└─────────────┘     └─────────────────┘     └─────────────────┘
       │                                            │
       │         JSON-RPC: collaborationMode/list   │
       │◄───────────────────────────────────────────│
       │                                            │
       │         返回 CollaborationModeListResponse │
       │◄───────────────────────────────────────────│
       │                                            │
       ▼                                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 验证: 比较返回的 presets 与 builtin_collaboration_mode_presets() │
└─────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 风险分析

1. **低覆盖率风险**
   - 当前仅有一个基础测试用例
   - 未测试边界情况（如空列表、错误响应）
   - 未测试模式属性的有效性验证

2. **依赖核心库内部实现**
   - 测试直接依赖 `builtin_collaboration_mode_presets()`
   - 如果核心库更改预设，测试可能失败
   - 这是有意为之，确保 API 契约一致性

3. **无并发测试**
   - 未测试并发调用 `collaborationMode/list`
   - 未测试初始化前调用的错误处理

### 边界情况

1. **空预设列表**
   - 理论上可能返回空列表
   - 当前测试未覆盖此场景

2. **字段缺失**
   - `mode`, `model`, `reasoning_effort` 都是 `Option<T>`
   - 测试未验证部分字段缺失的情况

3. **重复模式名称**
   - 未测试列表中包含重复名称的模式

### 改进建议

1. **增加测试覆盖**
   ```rust
   // 建议添加：验证非空列表
   #[tokio::test]
   async fn list_collaboration_modes_returns_non_empty() {
       // 验证返回至少包含 plan 和 default 模式
   }

   // 建议添加：验证模式名称唯一性
   #[tokio::test]
   async fn list_collaboration_modes_has_unique_names() {
       // 验证无重复名称
   }

   // 建议添加：未初始化错误
   #[tokio::test]
   async fn list_collaboration_modes_rejects_when_not_initialized() {
       // 验证初始化前调用返回错误
   }
   ```

2. **属性验证增强**
   ```rust
   // 验证每个模式至少包含 name
   for item in &items {
       assert!(!item.name.is_empty(), "mode name should not be empty");
   }
   ```

3. **文档完善**
   - 添加协作模式的业务说明
   - 解释每种 ModeKind 的用途
   - 添加预设变更的测试策略说明

4. **性能考虑**
   - 当前测试使用 10 秒超时
   - 可考虑缩短，因为该操作是本地计算

### 相关测试模式

该测试遵循 App Server v2 API 测试的标准模式：
1. 创建临时 `CODEX_HOME`
2. 启动 `McpProcess`
3. 初始化 MCP 连接
4. 发送 RPC 请求
5. 验证响应

与其他列表测试（`app_list.rs`, `model_list.rs`）相比：
- 更简单：无分页、无过滤、无缓存
- 更稳定：无外部依赖
- 更轻量：无 Mock 服务器
