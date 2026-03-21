# 研究报告: codex-rs/execpolicy/src

## 概述

`codex-execpolicy` 是 Codex 项目的命令执行策略引擎，负责定义、解析和评估命令执行的安全策略。它使用基于 Starlark 的领域特定语言（DSL）来声明命令前缀匹配规则，支持三种决策类型：允许（Allow）、提示（Prompt）、禁止（Forbidden）。该 crate 是 Codex 安全模型的核心组件，决定了哪些 shell 命令可以在沙箱内外执行。

---

## 1. 场景与职责

### 1.1 核心职责

| 职责领域 | 说明 |
|---------|------|
| **策略定义** | 提供 Starlark DSL 让用户定义命令执行规则 |
| **策略解析** | 解析 `.rules` 文件并构建内部策略表示 |
| **命令评估** | 对输入命令进行前缀匹配，返回执行决策 |
| **运行时策略管理** | 支持策略热更新和动态扩展 |
| **网络策略** | 管理网络访问规则（HTTP/HTTPS/SOCKS5） |

### 1.2 使用场景

1. **命令预执行检查**: 在 shell 工具执行前评估命令是否被允许
2. **用户审批流程**: 对需要提示的命令生成审批请求
3. **策略自动扩展**: 根据用户审批自动添加允许规则
4. **网络代理决策**: 决定哪些域名可以通过代理访问

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                    Codex Core / CLI                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              ExecPolicyManager                        │   │
│  │  (codex-rs/core/src/exec_policy.rs)                  │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │ uses                             │
│  ┌──────────────────────▼──────────────────────────────┐   │
│  │              codex-execpolicy (this crate)           │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐  │   │
│  │  │ Parser  │ │ Policy  │ │  Rule   │ │ Decision │  │   │
│  │  │(Starlark)│ │(Engine) │ │(Matcher)│ │ (Enum)   │  │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └──────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 前缀规则 (Prefix Rule)

**目的**: 基于命令前缀模式匹配来控制命令执行权限。

**功能特性**:
- 支持精确字符串匹配和备选模式（alternatives）
- 支持决策类型：`allow`、`prompt`、`forbidden`
- 可选的 `justification` 字段解释规则原因
- 支持 `match`/`not_match` 示例验证

**示例**:
```starlark
prefix_rule(
    pattern = ["git", ["status", "log"]],  # git status 或 git log
    decision = "allow",
    justification = "Safe read-only git commands",
    match = [["git", "status"], "git log"],
    not_match = [["git", "reset", "--hard"]],
)
```

### 2.2 网络规则 (Network Rule)

**目的**: 控制特定主机的网络访问权限。

**功能特性**:
- 支持协议：`http`、`https`、`socks5_tcp`、`socks5_udp`
- 严格的域名验证（拒绝通配符）
- 支持 IPv4/IPv6 地址和端口

**示例**:
```starlark
network_rule(
    host = "api.github.com",
    protocol = "https",
    decision = "allow",
    justification = "Allow GitHub API access",
)
```

### 2.3 主机可执行文件映射 (Host Executable)

**目的**: 将基本命令名映射到允许的绝对路径，防止路径欺骗攻击。

**功能特性**:
- 限制哪些绝对路径可以匹配基本名规则
- 支持多个允许路径
- 路径去重和验证

**示例**:
```starlark
host_executable(
    name = "git",
    paths = [
        "/opt/homebrew/bin/git",
        "/usr/bin/git",
    ],
)
```

### 2.4 策略评估引擎

**目的**: 对输入命令进行高效的规则匹配。

**匹配优先级**:
1. 精确匹配（第一令牌精确匹配）
2. 主机可执行文件解析（如果启用）
3. 启发式回退（heuristics fallback）

**决策聚合**: 当多个规则匹配时，选择最严格的决策（`forbidden > prompt > allow`）。

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 Decision 枚举 (`decision.rs`)

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Decision {
    Allow,      // 命令可直接执行
    Prompt,     // 需要用户审批
    Forbidden,  // 禁止执行
}
```

决策类型实现了 `Ord`，支持使用 `max()` 进行严格度比较。

#### 3.1.2 Policy 结构 (`policy.rs`)

```rust
#[derive(Clone, Debug)]
pub struct Policy {
    rules_by_program: MultiMap<String, RuleRef>,  // 按程序名索引的规则
    network_rules: Vec<NetworkRule>,              // 网络访问规则
    host_executables_by_name: HashMap<String, Arc<[AbsolutePathBuf]>>,  // 允许的路径映射
}
```

使用 `MultiMap` 支持一个程序名对应多个规则。

#### 3.1.3 规则类型层次 (`rule.rs`)

```rust
pub trait Rule: Any + Debug + Send + Sync {
    fn program(&self) -> &str;
    fn matches(&self, cmd: &[String]) -> Option<RuleMatch>;
    fn as_any(&self) -> &dyn Any;
}

