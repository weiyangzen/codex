# SkillsListEntry 研究文档

## 场景与职责

`SkillsListEntry` 是 Codex App Server Protocol v2 API 中 `skills/list` 响应的核心数据结构，用于表示单个工作目录下的技能列表和错误信息。它是 `SkillsListResponse` 的组成元素，每个条目对应一个查询的工作目录。

### 使用场景

1. **多工作目录技能查询**：当客户端查询多个工作目录的技能时，每个目录对应一个 `SkillsListEntry`
2. **技能发现结果展示**：客户端使用此数据结构展示可使用的技能列表
3. **错误报告**：当某个目录的技能扫描失败时，通过 `errors` 字段报告问题而不影响其他目录

## 功能点目的

### 核心功能

- **目录技能聚合**：将单个工作目录下发现的所有技能聚合在一起
- **错误隔离**：将扫描错误与成功发现的技能分开，确保部分失败不会导致整个查询失败
- **技能元数据封装**：包含技能的完整元数据（名称、描述、路径、作用域、启用状态等）

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `cwd` | `string` | 工作目录路径，表示该条目对应的查询目录 |
| `skills` | `SkillMetadata[]` | 在该目录下发现的技能列表 |
| `errors` | `SkillErrorInfo[]` | 技能扫描过程中发生的错误列表 |

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/protocol/src/protocol.rs:3002-3007
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS)]
pub struct SkillsListEntry {
    pub cwd: PathBuf,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}
```

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3224-3228
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListEntry {
    pub cwd: PathBuf,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}
```

### 关联类型定义

#### SkillMetadata（技能元数据）

```rust
// codex-rs/protocol/src/protocol.rs:2937-2960
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    /// Legacy short_description from SKILL.md. Prefer SKILL.json interface.short_description.
    pub short_description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub interface: Option<SkillInterface>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub dependencies: Option<SkillDependencies>,
    pub path: PathBuf,
    pub scope: SkillScope,
    pub enabled: bool,
}
```

#### SkillErrorInfo（技能错误信息）

```rust
// codex-rs/protocol/src/protocol.rs:2997-3000
pub struct SkillErrorInfo {
    pub path: PathBuf,
    pub message: String,
}
```

#### SkillScope（技能作用域）

```rust
// codex-rs/protocol/src/protocol.rs
pub enum SkillScope {
    User,   // 用户级技能（~/.codex/skills/）
    Repo,   // 仓库级技能（项目 .codex/skills/）
    System, // 系统级技能
    Admin,  // 管理员级技能
}
```

### 关键处理流程

1. **请求处理入口**：`CodexMessageProcessor::skills_list()`
   ```rust
   // codex-rs/app-server/src/codex_message_processor.rs:5385-5440
   async fn skills_list(&self, request_id: ConnectionRequestId, params: SkillsListParams) {
       let SkillsListParams { cwds, force_reload, per_cwd_extra_user_roots } = params;
       
       // 处理默认 cwd
       let cwds = if cwds.is_empty() { vec![self.config.cwd.clone()] } else { cwds };
       
       // 构建每个 cwd 的额外根目录映射
       let mut extra_roots_by_cwd: HashMap<PathBuf, Vec<PathBuf>> = HashMap::new();
       for entry in per_cwd_extra_user_roots.unwrap_or_default() {
           // 验证 cwd 有效性...
           // 验证 extra_user_roots 为绝对路径...
           extra_roots_by_cwd.insert(entry.cwd, entry.extra_user_roots);
       }
       
       // 调用技能管理器获取技能列表
       let result = self.thread_manager.skills_manager()
           .list_skills(cwds, force_reload, extra_roots_by_cwd)
           .await;
       
       // 构建响应...
   }
   ```

2. **技能发现流程**：`SkillsManager::list_skills()`
   - 扫描标准技能目录（用户级、仓库级、系统级）
   - 解析 `SKILL.md` 和 `SKILL.json` 文件
   - 应用配置中的启用/禁用设置
   - 返回按目录分组的技能列表

3. **响应构建**：将技能管理器返回的结果转换为 `SkillsListEntry` 列表
   ```rust
   SkillsListResponse {
       data: results.into_iter().map(|(cwd, skills, errors)| {
           SkillsListEntry {
               cwd,
               skills,
               errors,
           }
       }).collect(),
   }
   ```

### 生成的 TypeScript 类型

