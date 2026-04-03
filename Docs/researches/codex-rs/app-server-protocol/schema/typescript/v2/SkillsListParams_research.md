# SkillsListParams 研究文档

## 1. 场景与职责

**SkillsListParams** 是 app-server-protocol v2 协议中用于请求技能列表的参数类型。该类型在以下场景中使用：

- **技能列表查询**：客户端请求获取一个或多个工作目录下的技能列表
- **技能缓存控制**：控制是否使用缓存或强制重新扫描技能
- **自定义技能来源**：指定额外的用户技能根目录以扩展技能搜索范围

## 2. 功能点目的

该类型的主要目的是：

1. **多目录查询**：支持一次查询多个工作目录的技能
2. **缓存控制**：允许客户端控制是否使用缓存的技能结果
3. **灵活的技能定位**：支持为特定工作目录指定额外的技能扫描路径

### 与其他类型的关系

- **请求方法**：与 `SkillsList` 请求方法配对使用
- **响应类型**：对应 `SkillsListResponse` 响应
- **子类型**：包含 `SkillsListExtraRootsForCwd` 用于指定额外技能根目录

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
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

### Rust 源码定义

```rust
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

位于：`codex-rs/app-server-protocol/src/protocol/v2.rs:3065-3078`

### 关键流程

1. **客户端构造请求**：客户端指定工作目录列表、是否强制刷新、额外技能根目录
2. **服务器处理**：
   - 如果 `cwds` 为空，使用当前会话工作目录
   - 验证 `per_cwd_extra_user_roots` 中的路径
   - 根据 `force_reload` 决定是否使用缓存
3. **技能扫描**：调用技能管理器扫描指定目录的技能
4. **返回结果**：返回 `SkillsListResponse` 包含每个目录的技能列表

### 代码示例

```rust
async fn skills_list(&self, request_id: ConnectionRequestId, params: SkillsListParams) {
    let SkillsListParams {
        cwds,
        force_reload,
        per_cwd_extra_user_roots,
    } = params;
    
    // 默认使用当前工作目录
    let cwds = if cwds.is_empty() {
        vec![self.config.cwd.clone()]
    } else {
        cwds
    };
    
    // 处理额外根目录
    let mut extra_roots_by_cwd: HashMap<PathBuf, Vec<PathBuf>> = HashMap::new();
    for entry in per_cwd_extra_user_roots.unwrap_or_default() {
        // 验证 cwd 存在性
        if !cwd_set.contains(&entry.cwd) {
            warn!("ignoring per-cwd extra roots for cwd not present in skills/list cwds");
            continue;
        }
        
        // 验证路径为绝对路径
        for root in entry.extra_user_roots {
            if !root.is_absolute() {
                self.send_invalid_request_error(request_id, "paths must be absolute").await;
                return;
            }
        }
        
        extra_roots_by_cwd.entry(entry.cwd).or_default().extend(valid_extra_roots);
    }
    
    // 扫描技能
    let skills_manager = self.thread_manager.skills_manager();
    for cwd in cwds {
        let extra_roots = extra_roots_by_cwd.get(&cwd).map_or(&[][..], Vec::as_slice);
        let outcome = skills_manager
            .skills_for_cwd_with_extra_user_roots(&cwd, &config, force_reload, extra_roots)
            .await;
        // ... 构建响应
    }
}
```

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs:3065-3078`
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListParams.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/SkillsListParams.json`

### 服务端实现
- **请求处理**：`codex-rs/app-server/src/codex_message_processor.rs:5385-5456`

### 相关类型定义
- **SkillsListExtraRootsForCwd**：`codex-rs/app-server-protocol/src/protocol/v2.rs:3083-3086`
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
| `SkillsListExtraRootsForCwd` | 额外技能根目录 |
| `PathBuf` | 路径表示 |

### 数据流

```
客户端 (VSCode/CLI)
    │
    ├── 构造 SkillsListParams ────────────────────────▶
    │   ├── cwds: ["/project/a", "/project/b"]
    │   ├── force_reload: false
    │   └── per_cwd_extra_user_roots: [
    │           { cwd: "/project/a", extra_user_roots: ["/shared/skills"] }
    │       ]
    │
    │                                                    服务器 (app-server)
    │                                                    ├── 解析参数
    │                                                    ├── 默认 cwd 处理
    │                                                    ├── 验证额外根目录
    │                                                    ├── 技能扫描（带缓存）
    │                                                    └── 构建 SkillsListResponse
    │
    ◀── 返回 SkillsListResponse ────────────────────────
        └── data: [
                SkillsListEntry { cwd: "/project/a", skills: [...], errors: [] },
                SkillsListEntry { cwd: "/project/b", skills: [...], errors: [] }
            ]
