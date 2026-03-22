# personality_migration_tests.rs 深度研究文档

## 场景与职责

`personality_migration_tests.rs` 是 `personality_migration.rs` 的配套测试模块，提供对个性配置迁移逻辑的单元测试覆盖。测试验证迁移的各种场景：正常应用、跳过条件、幂等性等。

## 功能点目的

### 1. 正常迁移测试 (`applies_when_sessions_exist_and_no_personality`)
- **目的**：验证当有历史会话且未设置个性时，迁移正确应用
- **测试场景**：
  - 创建历史会话文件
  - 调用迁移函数
  - 验证个性设置为 `Pragmatic`
  - 验证标记文件创建

### 2. 标记文件跳过测试 (`skips_when_marker_exists`)
- **目的**：验证当标记文件存在时，迁移被跳过
- **测试场景**：
  - 预先创建标记文件
  - 调用迁移函数
  - 验证返回 `SkippedMarker`
  - 验证不创建配置文件

### 3. 显式个性跳过测试 (`skips_when_personality_explicit`)
- **目的**：验证当用户已显式设置个性时，迁移被跳过
- **测试场景**：
  - 预先设置个性为 `Friendly`
  - 调用迁移函数
  - 验证返回 `SkippedExplicitPersonality`
  - 验证个性保持为 `Friendly`

### 4. 无会话跳过测试 (`skips_when_no_sessions`)
- **目的**：验证当无历史会话时，迁移被跳过
- **测试场景**：
  - 空 Codex 主目录
  - 调用迁移函数
  - 验证返回 `SkippedNoSessions`
  - 验证标记文件创建（防止未来重复检查）

## 具体技术实现

### 测试结构

```rust
use super::*;
use codex_protocol::ThreadId;
use codex_protocol::protocol::EventMsg;
use codex_protocol::protocol::RolloutItem;
use codex_protocol::protocol::RolloutLine;
use codex_protocol::protocol::SessionMeta;
use codex_protocol::protocol::SessionMetaLine;
use codex_protocol::protocol::SessionSource;
use codex_protocol::protocol::UserMessageEvent;
use pretty_assertions::assert_eq;
use tempfile::TempDir;
use tokio::io::AsyncWriteExt;
```

### 辅助函数

```rust
const TEST_TIMESTAMP: &str = "2025-01-01T00-00-00";

// 读取配置文件
async fn read_config_toml(codex_home: &Path) -> io::Result<ConfigToml> {
    let contents = tokio::fs::read_to_string(codex_home.join("config.toml")).await?;
    toml::from_str(&contents).map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))
}

// 创建带用户事件的会话
async fn write_session_with_user_event(codex_home: &Path) -> io::Result<()> {
    let thread_id = ThreadId::new();
    let dir = codex_home
        .join(SESSIONS_SUBDIR)
        .join("2025")
        .join("01")
        .join("01");
    tokio::fs::create_dir_all(&dir).await?;
    let file_path = dir.join(format!("rollout-{TEST_TIMESTAMP}-{thread_id}.jsonl"));
    let mut file = tokio::fs::File::create(&file_path).await?;
    
    // 构造会话元数据和用户事件...
    let session_meta = SessionMetaLine { ... };
    let user_event = RolloutLine { ... };
    
    file.write_all(format!("{}\n", serde_json::to_string(&meta_line)?).as_bytes())
        .await?;
    file.write_all(format!("{}\n", serde_json::to_string(&user_event)?).as_bytes())
        .await?;
    Ok(())
}
```

### 测试实现

