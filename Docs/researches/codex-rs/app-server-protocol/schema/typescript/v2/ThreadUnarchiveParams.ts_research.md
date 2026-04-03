# ThreadUnarchiveParams Research Document

## 场景与职责 (Usage Scenarios and Responsibilities)

`ThreadUnarchiveParams` 是 `thread/unarchive` RPC 方法的请求参数类型，用于将已归档的线程恢复到活跃状态。这是线程生命周期管理的重要组成部分，支持用户重新访问历史对话。

**核心使用场景：**
1. **恢复历史对话**：用户想要继续之前归档的对话
2. **归档管理**：从归档目录中恢复误归档的线程
3. **数据迁移**：将旧线程迁移到新的工作目录
4. **批量恢复**：批量恢复多个归档线程

**职责范围：**
- 标识要恢复的线程
- 触发归档到活跃的转换
- 支持线程数据的持久化恢复

## 功能点目的 (Purpose of the Functionality)

**主要设计目标：**

1. **数据恢复**
   - 支持将归档线程恢复到可交互状态
   - 保留线程的完整历史和元数据

2. **存储管理**
   - 将线程从归档目录移回活跃会话目录
   - 更新线程的 `updated_at` 时间戳

3. **用户体验**
   - 允许用户随时恢复之前的对话
   - 保持线程状态的连续性

4. **生命周期管理**
   - 完善线程的完整生命周期（创建 → 活跃 → 归档 → 恢复）

## 具体技术实现 (Technical Implementation Details)

### 数据结构定义

**Rust 源码**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 2793-2795）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnarchiveParams {
    pub thread_id: String,
}
```

**TypeScript 生成类型**（`ThreadUnarchiveParams.ts`）：

```typescript
export type ThreadUnarchiveParams = { threadId: string };
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 要恢复的线程唯一标识符 |

### RPC 方法注册

**协议注册**（`codex-rs/app-server-protocol/src/protocol/common.rs` lines 262-265）：

```rust
client_request_definitions! {
    // ...
    ThreadUnarchive => "thread/unarchive" {
        params: v2::ThreadUnarchiveParams,
        response: v2::ThreadUnarchiveResponse,
    },
    // ...
}
```

### 对应的响应类型

**ThreadUnarchiveResponse**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 2857-2862）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnarchiveResponse {
    pub thread: Thread,
}
```

### 对应的通知

**ThreadUnarchivedNotification**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 4635-4640）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnarchivedNotification {
    pub thread_id: String,
}
```

通知注册（`codex-rs/app-server-protocol/src/protocol/common.rs` line 880）：

```rust
server_notification_definitions! {
    // ...
    ThreadUnarchived => "thread/unarchived" (v2::ThreadUnarchivedNotification),
    // ...
}
```

### 序列化示例

**请求：**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "thread/unarchive",
    "params": {
        "threadId": "thread-uuid"
    }
}
```

**响应：**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "thread": {
            "id": "thread-uuid",
            "preview": "Previous conversation preview",
            "ephemeral": false,
            "modelProvider": "openai",
            "createdAt": 1704067200,
            "updatedAt": 1704153600,
            "status": { "type": "notLoaded" },
            "path": "/home/user/.codex/sessions/...",
            "cwd": "/home/user/project",
            "cliVersion": "1.0.0",
            "source": "cli",
            "agentNickname": null,
            "agentRole": null,
            "gitInfo": null,
            "name": "My Thread",
            "turns": []
        }
    }
}
```

**通知：**
```json
{
    "jsonrpc": "2.0",
    "method": "thread/unarchived",
    "params": {
        "threadId": "thread-uuid"
    }
}
```

## 关键代码路径与文件引用 (Key Code Paths and File References)

### 协议定义
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 2793-2795)
  - `ThreadUnarchiveParams` 结构体定义

- **`codex-rs/app-server-protocol/src/protocol/common.rs`** (lines 262-265)
  - RPC 方法注册

