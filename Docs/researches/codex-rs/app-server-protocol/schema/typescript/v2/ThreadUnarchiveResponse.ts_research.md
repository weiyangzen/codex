# ThreadUnarchiveResponse Research Document

## 场景与职责 (Usage Scenarios and Responsibilities)

`ThreadUnarchiveResponse` 是 `thread/unarchive` RPC 方法的响应类型，用于确认线程已成功从归档状态恢复，并向客户端返回恢复后的线程元数据。

**核心使用场景：**
1. **恢复确认**：向客户端确认线程已成功解档
2. **状态同步**：提供解档后线程的最新状态（`NotLoaded`）
3. **UI 更新**：客户端使用返回的线程数据更新界面
4. **后续操作准备**：为客户端提供进行后续操作（如 `thread/resume`）所需的信息

**职责范围：**
- 返回解档后的 `Thread` 对象
- 确认文件系统操作成功
- 提供更新后的时间戳和状态
- 与 `ThreadUnarchivedNotification` 配合完成事件广播

## 功能点目的 (Purpose of the Functionality)

**主要设计目标：**

1. **操作确认**
   - 明确告知客户端解档操作成功完成
   - 提供可验证的操作结果

2. **数据同步**
   - 返回解档后线程的最新元数据
   - 特别是更新的 `updated_at` 时间戳

3. **状态传达**
   - 明确线程当前处于 `NotLoaded` 状态
   - 提示客户端需要调用 `thread/resume` 才能继续交互

4. **一致性保证**
   - 确保响应中的数据与实际文件系统状态一致
   - 与广播通知的数据保持一致

## 具体技术实现 (Technical Implementation Details)

### 数据结构定义

**Rust 源码**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 2857-2862）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnarchiveResponse {
    pub thread: Thread,
}
```

**TypeScript 生成类型**（`ThreadUnarchiveResponse.ts`）：

```typescript
import type { Thread } from "./Thread";

export type ThreadUnarchiveResponse = { thread: Thread };
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `thread` | `Thread` | 解档后的线程完整元数据 |

### Thread 对象关键字段

解档后的 `Thread` 对象具有以下特征：

```typescript
type Thread = {
    id: string,                    // 线程唯一标识符
    preview: string,               // 对话预览
    ephemeral: boolean,            // 是否为临时线程（解档后通常为 false）
    modelProvider: string,         // 模型提供商
    createdAt: number,             // 创建时间戳（不变）
    updatedAt: number,             // 更新时间戳（解档时更新）
    status: ThreadStatus,          // 状态（解档后为 NotLoaded）
    path: string | null,           // 会话目录中的路径
    cwd: string,                   // 工作目录
    cliVersion: string,            // CLI 版本
    source: SessionSource,         // 来源
    agentNickname: string | null,
    agentRole: string | null,
    gitInfo: GitInfo | null,
    name: string | null,           // 线程名称
    turns: Array<Turn>,            // 轮次列表（通常为空）
};
```

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

### 对应的请求类型

**ThreadUnarchiveParams**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 2793-2795）：

```rust
pub struct ThreadUnarchiveParams {
    pub thread_id: String,
}
```

### 对应的通知

**ThreadUnarchivedNotification**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 4635-4640）：

```rust
pub struct ThreadUnarchivedNotification {
    pub thread_id: String,
}
```

### 序列化示例

**完整响应：**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "thread": {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "preview": "Previous conversation about Rust",
            "ephemeral": false,
            "modelProvider": "openai",
            "createdAt": 1704067200,
            "updatedAt": 1704153600,
            "status": { "type": "notLoaded" },
            "path": "/home/user/.codex/sessions/2024-01-01_thread-uuid.jsonl",
            "cwd": "/home/user/projects/myapp",
            "cliVersion": "1.0.0",
            "source": "cli",
            "agentNickname": null,
            "agentRole": null,
            "gitInfo": {
                "commit": "abc123",
                "branch": "main"
            },
            "name": "Rust Learning Session",
            "turns": []
        }
    }
}
```

## 关键代码路径与文件引用 (Key Code Paths and File References)

### 协议定义
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 2857-2862)
  - `ThreadUnarchiveResponse` 结构体定义

- **`codex-rs/app-server-protocol/src/protocol/common.rs`** (lines 262-265)
  - RPC 方法注册

### TypeScript 生成文件
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadUnarchiveResponse.ts`**
- **`codex-rs/app-server-protocol/schema/json/v2/ThreadUnarchiveResponse.json`**