```rust
#[tokio::test]
async fn applies_when_sessions_exist_and_no_personality() -> io::Result<()> {
    let temp = TempDir::new()?;
    write_session_with_user_event(temp.path()).await?;
    
    let config_toml = ConfigToml::default();
    let status = maybe_migrate_personality(temp.path(), &config_toml).await?;
    
    assert_eq!(status, PersonalityMigrationStatus::Applied);
    assert!(temp.path().join(PERSONALITY_MIGRATION_FILENAME).exists());
    
    let persisted = read_config_toml(temp.path()).await?;
    assert_eq!(persisted.personality, Some(Personality::Pragmatic));
    Ok(())
}

#[tokio::test]
async fn skips_when_marker_exists() -> io::Result<()> {
    let temp = TempDir::new()?;
    create_marker(&temp.path().join(PERSONALITY_MIGRATION_FILENAME)).await?;
    
    let config_toml = ConfigToml::default();
    let status = maybe_migrate_personality(temp.path(), &config_toml).await?;
    
    assert_eq!(status, PersonalityMigrationStatus::SkippedMarker);
    assert!(!temp.path().join("config.toml").exists());
    Ok(())
}

#[tokio::test]
async fn skips_when_personality_explicit() -> io::Result<()> {
    let temp = TempDir::new()?;
    ConfigEditsBuilder::new(temp.path())
        .set_personality(Some(Personality::Friendly))
        .apply()
        .await
        .map_err(|err| io::Error::other(format!("failed to write config: {err}")))?;
    
    let config_toml = read_config_toml(temp.path()).await?;
    let status = maybe_migrate_personality(temp.path(), &config_toml).await?;
    
    assert_eq!(status, PersonalityMigrationStatus::SkippedExplicitPersonality);
    assert!(temp.path().join(PERSONALITY_MIGRATION_FILENAME).exists());
    
    let persisted = read_config_toml(temp.path()).await?;
    assert_eq!(persisted.personality, Some(Personality::Friendly));
    Ok(())
}

#[tokio::test]
async fn skips_when_no_sessions() -> io::Result<()> {
    let temp = TempDir::new()?;
    let config_toml = ConfigToml::default();
    let status = maybe_migrate_personality(temp.path(), &config_toml).await?;
    
    assert_eq!(status, PersonalityMigrationStatus::SkippedNoSessions);
    assert!(temp.path().join(PERSONALITY_MIGRATION_FILENAME).exists());
    assert!(!temp.path().join("config.toml").exists());
    Ok(())
}
```

## 关键代码路径与文件引用

### 测试函数清单

| 测试函数 | 行号 | 测试目标 |
|----------|------|----------|
| `read_config_toml` | 16-19 | 辅助：读取配置 |
| `write_session_with_user_event` | 21-69 | 辅助：创建测试会话 |
| `applies_when_sessions_exist_and_no_personality` | 71-85 | 正常迁移 |
| `skips_when_marker_exists` | 87-98 | 标记文件跳过 |
| `skips_when_personality_explicit` | 100-121 | 显式个性跳过 |
| `skips_when_no_sessions` | 123-133 | 无会话跳过 |

### 被测函数覆盖

| 被测函数 | 测试覆盖 |
|----------|----------|
| `maybe_migrate_personality` | 所有测试 |
| `has_recorded_sessions` | `applies_when_sessions_exist_*`, `skips_when_no_sessions` |
| `create_marker` | 所有测试（通过辅助函数或直接调用） |

### 辅助函数使用

| 辅助函数 | 用途 |
|----------|------|
| `TempDir::new()` | 创建临时测试目录 |
| `ConfigEditsBuilder` | 构建和写入测试配置 |
| `ThreadId::new()` | 生成唯一线程 ID |
| `serde_json::to_string` | 序列化会话数据 |

## 依赖与外部交互

### 测试依赖

```rust
// 被测模块
use super::*;

// 协议类型
codex_protocol::ThreadId
codex_protocol::protocol::EventMsg
codex_protocol::protocol::RolloutItem
codex_protocol::protocol::RolloutLine
codex_protocol::protocol::SessionMeta
codex_protocol::protocol::SessionMetaLine
codex_protocol::protocol::SessionSource
codex_protocol::protocol::UserMessageEvent

// 断言增强
use pretty_assertions::assert_eq;

// 临时目录
use tempfile::TempDir;

// 异步文件操作
use tokio::io::AsyncWriteExt;
```

### 隐式依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `ConfigToml` | crate::config | 默认配置 |
| `Personality` | codex_protocol | 个性枚举 |
| `PersonalityMigrationStatus` | personality_migration | 迁移状态 |
| `SESSIONS_SUBDIR` | crate::rollout | 会话目录 |

