# GhostCommit Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`GhostCommit` 是 Codex 中用于代码状态快照管理的核心类型。它代表一个"幽灵提交"——一种临时的 Git 提交，用于保存工作区的当前状态，而不影响正常的 Git 历史。

主要使用场景：
- **对话快照**：在对话开始时捕获代码库状态，支持后续回滚
- **安全检查点**：在执行可能修改文件的操作前创建恢复点
- **无痕迹恢复**：允许恢复到之前的状态而不留下 Git 历史记录

## 2. 功能点目的 (Purpose of This Type)

- **状态捕获**：保存当前工作目录的完整状态（包括未跟踪文件）
- **快速回滚**：支持快速恢复到捕获时的状态
- **隔离管理**：跟踪预存在的未跟踪文件，避免恢复时误删用户文件
- **临时存储**：幽灵提交通常在对话结束后被清理

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
export type GhostCommit = {
  id: string,
  parent: string | null,
  preexisting_untracked_files: Array<string>,
  preexisting_untracked_dirs: Array<string>,
};
```

```rust
// Rust 定义
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema, TS)]
pub struct GhostCommit {
    id: CommitID,
    parent: Option<CommitID>,
    preexisting_untracked_files: Vec<PathBuf>,
    preexisting_untracked_dirs: Vec<PathBuf>,
}

impl GhostCommit {
    pub fn new(
        id: CommitID,
        parent: Option<CommitID>,
        preexisting_untracked_files: Vec<PathBuf>,
        preexisting_untracked_dirs: Vec<PathBuf>,
    ) -> Self;
    
    pub fn id(&self) -> &str;
    pub fn parent(&self) -> Option<&str>;
    pub fn preexisting_untracked_files(&self) -> &[PathBuf];
    pub fn preexisting_untracked_dirs(&self) -> &[PathBuf];
}

impl fmt::Display for GhostCommit {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.id)
    }
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|-----|------|------|
| `id` | `string` | 幽灵提交的 Git commit SHA |
| `parent` | `string \| null` | 父提交的 SHA（如果有） |
| `preexisting_untracked_files` | `string[]` | 创建快照时已存在的未跟踪文件 |
| `preexisting_untracked_dirs` | `string[]` | 创建快照时已存在的未跟踪目录 |

### 实现模块

位于 `codex-utils-git` crate：
- `ghost_commits.rs`：核心实现
- `create_ghost_commit()`：创建幽灵提交
- `restore_ghost_commit()`：恢复幽灵提交
- `capture_ghost_snapshot_report()`：捕获快照报告

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/utils/git/src/lib.rs` (lines 40-89) | `GhostCommit` 结构体定义 |
| `/codex-rs/utils/git/src/ghost_commits.rs` | 幽灵提交操作实现 |
| `/codex-rs/protocol/src/models.rs` (line 440) | 在 `ResponseItem::GhostSnapshot` 中使用 |
| `/codex-rs/app-server-protocol/schema/typescript/GhostCommit.ts` | TypeScript 类型定义（生成） |

### 使用位置

```rust
// ResponseItem 枚举中使用
pub enum ResponseItem {
    // ...
    GhostSnapshot {
        ghost_commit: GhostCommit,
    },
    // ...
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `std::path::PathBuf`：路径处理
- `serde`：序列化/反序列化
- `schemars::JsonSchema`：JSON Schema 生成
- `ts_rs::TS`：TypeScript 类型生成

### 相关类型

- `GhostSnapshotConfig`：快照配置
- `GhostSnapshotReport`：快照报告
- `CreateGhostCommitOptions`：创建选项
- `RestoreGhostCommitOptions`：恢复选项

### 外部工具

- Git 命令行工具：实际执行提交和恢复操作

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **Git 依赖**：需要工作目录是 Git 仓库
2. **存储开销**：幽灵提交占用磁盘空间，需要定期清理
3. **并发问题**：多个操作同时创建幽灵提交可能导致冲突
4. **大文件处理**：未跟踪文件列表可能很大，影响序列化性能

### 改进建议

1. **自动清理**：添加定期清理过期幽灵提交的机制
2. **压缩存储**：考虑压缩快照数据
3. **增量快照**：支持增量式快照减少存储开销
4. **并发控制**：添加锁机制防止并发冲突

### 测试建议

- 测试非 Git 仓库的行为
- 测试大量未跟踪文件的场景
- 测试并发创建幽灵提交
- 测试恢复后文件权限保持

### 安全考虑

- 幽灵提交可能包含敏感文件，需要确保适当的访问控制
- 恢复操作应验证提交 ID 的有效性
- 防止通过恶意构造的幽灵提交路径进行目录遍历攻击