### 相关类型
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 2793-2795)
  - `ThreadUnarchiveParams` 定义

- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 4635-4640)
  - `ThreadUnarchivedNotification` 定义

- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 3022-3035)
  - `ThreadStatus` 定义（解档后为 `NotLoaded`）

### 测试文件
- **`codex-rs/app-server/tests/suite/v2/thread_unarchive.rs`**
  - 完整的解档功能测试
  - 验证响应中的线程数据
  - 验证 `updated_at` 时间戳更新
  - 验证状态为 `NotLoaded`

### 核心库
- **`codex-rs/core/src/lib.rs`**
  - 归档路径查找和文件操作

## 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `Thread` | 响应中返回的核心数据 |
| `ThreadUnarchiveParams` | 对应的请求类型 |
| `ThreadUnarchivedNotification` | 配套的通知 |
| `ThreadStatus` | 线程状态枚举 |
| `SessionSource` | 会话来源枚举 |
| `GitInfo` | Git 元数据 |
| `Turn` | 轮次数据 |

### 外部系统交互

1. **文件系统**
   - 从归档目录移动文件到会话目录
   - 读取线程元数据
   - 更新文件时间戳

2. **存储系统**
   - 验证归档数据完整性
   - 确保数据正确恢复

### 响应构造流程

```
接收 thread/unarchive 请求
        ↓
验证 thread_id
        ↓
查找归档文件
        ↓
移动文件到会话目录
        ↓
更新文件修改时间
        ↓
读取线程数据
        ↓
构造 Thread 对象
        ↓
设置 status = NotLoaded
        ↓
构造 ThreadUnarchiveResponse
        ↓
发送响应
        ↓
广播 ThreadUnarchivedNotification
```

### 关键特性

1. **时间戳更新**
   - 测试验证了 `updated_at` 会被更新
   - 示例：解档前时间戳为旧值，解档后变为当前时间

2. **状态设置**
   - 解档后状态始终为 `NotLoaded`
   - 需要后续 `thread/resume` 才能加载到内存

3. **路径更新**
   - `path` 指向会话目录中的新位置
   - 不再是归档目录路径

## 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 已知风险

1. **数据一致性**
   - 响应中的数据必须与文件系统状态一致
   - 并发操作可能导致数据不一致

2. **序列化问题**
   - 测试验证了 `name` 字段需要正确序列化为 `null`（如果未设置）
   - 需要确保所有可选字段的正确序列化

3. **大文件处理**
   - 大型线程文件可能导致响应延迟
   - 需要优化文件读取性能

### 边界情况

1. **空线程名称**
   - `name` 为 `null` 时需要正确序列化
   - 测试代码明确验证了这一点

2. **空轮次列表**
   - 解档后 `turns` 通常为空数组
   - 需要 `thread/read` 并设置 `include_turns: true` 才能获取完整历史

3. **Git 信息**
   - 解档后的 `gitInfo` 保留原始值
   - 可能与当前工作目录的 Git 状态不一致

### 测试覆盖

测试文件 `thread_unarchive.rs` 验证了：
1. 响应成功返回
2. 返回的线程 ID 与请求一致
3. `updated_at` 时间戳被更新（大于旧值）
4. 线程状态为 `NotLoaded`
5. `name` 字段正确序列化为 `null`（如果未设置）
6. 归档文件被移动到会话目录
7. 归档文件被删除

### 改进建议

1. **完整历史选项**
   - 添加参数控制是否返回完整轮次列表
   - 例如：`include_turns: boolean`

2. **加载选项**
   - 考虑支持解档并自动加载（`auto_load: boolean`）
   - 减少客户端的额外 RPC 调用

3. **冲突信息**
   - 如果工作目录已不存在，在响应中提供警告
   - 帮助用户了解潜在问题

4. **版本兼容性**
   - 检查线程文件的版本兼容性
   - 在响应中提供版本信息

5. **元数据对比**
   - 对比原始 Git 状态与当前状态
   - 在响应中提供差异信息

6. **批量响应**
   - 支持批量解档的响应格式
   - 返回多个线程的数据

7. **错误详情**
   - 提供更详细的错误信息
   - 区分文件不存在、权限错误等不同错误类型
