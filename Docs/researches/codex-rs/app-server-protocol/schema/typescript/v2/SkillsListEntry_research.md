# SkillsListEntry 研究文档

## 1. 场景与职责

**SkillsListEntry** 是 app-server-protocol v2 协议中用于表示单个工作目录下技能列表的条目类型。该类型在以下场景中使用：

- **技能列表展示**：当客户端请求技能列表时，服务器为每个工作目录返回一个 `SkillsListEntry`
- **多目录技能扫描**：支持同时扫描多个工作目录（cwds），每个目录对应一个 `SkillsListEntry`
- **技能错误报告**：收集并报告在技能扫描过程中遇到的错误

## 2. 功能点目的

该类型的主要目的是：

1. **组织技能数据**：按工作目录组织技能，便于客户端理解和展示
2. **聚合错误信息**：收集每个工作目录下的技能扫描错误
3. **支持多目录查询**：允许一次查询多个工作目录的技能状态

### 与其他类型的关系

- **父容器**：作为 `SkillsListResponse.data` 数组的元素
- **技能详情**：包含 `SkillMetadata` 数组，描述每个技能的详细信息
- **错误信息**：包含 `SkillErrorInfo` 数组，报告技能扫描错误

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
import type { SkillErrorInfo } from "./SkillErrorInfo";
import type { SkillMetadata } from "./SkillMetadata";

export type SkillsListEntry = { 
    cwd: string, 
    skills: Array<SkillMetadata>, 
    errors: Array<SkillErrorInfo>, 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListEntry {
    pub cwd: PathBuf,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}
```

位于：`codex-rs/app-server-protocol/src/protocol/v2.rs:3224-3228`

### 核心协议定义

在 `codex-protocol` crate 中也有对应的定义：

```rust
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS)]
pub struct SkillsListEntry {
    pub cwd: PathBuf,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}
```

位于：`codex-rs/protocol/src/protocol.rs:3002-3007`

### 关键流程

1. **接收请求**：服务器接收 `SkillsListParams`，包含工作目录列表
2. **遍历目录**：为每个工作目录扫描技能
3. **收集结果**：将每个目录的技能和错误收集到 `SkillsListEntry`
4. **构建响应**：将所有 `SkillsListEntry` 放入 `SkillsListResponse.data`

### 代码示例

```rust
async fn skills_list(&self, request_id: ConnectionRequestId, params: SkillsListParams) {
    let SkillsListParams { cwds, force_reload, per_cwd_extra_user_roots } = params;
    let cwds = if cwds.is_empty() { vec![self.config.cwd.clone()] } else { cwds };
    
    // ... 处理 extra_roots ...
    
    let skills_manager = self.thread_manager.skills_manager();
    let mut data = Vec::new();
    for cwd in cwds {
        let extra_roots = extra_roots_by_cwd.get(&cwd).map_or(&[][..], Vec::as_slice);
        let outcome = skills_manager
            .skills_for_cwd_with_extra_user_roots(&cwd, &config, force_reload, extra_roots)
            .await;
        let errors = errors_to_info(&outcome.errors);
        let skills = skills_to_info(&outcome.skills, &outcome.disabled_paths);
        data.push(SkillsListEntry {
            cwd,
            skills,
            errors,
        });
    }
    self.outgoing.send_response(request_id, SkillsListResponse { data }).await;
}
```

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 定义（app-server-protocol）**：`codex-rs/app-server-protocol/src/protocol/v2.rs:3224-3228`
- **Rust 定义（protocol）**：`codex-rs/protocol/src/protocol.rs:3002-3007`
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListEntry.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/SkillsListEntry.json`

### 服务端实现
- **请求处理**：`codex-rs/app-server/src/codex_message_processor.rs:5385-5456`

### 相关类型定义
- **SkillMetadata**：`codex-rs/app-server-protocol/src/protocol/v2.rs:3145-3164`
- **SkillErrorInfo**：`codex-rs/app-server-protocol/src/protocol/v2.rs:3216-3219`
- **SkillsListResponse**：`codex-rs/app-server-protocol/src/protocol/v2.rs:3091-3093`

