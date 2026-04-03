# SkillsListParams.ts 研究文档

## 场景与职责

`SkillsListParams.ts` 定义了技能列表查询的参数数据结构，用于 `skills/list` RPC 方法。这是 Codex 技能系统查询接口的核心参数类型，支持灵活的技能发现和加载控制。

## 功能点目的

该类型用于：
1. **目录指定**：指定要查询技能的工作目录
2. **缓存控制**：控制是否绕过缓存重新扫描
3. **额外根目录**：为特定目录指定额外的技能扫描路径
4. **批量查询**：支持一次查询多个工作目录

## 具体技术实现

### 数据结构定义

```typescript
import type { SkillsListExtraRootsForCwd } from "./SkillsListExtraRootsForCwd";

export type SkillsListParams = { 
  /**
   * When empty, defaults to the current session working directory.
   */
  cwds?: Array<string>,     // 工作目录列表
  
  /**
   * When true, bypass the skills cache and re-scan skills from disk.
   */
  forceReload?: boolean,    // 是否强制重新加载
  
  /**
   * Optional per-cwd extra roots to scan as user-scoped skills.
   */
  perCwdExtraUserRoots?: Array<SkillsListExtraRootsForCwd> | null,  // 额外技能根目录
};
```

### 字段详解

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| cwds | string[] | 否 | 要查询技能的工作目录列表，为空时使用会话当前目录 |
| forceReload | boolean | 否 | 是否绕过缓存重新从磁盘扫描技能，默认为 false |
| perCwdExtraUserRoots | SkillsListExtraRootsForCwd[] \| null | 否 | 每个工作目录的额外用户级技能根目录 |

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListParams {
    /// 工作目录列表，为空时使用当前会话工作目录
    #[ts(optional = nullable)]
    pub cwds: Option<Vec<String>>,
    
    /// 是否绕过缓存重新扫描
    #[serde(default)]
    pub force_reload: bool,
    
    /// 每个工作目录的额外用户级技能根目录
    #[ts(optional = nullable)]
    pub per_cwd_extra_user_roots: Option<Vec<SkillsListExtraRootsForCwd>>,
}
```

### 默认值处理

```rust
impl SkillsListParams {
    pub fn get_cwds_or_default(&self, default_cwd: &Path) -> Vec<PathBuf> {
        match &self.cwds {
            Some(cwds) if !cwds.is_empty() => {
                cwds.iter().map(PathBuf::from).collect()
            }
            _ => vec![default_cwd.to_path_buf()],
        }
    }
}
```

### 使用场景

#### 基本查询

```typescript
// 使用默认工作目录（会话当前目录）
const response = await api.skills.list({});
```

#### 指定目录

```typescript
// 查询特定目录的技能
const response = await api.skills.list({
  cwds: ["/home/user/project"]
});
```

#### 多目录查询

```typescript
// 同时查询多个目录
const response = await api.skills.list({
  cwds: [
    "/home/user/project1",
    "/home/user/project2"
  ]
});
```

#### 强制刷新

```typescript
// 绕过缓存重新扫描
const response = await api.skills.list({
  cwds: ["/home/user/project"],
  forceReload: true
});
```

#### 额外根目录

```typescript
// 指定额外的技能扫描路径
const response = await api.skills.list({
  cwds: ["/home/user/project"],
  perCwdExtraUserRoots: [
    {
      cwd: "/home/user/project",
      extraUserRoots: ["/shared/team-skills"]
    }
  ]
});
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListParams.ts`

### Rust 协议定义
- V2 协议：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- 通用协议：`codex-rs/app-server-protocol/src/protocol/common.rs`

### 服务端实现
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 客户端使用
- Exec 模块：`codex-rs/exec/src/lib.rs`
- MCP 进程：`codex-rs/app-server/tests/common/mcp_process.rs`
- TUI 应用服务器：`codex-rs/tui_app_server/src/app_server_session.rs`

### 测试覆盖
- 技能列表测试：`codex-rs/app-server/tests/suite/v2/skills_list.rs`

### 父类型引用
- ClientRequest：`codex-rs/app-server-protocol/schema/typescript/ClientRequest.ts`

### 相关类型
- SkillsListExtraRootsForCwd：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListExtraRootsForCwd.ts`
- SkillsListResponse：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListResponse.ts`

## 依赖与外部交互

### 上游依赖
- 用户输入：通过 UI 或命令行指定参数
- 会话状态：获取默认工作目录

### 下游消费
- 技能管理器：根据参数加载技能
- 缓存系统：根据 forceReload 决定是否使用缓存

### RPC 流程

```
客户端
  |
  |-- SkillsListParams -->
  |                      服务器
  |<-- SkillsListResponse --
  |
SkillsListEntry[]
```

## 风险、边界与改进建议

### 边界情况
1. **空 cwds**：使用会话当前工作目录
2. **无效路径**：cwds 中的路径可能不存在或不可访问
3. **大量目录**：大量 cwds 可能导致性能问题

### 潜在风险
1. **路径遍历**：cwds 可能包含恶意路径
2. **资源消耗**：forceReload 频繁调用可能影响性能
3. **信息泄露**：路径信息可能包含敏感信息

### 改进建议
1. **路径验证**：验证 cwds 的合法性和可访问性
2. **限制数量**：限制 cwds 的最大数量
3. **批量优化**：优化多目录查询的性能
4. **增量更新**：支持增量更新而非全量刷新
5. **过滤选项**：添加按作用域、启用状态过滤的参数
6. **排序选项**：支持指定返回结果的排序方式
