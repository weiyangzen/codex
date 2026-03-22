# ThreadResumeParams.json 研究文档

## 场景与职责

`ThreadResumeParams` 是 Codex App Server Protocol v2 中 `thread/resume` 方法的请求参数结构，用于从磁盘或内存中恢复一个已存在的线程（Thread）会话。这是 Codex 多轮对话系统的核心生命周期管理 API 之一。

该参数结构支持三种恢复方式：
1. **By thread_id**: 通过线程 ID 从磁盘加载并恢复（推荐方式）
2. **By history**: 从内存中直接实例化历史记录恢复（实验性功能，仅限 Codex Cloud 内部使用）
3. **By path**: 通过指定 rollout 文件路径加载（实验性功能）

优先级顺序为：`history > path > thread_id`

## 功能点目的

### 核心功能
- **线程恢复**: 允许客户端重新连接到之前创建的对话线程，继续多轮交互
- **配置覆盖**: 支持在恢复时动态覆盖原线程的模型、沙箱策略、审批策略等配置
- **历史记录加载**: 自动加载线程的完整对话历史（turns）
- **并发安全**: 支持多个客户端同时恢复同一运行中线程，实现会话共享

### 实验性功能
- **`history` 字段**: 允许直接传入 `ResponseItem` 数组作为历史记录，而非从磁盘加载
- **`path` 字段**: 指定具体的 rollout 文件路径进行恢复
- **`persist_extended_history`**: 控制是否持久化额外的 EventMsg 变体以支持更丰富的历史重建

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadResumeParams {
    pub thread_id: String,
    
    // 实验性功能：直接传入历史记录
    #[experimental("thread/resume.history")]
    #[ts(optional = nullable)]
    pub history: Option<Vec<ResponseItem>>,
    
    // 实验性功能：指定 rollout 路径
    #[experimental("thread/resume.path")]
    #[ts(optional = nullable)]
    pub path: Option<PathBuf>,
    
    // 配置覆盖字段
    #[ts(optional = nullable)]
    pub model: Option<String>,
    #[ts(optional = nullable)]
    pub model_provider: Option<String>,
    #[ts(optional = nullable)]
    pub service_tier: Option<Option<ServiceTier>>,
    #[ts(optional = nullable)]
    pub cwd: Option<String>,
    #[experimental(nested)]
    #[ts(optional = nullable)]
    pub approval_policy: Option<AskForApproval>,
    #[ts(optional = nullable)]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    #[ts(optional = nullable)]
    pub sandbox: Option<SandboxMode>,
    #[ts(optional = nullable)]
    pub config: Option<HashMap<String, serde_json::Value>>,
    #[ts(optional = nullable)]
    pub base_instructions: Option<String>,
    #[ts(optional = nullable)]
    pub developer_instructions: Option<String>,
    #[ts(optional = nullable)]
    pub personality: Option<Personality>,
    #[experimental("thread/resume.persistFullHistory")]
    #[serde(default)]
    pub persist_extended_history: bool,
}
```

### 关键流程

1. **请求处理入口**: `CodexMessageProcessor::thread_resume()` (codex_message_processor.rs:3376)
2. **运行中线程检测**: 检查线程是否已在运行，如果是则直接加入现有会话
3. **历史记录加载**:
   - 如果提供了 `history`，使用 `resume_thread_from_history()`
   - 否则通过 `resume_thread_from_rollout()` 从磁盘加载
4. **配置合并**: 将请求中的配置覆盖与持久化的恢复元数据合并
5. **线程恢复**: 调用 `ThreadManager::resume_thread_with_history()` 创建线程实例
6. **响应返回**: 返回 `ThreadResumeResponse` 包含完整的线程信息和当前配置

### 关联数据结构

- **ThreadResumeResponse**: 包含恢复后的 Thread 对象、当前模型、提供商、服务层级等
- **ResponseItem**: Responses API 兼容的内容项，用于历史记录表示
- **AskForApproval**: 审批策略枚举（untrusted/on-failure/on-request/never/granular）
- **SandboxMode**: 沙箱模式（read-only/workspace-write/danger-full-access）

## 关键代码路径与文件引用

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`: ThreadResumeParams 结构体定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`: ClientRequest 枚举包含 ThreadResume 变体

### 服务端实现
- `codex-rs/app-server/src/codex_message_processor.rs`:
  - `thread_resume()` 方法 (line 3376)
  - `resume_running_thread()` 处理运行中线程恢复 (line 3394)
  - `resume_thread_from_history()` 内存历史恢复 (line 3419)
  - `resume_thread_from_rollout()` 磁盘文件恢复 (line 3428)

### 测试用例
- `codex-rs/app-server/tests/suite/v2/thread_resume.rs`:
  - `thread_resume_rejects_unmaterialized_thread`: 验证未物化线程的拒绝
  - `thread_resume_returns_rollout_history`: 验证历史记录正确返回
  - `thread_resume_keeps_in_flight_turn_streaming`: 验证运行中 turn 的保持
  - `thread_resume_rejects_history_when_thread_is_running`: 验证运行线程的历史覆盖拒绝

### TypeScript 类型定义
- `codex-rs/app-server-protocol/schema/typescript/v2/ThreadResumeParams.ts`

## 依赖与外部交互

### 内部依赖
- **codex_core**: `ThreadManager::resume_thread_with_history()` 提供核心恢复逻辑
- **codex_protocol**: `ThreadId`, `ResponseItem`, `SessionSource` 等类型
- **codex_state**: StateRuntime 用于持久化元数据查询

### 外部交互
- **文件系统**: 读取 `$CODEX_HOME/sessions/YYYY/MM/DD/*.jsonl` rollout 文件
- **SQLite**: 查询 state_db 获取线程元数据（如 git_info）
- **WebSocket/SSE**: 恢复后自动附加线程监听器，接收实时事件

### 配置层交互
恢复时会重新构建配置，涉及以下配置层（按优先级）：
1. SessionFlags (请求参数覆盖)
2. Project (.codex/ 目录配置)
3. User ($CODEX_HOME/config.toml)
4. System (系统级配置)
5. MDM (移动设备管理配置)

## 风险、边界与改进建议

### 已知风险

1. **并发恢复竞争**: 多个客户端同时恢复同一运行中线程时，配置覆盖可能产生非确定性行为
2. **历史记录完整性**: `ThreadItem` 是 lossy 的，不持久化所有代理交互（如命令执行详情）
3. **实验性功能稳定性**: `history` 和 `path` 字段标记为不稳定，API 可能变更

### 边界情况

1. **未物化线程**: 线程创建后未发送首条消息前，rollout 文件不存在，恢复会失败
2. **运行中线程限制**: 线程有活跃 turn 时，拒绝 `history` 和 `path` 覆盖（防止状态不一致）
3. **配置验证失败**: 覆盖的配置若与云策略冲突，恢复会失败并返回配置错误

### 改进建议

1. **配置原子性**: 当前配置覆盖是部分应用，建议实现原子性配置验证（全成功或全失败）
2. **历史版本兼容**: 考虑 rollout 文件格式版本迁移机制，支持旧格式恢复
3. **恢复进度通知**: 大型历史记录加载时，添加进度通知机制改善 UX
4. **配置冲突提示**: 当覆盖的配置被云策略否决时，提供更详细的冲突说明

### 安全考虑
- `history` 字段允许客户端传入任意历史记录，需确保服务端验证历史内容的合法性
- `path` 字段涉及文件系统访问，需验证路径在允许的 CODEX_HOME 范围内