### 协议注册
- **ClientRequest 枚举**：`codex-rs/app-server-protocol/src/protocol/common.rs:295-298`
  ```rust
  SkillsList => "skills/list" {
      params: v2::SkillsListParams,
      response: v2::SkillsListResponse,
  }
  ```

### 测试覆盖
- **集成测试**：`codex-rs/app-server/tests/suite/v2/skills_list.rs`
  - `skills_list_includes_skills_from_per_cwd_extra_user_roots`
  - `skills_list_rejects_relative_extra_user_roots`
  - `skills_list_ignores_per_cwd_extra_roots_for_unknown_cwd`
  - `skills_list_uses_cached_result_until_force_reload`

## 5. 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `ts-rs` | TypeScript 类型生成 |
| `SkillMetadata` | 技能元数据 |
| `SkillErrorInfo` | 技能错误信息 |
| `PathBuf` | 工作目录路径 |

### 数据流

```
SkillsListRequest (SkillsListParams)
    │
    ▼
┌─────────────────┐
│  SkillsManager  │
│  skills_for_    │
│  cwd_with_extra │
│  _user_roots    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ SkillsOutcome   │
│ - skills        │
│ - errors        │
│ - disabled_paths│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ SkillsListEntry │
│ - cwd           │
│ - skills        │
│ - errors        │
└────────┬────────┘
         │
         ▼
SkillsListResponse
    │
    ▼
客户端
```

### 技能扫描流程

1. **技能管理器**：`thread_manager.skills_manager()`
2. **扫描方法**：`skills_for_cwd_with_extra_user_roots()`
3. **结果处理**：`errors_to_info()` 和 `skills_to_info()` 转换

## 6. 风险、边界与改进建议

### 潜在风险

1. **路径遍历**：如果 `cwd` 包含恶意路径，可能导致安全问题
2. **大量技能**：如果某个目录下有大量技能，可能导致响应过大
3. **错误累积**：多个目录的错误可能累积，影响用户体验

### 边界情况

1. **空目录**：`skills` 和 `errors` 都可能为空
2. **无效路径**：`cwd` 可能不存在或不可访问
3. **权限问题**：可能无法读取某些目录的技能

### 改进建议

1. **添加统计信息**：提供技能数量和错误数量的汇总
   ```rust
   pub struct SkillsListEntry {
       pub cwd: PathBuf,
       pub skills: Vec<SkillMetadata>,
       pub errors: Vec<SkillErrorInfo>,
       pub stats: SkillsListStats, // 新增统计
   }
   
   pub struct SkillsListStats {
       pub total_skills: usize,
       pub enabled_skills: usize,
       pub disabled_skills: usize,
       pub error_count: usize,
   }
   ```

2. **支持分页**：对于技能数量较多的目录，支持分页返回
   ```rust
   pub struct SkillsListEntry {
       pub cwd: PathBuf,
       pub skills: Vec<SkillMetadata>,
       pub errors: Vec<SkillErrorInfo>,
       pub has_more: bool, // 是否有更多技能
       pub next_cursor: Option<String>, // 分页游标
   }
   ```

3. **添加目录状态**：指示目录的扫描状态
   ```rust
   pub struct SkillsListEntry {
       pub cwd: PathBuf,
       pub skills: Vec<SkillMetadata>,
       pub errors: Vec<SkillErrorInfo>,
       pub status: SkillsListEntryStatus, // 新增状态
   }
   
   pub enum SkillsListEntryStatus {
       Success,
       PartialSuccess, // 部分成功，有错误
       AccessDenied,
       DirectoryNotFound,
   }
   ```

4. **支持过滤**：允许客户端指定只返回特定范围的技能
   ```rust
   pub struct SkillsListParams {
       pub cwds: Vec<PathBuf>,
       pub force_reload: bool,
       pub per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>,
       pub filter: Option<SkillsFilter>, // 新增过滤
   }
   ```

5. **性能优化**：对于频繁查询的场景，考虑添加缓存控制头
   ```rust
   pub struct SkillsListEntry {
       pub cwd: PathBuf,
       pub skills: Vec<SkillMetadata>,
       pub errors: Vec<SkillErrorInfo>,
       pub cached_at: Option<i64>, // 缓存时间戳
       pub etag: Option<String>, // 缓存验证
   }
   ```
