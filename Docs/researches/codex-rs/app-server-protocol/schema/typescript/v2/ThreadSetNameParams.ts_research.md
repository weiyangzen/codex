# ThreadSetNameParams 类型研究报告

## 场景与职责

`ThreadSetNameParams` 是 Codex App-Server Protocol v2 中的参数类型，用于在客户端为对话线程设置或修改自定义名称时，传递必要的参数。

**主要使用场景：**
- 用户为对话线程设置有意义的自定义标题
- 在对话列表中更容易识别和区分不同线程
- 组织和归档对话历史
- 通过名称快速搜索和定位特定对话

**职责范围：**
- 标识目标线程（`threadId`）
- 提供新的线程名称（`name`）
- 支持线程的元数据管理

## 功能点目的

该类型的核心目的是为 `thread/set_name` RPC 调用提供参数，使客户端能够：

1. **自定义线程标识**: 允许用户用有意义的名称替代自动生成的预览文本
2. **改善可发现性**: 通过自定义名称更容易在列表中找到特定线程
3. **支持组织管理**: 用户可以通过命名约定对线程进行分类
4. **持久化元数据**: 将用户定义的名称保存到线程元数据中

**设计特点：**
- 简单直接的参数结构
- 支持设置任意字符串名称（包括空字符串）
- 与线程的 `preview` 字段分离，两者可独立存在

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadSetNameParams = {
  threadId: string,
  name: string,
};
```

### Rust 源类型定义

```rust
// Line 2782-2788
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadSetNameParams {
    pub thread_id: String,
    pub name: String,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 目标线程的唯一标识符 |
| `name` | `string` | 要为线程设置的新名称 |

### 类型约束

- `threadId`: 非空字符串，对应已存在的线程
- `name`: 任意字符串，包括空字符串
- 没有长度限制（由服务端实现决定）
- 没有字符集限制（支持 Unicode）

### 与 Thread 类型的关系

在 `Thread` 类型中，`name` 字段定义为：
```typescript
name: string | null,  // Optional user-facing thread title.
```

说明：
- `name` 是可选的用户可见线程标题
- 可以为 `null` 表示未设置自定义名称
- 与 `preview` 字段不同，后者通常是第一条用户消息的摘要

## 关键代码路径与文件引用

### TypeScript 定义文件
- **路径**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadSetNameParams.ts`
- **生成工具**: ts-rs (自动从 Rust 代码生成)

### Rust 源文件
- **路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 2785-2788

### 相关类型
| 类型 | 说明 | 路径 |
|------|------|------|
| ThreadSetNameResponse | 设置名称操作的响应（空对象） | `v2/ThreadSetNameResponse.ts` |
| Thread | 线程对象，包含 name 字段 | `v2/Thread.ts` |
| ThreadNameUpdatedNotification | 名称更新通知 | `v2/ThreadNameUpdatedNotification.ts` |

### 使用场景
- 与 `ThreadSetNameResponse` 配对使用
- 操作成功后通常会触发 `ThreadNameUpdatedNotification` 通知

## 依赖与外部交互

### 内部依赖

1. **Thread 类型**: 操作的目标对象，包含 `name` 字段
2. **ThreadSetNameResponse**: 操作的响应类型（空对象）

### 外部交互

1. **与 ThreadSetNameResponse 的交互**:
   - 请求设置名称
   - 返回空对象表示成功（无额外数据）

2. **与通知系统的交互**:
   - 操作成功后，服务端应发送 `ThreadNameUpdatedNotification`
   - 通知其他订阅该线程的客户端

3. **与 Thread 列表的交互**:
   - 设置名称后，线程列表应显示新名称而非预览文本
   - 搜索功能应支持按名称搜索

### 工作流程

```
客户端                              服务端
  |                                   |
  |-- ThreadSetNameParams ----------->|
  |   { threadId, name }              |
  |                                   | 更新线程元数据
  |                                   | 发送通知
  |<-- ThreadSetNameResponse ---------|
  |   {}                              |
  |                                   |
  |<-- ThreadNameUpdatedNotification--|
  |   { threadId, name }              |
```

## 风险、边界与改进建议

### 潜在风险

1. **名称冲突**:
   - 多个线程可以有相同的名称
   - 可能导致用户混淆
   - 建议客户端在 UI 中同时显示 ID 或其他区分信息

2. **空名称处理**:
   - 空字符串和 `null` 的语义可能不明确
   - 建议明确约定：空字符串表示清除名称，还是作为有效名称

3. **并发修改**:
   - 多个客户端同时修改同一线程名称
   - 最后写入者获胜，可能导致预期外的覆盖

4. **特殊字符**:
   - 名称可能包含特殊字符或控制字符
   - 可能影响存储、显示或搜索

### 边界情况

1. **空字符串名称**: 是否允许？语义是什么？
2. **超长名称**: 是否应限制长度？如何截断显示？
3. **仅空白字符**: `"   "` 这样的名称是否有效？
4. **不存在的线程**: 应返回什么错误？
5. **无权限修改**: 只读线程或子代理线程

### 改进建议

1. **添加验证规则**:
   ```rust
   pub fn validate(&self) -> Result<(), ValidationError> {
       if self.name.len() > 256 {
           return Err(ValidationError::NameTooLong);
       }
       // 可选：检查控制字符
       if self.name.chars().any(|c| c.is_control()) {
           return Err(ValidationError::InvalidCharacters);
       }
       Ok(())
   }
   ```

2. **支持清除名称**:
   - 明确支持将名称设为 `null` 以清除自定义名称
   - 或约定空字符串表示恢复自动预览

3. **添加元数据**:
   ```rust
   pub struct ThreadSetNameParams {
       pub thread_id: String,
       pub name: String,
       pub updated_by: Option<String>,  // 修改者标识
       pub updated_at: Option<i64>,     // 修改时间戳
   }
   ```

4. **批量操作**:
   - 考虑支持批量设置多个线程的名称
   - 提高管理效率

5. **命名建议**:
   - 服务端可提供基于对话内容的命名建议
   - 帮助用户快速设置有意义的名称

6. **版本控制**:
   - 记录名称修改历史
   - 允许查看和恢复之前的名称

7. **国际化支持**:
   - 确保名称在各种语言环境下的正确显示
   - 考虑 RTL（从右到左）语言的布局

8. **响应增强**:
   ```typescript
   export type ThreadSetNameResponse = {
     previousName: string | null,  // 之前的名称
     updatedAt: number,            // 更新时间
   };
   ```
