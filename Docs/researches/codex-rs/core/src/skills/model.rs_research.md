# model.rs 深度研究文档

## 场景与职责

`model.rs` 是 Codex 核心技能系统的数据模型定义文件，负责定义技能相关的所有核心数据结构。这些结构体是技能子系统各模块之间通信的基础，也是对外暴露的主要 API 类型。

### 核心职责

1. **技能元数据定义**：定义 `SkillMetadata` 结构体，包含技能的完整描述信息
2. **加载结果封装**：定义 `SkillLoadOutcome`，封装技能加载的结果和错误
3. **策略和权限模型**：定义 `SkillPolicy` 和权限相关结构
4. **依赖和接口定义**：定义技能依赖和 UI 接口配置
5. **网络覆盖配置**：定义 `SkillManagedNetworkOverride` 用于域名级网络控制

---

## 功能点目的

### 1. SkillMetadata - 技能元数据

**目的**：表示一个已加载技能的完整元数据。

```rust
pub struct SkillMetadata {
    pub name: String,                           // 技能名称（唯一标识）
    pub description: String,                    // 详细描述
    pub short_description: Option<String>,      // 简短描述
    pub interface: Option<SkillInterface>,      // UI 接口配置
    pub dependencies: Option<SkillDependencies>, // 依赖工具
    pub policy: Option<SkillPolicy>,            // 策略配置
    pub permission_profile: Option<PermissionProfile>, // 权限配置
    pub managed_network_override: Option<SkillManagedNetworkOverride>, // 网络覆盖
    pub path_to_skills_md: PathBuf,             // SKILL.md 文件路径
    pub scope: SkillScope,                      // 作用域
}
```

**设计决策**：
- 使用 `Option<T>` 表示可选字段，允许部分配置
- `path_to_skills_md` 用于定位技能文件，支持动态加载内容
- `scope` 用于权限控制和加载优先级

**辅助方法**：
```rust
impl SkillMetadata {
    fn allow_implicit_invocation(&self) -> bool {
        self.policy
            .as_ref()
            .and_then(|policy| policy.allow_implicit_invocation)
            .unwrap_or(true)  // 默认允许隐式调用
    }
}
```

### 2. SkillLoadOutcome - 加载结果

**目的**：封装技能加载操作的完整结果。

```rust
pub struct SkillLoadOutcome {
    pub skills: Vec<SkillMetadata>,                    // 成功加载的技能
    pub errors: Vec<SkillError>,                       // 加载错误
    pub disabled_paths: HashSet<PathBuf>,              // 禁用的技能路径
    pub(crate) implicit_skills_by_scripts_dir: Arc<HashMap<PathBuf, SkillMetadata>>, // 脚本目录索引
    pub(crate) implicit_skills_by_doc_path: Arc<HashMap<PathBuf, SkillMetadata>>,    // 文档路径索引
}
```

**设计决策**：
- 使用 `Arc` 共享索引，避免克隆大型 HashMap
- `disabled_paths` 支持运行时启用/禁用控制
- 索引使用 `pub(crate)` 限制外部直接访问

**查询方法**：
```rust
impl SkillLoadOutcome {
    pub fn is_skill_enabled(&self, skill: &SkillMetadata) -> bool
    pub fn is_skill_allowed_for_implicit_invocation(&self, skill: &SkillMetadata) -> bool
    pub fn allowed_skills_for_implicit_invocation(&self) -> Vec<SkillMetadata>
    pub fn skills_with_enabled(&self) -> impl Iterator<Item = (&SkillMetadata, bool)>
}
```

### 3. SkillPolicy - 策略配置

**目的**：控制技能的行为策略。

```rust
pub struct SkillPolicy {
    pub allow_implicit_invocation: Option<bool>,  // 是否允许隐式调用
    pub products: Vec<Product>,                    // 支持的产品
}
```