pub type RuleRef = Arc<dyn Rule>;

pub struct PrefixRule {
    pub pattern: PrefixPattern,
    pub decision: Decision,
    pub justification: Option<String>,
}

pub struct NetworkRule {
    pub host: String,
    pub protocol: NetworkRuleProtocol,
    pub decision: Decision,
    pub justification: Option<String>,
}
```

#### 3.1.4 模式匹配 (`rule.rs`)

```rust
pub enum PatternToken {
    Single(String),      // 精确匹配
    Alts(Vec<String>),   // 多选一
}

pub struct PrefixPattern {
    pub first: Arc<str>,           // 第一令牌（用于索引）
    pub rest: Arc<[PatternToken]>, // 剩余模式
}
```

### 3.2 关键流程

#### 3.2.1 策略解析流程 (`parser.rs`)

```
.rules 文件 → Starlark AST → PolicyBuilder → Policy
```

1. **AST 解析**: 使用 `starlark` crate 解析 Starlark 语法
2. **内置函数注册**: 注册 `prefix_rule()`, `network_rule()`, `host_executable()`
3. **规则构建**: 在 `PolicyBuilder` 中累积规则
4. **示例验证**: 验证 `match`/`not_match` 示例
5. **策略生成**: 构建最终的 `Policy` 对象

#### 3.2.2 命令评估流程 (`policy.rs`)

```rust
pub fn check<F>(&self, cmd: &[String], heuristics_fallback: &F) -> Evaluation
where
    F: Fn(&[String]) -> Decision,
{
    let matched_rules = self.matches_for_command_with_options(...);
    Evaluation::from_matches(matched_rules)
}
```

匹配逻辑:
1. 尝试 `match_exact_rules`: 精确第一令牌匹配
2. 如启用 `resolve_host_executables`，尝试 `match_host_executable_rules`
3. 如无匹配且有启发式回退，返回 `HeuristicsRuleMatch`

#### 3.2.3 策略修改流程 (`amend.rs`)

```rust
pub fn blocking_append_allow_prefix_rule(
    policy_path: &Path,
    prefix: &[String],
) -> Result<(), AmendError>
```

1. 使用文件锁保证并发安全
2. 读取现有内容，检查重复
3. 追加新规则行
4. 自动创建目录（如不存在）

### 3.3 协议与接口

#### 3.3.1 CLI 接口 (`execpolicycheck.rs`)

```bash
codex-execpolicy check \
    --rules path/to/policy.rules \
    --resolve-host-executables \
    --pretty \
    git status