```

### 缓存机制

```rust
let outcome = skills_manager
    .skills_for_cwd_with_extra_user_roots(
        &cwd,
        &config,
        force_reload,  // 控制是否使用缓存
        extra_roots
    )
    .await;
```

- `force_reload = false`：优先使用缓存
- `force_reload = true`：绕过缓存，重新扫描

## 6. 风险、边界与改进建议

### 潜在风险

1. **路径遍历**：如果不对路径进行验证，可能导致安全问题
2. **性能问题**：查询过多目录或过多额外根目录可能导致性能下降
3. **缓存不一致**：额外根目录的变更可能不会触发缓存失效

### 边界情况

1. **空 cwds**：默认使用当前会话工作目录
2. **无效路径**：目录可能不存在或不可访问
3. **重复配置**：同一个 cwd 可能在 `per_cwd_extra_user_roots` 中出现多次

### 当前验证

当前实现已包含以下验证：

1. **绝对路径检查**：`extra_user_roots` 中的路径必须为绝对路径
2. **cwd 存在性检查**：忽略不在 `cwds` 列表中的配置

### 改进建议

1. **添加分页支持**：对于技能数量较多的场景，支持分页查询
   ```rust
   pub struct SkillsListParams {
       pub cwds: Vec<PathBuf>,
       pub force_reload: bool,
       pub per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>,
       pub cursor: Option<String>, // 分页游标
       pub limit: Option<usize>,   // 每页限制
   }
   ```

2. **支持过滤**：允许客户端指定只返回特定类型的技能
   ```rust
   pub struct SkillsListParams {
       // ... 现有字段
       pub filter: Option<SkillsFilter>,
   }
   
   pub struct SkillsFilter {
       pub scope: Option<Vec<SkillScope>>, // 按作用域过滤
       pub enabled_only: Option<bool>,     // 只返回启用的技能
       pub search_term: Option<String>,    // 搜索关键词
   }
   ```

3. **添加排序选项**：允许客户端指定返回技能的排序方式
   ```rust
   pub struct SkillsListParams {
       // ... 现有字段
       pub sort_by: Option<SkillsSortBy>,
       pub sort_order: Option<SortOrder>,
   }
   
   pub enum SkillsSortBy {
       Name,
       Path,
       Scope,
       Enabled,
   }
   ```

4. **支持深度控制**：控制技能扫描的递归深度
   ```rust
   pub struct SkillsListParams {
       // ... 现有字段
       pub max_depth: Option<usize>, // 最大扫描深度
   }
   ```

5. **添加元数据选项**：允许客户端请求额外的元数据
   ```rust
   pub struct SkillsListParams {
       // ... 现有字段
       pub include_metadata: Option<SkillsMetadataOptions>,
   }
   
   pub struct SkillsMetadataOptions {
       pub include_dependencies: bool,
       pub include_interface: bool,
       pub include_stats: bool,
   }
   ```

6. **支持批量操作 ID**：允许客户端跟踪批量操作
   ```rust
   pub struct SkillsListParams {
       // ... 现有字段
       pub request_id: Option<String>, // 客户端请求 ID
   }
   ```
