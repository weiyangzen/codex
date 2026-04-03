# SkillsListParams 研究文档

## 1. 场景与职责

**SkillsListParams** 是 app-server-protocol v2 协议中用于查询可用技能列表的请求参数类型。该类型在以下场景中使用：

- **技能发现**：客户端启动时获取当前工作目录下的可用技能
- **技能管理界面**：为技能管理 UI 提供数据查询接口
- **多工作目录支持**：支持同时查询多个工作目录的技能
- **缓存控制**：支持强制刷新技能缓存，重新从磁盘扫描
- **自定义技能源**：支持为特定工作目录指定额外的技能搜索路径

该类型属于 `skills/list` RPC 方法的请求参数，是技能管理功能的核心入口。

## 2. 功能点目的

该类型的核心目的是：

1. **灵活的工作目录指定**：支持查询单个或多个工作目录的技能
2. **缓存控制**：通过 `force_reload` 控制是否使用缓存或重新扫描
3. **扩展技能源**：通过 `per_cwd_extra_user_roots` 支持自定义技能搜索路径
4. **支持开发工作流**：允许开发者指定开发中的技能路径进行测试

与 `SkillsListResponse` 配合使用，实现完整的技能查询功能。

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
import type { SkillsListExtraRootsForCwd } from "./SkillsListExtraRootsForCwd";

export type SkillsListParams = {
  cwds: Array<string>,
  forceReload: boolean,
  perCwdExtraUserRoots?: Array<SkillsListExtraRootsForCwd>,
};
```

### Rust 源类型定义

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

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `cwds` | `Vec<PathBuf>` | 要查询技能的工作目录列表，为空时使用当前会话工作目录 |
| `force_reload` | `bool` | 是否强制重新扫描，绕过缓存 |
| `per_cwd_extra_user_roots` | `Option<Vec<SkillsListExtraRootsForCwd>>` | 可选的每目录额外技能根目录 |

### 序列化特性

- 使用 camelCase 命名规范
- `cwds` 使用 `#[serde(default, skip_serializing_if = "Vec::is_empty")]`，空数组时不序列化
- `force_reload` 使用 `#[serde(default, skip_serializing_if = "std::ops::Not::not")]`，为 `false` 时不序列化
- `per_cwd_extra_user_roots` 使用 `#[ts(optional = nullable)]`，TypeScript 中表现为可选的可空字段

### 默认值行为

| 字段 | 默认值 | 行为 |
|------|--------|------|
| `cwds` | `[]` | 使用当前会话工作目录 |
| `force_reload` | `false` | 使用缓存的技能列表 |
| `per_cwd_extra_user_roots` | `None` | 不使用额外技能根目录 |

## 4. 关键代码路径与文件引用

### 定义位置
- **主定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` 第 3065-3078 行

### 协议注册
- **RPC 方法注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 295-298 行
  ```rust
  SkillsList => "skills/list" {
      params: v2::SkillsListParams,
      response: v2::SkillsListResponse,
  }
  ```

### 相关文件
- **TypeScript 类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListParams.ts`
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/SkillsListParams.json`
- **响应类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListResponse.ts`
- **依赖类型**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListExtraRootsForCwd.ts`

### 使用场景
- **TUI 技能列表**: `codex-rs/tui/src/chatwidget/skills.rs`
- **TUI App Server**: `codex-rs/tui_app_server/src/chatwidget/skills.rs`
- **核心技能模型**: `codex-rs/core/src/codex.rs`
- **协议层**: `codex-rs/protocol/src/protocol.rs`

### 集成测试
- **技能列表测试**: `codex-rs/app-server/tests/suite/v2/skills_list.rs`
  - 测试额外根目录功能
  - 测试相对路径拒绝
  - 测试缓存行为

## 5. 依赖与外部交互

### 导入依赖

| 依赖类型 | 路径 | 说明 |
|----------|------|------|
| `SkillsListExtraRootsForCwd` | `./SkillsListExtraRootsForCwd` | 额外技能根目录配置 |

### 类型关系图

```
SkillsListParams
    ├── cwds: Vec<PathBuf>
    ├── force_reload: bool
    └── per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>
            └── SkillsListExtraRootsForCwd
                    ├── cwd: PathBuf
                    └── extra_user_roots: Vec<PathBuf>
```

### 请求-响应流程

```
客户端                                              服务器
   │                                                  │
   ├──── SkillsListParams ───────────────────────────>│
   │   {                                              │
   │     cwds: ["/project"],                          │ 扫描标准技能目录
   │     force_reload: true,                          │ 扫描额外根目录
   │     perCwdExtraUserRoots: [...]                  │ 缓存结果
   │   }                                              │
   │                                                  │
   │<──── SkillsListResponse ─────────────────────────┤
   │   {                                              │
   │     data: [                                      │
   │       {                                          │
   │         cwd: "/project",                         │
   │         skills: [...],                           │
   │         errors: []                               │
   │       }                                          │
   │     ]                                            │
   │   }                                              │
   │                                                  │
   ▼                                                  ▼
 更新技能列表 UI
```

## 6. 风险、边界与改进建议

### 潜在风险

1. **缓存一致性问题**
   - 风险：客户端可能使用过期的缓存数据
   - 缓解：`force_reload` 选项允许强制刷新
   - 建议：考虑添加缓存失效通知机制

2. **大量工作目录性能**
   - 风险：查询过多工作目录可能导致响应时间过长
   - 建议：考虑添加分页或流式响应支持

3. **路径安全问题**
   - 风险：`per_cwd_extra_user_roots` 中的路径可能包含恶意路径
   - 现状：服务器会验证路径为绝对路径
   - 建议：添加更多路径验证（如禁止符号链接、路径遍历防护）

### 边界情况

1. **空 cwds 数组**
   - 服务器应使用当前会话工作目录作为默认值

2. **不存在的工作目录**
   - 应返回错误或在响应中标记

3. **权限不足的工作目录**
   - 应返回错误信息到 `errors` 字段

4. **重复的工作目录**
   - 应去重处理，避免重复扫描

### 改进建议

1. **添加分页支持**
   ```rust
   pub struct SkillsListParams {
       pub cwds: Vec<PathBuf>,
       pub force_reload: bool,
       pub per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>,
       pub cursor: Option<String>, // 分页游标
       pub limit: Option<u32>,     // 每页限制
   }
   ```

2. **添加过滤选项**
   ```rust
   pub struct SkillsListParams {
       // ... 现有字段
       pub scope_filter: Option<Vec<SkillScope>>, // 按作用域过滤
       pub enabled_only: bool,                     // 仅返回启用的技能
       pub search_query: Option<String>,          // 搜索关键词
   }
   ```

3. **添加排序选项**
   ```rust
   pub enum SkillsSortBy {
       Name,
       Scope,
       Enabled,
       Path,
   }
   
   pub struct SkillsListParams {
       // ... 现有字段
       pub sort_by: Option<SkillsSortBy>,
       pub sort_desc: bool,
   }
   ```

4. **支持订阅模式**
   - 添加 `subscribe_changes` 选项，当技能列表变化时推送通知

### 测试覆盖

- **单元测试**: 验证序列化/反序列化正确性
- **集成测试**: 
  - 验证标准技能扫描
  - 验证额外根目录功能
  - 验证缓存行为
  - 验证相对路径拒绝
- **边界测试**: 空列表、大量目录、无效路径等场景
