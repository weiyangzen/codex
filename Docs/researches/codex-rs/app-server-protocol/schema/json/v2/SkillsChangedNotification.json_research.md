# SkillsChangedNotification.json 研究文档

## 场景与职责

`SkillsChangedNotification` 是 Codex App-Server Protocol v2 API 中的服务器通知类型，用于通知客户端本地技能文件已发生变更。该通知作为失效信号（invalidation signal），提示客户端需要重新获取技能元数据。

## 功能点目的

1. **技能变更通知**: 当被监视的本地技能文件发生变化时通知客户端
2. **缓存失效信号**: 提示客户端当前缓存的技能元数据可能已过时
3. **实时同步**: 支持技能文件的实时监视和同步
4. **性能优化**: 避免客户端频繁轮询，采用推送式更新通知

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsChangedNotification {}
```

### 字段说明

该通知是一个空对象，不包含任何字段。这种设计遵循"失效信号"模式：
- 通知本身仅表示"有变化发生"
- 客户端需要主动调用 `skills/list` 获取最新数据
- 避免在通知中传输大量变更详情

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "Notification emitted when watched local skill files change.\n\nTreat this as an invalidation signal and re-run `skills/list` with the client's current parameters when refreshed skill metadata is needed.",
  "title": "SkillsChangedNotification",
  "type": "object"
}
```

## 关键代码路径与文件引用

### 源文件位置
- **Rust 结构定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `SkillsChangedNotification`: 第 4656 行附近

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsChangedNotification {}
```

### Schema 生成
- **生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`
- **生成函数**: `export_server_notification_schemas()` 在 `common.rs` 中定义

### 使用位置
- **ServerNotification 定义**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 882 行
```rust
SkillsChanged => "skills/changed" (v2::SkillsChangedNotification),
```

### 关联请求类型
- `SkillsListParams`: 获取技能列表的请求参数
  - `cwds`: 工作目录列表
  - `force_reload`: 强制重新扫描
  - `per_cwd_extra_user_roots`: 每工作目录的额外用户根目录

- `SkillsListResponse`: 技能列表响应
  - `data`: 按工作目录分组的技能列表

## 依赖与外部交互

### 内部依赖
1. **schemars**: JSON Schema 生成
2. **ts_rs**: TypeScript 类型生成
3. **serde**: 序列化/反序列化

### 外部交互
1. **文件系统监视**: 监视 `.codex/skills/` 等目录的文件变更
2. **技能扫描器**: 重新扫描和解析技能文件
3. **客户端缓存**: 触发客户端缓存失效和刷新

### 数据流
```
File System Change (skill file modified)
  -> File Watcher
    -> SkillsChangedNotification
      -> Client
        -> skills/list request (with force_reload: true)
          -> Server
            -> SkillsListResponse (updated metadata)
```

### 客户端处理逻辑
```typescript
// 伪代码示例
let skillsCache: SkillsListResponse | null = null;
let isRefreshing = false;

onSkillsChanged(notification) {
  // 标记缓存为失效
  skillsCache = null;
  
  // 如果需要，触发刷新
  if (shouldAutoRefresh()) {
    refreshSkills();
  }
}

async function refreshSkills() {
  if (isRefreshing) return;
  isRefreshing = true;
  
  try {
    const response = await callSkillsList({
      cwds: getCurrentCwds(),
      forceReload: true  // 重要：绕过缓存
    });
    skillsCache = response;
    updateSkillsUI(response);
  } finally {
    isRefreshing = false;
  }
}
```

## 风险、边界与改进建议

### 风险点
1. **通知风暴**: 批量文件变更可能导致大量通知
2. **竞态条件**: 客户端刷新时文件可能再次变更
3. **网络延迟**: 通知到达前客户端可能使用过时的缓存
4. **重复刷新**: 多个通知可能导致不必要的重复刷新

### 边界情况
1. **频繁变更**: 技能文件被频繁修改（如保存时）
2. **批量变更**: 多个技能文件同时变更
3. **无效变更**: 文件变更但内容未实际改变
4. **权限问题**: 文件变更但客户端无法读取

### 改进建议
1. **添加变更类型**: 区分创建、修改、删除：
   ```rust
   pub struct SkillsChangedNotification {
       pub change_type: SkillChangeType,  // Created | Modified | Deleted
       pub skill_path: Option<String>,    // 受影响的技能路径
   }
   ```

2. **添加变更摘要**: 提供变更概览，避免不必要的全量刷新：
   ```rust
   pub struct SkillsChangedNotification {
       // ... existing fields
       pub affected_skills: Vec<String>,  // 受影响的技能名称列表
       pub change_timestamp: i64,         // 变更时间戳
   }
   ```

3. **防抖机制**: 服务器端合并短时间内的多次变更：
   ```rust
   pub struct SkillsChangedNotification {
       // ... existing fields
       pub is_batch: bool,                // 是否为批量变更
       pub batch_size: u32,               // 批量中的变更数量
   }
   ```

4. **版本标记**: 支持基于版本的缓存验证：
   ```rust
   pub struct SkillsChangedNotification {
       pub skills_version: String,        // 技能元数据版本
   }
   
   // 客户端请求时携带版本
   pub struct SkillsListParams {
       // ... existing fields
       pub if_none_match: Option<String>, // 条件请求
   }
   ```

5. **选择性刷新**: 允许客户端指定只刷新特定范围：
   ```rust
   pub struct SkillsChangedNotification {
       // ... existing fields
       pub scope: ChangeScope,            // user | repo | system | all
   }
   ```

6. **心跳机制**: 定期发送通知确认连接正常，同时作为隐式的"无变更"信号