**TODO 注释**：
```rust
// TODO: Enforce product gating in Codex skill selection/injection instead of only parsing and
// storing this metadata.
```

说明 `products` 字段当前仅解析存储，尚未在技能选择中强制执行。

### 4. SkillInterface - UI 接口配置

**目的**：定义技能在 UI 中的展示方式。

```rust
pub struct SkillInterface {
    pub display_name: Option<String>,       // 显示名称
    pub short_description: Option<String>,  // 简短描述
    pub icon_small: Option<PathBuf>,        // 小图标路径
    pub icon_large: Option<PathBuf>,        // 大图标路径
    pub brand_color: Option<String>,        // 品牌色（#RRGGBB）
    pub default_prompt: Option<String>,     // 默认提示词
}
```

### 5. SkillDependencies - 依赖配置

**目的**：定义技能的依赖工具。

```rust
pub struct SkillDependencies {
    pub tools: Vec<SkillToolDependency>,
}

pub struct SkillToolDependency {
    pub r#type: String,         // 类型：env_var, mcp, cli
    pub value: String,          // 值：变量名、MCP 名称、命令名
    pub description: Option<String>,
    pub transport: Option<String>,  // MCP 传输方式
    pub command: Option<String>,    // MCP 命令
    pub url: Option<String>,        // MCP URL
}
```

**依赖类型**：
- `env_var`：环境变量依赖（如 `GITHUB_TOKEN`）
- `mcp`：MCP 服务器依赖（stdio 或 streamable_http）
- `cli`：命令行工具依赖（如 `gh`）

### 6. SkillError - 错误信息

**目的**：封装技能加载错误。

```rust
pub struct SkillError {
    pub path: PathBuf,      // 出错的文件路径
    pub message: String,    // 错误信息
}
```

### 7. SkillManagedNetworkOverride - 网络覆盖

**目的**：支持技能级别的域名访问控制。

```rust
pub struct SkillManagedNetworkOverride {
    pub allowed_domains: Option<Vec<String>>,
    pub denied_domains: Option<Vec<String>>,
}

impl SkillManagedNetworkOverride {
    pub fn has_domain_overrides(&self) -> bool {
        self.allowed_domains.is_some() || self.denied_domains.is_some()
    }
}
```

**与 PermissionProfile 的关系**：
- `PermissionProfile.network.enabled` 控制网络总开关
- `SkillManagedNetworkOverride` 提供细粒度的域名控制
- 两者在 `loader.rs` 的 `normalize_permissions` 中分离

---

## 具体技术实现

### 派生宏使用

```rust
#[derive(Debug, Clone, Default, Deserialize, PartialEq, Eq)]  // SkillManagedNetworkOverride
#[derive(Debug, Clone, PartialEq)]                              // SkillMetadata
#[derive(Debug, Clone, PartialEq, Eq, Default)]                // SkillPolicy
#[derive(Debug, Clone, PartialEq, Eq)]                         // SkillInterface, SkillDependencies, SkillToolDependency, SkillError
#[derive(Debug, Clone, Default)]                               // SkillLoadOutcome
```

**设计决策**：
- `SkillMetadata` 不实现 `Eq` 因为包含 `PathBuf`（某些平台路径比较可能有差异）
- `SkillLoadOutcome` 不实现 `PartialEq` 因为包含 `Arc`（指针比较而非内容比较）

### 外部类型依赖

```rust
use codex_protocol::models::PermissionProfile;    // 权限配置
use codex_protocol::protocol::Product;            // 产品枚举
use codex_protocol::protocol::SkillScope;         // 作用域枚举
```

### Default 实现

```rust
impl Default for SkillLoadOutcome {
    fn default() -> Self {
        Self {
            skills: Vec::new(),
            errors: Vec::new(),
            disabled_paths: HashSet::new(),
            implicit_skills_by_scripts_dir: Arc::new(HashMap::new()),
            implicit_skills_by_doc_path: Arc::new(HashMap::new()),
        }
    }
}
```

