# ThreadMetadataUpdateResponse 类型研究文档

## 场景与职责

`ThreadMetadataUpdateResponse` 是 Codex App Server Protocol v2 API 中 `thread/metadata/update` RPC 方法的响应类型。它承载了线程元数据更新操作成功后的完整线程状态，确认更新已生效并同步最新数据。

### 主要使用场景

- **确认更新成功**: 客户端接收更新后的线程状态，确认操作完成
- **状态同步**: 获取应用更新后的完整线程元数据
- **UI 刷新**: 基于最新数据更新界面展示
- **后续操作**: 基于更新后的状态决定下一步操作

### 架构定位

该类型与 `ThreadMetadataUpdateParams` 形成完整的元数据更新契约，遵循**更新后读取（read-after-write）**模式，确保客户端看到一致的数据状态。

---

## 功能点目的

### 核心字段

| 字段 | 类型 | 目的 |
|------|------|------|
| `thread` | `Thread` | 更新后的完整线程对象 |

### 设计意图

1. **确认语义**: 返回完整对象证明更新已成功应用
2. **状态同步**: 客户端无需额外查询即可获取最新状态
3. **一致性**: 与 `ThreadForkResponse`、`ThreadStartResponse` 等保持相同模式
4. **简单性**: 单一字段设计，职责清晰

---

## 具体技术实现

### TypeScript 类型定义

```typescript
import type { Thread } from "./Thread";

export type ThreadMetadataUpdateResponse = {
  thread: Thread,
};
```

### Rust 实现细节

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadMetadataUpdateResponse {
    pub thread: Thread,
}
```

### Thread 对象内容

返回的 `Thread` 对象包含更新后的完整元数据：

```typescript
interface Thread {
  id: string;
  name: string | null;
  preview: string;
  status: ThreadStatus;
  createdAt: number;
  updatedAt: number;
  cwd: string;
  modelProvider: string;
  source: SessionSource;
  gitInfo: GitInfo | null;  // ← 更新后的 Git 信息
  turns: Turn[];
  path: string | null;
  ephemeral: boolean;
  // ... 其他字段
}
```

### 关键技术点

1. **完整对象返回**: 不返回差异或部分更新，而是完整线程对象
2. **强类型保证**: 使用 `Thread` 类型确保数据完整性
3. **序列化一致**: 与 `thread/read` 等其他接口返回的 `Thread` 格式一致

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 作用 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 2850-2856) | Rust 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` (line 258-261) | RPC 方法注册 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadMetadataUpdateResponse.ts` | TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/ThreadMetadataUpdateResponse.json` | JSON Schema |

### 服务端实现

| 文件 | 作用 |
|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs` | 构造响应对象 |
| `codex-rs/app-server/src/thread_state.rs` | 提供更新后的线程数据 |

### 测试覆盖

| 文件 | 作用 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs` | 响应验证测试 |

### 关键测试断言

```rust
// 验证更新后的线程
let ThreadMetadataUpdateResponse { thread: updated } = 
    to_response::<ThreadMetadataUpdateResponse>(update_resp)?;

assert_eq!(updated.id, thread_id);
assert_eq!(
    updated.git_info,
    Some(GitInfo {
        sha: None,
        branch: Some("feature/sidebar-pr".to_string()),
        origin_url: None,
    })
);
assert_eq!(updated.status, ThreadStatus::Idle);

// 验证 wire 格式
let updated_thread_json = update_result
    .get("thread")
    .and_then(Value::as_object)
    .expect("thread/metadata/update result.thread must be an object");
    
let updated_git_info_json = updated_thread_json
    .get("gitInfo")
    .and_then(Value::as_object)
    .expect("thread/metadata/update must serialize `thread.gitInfo`");
    
assert_eq!(
    updated_git_info_json.get("branch").and_then(Value::as_str),
    Some("feature/sidebar-pr")
);

// 验证读取一致性
let ThreadReadResponse { thread: read } = 
    to_response::<ThreadReadResponse>(read_resp)?;
assert_eq!(read.git_info, updated.git_info);
```

---

## 依赖与外部交互

### 依赖类型

```typescript
import type { Thread } from "./Thread";
```

### 数据流

```
ThreadMetadataUpdateParams (请求)
    ↓
应用元数据更新
    ↓
从数据库/内存读取最新状态
    ↓
构建 Thread 对象
    ↓
ThreadMetadataUpdateResponse { thread: Thread }
```

### 与 ThreadReadResponse 的关系

`ThreadMetadataUpdateResponse` 和 `ThreadReadResponse` 都返回 `Thread` 对象，但语义不同：

| 响应类型 | 触发操作 | 使用场景 |
|---------|---------|---------|
| `ThreadMetadataUpdateResponse` | 元数据修改 | 确认更新并查看最新状态 |
| `ThreadReadResponse` | 纯读取 | 获取线程信息而不修改 |

---

## 风险、边界与改进建议

### 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **响应体积** | 返回完整 Thread 对象可能较大 | 对于大历史线程，考虑简略模式 |
| **并发修改** | 返回后数据可能已被其他客户端修改 | 客户端应处理数据过期 |
| **修复副作用** | 自动修复可能改变未预期的字段 | 测试覆盖修复场景 |

### 边界情况

1. **修复后返回**: 如果触发了自动修复，返回的线程可能包含从 rollout 文件重建的完整数据
2. **空更新错误**: 请求无效时不会返回此响应，而是返回错误
3. **归档线程**: 可以更新并返回归档线程的元数据

### 改进建议

1. **简略模式**: 添加参数控制是否包含 `turns` 等大字段
2. **变更摘要**: 添加 `changes` 字段说明哪些元数据被修改
3. **版本信息**: 添加 `version` 或 `etag` 字段支持乐观并发控制
4. **部分返回**: 只返回变更的元数据部分，减少数据传输
5. **通知机制**: 元数据更新时发送通知给订阅该线程的其他客户端

### 使用模式

```typescript
// 模式 1: 简单更新并确认
const response = await client.threadMetadataUpdate({
  threadId: "thread-123",
  gitInfo: { branch: "main" }
});
console.log("Updated branch:", response.thread.gitInfo?.branch);

// 模式 2: 更新后验证
const before = await client.threadRead({ threadId: "thread-123" });
const updateResponse = await client.threadMetadataUpdate({ ... });
const after = updateResponse.thread;

// 验证更新生效
assert.notEqual(before.gitInfo?.branch, after.gitInfo?.branch);

// 模式 3: 链式操作
const { thread } = await client.threadMetadataUpdate({ ... });
if (thread.gitInfo?.branch === "main") {
  await client.threadArchive({ threadId: thread.id });
}
```

### 相关类型对比

| 响应类型 | 相同点 | 不同点 |
|---------|--------|--------|
| `ThreadMetadataUpdateResponse` | 都返回 Thread | 元数据更新后返回 |
| `ThreadReadResponse` | 都返回 Thread | 纯读取操作 |
| `ThreadForkResponse` | 都返回 Thread | 分叉操作，返回新线程 |
| `ThreadStartResponse` | 都返回 Thread | 启动新线程 |
| `ThreadResumeResponse` | 都返回 Thread | 恢复已有线程 |

### 响应模式一致性

Codex App Server Protocol v2 中，修改线程的操作通常遵循以下响应模式：

```
操作请求 → 执行操作 → 读取最新状态 → 返回完整 Thread
```

这种设计确保客户端始终获得一致、最新的数据状态，简化了客户端的状态管理逻辑。
