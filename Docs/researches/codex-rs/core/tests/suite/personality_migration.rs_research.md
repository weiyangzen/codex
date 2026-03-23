# personality_migration.rs 研究文档

## 场景与职责

`personality_migration.rs` 是 Codex Core 的集成测试套件，专门测试 **Personality Migration（人格配置迁移）** 功能。该功能负责在 Codex 升级时自动为用户设置默认人格配置，确保现有用户在启用 Personality 功能后有合理的默认行为。

迁移逻辑的核心目标是：
- **新用户**（无历史会话）：不设置人格，使用系统默认
- **老用户**（有历史会话）：自动设置 `personality = "pragmatic"`，保持与之前行为一致
- **已配置用户**：尊重现有配置，不做修改

## 功能点目的

### 1. 向后兼容性保障
当 Personality 功能推出时，已有历史会话的用户应该继续使用务实型（Pragmatic）风格，这与 Codex 之前的默认行为一致。

### 2. 幂等性保证
迁移操作可以安全地多次执行，不会重复修改配置。

### 3. 显式配置保护
如果用户已显式设置人格（全局或 Profile 级别），迁移应跳过，尊重用户选择。

### 4. 会话检测
通过检测历史会话（包括归档会话）来判断用户是否为"老用户"。

## 具体技术实现

### 关键数据结构

```rust
// 迁移状态枚举
codex-rs/core/src/personality_migration.rs
pub enum PersonalityMigrationStatus {
    SkippedMarker,           // 已存在迁移标记文件
    SkippedExplicitPersonality, // 用户已显式设置人格
    SkippedNoSessions,       // 无历史会话
    Applied,                 // 迁移成功应用
}

// 迁移标记文件名
pub const PERSONALITY_MIGRATION_FILENAME: &str = ".personality_migration";
```

### 迁移判断流程

```rust
pub async fn maybe_migrate_personality(
    codex_home: &Path,
    config_toml: &ConfigToml,
) -> io::Result<PersonalityMigrationStatus> {
    // 1. 检查迁移标记文件
    if marker_exists { return SkippedMarker; }
    
    // 2. 检查显式配置
    if config_toml.personality.is_some() || profile.personality.is_some() {
        create_marker();
        return SkippedExplicitPersonality;
    }
    
    // 3. 检查历史会话
    if !has_recorded_sessions(codex_home, provider).await? {
        create_marker();
        return SkippedNoSessions;
    }
    
    // 4. 执行迁移
    ConfigEditsBuilder::new(codex_home)
        .set_personality(Some(Personality::Pragmatic))
        .apply()
        .await?;
    create_marker();
    Ok(Applied)
}
```

### 会话检测机制

```rust
async fn has_recorded_sessions(codex_home: &Path, default_provider: &str) -> io::Result<bool> {
    // 检查顺序：
    // 1. SQLite state_db 中的会话记录
    // 2. SESSIONS_SUBDIR 目录中的 rollout 文件
    // 3. ARCHIVED_SESSIONS_SUBDIR 目录中的归档会话
}
```

### 核心测试用例

| 测试函数 | 场景 | 预期结果 |
|---------|------|---------|
| `migration_marker_exists_no_sessions_no_change` | 标记文件已存在，无会话 | `SkippedMarker`，不创建 config.toml |
| `no_marker_no_sessions_no_change` | 无标记，无会话 | `SkippedNoSessions`，创建标记 |
| `no_marker_sessions_sets_personality` | 无标记，有会话 | `Applied`，设置 `personality = Pragmatic` |
| `no_marker_sessions_preserves_existing_config_fields` | 有现有配置 | 保留现有字段，仅添加 personality |
| `no_marker_meta_only_rollout_is_treated_as_no_sessions` | 只有 meta 的 rollout | `SkippedNoSessions` |
| `no_marker_explicit_global_personality_skips_migration` | 全局显式设置 | `SkippedExplicitPersonality` |
| `no_marker_profile_personality_skips_migration` | Profile 级别设置 | `SkippedExplicitPersonality` |
| `applied_migration_is_idempotent_on_second_run` | 重复执行 | 第一次 `Applied`，第二次 `SkippedMarker` |
| `no_marker_archived_sessions_sets_personality` | 只有归档会话 | `Applied` |

### 测试辅助函数

```rust
// 创建包含用户事件的会话文件
async fn write_session_with_user_event(codex_home: &Path) -> io::Result<()>

// 创建仅包含 meta 的会话文件
async fn write_session_with_meta_only(codex_home: &Path) -> io::Result<()>

// 创建归档会话
async fn write_archived_session_with_user_event(codex_home: &Path) -> io::Result<()>

// 读取并解析 config.toml
async fn read_config_toml(codex_home: &Path) -> io::Result<ConfigToml>
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|-----|------|
| `codex_core::personality_migration::*` | 被测试的核心迁移逻辑 |
| `codex_core::config::ConfigToml` | 配置解析 |
| `codex_core::rollout::*` | 会话存储路径常量 |
| `codex_protocol::ThreadId` | 会话 ID 生成 |
| `codex_protocol::protocol::*` | Rollout 数据结构 |

### 关键常量

```rust
// 会话存储路径
SESSIONS_SUBDIR = "sessions"           // 活跃会话
ARCHIVED_SESSIONS_SUBDIR = "archived"  // 归档会话

// Rollout 文件命名格式
rollout-{timestamp}-{thread_id}.jsonl
```

### Rollout 文件结构

```json
{"timestamp": "2025-01-01T00-00-00", "item": {"type": "session_meta", "meta": {...}}}
{"timestamp": "2025-01-01T00-00-00", "item": {"type": "event", "event": {"type": "user_message", ...}}}
```

## 风险、边界与改进建议

### 已知边界

1. **Profile 解析错误**: 如果配置的 Profile 不存在，迁移会返回错误且**不**创建标记文件，允许修复后重试。

2. **仅 meta 的 rollout**: 只包含 `SessionMeta` 没有用户事件的 rollout 被视为"无会话"，这是为了区分真正使用过的会话和空会话。

3. **多 Provider 支持**: 迁移检测特定于 model provider，但 personality 设置是全局的。

### 潜在风险

1. **并发执行**: 如果多个 Codex 实例同时启动，可能产生竞态条件。当前通过 `create_new(true)` 原子创建标记文件来缓解。

2. **磁盘空间**: 标记文件（`.personality_migration`）永久存在，但体积可忽略。

3. **配置覆盖**: 迁移使用 `ConfigEditsBuilder`，如果配置在迁移过程中被外部修改，可能导致冲突。

### 改进建议

1. **迁移日志**: 添加更详细的迁移日志，便于排查问题。

2. **迁移回滚**: 考虑添加迁移回滚机制，允许用户撤销自动设置的人格。

3. **批量迁移报告**: 对于企业部署，提供迁移报告汇总功能。

4. **异步迁移**: 考虑将迁移改为异步执行，不阻塞启动流程。

5. **迁移验证**: 添加迁移后验证步骤，确保配置正确写入。

### 相关文件引用

- 测试文件: `codex-rs/core/tests/suite/personality_migration.rs` (336 行)
- 核心实现: `codex-rs/core/src/personality_migration.rs` (135 行)
- 单元测试: `codex-rs/core/src/personality_migration_tests.rs` (133 行)
- 配置编辑: `codex-rs/core/src/config/edit.rs`
- Rollout 列表: `codex-rs/core/src/rollout/list.rs`