---

## 关键代码路径与文件引用

### 类型使用分布

| 类型 | 定义位置 | 主要使用者 |
|------|----------|------------|
| `SkillMetadata` | model.rs:24 | loader.rs, manager.rs, injection.rs, render.rs |
| `SkillLoadOutcome` | model.rs:87 | loader.rs, manager.rs, codex.rs |
| `SkillPolicy` | model.rs:48 | loader.rs |
| `SkillInterface` | model.rs:56 | loader.rs |
| `SkillDependencies` | model.rs:66 | loader.rs, env_var_dependencies.rs |
| `SkillToolDependency` | model.rs:71 | loader.rs |
| `SkillError` | model.rs:81 | loader.rs |
| `SkillManagedNetworkOverride` | model.rs:12 | loader.rs, manager.rs |

### 序列化/反序列化

- `SkillManagedNetworkOverride` 实现 `Deserialize` 用于从 YAML 配置解析
- 其他类型通过 `loader.rs` 中的中间结构（如 `SkillMetadataFile`）进行反序列化

### 转换关系

```
loader.rs:
  SkillMetadataFile (YAML) 
    -> LoadedSkillMetadata (内部)
    -> SkillMetadata (公共)

  SkillPermissionFile (YAML)
    -> normalize_permissions()
    -> (PermissionProfile, SkillManagedNetworkOverride)
```

---

## 依赖与外部交互

### 外部类型

| 类型 | 来源 | 用途 |
|------|------|------|
| `PermissionProfile` | `codex_protocol::models` | 权限配置共享定义 |
| `Product` | `codex_protocol::protocol` | 产品枚举（Codex, Chatgpt, Atlas） |
| `SkillScope` | `codex_protocol::protocol` | 作用域枚举（Repo, User, System, Admin） |

### 标准库依赖

```rust
use std::collections::HashMap;
use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::Arc;
```

---

## 风险、边界与改进建议

### 当前风险

1. **类型一致性**：
   - `SkillMetadata` 和 `loader.rs` 中的 `SkillFrontmatter` 需要保持字段同步
   - 变更需要同时更新多个文件

2. **Option 过度使用**：
   - 大量 `Option<T>` 字段可能导致空值处理复杂
   - 某些字段可能有业务上的必填要求

3. **PathBuf 平台差异**：
   - 不同平台的路径格式可能导致序列化/比较问题
   - Windows 和 Unix 的路径分隔符差异

### 边界情况

1. **空集合处理**：
   - `Vec::new()` 和 `None` 的语义差异
   - `HashSet::new()` 表示没有禁用路径

2. **Arc 共享**：
   - `implicit_skills_by_*` 使用 `Arc` 共享
   - 修改需要创建新的 `Arc`，不可变更新

3. **字符串长度**：
   - 模型层不强制执行长度限制
   - 长度验证在 `loader.rs` 中进行

### 改进建议

1. **类型安全**：
   - 考虑使用 newtype 模式包装字符串（如 `SkillName(String)`）
   - 添加验证方法到类型本身
   - 使用 `NonEmptyString` 等类型表示必填字段

2. **Builder 模式**：
   - 为 `SkillMetadata` 添加 builder 模式
   - 简化复杂结构的创建
   - 支持渐进式构造

3. **序列化优化**：
   - 考虑使用 `serde_with` 简化自定义序列化
   - 添加版本字段支持向后兼容
   - 使用 `#[serde(default)]` 减少 Option 使用

4. **文档**：
   - 为每个字段添加详细文档注释
   - 添加示例值到文档
   - 说明字段的默认值和业务含义

5. **测试**：
   - 添加构造函数的单元测试
   - 验证 Default 实现的正确性
   - 测试序列化/反序列化的往返一致性

6. **API 稳定性**：
   - 考虑使用 `#[non_exhaustive]` 标记公共结构体
   - 为未来扩展预留空间
   - 建立版本兼容性策略
