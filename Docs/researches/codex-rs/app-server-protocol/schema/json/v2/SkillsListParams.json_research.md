# SkillsListParams.json 研究文档

## 场景与职责

`SkillsListParams` 是 App-Server Protocol v2 中用于获取技能列表的请求参数结构。客户端通过此参数控制技能列表的查询范围，包括工作目录、缓存控制和额外的用户根目录。

该结构支持从多个作用域（用户、仓库、系统、管理员）发现技能，并提供灵活的技能扫描选项。

## 功能点目的

1. **技能发现**: 从多个作用域发现可用技能
2. **工作目录感知**: 根据工作目录发现项目级技能
3. **缓存控制**: 控制是否使用缓存或强制重新扫描
4. **自定义根目录**: 支持指定额外的技能扫描根目录

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "SkillsListExtraRootsForCwd": {
      "properties": {
        "cwd": { "type": "string" },
        "extraUserRoots": { "items": { "type": "string" }, "type": "array" }
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

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cwds` | string[] | 否 | 工作目录列表，为空时使用当前会话工作目录 |
| `forceReload` | boolean | 否 | 是否绕过缓存，强制从磁盘重新扫描技能 |
| `perCwdExtraUserRoots` | SkillsListExtraRootsForCwd[] \| null | 否 | 每个工作目录的额外用户根目录 |

### SkillsListExtraRootsForCwd 定义

| 字段 | 类型 | 说明 |
|------|------|------|
| `cwd` | string | 工作目录 |
| `extraUserRoots` | string[] | 该工作目录下的额外用户技能根目录 |

### 技能作用域

技能按作用域分类：
- `user`: 用户级技能（`~/.codex/skills/`）
- `repo`: 仓库级技能（`.codex/skills/`）
- `system`: 系统级技能
- `admin`: 管理员配置的技能

### 关联的 RPC 方法

- **方法**: `skills/list`
- **响应**: `SkillsListResponse`

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
SkillsList => "skills/list" {
    params: v2::SkillsListParams,
    response: v2::SkillsListResponse,
}
```

## 关键代码路径与文件引用

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListParams {
    /// When empty, defaults to the current session working directory.
    pub cwds: Vec<String>,
    /// When true, bypass the skills cache and re-scan skills from disk.
    #[serde(default)]
    pub force_reload: bool,
    /// Optional per-cwd extra roots to scan as user-scoped skills.
    #[ts(optional = nullable)]
    pub per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListExtraRootsForCwd {
    pub cwd: String,
    pub extra_user_roots: Vec<String>,
}
```

### 处理代码

```rust
// codex-rs/app-server/src/codex_message_processor.rs
async fn skills_list(&self, request_id: ConnectionRequestId, params: SkillsListParams) {
    let skills_manager = self.thread_manager.skills_manager();
    
    let cwds = if params.cwds.is_empty() {
        vec![self.current_cwd()]
    } else {
        params.cwds
    };
    
    let mut results = Vec::new();
    for cwd in cwds {
        let skills = skills_manager.list_skills(
            &cwd,
            params.force_reload,
            params.per_cwd_extra_user_roots.as_ref(),
        ).await;
        results.push(SkillsListEntry {
            cwd,
            skills: skills.into_iter().map(|s| s.into()).collect(),
            errors: vec![],
        });
    }
    
    let response = SkillsListResponse { data: results };
    self.outgoing.send_response(request_id, response).await;
}
```

### 相关文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 枚举定义 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 请求处理实现 |
| `codex-rs/app-server/tests/suite/v2/skills_list.rs` | 测试文件 |
| `codex-rs/tui_app_server/src/app.rs` | TUI 应用中的使用 |

## 依赖与外部交互

### 上游依赖

1. **技能管理器**: `codex_core::skills::SkillsManager`
2. **文件系统扫描**: 扫描技能目录和解析 `SKILL.md`/`SKILL.json`
3. **缓存系统**: 技能元数据缓存

### 下游交互

1. **技能列表 UI**: 客户端渲染技能列表
2. **技能启用/禁用**: 用户选择技能后配置启用状态

### 协议版本

- **版本**: v2
- **稳定性**: 稳定 API (非实验性)

## 风险、边界与改进建议

### 风险点

1. **扫描性能**: 大量技能目录时扫描可能较慢
2. **缓存失效**: `forceReload` 可能导致性能问题
3. **路径安全**: 需要验证 `cwds` 和 `extraUserRoots` 防止目录遍历

### 边界情况

1. **空目录**: 工作目录下没有技能
2. **无效路径**: 路径不存在或不可读
3. **损坏的技能**: `SKILL.md` 或 `SKILL.json` 损坏

### 改进建议

1. **添加过滤**: 建议添加 `filter: SkillFilter` 字段
2. **添加搜索**: 建议添加 `search: Option<String>` 字段
3. **添加作用域过滤**: 建议添加 `scopes: Vec<SkillScope>` 字段
4. **添加分页**: 对于大量技能，建议添加分页参数

### 示例改进结构

```json
{
  "cwds": ["/home/user/project1"],
  "forceReload": false,
  "perCwdExtraUserRoots": [
    {
      "cwd": "/home/user/project1",
      "extraUserRoots": ["/home/user/custom-skills"]
    }
  ],
  "search": "git",
  "scopes": ["user", "repo"],
  "filter": {
    "enabled": true,
    "hasTools": true
  }
}
```

### 测试覆盖

相关测试文件：`codex-rs/app-server/tests/suite/v2/skills_list.rs`

建议测试场景：
- 基本技能列表查询
- 带额外根目录的查询
- 强制重新加载
- 多工作目录查询
