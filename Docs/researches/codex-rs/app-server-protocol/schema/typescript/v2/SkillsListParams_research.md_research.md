# SkillsListParams 研究文档

## 场景与职责

`SkillsListParams` 是 Codex App Server Protocol v2 API 中 `skills/list` 方法的请求参数类型。该类型定义了查询可用技能列表时的完整参数集，支持多工作目录查询、缓存控制和自定义技能扫描路径。

### 使用场景

1. **初始化技能列表**：客户端启动时获取当前工作目录下的可用技能
2. **多工作区查询**：VS Code 等多工作区客户端查询多个文件夹的技能
3. **刷新技能列表**：用户手动刷新或检测到技能文件变化时强制重新扫描
4. **自定义技能路径**：从非标准位置加载项目特定的技能库

## 功能点目的

### 核心功能

- **多目录批量查询**：支持一次查询多个工作目录的技能
- **缓存控制**：通过 `forceReload` 参数控制是否使用缓存
- **灵活的技能发现**：支持为每个目录指定额外的技能扫描路径
- **默认回退**：当未指定工作目录时，使用服务器当前会话的工作目录

### 字段说明

| 字段 | 类型 | 可选 | 说明 |
|------|------|------|------|
| `cwds` | `string[]` | 是 | 要查询的工作目录列表，为空时使用默认目录 |
| `forceReload` | `boolean` | 是 | 是否绕过缓存强制重新扫描 |
| `perCwdExtraUserRoots` | `SkillsListExtraRootsForCwd[] \| null` | 是 | 每个目录的额外技能扫描路径 |

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3065-3078
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListParams {
    /// When empty, defaults to the current session working directory.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub cwds: Vec<PathBuf>,

    /// When true, bypass the skills cache and re-scan skills from disk.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_reload: bool,

    /// Optional per-cwd extra roots to scan as user-scoped skills.
    #[serde(default)]
    #[ts(optional = nullable)]
    pub per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>,
}
```

### 关键处理流程

1. **请求路由**：`ClientRequest::SkillsList` 在 `common.rs` 中定义
   ```rust
   // codex-rs/app-server-protocol/src/protocol/common.rs:295-298
   SkillsList => "skills/list" {
       params: v2::SkillsListParams,
       response: v2::SkillsListResponse,
   }
   ```

2. **请求处理入口**：`CodexMessageProcessor::skills_list()`
   ```rust
   // codex-rs/app-server/src/codex_message_processor.rs:5385-5440
   async fn skills_list(&self, request_id: ConnectionRequestId, params: SkillsListParams) {
       let SkillsListParams {
           cwds,
           force_reload,
           per_cwd_extra_user_roots,
       } = params;
       
       // 处理默认 cwd
       let cwds = if cwds.is_empty() {
           vec![self.config.cwd.clone()]
       } else {
           cwds
       };
       let cwd_set: HashSet<PathBuf> = cwds.iter().cloned().collect();

       // 处理 per-cwd extra roots
       let mut extra_roots_by_cwd: HashMap<PathBuf, Vec<PathBuf>> = HashMap::new();
       for entry in per_cwd_extra_user_roots.unwrap_or_default() {
           // 验证 cwd 是否在请求列表中
           if !cwd_set.contains(&entry.cwd) {
               warn!("ignoring per-cwd extra roots for cwd not present in skills/list cwds");
               continue;
           }
           
           // 验证 extra roots 为绝对路径
           for root in entry.extra_user_roots {
               if !root.is_absolute() {
                   self.send_invalid_request_error(request_id, "paths must be absolute").await;
                   return;
               }
           }
           extra_roots_by_cwd.insert(entry.cwd, entry.extra_user_roots);
       }
       
       // 调用技能管理器获取技能列表
       match self.thread_manager.skills_manager()
           .list_skills(cwds, force_reload, extra_roots_by_cwd)
           .await 
       {
           Ok(results) => {
               let response = SkillsListResponse {
                   data: results.into_iter()
                       .map(|(cwd, skills, errors)| SkillsListEntry { cwd, skills, errors })
                       .collect(),
               };
               self.outgoing.send_response(request_id, response).await;
           }
           Err(err) => { /* 发送错误响应 */ }
       }
   }
   ```

3. **缓存机制**：
   - `force_reload = false`：优先使用缓存结果
   - `force_reload = true`：绕过缓存，强制重新扫描磁盘
   - 缓存键包含 cwd 和 extra roots 配置

### 生成的 TypeScript 类型

```typescript
// GENERATED CODE! DO NOT MODIFY BY HAND!
import type { SkillsListExtraRootsForCwd } from "./SkillsListExtraRootsForCwd";

export type SkillsListParams = { 
    /**
     * When empty, defaults to the current session working directory.
     */
    cwds?: Array<string>, 
    /**
     * When true, bypass the skills cache and re-scan skills from disk.
     */
    forceReload?: boolean, 
    /**
     * Optional per-cwd extra roots to scan as user-scoped skills.
     */
    perCwdExtraUserRoots?: Array<SkillsListExtraRootsForCwd> | null, 
};
```

### JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "SkillsListExtraRootsForCwd": {
      "properties": {
        "cwd": { "type": "string" },
        "extraUserRoots": {
          "items": { "type": "string" },
          "type": "array"
        }
      },
      "required": ["cwd", "extraUserRoots"],
      "type": "object"
    }
  },
  "properties": {
    "cwds": {
      "description": "When empty, defaults to the current session working directory.",
      "items": { "type": "string" },
      "type": "array"
    },
    "forceReload": {
      "description": "When true, bypass the skills cache and re-scan skills from disk.",
      "type": "boolean"
    },
    "perCwdExtraUserRoots": {
      "default": null,
      "description": "Optional per-cwd extra roots to scan as user-scoped skills.",
      "items": { "$ref": "#/definitions/SkillsListExtraRootsForCwd" },
      "type": ["array", "null"]
    }
  },
  "title": "SkillsListParams",
  "type": "object"
}
```

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3065-3078` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:295-298` | 客户端请求路由定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListParams.ts` | 生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/SkillsListParams.json` | JSON Schema 定义 |

