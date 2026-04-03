# SkillScope.ts 研究文档

## 场景与职责

`SkillScope.ts` 定义了技能作用域的数据结构，用于标识技能的有效范围和加载来源。这是 Codex 技能系统的权限和隔离组件，决定技能在何时何地对用户可用。

## 功能点目的

该类型用于：
1. **范围隔离**：区分不同来源的技能，防止冲突
2. **优先级管理**：基于作用域确定技能优先级
3. **安全边界**：限制技能的影响范围
4. **加载控制**：决定从哪些位置加载技能

## 具体技术实现

### 数据结构定义

```typescript
export type SkillScope = "user" | "repo" | "system" | "admin";
```

### 变体详解

| 值 | 说明 | 加载位置 | 典型用途 |
|----|------|---------|---------|
| "user" | 用户级技能 | `~/.codex/skills/` | 个人自定义技能 |
| "repo" | 仓库级技能 | `.codex/skills/` | 项目特定技能 |
| "system" | 系统级技能 | 系统目录 | 系统预装技能 |
| "admin" | 管理员技能 | 管理员配置目录 | 组织强制技能 |

### Rust 协议定义

在 `codex-rs/protocol/src/protocol.rs` 中：

```rust
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Display, JsonSchema, TS,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum SkillScope {
    User,   // 用户级
    Repo,   // 仓库级
    System, // 系统级
    Admin,  // 管理员级
}
```

### 作用域优先级

```rust
impl SkillScope {
    /// 返回作用域优先级，数字越大优先级越高
    pub fn priority(&self) -> u8 {
        match self {
            SkillScope::System => 0,
            SkillScope::Admin => 1,
            SkillScope::User => 2,
            SkillScope::Repo => 3,
        }
    }
}
```

### 技能加载路径

在 `codex-rs/core/src/skills/loader.rs` 中：

```rust
pub fn get_skill_roots_for_scope(
    scope: SkillScope,
    cwd: &Path,
) -> Vec<PathBuf> {
    match scope {
        SkillScope::System => vec![
            "/usr/share/codex/skills".into(),
            "/opt/codex/skills".into(),
        ],
        SkillScope::Admin => vec![
            "/etc/codex/skills".into(),
        ],
        SkillScope::User => vec![
            dirs::home_dir()
                .map(|h| h.join(".codex/skills"))
                .unwrap_or_default(),
        ],
        SkillScope::Repo => {
            // 从 cwd 向上查找 .codex/skills 目录
            find_repo_skill_roots(cwd)
        }
    }
}
```

### 技能合并逻辑

```rust
pub fn merge_skills_by_scope(
    skills_by_scope: HashMap<SkillScope, Vec<SkillMetadata>>
) -> Vec<SkillMetadata> {
    let mut all_skills: HashMap<String, SkillMetadata> = HashMap::new();
    
    // 按优先级顺序处理
    let mut scopes: Vec<_> = skills_by_scope.keys().collect();
    scopes.sort_by_key(|s| s.priority());
    
    for scope in scopes {
        for skill in &skills_by_scope[scope] {
            // 高优先级作用域的技能覆盖低优先级的同名技能
            all_skills.insert(skill.name.clone(), skill.clone());
        }
    }
    
    all_skills.into_values().collect()
}
```

### 在 SkillMetadata 中的使用

```rust
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    // ...
    pub scope: SkillScope,
    pub enabled: bool,
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SkillScope.ts`

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/protocol.rs`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 核心技能实现
- 技能模型：`codex-rs/core/src/skills/model.rs`
- 技能加载器：`codex-rs/core/src/skills/loader.rs`
- 技能管理器：`codex-rs/core/src/skills/manager.rs`
- 管理器测试：`codex-rs/core/src/skills/manager_tests.rs`

### 服务端集成
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 客户端消费
- TUI 应用：`codex-rs/tui/src/app.rs`
- TUI 底部面板：`codex-rs/tui/src/bottom_pane/mod.rs`
- TUI App Server：`codex-rs/tui_app_server/src/bottom_pane/mod.rs`

### 测试覆盖
- 技能测试：`codex-rs/core/tests/suite/skills.rs`
- MCP 依赖测试：`codex-rs/core/src/mcp/skill_dependencies_tests.rs`

### 相关类型
- SkillMetadata：`codex-rs/app-server-protocol/schema/typescript/v2/SkillMetadata.ts`
- SkillsListEntry：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListEntry.ts`
- SkillsListParams：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsListParams.ts`

## 依赖与外部交互

### 上游依赖
- 文件系统：从相应目录加载技能
- 配置：可能通过配置禁用某些作用域

### 下游消费
- 技能列表：按作用域分组显示
- 技能合并：解决同名技能冲突
- 权限检查：验证用户对技能的访问权限

### 作用域层次结构

```
System (最低优先级)
    ↓
Admin
    ↓
User
    ↓
Repo (最高优先级)
```

## 风险、边界与改进建议

### 边界情况
1. **无仓库**：在非 Git 仓库中使用 Repo 作用域
2. **多仓库**：在嵌套仓库中确定使用哪个 Repo 技能
3. **作用域禁用**：某些作用域可能被管理员禁用

### 潜在风险
1. **技能劫持**：高优先级作用域的恶意技能覆盖系统技能
2. **作用域混淆**：用户可能不清楚技能来自哪个作用域
3. **权限提升**：Repo 技能可能获得比预期更高的权限

### 改进建议
1. **作用域显示**：在 UI 中明确显示技能的作用域来源
2. **冲突警告**：当同名技能覆盖时显示警告
3. **作用域过滤**：允许用户按作用域过滤技能列表
4. **签名验证**：对 Admin 和 System 作用域的技能强制签名验证
5. **作用域继承**：支持技能继承其他作用域的配置
6. **审计日志**：记录技能加载和覆盖的审计日志