```typescript
// GENERATED CODE! DO NOT MODIFY BY HAND!
import type { SkillErrorInfo } from "./SkillErrorInfo";
import type { SkillMetadata } from "./SkillMetadata";

export type SkillsListEntry = { 
    cwd: string, 
    skills: Array<SkillMetadata>, 
    errors: Array<SkillErrorInfo>, 
};
```

### JSON Schema（内嵌于 SkillsListResponse.json）

```json
{
  "SkillsListEntry": {
    "properties": {
      "cwd": { "type": "string" },
      "errors": {
        "items": { "$ref": "#/definitions/SkillErrorInfo" },
        "type": "array"
      },
      "skills": {
        "items": { "$ref": "#/definitions/SkillMetadata" },
        "type": "array"
      }
    },
    "required": ["cwd", "errors", "skills"],
    "type": "object"
  }
}
```

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/protocol/src/protocol.rs:3002-3007` | 核心协议层结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3224-3228` | v2 API 层结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListEntry.ts` | 生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/SkillsListResponse.json` | JSON Schema（内嵌定义） |

### 服务端实现

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs:5385-5440` | `skills_list` 方法实现 |
| `codex-rs/app-server/src/codex_message_processor.rs:704-707` | 请求路由分发 |

### 技能管理实现

| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/skills/` | 技能管理核心实现（推测路径） |
| `codex-rs/tui/src/chatwidget/skills.rs` | TUI 技能相关实现 |
| `codex-rs/tui_app_server/src/chatwidget/skills.rs` | TUI App Server 技能实现 |

### 测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/skills_list.rs` | 集成测试 |

## 依赖与外部交互

### 上游依赖

1. **技能管理器**：`thread_manager.skills_manager()` 负责实际的技能发现和元数据解析
2. **配置系统**：决定技能的启用/禁用状态
3. **文件系统**：扫描技能目录和解析技能文件

### 下游影响

1. **客户端 UI**：客户端使用 `skills` 列表渲染技能选择界面
2. **错误展示**：`errors` 用于向用户显示技能加载问题
3. **技能过滤**：客户端可能根据 `enabled` 字段过滤可使用的技能

### 关联类型依赖

```
SkillsListEntry
├── SkillMetadata
│   ├── SkillInterface（可选）
│   ├── SkillDependencies（可选）
│   └── SkillScope
└── SkillErrorInfo
```

## 风险、边界与改进建议

### 潜在风险

1. **大目录扫描性能**：如果工作目录包含大量技能，序列化/传输可能成为瓶颈
2. **错误信息泄露**：`SkillErrorInfo` 包含文件系统路径，可能泄露敏感信息
3. **重复扫描**：每次请求都重新扫描磁盘（除非使用缓存），影响性能

### 边界情况

1. **空目录**：`skills` 和 `errors` 都为空数组，表示该目录下未发现技能且无错误
2. **全错误**：`skills` 为空但 `errors` 有内容，表示该目录扫描完全失败
3. **部分成功**：`skills` 和 `errors` 都有内容，表示部分技能加载成功
4. **重复 cwd**：如果请求参数包含重复的 cwd，结果中也可能出现重复条目

### 改进建议

1. **添加分页支持**：对于技能数量庞大的目录，考虑添加分页参数
   ```rust
   pub struct SkillsListEntry {
       pub cwd: PathBuf,
       pub skills: Vec<SkillMetadata>,
       pub errors: Vec<SkillErrorInfo>,
       pub total_count: usize,  // 总技能数（用于分页）
   }
   ```

2. **错误分类**：为 `SkillErrorInfo` 添加错误类型字段，便于客户端处理
   ```rust
   pub struct SkillErrorInfo {
       pub path: PathBuf,
       pub message: String,
       pub error_kind: SkillErrorKind,  // ParseError, IoError, ValidationError, etc.
   }
   ```

3. **路径脱敏**：在发布版本中考虑对路径进行脱敏处理，保护用户隐私

4. **添加统计信息**：提供技能统计摘要，便于客户端快速了解目录状态
   ```rust
   pub struct SkillsListEntry {
       // ... existing fields
       pub stats: SkillStats,  // 启用数量、禁用数量等
   }
   ```

5. **缓存策略优化**：考虑在 `SkillsListEntry` 级别添加缓存元数据
   ```rust
   pub struct SkillsListEntry {
       // ... existing fields
       pub cached_at: Option<i64>,  // 缓存时间戳
       pub cache_valid: bool,       // 缓存是否有效
   }
   ```