```

输出格式（JSON）:
```json
{
  "matchedRules": [
    {
      "matchedPrefix": ["git", "status"],
      "decision": "allow",
      "resolvedProgram": null,
      "justification": null
    }
  ],
  "decision": "allow"
}
```

#### 3.3.2 库接口 (`lib.rs`)

主要导出类型:
- `Policy`: 策略引擎
- `PolicyParser`: 策略解析器
- `Decision`: 决策枚举
- `RuleMatch`: 规则匹配结果
- `Evaluation`: 评估结果
- `blocking_append_allow_prefix_rule`: 追加规则
- `blocking_append_network_rule`: 追加网络规则

### 3.4 错误处理

#### 3.4.1 错误类型 (`error.rs`)

```rust
pub enum Error {
    InvalidDecision(String),
    InvalidPattern(String),
    InvalidExample(String),
    InvalidRule(String),
    ExampleDidNotMatch { rules, examples, location },
    ExampleDidMatch { rule, example, location },
    Starlark(StarlarkError),
}
```

#### 3.4.2 错误定位

支持精确的错误位置信息:
```rust
pub struct ErrorLocation {
    pub path: String,
    pub range: TextRange,  // 行号 + 列号
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/execpolicy/src/
├── lib.rs              # 库入口，模块导出
├── main.rs             # CLI 入口
├── policy.rs           # Policy 结构体和评估逻辑 (375 lines)
├── rule.rs             # 规则定义和匹配逻辑 (306 lines)
├── decision.rs         # Decision 枚举 (27 lines)
├── parser.rs           # Starlark 解析器 (473 lines)
├── amend.rs            # 策略修改功能 (338 lines)
├── error.rs            # 错误类型定义 (101 lines)
├── execpolicycheck.rs  # CLI 检查命令 (95 lines)
└── executable_name.rs  # 可执行文件名处理 (29 lines)
```

### 4.2 关键代码路径

| 功能 | 文件 | 关键函数/结构 |
|-----|------|--------------|
| 策略解析 | `parser.rs` | `PolicyParser::parse()`, `policy_builtins` |
| 前缀匹配 | `rule.rs:46-59` | `PrefixPattern::matches_prefix()` |
| 规则评估 | `policy.rs:268-295` | `matches_for_command_with_options()` |
| 决策聚合 | `policy.rs:365-374` | `Evaluation::from_matches()` |
| 策略修改 | `amend.rs:66-126` | `blocking_append_allow_prefix_rule()` |
| 网络规则验证 | `rule.rs:156-212` | `normalize_network_rule_host()` |
| 主机可执行文件匹配 | `policy.rs:307-334` | `match_host_executable_rules()` |

### 4.3 测试覆盖

测试文件: `tests/basic.rs` (963 lines)

主要测试场景:
- 基本前缀匹配
- 多规则决策聚合
- 主机可执行文件解析
- 示例验证 (`match`/`not_match`)
- 网络规则编译
- 策略修改（追加规则）

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| Crate | 用途 |
|-------|------|
| `starlark` | Starlark 语言解析和执行 |
| `multimap` | 多值映射（一个键对应多个规则） |
| `serde`/`serde_json` | 序列化/反序列化 |
| `shlex` | Shell 风格字符串分词 |
| `thiserror` | 错误类型定义 |
| `anyhow` | 错误处理 |
| `clap` | CLI 参数解析 |
| `codex-utils-absolute-path` | 绝对路径类型 |

### 5.2 上游调用方

| 调用方 | 用途 |
|--------|------|
| `codex-rs/core/src/exec_policy.rs` | 核心执行策略管理 |
| `codex-rs/config/src/requirements_exec_policy.rs` | 需求配置策略解析 |
| `codex-rs/protocol/src/models.rs` | 开发者指令生成 |
| `codex-rs/cli/src/main.rs` | CLI execpolicy 子命令 |

### 5.3 与 execpolicy-legacy 的关系

`codex-rs/execpolicy-legacy` 是旧版策略引擎，已被本 crate 取代。遗留 crate 仍保留用于向后兼容测试。

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| **Starlark 注入** | 恶意构造的 `.rules` 文件可能利用 Starlark 引擎 | 仅暴露白名单内置函数，禁用文件系统访问 |
| **路径欺骗** | 攻击者可能通过同名可执行文件绕过规则 | `host_executable` 白名单机制 |
| **规则冲突** | 重叠规则可能导致意外决策 | 决策严格度聚合（取最严格） |
| **并发修改** | 多进程同时修改策略文件 | 使用文件锁（advisory locking） |

### 6.2 边界情况

1. **空策略**: 空策略对所有命令返回空匹配，依赖启发式回退
2. **全通配符**: 第一令牌不支持通配符，但后续令牌支持多选
3. **IPv6 主机**: 网络规则支持 `[::1]` 格式的 IPv6 字面量
4. **Windows 可执行文件**: 自动处理 `.exe`/`.cmd`/`.bat`/`.com` 后缀

### 6.3 改进建议

| 优先级 | 建议 | 理由 |
|--------|------|------|
| 中 | 添加规则优先级/权重机制 | 解决规则冲突时的明确排序需求 |
| 中 | 支持正则表达式模式 | 更灵活的匹配需求（如版本号） |
| 低 | 策略缓存和增量更新 | 提升大规模策略的加载性能 |
| 低 | 规则条件评估（时间、环境变量） | 支持更复杂的策略场景 |
| 低 | 策略版本迁移工具 | 简化未来 DSL 语法变更 |

### 6.4 代码质量观察

**优点**:
- 清晰的模块分离（解析、评估、修改分离）
- 完善的错误类型和位置信息
- 全面的单元测试覆盖
- 使用 Starlark 提供熟悉的 Python-like 语法

**潜在改进**:
- `parser.rs` 较长（473 lines），可考虑拆分内置函数定义
- `PolicyBuilder` 使用 `RefCell`，可考虑更函数式的构建器模式
- 缺少集成测试（仅单元测试）

---

## 7. 配置示例

完整的策略文件示例 (`examples/example.codexpolicy`):

```starlark
prefix_rule(
    pattern = ["git", "reset", "--hard"],
    decision = "forbidden",
    justification = "destructive operation",
    match = [["git", "reset", "--hard"]],
    not_match = [["git", "reset", "--keep"]],
)

prefix_rule(
    pattern = ["ls"],
    match = [["ls"], ["ls", "-l"]],
)

prefix_rule(
    pattern = [["bash", "sh"], ["-c", "-l"]],
    decision = "prompt",
)
```

---

## 8. 总结

`codex-execpolicy` 是一个设计精良的命令执行策略引擎，通过 Starlark DSL 提供了灵活且安全的策略定义能力。其核心优势在于：

1. **清晰的决策模型**: 三级决策（Allow/Prompt/Forbidden）满足大多数安全场景
2. **高效的前缀匹配**: 基于 MultiMap 的索引确保快速规则查找
3. **防御性设计**: host_executable 机制防止路径欺骗攻击
4. **可扩展架构**: 支持策略热更新和动态扩展

该 crate 是 Codex 安全架构的基石，建议在进行安全相关修改时进行全面的回归测试。

---

*生成时间: 2026-03-21*
*研究范围: codex-rs/execpolicy/src/*
