# 0005_threads_cli_version.sql 研究文档

## 场景与职责

本迁移为 `threads` 表添加 `cli_version` 字段，用于记录创建会话的 Codex CLI 版本号。这有助于版本兼容性管理、问题追踪和功能演进分析。

## 功能点目的

### 1. 添加 cli_version 字段
- **字段**: `cli_version TEXT`
- **约束**: `NOT NULL DEFAULT ''`
- **用途**: 存储创建会话的 CLI 版本号

### 默认值设计
- 使用空字符串作为默认值，确保与现有数据兼容
- 后续通过 rollout 文件中的 `SessionMeta` 回填实际版本

## 具体技术实现

### 关键流程
1. **版本提取**: 从 `SessionMetaLine` 的 `cli_version` 字段提取
2. **元数据构建**: 在 `ThreadMetadataBuilder` 中设置版本
3. **数据回填**: 通过 rollout 文件解析更新现有记录

### 代码映射
在 `codex-rs/state/src/extract.rs` 中：
```rust
fn apply_session_meta_from_item(metadata: &mut ThreadMetadata, meta_line: &SessionMetaLine) {
    if !meta_line.meta.cli_version.is_empty() {
        metadata.cli_version = meta_line.meta.cli_version.clone();
    }
}
```

在 `codex-rs/state/src/model/thread_metadata.rs` 中：
```rust
pub struct ThreadMetadataBuilder {
    pub cli_version: Option<String>,
    // ...
}

impl ThreadMetadataBuilder {
    pub fn build(&self, default_provider: &str) -> ThreadMetadata {
        ThreadMetadata {
            cli_version: self.cli_version.clone().unwrap_or_default(),
            // ...
        }
    }
}
```

## 关键代码路径与文件引用

### 版本提取
- `codex-rs/state/src/extract.rs`:
  - `apply_session_meta_from_item()`: 从 rollout 提取版本

### 元数据构建
- `codex-rs/state/src/model/thread_metadata.rs`:
  - `ThreadMetadataBuilder::build()`: 构建时设置默认值

### 数据写入
- `codex-rs/state/src/runtime/threads.rs`:
  - `upsert_thread()`: 插入/更新时写入版本
  - `insert_thread_if_absent()`: 条件插入时写入版本

## 依赖与外部交互

### 上游依赖
- `0001_threads.sql`: 基础 threads 表结构

### 下游依赖
- 无直接下游依赖

### 协议层
- `codex-protocol/src/protocol.rs`: `SessionMeta` 定义 `cli_version` 字段

## 风险、边界与改进建议

### 风险
1. **版本格式**: 无格式验证，可能存储任意字符串
2. **空值处理**: 默认空字符串与真实空值语义相同

### 边界情况
1. **版本演进**: 旧版本创建的会话版本号为空
2. **fork 会话**: 继承源会话的 CLI 版本

### 改进建议
1. 考虑添加版本号格式验证（如 semver）
2. 可为版本号添加索引（如果频繁按版本查询）
3. 考虑存储客户端类型（CLI、VSCode 扩展等）