### TypeScript 生成文件
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadUnarchiveParams.ts`**
- **`codex-rs/app-server-protocol/schema/json/v2/ThreadUnarchiveParams.json`**

### 相关类型
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 2857-2862)
  - `ThreadUnarchiveResponse` 定义

- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 4635-4640)
  - `ThreadUnarchivedNotification` 定义

### 服务器实现
- **`codex-rs/core/src/`**
  - 归档/解档的核心逻辑
  - `find_archived_thread_path_by_id_str` 函数

### 测试文件
- **`codex-rs/app-server/tests/suite/v2/thread_unarchive.rs`**
  - 完整的解档功能测试
  - 验证文件系统操作（归档目录 → 会话目录）
  - 验证时间戳更新
  - 验证状态变为 `NotLoaded`

### 核心库
- **`codex-rs/core/src/lib.rs`**
  - `find_archived_thread_path_by_id_str` 函数
  - 归档路径查找逻辑

## 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `Thread` | 响应中返回的线程对象 |
| `ThreadUnarchiveResponse` | 对应的响应类型 |
| `ThreadUnarchivedNotification` | 解档完成后发送的通知 |
| `ThreadStatus` | 解档后的线程状态（`NotLoaded`） |

### 外部系统交互

1. **文件系统**
   - 从归档目录（如 `~/.codex/archived/`）移动文件
   - 到会话目录（如 `~/.codex/sessions/`）
   - 更新文件修改时间戳

2. **存储系统**
   - 读取归档的线程数据
   - 验证数据完整性

### 操作流程

```
客户端调用 thread/unarchive
        ↓
服务器验证线程 ID
        ↓
查找归档路径
        ↓
验证归档文件存在
        ↓
移动文件到会话目录
        ↓
更新 updated_at 时间戳
        ↓
构造 Thread 对象（状态为 NotLoaded）
        ↓
返回 ThreadUnarchiveResponse
        ↓
广播 ThreadUnarchivedNotification
```

### 状态变化

解档操作后的线程状态：
- **状态**：`NotLoaded`（未加载到内存）
- **路径**：指向会话目录中的文件
- **updated_at**：更新为解档时间

## 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 已知风险

1. **文件系统操作失败**
   - 磁盘空间不足
   - 权限问题
   - 文件被其他进程锁定

2. **并发操作**
   - 多个客户端同时解档同一线程
   - 解档与归档操作并发执行

3. **数据一致性**
   - 归档文件可能在归档后被修改
   - 需要验证数据完整性

### 边界情况

1. **线程未归档**
   - 尝试解档一个未归档的线程
   - 应返回适当的错误信息

2. **线程不存在**
   - 提供的 thread_id 不存在
   - 应返回 `NotFound` 错误

3. **路径冲突**
   - 会话目录已存在同名文件
   - 需要处理冲突（覆盖或报错）

4. **已加载线程**
   - 尝试解档一个已加载的线程
   - 可能需要特殊处理

### 测试覆盖

测试文件 `thread_unarchive.rs` 验证了：
1. 归档文件被正确移动到会话目录
2. 归档文件被删除
3. `updated_at` 时间戳被更新
4. 返回的线程状态为 `NotLoaded`
5. `name` 字段正确序列化为 `null`（如果未设置）

### 改进建议

1. **批量操作**
   - 支持批量解档多个线程
   - 减少多次 RPC 调用的开销

2. **原子性保证**
   - 确保文件操作的原子性
   - 失败时能够回滚

3. **冲突处理选项**
   - 添加参数控制路径冲突时的行为
   - 例如：`onConflict: "overwrite" | "error" | "rename"`

4. **验证增强**
   - 验证归档文件的完整性
   - 检查文件格式版本兼容性

5. **进度通知**
   - 对于大型线程，发送进度通知
   - 改善大文件解档的用户体验

6. **元数据保留**
   - 记录解档操作的历史
   - 支持审计和追踪

7. **目标目录指定**
   - 支持指定解档的目标目录
   - 而不仅限于默认会话目录

8. **软链接支持**
   - 支持使用软链接而非移动文件
   - 保留归档作为备份
