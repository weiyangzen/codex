# ReviewStartResponse.json 研究文档

## 场景与职责

`ReviewStartResponse` 是 Codex App-Server Protocol v2 API 中 `review/start` 方法的响应结构，用于返回代码审查启动的结果。该响应包含审查线程 ID 和初始回合（Turn）信息，支持内联和分离两种审查模式的返回结果。

## 功能点目的

1. **审查启动确认**: 确认代码审查请求已成功处理并返回审查会话标识
2. **线程信息返回**: 返回审查运行的线程 ID（内联审查为原线程，分离审查为新线程）
3. **初始状态提供**: 返回初始 Turn 信息，包含审查项和状态
4. **模式透明**: 统一响应格式，不区分内联或分离审查模式

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReviewStartResponse {
    pub review_thread_id: String,
    pub turn: Turn,
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `reviewThreadId` | string | 是 | 审查运行的线程 ID |
| `turn` | Turn | 是 | 初始回合信息 |

### Turn 类型定义

**Turn** 结构体：
- `id`: string - 回合唯一标识
- `status`: TurnStatus - 回合状态（completed/interrupted/failed/inProgress）
- `items`: ThreadItem[] - 回合包含的线程项（仅在 thread/resume 或 thread/fork 响应中填充）
- `error`: TurnError | null - 错误信息（仅当 status 为 failed 时填充）

**TurnStatus** 枚举：
- `completed`: 已完成
- `interrupted`: 已中断
- `failed`: 失败
- `inProgress`: 进行中

**TurnError** 结构体：
- `message`: string - 错误消息
- `codexErrorInfo`: CodexErrorInfo | null - Codex 错误信息
- `additionalDetails`: string | null - 额外详情

### ThreadItem 联合类型

包含多种类型的线程项：
- `userMessage`: 用户消息
- `agentMessage`: 助手消息
- `plan`: 计划项（实验性）
- `reasoning`: 推理项
- `commandExecution`: 命令执行项
- `fileChange`: 文件变更项
- `mcpToolCall`: MCP 工具调用项
- `dynamicToolCall`: 动态工具调用项
- `collabAgentToolCall`: 协作代理工具调用项
- `webSearch`: Web 搜索项
- `imageView`: 图片查看项
- `imageGeneration`: 图像生成项
- `enteredReviewMode`: 进入审查模式项
- `exitedReviewMode`: 退出审查模式项
- `contextCompaction`: 上下文压缩项

### 关键子类型

**UserMessageThreadItem**:
- `id`: string
- `type`: "userMessage"
- `content`: UserInput[] - 用户输入内容

**AgentMessageThreadItem**:
- `id`: string
- `type`: "agentMessage"
- `text`: string - 消息文本
- `phase`: MessagePhase | null - 消息阶段（commentary/final_answer）
- `memoryCitation`: MemoryCitation | null - 记忆引用

**EnteredReviewModeThreadItem**:
- `id`: string
- `type`: "enteredReviewMode"
- `review`: string - 审查内容

**CommandExecutionThreadItem**:
- `id`: string
- `type`: "commandExecution"
- `command`: string - 命令
- `cwd`: string - 工作目录
- `status`: CommandExecutionStatus - 状态
- `aggregatedOutput`: string | null - 聚合输出
- `exitCode`: integer | null - 退出码
- `durationMs`: integer | null - 执行时长（毫秒）
- `processId`: string | null - 进程 ID
- `source`: CommandExecutionSource - 来源
- `commandActions`: CommandAction[] - 解析的命令动作

## 关键代码路径与文件引用

### 源文件位置
- **Rust 结构定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ReviewStartResponse`: 第 3898 行附近
  - `Turn`: 第 1191 行附近
  - `TurnStatus`: 第 1253 行附近
  - `TurnError`: 第 1225 行附近
  - `ThreadItem`: 第 584 行附近（Tagged Union）

### Schema 生成
- **生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`
- **生成函数**: `export_client_response_schemas()` 在 `common.rs` 中定义

### 使用位置
- **ClientRequest 定义**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 384-387 行
```rust
ReviewStart => "review/start" {
    params: v2::ReviewStartParams,
    response: v2::ReviewStartResponse,
}
```

### 关联请求类型
- `ReviewStartParams`: 对应的请求参数
  - `thread_id`: 当前线程 ID
  - `target`: 审查目标
  - `delivery`: 交付方式（inline/detached）

## 依赖与外部交互

### 内部依赖
1. **codex_protocol**: 核心协议类型（TurnStatus, TurnError 等）
2. **schemars**: JSON Schema 生成
3. **ts_rs**: TypeScript 类型生成
4. **serde**: 序列化/反序列化

### 外部交互
1. **线程管理**: 创建或复用审查线程
2. **AI 模型**: 启动审查任务
3. **Git 系统**: 获取审查目标的代码变更

### 数据流
```
Client -> ReviewStartParams -> Server
  -> Create/Select Thread
    -> Start AI Review
      -> ReviewStartResponse (reviewThreadId, turn)
        -> Client
```

## 风险、边界与改进建议

### 风险点
1. **响应体积大**: 包含完整的 Turn 信息，可能很大（1499 行 JSON Schema）
2. **items 字段为空**: 除 thread/resume 和 thread/fork 外，items 通常为空数组
3. **状态不一致**: 返回时 turn 可能仍在 inProgress 状态

### 边界情况
1. **立即完成**: 简单审查可能在响应前已完成
2. **立即失败**: 无效目标可能导致立即失败
3. **线程创建失败**: 分离模式下新线程创建失败

### 改进建议
1. **延迟加载 Turn**: 对大型 Turn 支持分页或延迟加载
2. **添加审查元数据**: 
   ```rust
   pub struct ReviewStartResponse {
       pub review_thread_id: String,
       pub turn: Turn,
       pub review_metadata: ReviewMetadata,  // 新增
   }
   
   pub struct ReviewMetadata {
       pub target_summary: String,      // 目标摘要
       pub estimated_duration_secs: u32, // 预估时长
       pub files_count: u32,            // 审查文件数
       pub lines_count: u32,            // 审查行数
   }
   ```

3. **支持部分结果**: 对长时间审查返回部分结果
   ```rust
   pub struct ReviewStartResponse {
       pub review_thread_id: String,
       pub turn: Turn,
       pub is_partial: bool,           // 是否部分结果
       pub continuation_token: Option<String>, // 续查令牌
   }
   ```

4. **添加审查配置**: 返回实际应用的审查配置
   ```rust
   pub struct ReviewStartResponse {
       // ... existing fields
       pub applied_config: ReviewConfig,  // 实际应用的配置
   }
   ```

5. **优化空 items**: 明确文档说明 items 为空的场景，或考虑省略该字段