### 服务端实现

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs:5385-5440` | `skills_list` 方法实现 |
| `codex-rs/app-server/src/codex_message_processor.rs:704-707` | 请求路由分发 |

### 测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/skills_list.rs` | 完整集成测试套件 |

## 依赖与外部交互

### 上游依赖

1. **SkillsListExtraRootsForCwd**：嵌套类型，定义每个目录的额外扫描路径
2. **配置系统**：获取默认工作目录 (`self.config.cwd`)
3. **技能管理器**：`thread_manager.skills_manager()` 执行实际的技能发现

### 下游影响

1. **SkillsListResponse**：返回与请求参数对应的技能列表
2. **缓存系统**：`force_reload` 影响缓存命中/失效行为
3. **文件系统**：触发技能目录的扫描操作

### 请求-响应流程

```
ClientRequest::SkillsList
├── params: SkillsListParams
│   ├── cwds: Vec<PathBuf>
│   ├── force_reload: bool
│   └── per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>
│
└── response: SkillsListResponse
    └── data: Vec<SkillsListEntry>
        ├── cwd: PathBuf
        ├── skills: Vec<SkillMetadata>
        └── errors: Vec<SkillErrorInfo>
```

## 风险、边界与改进建议

### 潜在风险

1. **性能风险**：
   - 大量 cwd 或深层目录扫描可能导致请求超时
   - `force_reload = true` 时所有请求都触发磁盘扫描，可能压垮文件系统

2. **安全风险**：
   - `perCwdExtraUserRoots` 中的路径需要严格验证，防止路径遍历攻击
   - 当前仅验证绝对路径，未验证路径是否在允许范围内

3. **缓存一致性**：
   - 多个客户端并发修改技能配置时，缓存可能不一致
   - 文件系统 watcher 可能遗漏某些变更事件

### 边界情况

1. **空 cwds 数组**：使用服务器默认工作目录
2. **无效路径**：cwd 或 extra roots 指向不存在的目录
3. **重复 cwd**：请求数组中包含重复的工作目录
4. **权限不足**：某些目录因权限问题无法访问
5. **超长路径**：极端长的路径可能导致序列化问题

### 测试覆盖

集成测试覆盖了以下场景：

```rust
// 1. 从额外根目录加载技能
async fn skills_list_includes_skills_from_per_cwd_extra_user_roots()

// 2. 拒绝相对路径的 extra roots
async fn skills_list_rejects_relative_extra_user_roots()

// 3. 忽略未知 cwd 的 extra roots
async fn skills_list_ignores_per_cwd_extra_roots_for_unknown_cwd()

// 4. 缓存行为验证
async fn skills_list_uses_cached_result_until_force_reload()

// 5. 技能变更通知
async fn skills_changed_notification_is_emitted_after_skill_change()
```

### 改进建议

1. **添加分页支持**：对于大量工作目录的查询，考虑添加分页参数
   ```rust
   pub struct SkillsListParams {
       // ... existing fields
       pub cursor: Option<String>,
       pub limit: Option<u32>,
   }
   ```

2. **添加超时控制**：允许客户端指定扫描超时时间
   ```rust
   pub struct SkillsListParams {
       // ... existing fields
       pub timeout_ms: Option<u64>,
   }
   ```

3. **路径白名单**：限制 extra roots 必须在特定白名单内
   ```rust
   // 在配置中添加 allowed_skill_roots
   pub struct Config {
       // ...
       pub allowed_skill_roots: Vec<PathBuf>,
   }
   ```

4. **选择性字段返回**：允许客户端指定只需要特定字段，减少传输开销
   ```rust
   pub struct SkillsListParams {
       // ... existing fields
       pub include_disabled: bool,  // 是否包含禁用的技能
       pub include_errors: bool,    // 是否包含错误信息
   }
   ```

5. **添加过滤条件**：支持按作用域、启用状态等过滤
   ```rust
   pub struct SkillsListParams {
       // ... existing fields
       pub scope_filter: Option<Vec<SkillScope>>,
       pub name_pattern: Option<String>,  // 支持通配符匹配
   }
   ```

6. **响应元数据**：在响应中添加扫描统计信息
   ```rust
   pub struct SkillsListResponse {
       pub data: Vec<SkillsListEntry>,
       pub meta: SkillsListMeta,  // 新增：扫描时间、缓存状态等
   }
   ```

7. **批量操作优化**：对于频繁查询相同 cwd 的场景，考虑订阅模式替代轮询
   ```rust
   // 新增订阅 API
   SkillsSubscribe => "skills/subscribe" {
       params: SkillsSubscribeParams,
       response: SkillsSubscribeResponse,
   }
   // 通过 SkillsChangedNotification 推送变更
   ```
