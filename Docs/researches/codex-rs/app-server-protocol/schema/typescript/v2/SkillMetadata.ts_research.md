# SkillMetadata.ts 研究文档

## 场景与职责

`SkillMetadata.ts` 定义了技能元数据的完整数据结构，用于描述 Codex 技能的所有属性。这是 Codex 技能系统的核心类型，包含技能的标识、描述、界面、依赖和状态等信息。

## 功能点目的

该类型用于：
1. **技能描述**：提供技能的完整描述和标识信息
2. **功能声明**：声明技能的依赖和接口
3. **状态管理**：跟踪技能的启用/禁用状态
4. **作用域定义**：定义技能的作用范围（用户/仓库/系统）

## 具体技术实现

### 数据结构定义

```typescript
import type { SkillDependencies } from "./SkillDependencies";
import type { SkillInterface } from "./SkillInterface";
import type { SkillScope } from "./SkillScope";

export type SkillMetadata = { 
  name: string,                          // 技能唯一名称
  description: string,                   // 技能描述
  /**
   * Legacy short_description from SKILL.md. Prefer SKILL.json interface.short_description.
   */
  shortDescription?: string,             // 简短描述（向后兼容）
  interface?: SkillInterface,            // 界面配置
  dependencies?: SkillDependencies,      // 依赖声明
  path: string,                          // 技能文件路径
  scope: SkillScope,                     // 作用域
  enabled: boolean,                      // 是否启用
};
```

### 字段详解

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| name | string | 是 | 技能唯一标识名，用于引用 |
| description | string | 是 | 技能的详细描述 |
| shortDescription | string | 否 | 简短描述（向后兼容，优先使用 interface.shortDescription）|
| interface | SkillInterface | 否 | UI 展示配置 |
| dependencies | SkillDependencies | 否 | 依赖的工具和资源 |
| path | string | 是 | 技能定义文件的路径 |
| scope | SkillScope | 是 | 技能作用范围 |
| enabled | boolean | 是 | 技能是否启用 |

### Rust 协议定义

在 `codex-rs/protocol/src/protocol.rs` 中：

```rust
#[derive(
    Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema, TS,
)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    /// Legacy short_description from SKILL.md. Prefer SKILL.json interface.short_description.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub short_description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub interface: Option<SkillInterface>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dependencies: Option<SkillDependencies>,
    pub path: String,
    pub scope: SkillScope,
    pub enabled: bool,
}
```

### 核心技能元数据类型

在 `codex-rs/core/src/skills/model.rs` 中：

```rust
#[derive(Debug, Clone, PartialEq)]
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    pub short_description: Option<String>,
    pub interface: Option<SkillInterface>,
    pub dependencies: Option<SkillDependencies>,
    pub policy: Option<SkillPolicy>,
    pub permission_profile: Option<PermissionProfile>,
    pub managed_network_override: Option<SkillManagedNetworkOverride>,
    pub path_to_skills_md: PathBuf,
    pub scope: SkillScope,
}

impl SkillMetadata {
    fn allow_implicit_invocation(&self) -> bool {
        self.policy
            .as_ref()
            .and_then(|policy| policy.allow_implicit_invocation)
            .unwrap_or(true)
    }
}
```

### 技能加载结果

```rust
#[derive(Debug, Clone, Default)]
pub struct SkillLoadOutcome {
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillError>,
    pub disabled_paths: HashSet<PathBuf>,
    pub(crate) implicit_skills_by_scripts_dir: Arc<HashMap<PathBuf, SkillMetadata>>,
    pub(crate) implicit_skills_by_doc_path: Arc<HashMap<PathBuf, SkillMetadata>>,
}

impl SkillLoadOutcome {
    pub fn is_skill_enabled(&self, skill: &SkillMetadata) -> bool {
        !self.disabled_paths.contains(&skill.path_to_skills_md)
    }
}
```

### 技能加载流程

```rust
// skills/loader.rs
pub async fn load_skills(
    roots: &[PathBuf],
    disabled_paths: &HashSet<PathBuf>,
) -> SkillLoadOutcome {
    let mut outcome = SkillLoadOutcome::default();
    
    for root in roots {
        match load_skill_from_path(root).await {
            Ok(metadata) => {
                let enabled = !disabled_paths.contains(&metadata.path_to_skills_md);
                outcome.skills.push(metadata);
            }
            Err(error) => {
                outcome.errors.push(error);
            }
        }
    }
    
    outcome
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SkillMetadata.ts`

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/protocol.rs`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 核心技能实现
- 技能模型：`codex-rs/core/src/skills/model.rs`
- 技能加载器：`codex-rs/core/src/skills/loader.rs`
- 加载器测试：`codex-rs/core/src/skills/loader_tests.rs`
- 技能注入：`codex-rs/core/src/skills/injection.rs`
- 技能渲染：`codex-rs/core/src/skills/render.rs`

### 服务端集成
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`
- 传输层：`codex-rs/app-server/src/transport.rs`

### 客户端消费
- TUI 应用：`codex-rs/tui/src/chatwidget.rs`
- TUI 技能助手：`codex-rs/tui/src/chatwidget/skills.rs`
- TUI App Server：`codex-rs/tui_app_server/src/app.rs`

### 相关类型
- SkillInterface：`codex-rs/app-server-protocol/schema/typescript/v2/SkillInterface.ts`
- SkillDependencies：`codex-rs/app-server-protocol/schema/typescript/v2/SkillDependencies.ts`
- SkillScope：`codex-rs/app-server-protocol/schema/typescript/v2/SkillScope.ts`
- SkillsListEntry：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListEntry.ts`

## 依赖与外部交互

### 上游依赖
- SKILL.md/SKILL.json：技能定义文件
- 文件系统：读取技能文件
- 配置：技能启用/禁用状态

### 下游消费
- 技能列表：作为 SkillsListEntry.skills 返回
- 提示注入：根据技能生成系统提示
- 工具注册：注册技能依赖的工具

### 作用域分布

| 作用域 | 加载位置 | 优先级 |
|-------|---------|-------|
| system | 系统目录 | 低 |
| admin | 管理员配置 | 中 |
| user | 用户目录 | 高 |
| repo | 仓库 .codex 目录 | 最高 |

## 风险、边界与改进建议

### 边界情况
1. **名称冲突**：不同作用域可能有同名技能
2. **路径变更**：技能文件可能被移动或删除
3. **循环依赖**：技能依赖可能形成循环

### 潜在风险
1. **恶意技能**：技能可能包含恶意代码
2. **信息泄露**：技能路径可能泄露敏感信息
3. **性能影响**：大量技能可能影响启动性能

### 改进建议
1. **签名验证**：添加技能签名验证机制
2. **沙箱执行**：在隔离环境中执行技能代码
3. **依赖解析**：自动解析和安装技能依赖
4. **版本管理**：支持技能版本管理
5. **热重载**：支持技能的热更新
6. **使用统计**：收集技能使用统计优化推荐
