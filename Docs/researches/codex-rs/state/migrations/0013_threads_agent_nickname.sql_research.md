# 0013_threads_agent_nickname.sql 研究文档

## 场景与职责

本迁移为 `threads` 表添加 `agent_nickname` 和 `agent_role` 字段，用于支持 Agent 子代理功能。这些字段标识由 AgentControl 创建的子代理会话，支持多代理协作场景。

## 功能点目的

### 1. 添加 agent_nickname 字段
- **字段**: `agent_nickname TEXT`
- **约束**: 可为空（NULL）
- **用途**: 子代理的随机唯一昵称

### 2. 添加 agent_role 字段
- **字段**: `agent_role TEXT`
- **约束**: 可为空（NULL）
- **用途**: 子代理的角色描述

### 使用场景
- **多代理协作**: 区分不同子代理的会话
- **UI 展示**: 在会话列表中显示代理昵称
- **权限控制**: 根据角色应用不同策略

## 具体技术实现

### 关键流程
1. **代理创建**: AgentControl 创建子代理时生成昵称和角色
2. **会话记录**: 将会话标记为子代理会话
3. **查询筛选**: 可按代理属性筛选会话

### 代码映射
在 `codex-rs/state/src/model/thread_metadata.rs` 中：
```rust
pub struct ThreadMetadata {
    // ...
    /// Optional random unique nickname assigned to an AgentControl-spawned sub-agent.
    pub agent_nickname: Option<String>,
    /// Optional role (agent_role) assigned to an AgentControl-spawned sub-agent.
    pub agent_role: Option<String>,
    // ...
}

pub struct ThreadMetadataBuilder {
    // ...
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
    // ...
}
```

在 `codex-rs/state/src/extract.rs` 中：
```rust
fn apply_session_meta_from_item(metadata: &mut ThreadMetadata, meta_line: &SessionMetaLine) {
    metadata.agent_nickname = meta_line.meta.agent_nickname.clone();
    metadata.agent_role = meta_line.meta.agent_role.clone();
    // ...
}
```

在 `codex-rs/state/src/runtime/threads.rs` 中：
```rust
pub async fn upsert_thread(&self, metadata: &crate::ThreadMetadata) -> anyhow::Result<()> {
    sqlx::query(
        r#"
INSERT INTO threads (
    // ...
    agent_nickname,
    agent_role,
    // ...
) VALUES (..., ?, ?, ...)
ON CONFLICT(id) DO UPDATE SET
    // ...
    agent_nickname = excluded.agent_nickname,
    agent_role = excluded.agent_role,
    // ...
        "#,
    )
    .bind(metadata.agent_nickname.as_deref())
    .bind(metadata.agent_role.as_deref())
    // ...
}
```

## 关键代码路径与文件引用

### 模型定义
- `codex-rs/state/src/model/thread_metadata.rs`:
  - `ThreadMetadata`: 包含代理字段
  - `ThreadMetadataBuilder`: 构建时设置代理属性
  - `ThreadRow`: 数据库行映射

### 数据提取
- `codex-rs/state/src/extract.rs`:
  - `apply_session_meta_from_item()`: 从 rollout 提取代理信息

### 数据写入
- `codex-rs/state/src/runtime/threads.rs`:
  - `upsert_thread()`: 写入代理字段
  - `insert_thread_if_absent()`: 条件插入时写入

### 协议层
- `codex-protocol/src/protocol.rs`:
  - `SessionMeta`: 包含 `agent_nickname` 和 `agent_role` 字段

## 依赖与外部交互

### 上游依赖
- `0001_threads.sql`: 基础 threads 表结构

### 下游依赖
- 无直接下游依赖

### 应用层交互
- `codex-rs/core/src/agent_control.rs`: 创建子代理
- `codex-rs/tui/src/components/thread_list.rs`: UI 展示代理信息

## 风险、边界与改进建议

### 风险
1. **昵称冲突**: 随机生成的昵称理论上可能冲突
2. **角色滥用**: 无验证的角色字段可能被滥用

### 边界情况
1. **普通会话**: 非代理会话这两个字段为 NULL
2. **Fork 会话**: 继承源会话的代理属性
3. **空字符串**: 与 NULL 的语义区别

### 改进建议
1. 考虑添加代理会话的索引（如果频繁按代理筛选）
2. 可为角色添加枚举约束（如果角色是预定义的）
3. 考虑添加代理层级字段（支持嵌套代理）
4. 添加代理会话的统计和监控
