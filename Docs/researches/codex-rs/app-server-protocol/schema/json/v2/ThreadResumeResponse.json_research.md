# ThreadResumeResponse.json 研究文档

## 场景与职责

`ThreadResumeResponse.json` 是 Codex App-Server Protocol v2 API 中 `thread/resume` 方法的核心响应结构定义。该 JSON Schema 定义了当客户端请求恢复一个已有线程时，服务器返回的完整数据结构。

**核心职责：**
- 提供线程恢复操作后的完整线程状态快照
- 返回线程的配置信息（模型、沙盒策略、审批策略等）
- 包含线程的完整历史记录（turns）用于 UI 渲染
- 支持实验性 API 字段的标注与隔离

**典型使用场景：**
1. 用户重新打开 VSCode 扩展时恢复之前的对话
2. 客户端从断线状态恢复后重建会话状态
3. 多设备同步时获取线程完整上下文

## 功能点目的

### 1. 线程状态返回
响应中包含完整的 `Thread` 对象，包括：
- `id`: 线程唯一标识符
- `turns`: 线程的完整回合历史（仅在 `thread/resume`、`thread/rollback`、`thread/fork`、`thread/read` 时填充）
- `status`: 线程当前运行状态（idle/active/notLoaded/systemError）
- `name`: 用户设置的线程名称
- `createdAt`/`updatedAt`: 时间戳

### 2. 配置信息同步
返回线程生效的运行时配置：
- `model`: 使用的模型 ID
- `modelProvider`: 模型提供商
- `serviceTier`: 服务层级（fast/flex）
- `approvalPolicy`: 审批策略配置
- `approvalsReviewer`: 审批请求路由目标（user/guardian_subagent）
- `sandbox`: 沙盒安全策略
- `reasoningEffort`: 推理强度设置

### 3. 实验性 API 支持
通过 `#[experimental]` 属性标记不稳定字段：
- `approvalPolicy` 及其嵌套字段为实验性
- 使用 `ExperimentalApi` trait 进行运行时检查

## 具体技术实现

### 数据结构定义

**Rust 源码位置：** `codex-rs/app-server-protocol/src/protocol/v2.rs:2613-2628`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadResumeResponse {
    pub thread: Thread,
    pub model: String,
    pub model_provider: String,
    pub service_tier: Option<ServiceTier>,
    pub cwd: PathBuf,
    #[experimental(nested)]
    pub approval_policy: AskForApproval,
    pub approvals_reviewer: ApprovalsReviewer,
    pub sandbox: SandboxPolicy,
    pub reasoning_effort: Option<ReasoningEffort>,
}
```

### 关键流程

**1. 请求处理流程：**
```
ClientRequest::ThreadResume 
  → codex_message_processor::thread_resume()
  → ThreadManager::load_thread()
  → 构建 ThreadResumeResponse
  → 返回 JSON-RPC 响应
```

**2. 线程恢复参数（ThreadResumeParams）：**
- `thread_id`: 必填，目标线程 ID
- `history`: [UNSTABLE] 实验性字段，支持从内存历史恢复而非磁盘
- `path`: [UNSTABLE] 实验性字段，支持从指定路径恢复
- 配置覆盖字段：`model`, `model_provider`, `service_tier`, `cwd`, `approval_policy`, `sandbox` 等

**3. 线程状态转换：**
- 恢复前：`notLoaded`
- 恢复中：`active`（带有 `waitingOnUserInput` 或 `waitingOnApproval` 标志）
- 恢复完成：`idle`

### 协议规范

**Wire 格式（camelCase）：**
```json
{
  "thread": {
    "id": "thr_xxx",
    "turns": [...],
    "status": { "type": "idle" },
    ...
  },
  "model": "gpt-5.1-codex",
  "modelProvider": "openai",
  "serviceTier": "fast",
  "cwd": "/workspace",
  "approvalPolicy": "never",
  "approvalsReviewer": "user",
  "sandbox": { "type": "workspaceWrite", ... },
  "reasoningEffort": "medium"
}
```

### 嵌套类型定义

**Thread 结构（definitions/Thread）：**
- 包含 12+ 个字段的完整线程元数据
- `turns` 字段为 Turn 数组，仅在特定响应中填充
- `gitInfo` 记录创建时的 Git 上下文

**ThreadItem 联合类型（definitions/ThreadItem）：**
支持 16+ 种项目类型：
- `userMessage`: 用户输入
- `agentMessage`: 助手回复
- `commandExecution`: 命令执行
- `fileChange`: 文件变更
- `mcpToolCall`: MCP 工具调用
- `dynamicToolCall`: 动态工具调用
- `collabAgentToolCall`: 协作代理调用
- `webSearch`: 网页搜索
- `imageView`/`imageGeneration`: 图像相关
- `enteredReviewMode`/`exitedReviewMode`: 审查模式
- `contextCompaction`: 上下文压缩

## 关键代码路径与文件引用

### 协议定义
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2613-2628` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:219-222` | ClientRequest 枚举注册 |
| `codex-rs/app-server-protocol/schema/json/v2/ThreadResumeResponse.json` | JSON Schema 导出 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadResumeResponse.ts` | TypeScript 类型导出 |