## 风险、边界与改进建议

### 当前测试覆盖 gaps

1. **并发测试缺失**
   - 没有测试多进程同时执行迁移
   - 没有测试竞态条件处理

2. **错误场景测试缺失**
   - 没有测试配置编辑失败
   - 没有测试文件系统权限问题
   - 没有测试损坏的会话文件

3. **边界条件测试缺失**
   - 没有测试空会话文件
   - 没有测试只有归档会话的场景
   - 没有测试 SQLite 数据库存在但为空

4. **提供商切换测试缺失**
   - 没有测试非默认提供商的会话检测

5. **标记文件版本测试缺失**
   - 没有测试标记文件内容验证
   - 没有测试未来版本升级场景

### 改进建议

1. **添加并发测试**
```rust
#[tokio::test]
async fn concurrent_migrations_are_safe() -> io::Result<()> {
    let temp = TempDir::new()?;
    write_session_with_user_event(temp.path()).await?;
    
    let mut handles = vec![];
    for _ in 0..5 {
        let path = temp.path().to_path_buf();
        handles.push(tokio::spawn(async move {
            let config_toml = ConfigToml::default();
            maybe_migrate_personality(&path, &config_toml).await
        }));
    }
    
    let results: Vec<_> = futures::future::join_all(handles).await;
    // 验证只有一个 Applied，其他为 SkippedMarker
    let applied_count = results.iter()
        .filter(|r| matches!(r, Ok(PersonalityMigrationStatus::Applied)))
        .count();
    assert_eq!(applied_count, 1);
    Ok(())
}
```

2. **添加错误处理测试**
```rust
#[tokio::test]
async fn handles_readonly_config_directory() -> io::Result<()> {
    let temp = TempDir::new()?;
    write_session_with_user_event(temp.path()).await?;
    
    // 设置只读权限
    let mut perms = tokio::fs::metadata(temp.path()).await?.permissions();
    perms.set_readonly(true);
    tokio::fs::set_permissions(temp.path(), perms).await?;
    
    let config_toml = ConfigToml::default();
    let result = maybe_migrate_personality(temp.path(), &config_toml).await;
    
    // 应该返回错误
    assert!(result.is_err());
    Ok(())
}
```

3. **添加边界条件测试**
```rust
#[tokio::test]
async fn detects_archived_sessions_only() -> io::Result<()> {
    let temp = TempDir::new()?;
    // 只创建归档会话...
    
    let config_toml = ConfigToml::default();
    let status = maybe_migrate_personality(temp.path(), &config_toml).await?;
    
    assert_eq!(status, PersonalityMigrationStatus::Applied);
    Ok(())
}

#[tokio::test]
async fn handles_empty_session_file() -> io::Result<()> {
    let temp = TempDir::new()?;
    // 创建空会话文件...
    
    let config_toml = ConfigToml::default();
    let status = maybe_migrate_personality(temp.path(), &config_toml).await?;
    
    // 应该视为无有效会话
    assert_eq!(status, PersonalityMigrationStatus::SkippedNoSessions);
    Ok(())
}
```

4. **使用 insta snapshot 测试**
   - 对会话文件格式进行快照测试
   - 便于检测意外的格式变化

5. **提取公共辅助函数**
```rust
async fn create_test_session(
    codex_home: &Path,
    timestamp: &str,
) -> io::Result<ThreadId> {
    // 提取公共会话创建逻辑
}

async fn create_archived_session(
    codex_home: &Path,
) -> io::Result<()> {
    // 创建归档会话
}
```

### 测试代码质量建议

1. **减少重复代码**
   - `write_session_with_user_event` 中的会话数据构造可以提取常量
   - 多个测试重复创建 `ConfigToml::default()`

2. **改进断言消息**
   - 添加更多上下文到断言失败消息

3. **添加文档注释**
   - 为辅助函数添加文档说明

4. **使用参数化测试**
   - 使用 `rstest` 测试多种个性值