### 服务端实现
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs` | 请求处理入口 |
| `codex-rs/app-server/src/thread_state.rs` | 线程状态管理 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 事件处理与响应构建 |

### 客户端使用
| 文件 | 说明 |
|------|------|
| `codex-rs/tui_app_server/src/app_server_session.rs` | TUI 客户端会话实现 |
| `codex-rs/debug-client/src/client.rs` | 调试客户端 |
| `codex-rs/exec/src/lib.rs` | exec 模式集成 |

### 测试覆盖
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_resume.rs` | 恢复功能集成测试 |
| `codex-rs/app-server/tests/suite/v2/thread_rollback.rs` | 与 rollback 联动测试 |
| `codex-rs/app-server/tests/suite/v2/thread_archive.rs` | 归档后恢复测试 |
| `codex-rs/app-server/tests/suite/v2/thread_name_websocket.rs` | WebSocket 场景测试 |

## 依赖与外部交互

### 上游依赖
1. **codex-core**: `ThreadManager` 提供线程加载能力
2. **codex-protocol**: 基础类型定义（`ThreadId`, `Turn`, `EventMsg` 等）
3. **ts-rs**: TypeScript 类型生成
4. **schemars**: JSON Schema 生成

### 下游消费者
1. **VSCode Extension**: 通过 WebSocket/stdio 调用恢复会话
2. **TUI**: 终端界面恢复历史对话
3. **exec 模式**: 命令行执行时恢复上下文

### 相关 API 方法
- `thread/start`: 创建新线程（响应结构类似）
- `thread/fork`: 分叉线程（响应结构类似）
- `thread/read`: 读取线程（返回 Thread 子集）
- `thread/rollback`: 回滚后返回更新后的线程状态

## 风险、边界与改进建议

### 已知风险

**1. 大线程历史加载性能**
- `turns` 字段在恢复时完整填充，大历史记录可能导致：
  - 响应体过大（>1MB）
  - 序列化/反序列化延迟
  - 内存峰值
- **缓解**: 客户端可使用 `persistExtendedHistory: false` 减少历史记录

**2. 实验性字段稳定性**
- `approvalPolicy` 为实验性 API，字段结构可能变化
- 嵌套实验性字段需要递归检查 `experimental_reason()`

**3. 并发恢复冲突**
- 同一线程并发恢复可能导致状态竞争
- `thread_state.rs` 中使用 Mutex 保护，但跨连接无全局锁

### 边界条件

| 场景 | 行为 |
|------|------|
| thread_id 不存在 | 返回 `invalidRequest` 错误 |
| 线程已加载 | 返回当前状态，不重复加载 |
| 线程已归档 | 需要先调用 `thread/unarchive` |
| 配置覆盖冲突 | 显式参数优先于持久化配置 |

### 改进建议

**1. 分页历史支持**
```rust
// 建议添加
pub struct ThreadResumeParams {
    // ...
    #[ts(optional = nullable)]
    pub turn_cursor: Option<String>,
    #[ts(optional = nullable)]
    pub turn_limit: Option<u32>,
}
```

**2. 选择性字段加载**
- 添加 `includeTurns: bool` 类似 `thread/read` 的参数
- 允许客户端仅获取元数据而不加载完整历史

**3. 响应压缩**
- 对于大线程历史，考虑支持 `Accept-Encoding: gzip`
- 或提供二进制序列化选项（MessagePack）

**4. 缓存优化**
- 已加载线程的响应可缓存，避免重复查询
- 使用 ETag 机制支持客户端缓存验证

### 版本兼容性

- v2 API 稳定，但内部实验性字段可能变化
- JSON Schema 使用 `draft-07` 标准
- TypeScript 类型通过 `ts-rs` 自动生成，保持同步
