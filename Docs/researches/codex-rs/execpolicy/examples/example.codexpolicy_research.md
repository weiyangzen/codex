# example.codexpolicy 研究文档

## 概述

`example.codexpolicy` 是 Codex 执行策略（execpolicy）系统的示例策略文件，位于 `codex-rs/execpolicy/examples/` 目录下。该文件使用 Starlark 语言语法定义了一组前缀规则（prefix rules），用于控制命令执行时的权限决策（allow/prompt/forbidden）。

**文件路径**: `/home/sansha/Github/codex/codex-rs/execpolicy/examples/example.codexpolicy`

---

## 场景与职责

### 1. 核心场景

`example.codexpolicy` 服务于以下核心场景：

| 场景 | 描述 |
|------|------|
| **命令执行权限控制** | 决定哪些 shell 命令可以自动执行、哪些需要用户确认、哪些被禁止 |
| **安全策略定义** | 通过声明式规则限制 AI Agent 可执行的命令范围 |
| **策略语法示例** | 作为开发者的参考模板，展示 `prefix_rule` 和 `host_executable` 的用法 |

### 2. 职责边界

- **不用于生产环境**：文件头部明确标注 "not comprehensive and not recommended for actual use"
- **语法演示**：展示 `prefix_rule` 的各种参数组合（pattern, decision, justification, match, not_match）
- **测试参考**：为 `codex-execpolicy` CLI 工具和核心库提供测试输入

### 3. 典型使用流程

```
用户命令输入
    ↓
Codex Core 解析命令
    ↓
ExecPolicyManager 加载策略文件（包括 .codexpolicy 文件）
    ↓
PolicyParser 解析 Starlark 规则
    ↓
Policy.check() 匹配命令前缀
    ↓
返回 Decision: Allow / Prompt / Forbidden
```

---

## 功能点目的

### 1. 策略规则类型

#### 1.1 Prefix Rule（前缀规则）

示例文件中的核心规则类型，匹配命令的前缀令牌序列：

```starlark
prefix_rule(
    pattern = ["git", "reset", "--hard"],
    decision = "forbidden",
    justification = "destructive operation",
    match = [["git", "reset", "--hard"]],
    not_match = [["git", "reset", "--keep"], "git reset --merge"],
)
```

**字段说明**：

| 字段 | 类型 | 必需 | 描述 |
|------|------|------|------|
| `pattern` | `list[string \| list[string]]` | 是 | 匹配模式，首元素为程序名，后续为参数；支持嵌套列表表示备选 |
| `decision` | `"allow" \| "prompt" \| "forbidden"` | 否 | 默认 `"allow"` |
| `justification` | `string` | 否 | 规则理由，用于提示/拒绝消息 |
| `match` | `list[string \| list[string]]` | 否 | 必须匹配的示例（加载时验证） |
| `not_match` | `list[string \| list[string]]` | 否 | 必须不匹配的示例（加载时验证） |

#### 1.2 Host Executable（主机可执行文件）

虽然示例文件未展示，但配套 README 说明了此功能：

```starlark
host_executable(
    name = "git",
    paths = ["/opt/homebrew/bin/git", "/usr/bin/git"],
)
```

用于限制哪些绝对路径的程序可以匹配基础名称规则。

#### 1.3 Network Rule（网络规则）

示例文件未展示，但系统支持：

```starlark
network_rule(
    host = "api.github.com",
    protocol = "https",
    decision = "allow",
    justification = "Allow GitHub API access",
)
```

### 2. 决策优先级

当多个规则匹配时，采用最严格的决策：

```
Forbidden > Prompt > Allow
```

### 3. 示例文件中的具体规则分析

| 规则 | Pattern | Decision | 目的 |
|------|---------|----------|------|
| git reset --hard | `["git", "reset", "--hard"]` | `forbidden` | 阻止破坏性 Git 操作 |
| ls | `["ls"]` | `allow` (默认) | 允许基本目录列表 |
| cat | `["cat"]` | `allow` | 允许文件查看 |
| cp | `["cp"]` | `prompt` | 复制操作需确认 |
| head | `["head"]` | `allow` | 允许查看文件头部 |
| printenv | `["printenv"]` | `allow` | 允许环境变量查看 |
| pwd | `["pwd"]` | `allow` | 允许查看当前目录 |
| which | `["which"]` | `allow` | 允许查找程序路径 |

---

## 具体技术实现

### 1. 关键数据结构

#### 1.1 Policy（策略）

```rust
// codex-rs/execpolicy/src/policy.rs
pub struct Policy {
    rules_by_program: MultiMap<String, RuleRef>,  // 按首令牌索引的规则
    network_rules: Vec<NetworkRule>,              // 网络规则列表
    host_executables_by_name: HashMap<String, Arc<[AbsolutePathBuf]>>, // 主机可执行文件映射
}
```

#### 1.2 PrefixRule（前缀规则）

```rust
// codex-rs/execpolicy/src/rule.rs
pub struct PrefixRule {
    pub pattern: PrefixPattern,
    pub decision: Decision,
    pub justification: Option<String>,
}

pub struct PrefixPattern {
    pub first: Arc<str>,           // 首令牌（程序名）
    pub rest: Arc<[PatternToken]>, // 后续令牌
}

pub enum PatternToken {
    Single(String),       // 单一值
    Alts(Vec<String>),    // 备选值列表
}
```

#### 1.3 Decision（决策枚举）

```rust
// codex-rs/execpolicy/src/decision.rs
pub enum Decision {
    Allow,      // 直接允许
    Prompt,     // 需要用户确认
    Forbidden,  // 禁止执行
}
```

### 2. 解析流程

#### 2.1 Starlark 解析

```rust
// codex-rs/execpolicy/src/parser.rs
impl PolicyParser {
    pub fn parse(&mut self, policy_identifier: &str, policy_file_contents: &str) -> Result<()> {
        // 1. 使用 Starlark 解析器解析 AST
        let ast = AstModule::parse(policy_identifier, policy_file_contents.to_string(), &dialect)?;
        
        // 2. 注册内置函数（prefix_rule, network_rule, host_executable）
        let globals = GlobalsBuilder::standard().with(policy_builtins).build();
        
        // 3. 执行 Starlark 代码，构建 PolicyBuilder
        let mut eval = Evaluator::new(&module);
        eval.extra = Some(&self.builder);
        eval.eval_module(ast, &globals)?;
        
        // 4. 验证 match/not_match 示例
        self.builder.validate_pending_examples_from(...)?;
        
        Ok(())
    }
}
```

#### 2.2 内置函数实现

```rust
// codex-rs/execpolicy/src/parser.rs
#[starlark_module]
fn policy_builtins(builder: &mut GlobalsBuilder) {
    fn prefix_rule<'v>(
        pattern: UnpackList<Value<'v>>,
        decision: Option<&'v str>,
        r#match: Option<UnpackList<Value<'v>>>,
        not_match: Option<UnpackList<Value<'v>>>,
        justification: Option<&'v str>,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<NoneType> {
        // 解析 pattern 为 PatternToken 列表
        // 创建 PrefixRule 并添加到 PolicyBuilder
        // 延迟验证 match/not_match 示例
    }
}
```

### 3. 匹配流程

#### 3.1 命令匹配算法

```rust
// codex-rs/execpolicy/src/policy.rs
pub fn matches_for_command_with_options(
    &self,
    cmd: &[String],
    heuristics_fallback: HeuristicsFallback<'_>,
    options: &MatchOptions,
) -> Vec<RuleMatch> {
    // 1. 尝试精确匹配（首令牌完全匹配）
    let matched_rules = self.match_exact_rules(cmd)
        .filter(|rules| !rules.is_empty())
        // 2. 如启用，尝试主机可执行文件解析
        .or_else(|| options.resolve_host_executables
            .then(|| self.match_host_executable_rules(cmd))
            .filter(|rules| !rules.is_empty()))
        .unwrap_or_default();
    
    // 3. 无匹配时回退到启发式决策
    if matched_rules.is_empty() && let Some(fallback) = heuristics_fallback {
        vec![RuleMatch::HeuristicsRuleMatch { ... }]
    } else {
        matched_rules
    }
}
```

#### 3.2 前缀匹配逻辑

```rust
// codex-rs/execpolicy/src/rule.rs
impl PrefixPattern {
    pub fn matches_prefix(&self, cmd: &[String]) -> Option<Vec<String>> {
        let pattern_length = self.rest.len() + 1;
        // 检查长度和首令牌
        if cmd.len() < pattern_length || cmd[0] != self.first.as_ref() {
            return None;
        }
        // 逐令牌匹配
        for (pattern_token, cmd_token) in self.rest.iter().zip(&cmd[1..pattern_length]) {
            if !pattern_token.matches(cmd_token) {
                return None;
            }
        }
        Some(cmd[..pattern_length].to_vec())
    }
}
```

### 4. 策略修改（Amend）

```rust
// codex-rs/execpolicy/src/amend.rs
pub fn blocking_append_allow_prefix_rule(
    policy_path: &Path,
    prefix: &[String],
) -> Result<(), AmendError> {
    // 1. 序列化前缀为 JSON 字符串
    // 2. 构造 prefix_rule 语句
    // 3. 使用文件锁追加到策略文件
    // 4. 去重检查
}
```

---

## 关键代码路径与文件引用

### 1. 核心库文件

| 文件 | 职责 |
|------|------|
| `codex-rs/execpolicy/src/lib.rs` | 模块导出，公共 API 暴露 |
| `codex-rs/execpolicy/src/policy.rs` | Policy 结构体，规则匹配逻辑，决策聚合 |
| `codex-rs/execpolicy/src/rule.rs` | Rule trait, PrefixRule, NetworkRule, PatternToken 定义 |
| `codex-rs/execpolicy/src/parser.rs` | Starlark 解析器，内置函数实现 |
| `codex-rs/execpolicy/src/decision.rs` | Decision 枚举定义 |
| `codex-rs/execpolicy/src/amend.rs` | 策略文件追加修改功能 |
| `codex-rs/execpolicy/src/execpolicycheck.rs` | CLI check 命令实现 |
| `codex-rs/execpolicy/src/executable_name.rs` | 可执行文件名处理（跨平台） |
| `codex-rs/execpolicy/src/error.rs` | 错误类型定义 |

### 2. 调用方代码路径

#### 2.1 Core 层集成

```
codex-rs/core/src/exec_policy.rs
  ├── ExecPolicyManager::load()           # 加载策略文件
  ├── ExecPolicyManager::create_exec_approval_requirement_for_command()
  │   └── 调用 Policy.check_multiple_with_options()
  ├── render_decision_for_unmatched_command()  # 未匹配命令的启发式决策
  └── derive_requested_execpolicy_amendment_from_prefix_rule()  # 生成策略修改建议
```

#### 2.2 CLI 集成

```
codex-rs/cli/src/main.rs
  └── codex execpolicy check 命令
      └── codex-rs/execpolicy/src/main.rs
          └── ExecPolicyCheckCommand::run()
```

#### 2.3 测试覆盖

```
codex-rs/execpolicy/tests/basic.rs        # 单元测试
codex-rs/cli/tests/execpolicy.rs          # CLI 集成测试
codex-rs/core/tests/suite/exec_policy.rs  # Core 层集成测试
```

### 3. 配置与加载路径

```
~/.codex/rules/*.rules                    # 默认策略文件搜索路径
CODEX_HOME/rules/default.rules            # 默认策略文件
```

---

## 依赖与外部交互

### 1. 外部依赖

| 依赖 | 用途 |
|------|------|
| `starlark` | Starlark 语言解析与执行 |
| `serde` / `serde_json` | 序列化/反序列化 |
| `shlex` | Shell 命令令牌化 |
| `multimap` | 多值哈希表（rules_by_program） |
| `clap` | CLI 参数解析 |
| `anyhow` / `thiserror` | 错误处理 |
| `codex-utils-absolute-path` | 绝对路径处理 |

### 2. 内部依赖关系

```
codex-execpolicy (crate)
    ├── codex-utils-absolute-path
    └── 被依赖：
        ├── codex-core (ExecPolicyManager)
        ├── codex-cli (execpolicy check 命令)
        └── codex-protocol (ExecPolicyAmendment 类型)
```

### 3. 协议集成

```rust
// codex-rs/protocol/src/approvals.rs
pub struct ExecPolicyAmendment {
    pub command: Vec<String>,  // 建议添加的前缀规则
}

pub struct ExecApprovalRequestEvent {
    pub proposed_execpolicy_amendment: Option<ExecPolicyAmendment>,
}
```

### 4. 跨平台支持

| 平台 | 特殊处理 |
|------|----------|
| Windows | 可执行文件后缀处理（.exe, .cmd, .bat, .com），大小写不敏感匹配 |
| Unix | 大小写敏感匹配 |

---

## 风险、边界与改进建议

### 1. 已知风险

#### 1.1 安全性风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **过度宽松的规则** | `pattern = ["bash"]` 会允许所有 bash 命令 | 使用更具体的模式，如 `["bash", "-c", "specific-script"]` |
| **路径遍历绕过** | 使用相对路径或符号链接可能绕过 host_executable 限制 | 解析绝对路径并进行规范化 |
| **命令注入** | match/not_match 示例中的字符串通过 shlex 解析，可能被绕过 | 优先使用列表形式定义示例 |

#### 1.2 功能限制

- **仅支持前缀匹配**：无法匹配命令中间或末尾的参数
- **无变量支持**：无法根据环境变量动态决策
- **无通配符**：`pattern` 不支持 `*` 或 `?` 通配符

### 2. 边界情况

#### 2.1 空命令处理

```rust
// add_prefix_rule 拒绝空前缀
if prefix.is_empty() {
    return Err(Error::InvalidPattern("prefix cannot be empty".to_string()));
}
```

#### 2.2 重复规则处理

- 相同规则多次追加时，`amend.rs` 会去重
- 不同决策的相同前缀规则共存时，最严格的决策生效

#### 2.3 主机可执行文件解析边界

```rust
// 仅当满足以下条件时启用 basename 回退：
// 1. resolve_host_executables = true
// 2. 无精确匹配
// 3. host_executable 未定义或路径在白名单中
```

### 3. 改进建议

#### 3.1 功能增强

| 建议 | 优先级 | 描述 |
|------|--------|------|
| **正则表达式支持** | 中 | 允许在 pattern 中使用正则匹配参数值 |
| **条件规则** | 低 | 支持基于环境变量或工作目录的条件规则 |
| **规则继承/包含** | 中 | 支持 `load()` 或 `include()` 复用规则文件 |
| **规则注释元数据** | 低 | 支持 `@deprecated` 等元数据标签 |

#### 3.2 性能优化

| 建议 | 描述 |
|------|------|
| **规则索引优化** | 对高频命令建立缓存索引 |
| **懒加载策略** | 大型策略文件支持按需加载 |

#### 3.3 可观测性

| 建议 | 描述 |
|------|------|
| **规则匹配日志** | 记录每次命令执行的规则匹配过程 |
| **策略覆盖率报告** | 统计哪些规则从未被匹配 |
| **冲突检测** | 加载时检测可能冲突的规则 |

#### 3.4 示例文件改进

针对 `example.codexpolicy` 本身：

1. **添加注释说明**：每个规则应包含更详细的用途注释
2. **展示高级特性**：添加 `host_executable` 和 `network_rule` 示例
3. **安全最佳实践**：展示如何安全地限制解释器调用（python, node 等）
4. **分层策略示例**：展示如何通过多个文件组织策略

### 4. 相关 Issue/PR 参考

- 策略系统仍在活跃开发中（README 标注 "still in preview"）
- API 可能有破坏性变更
- 旧版规则匹配器位于 `codex-execpolicy-legacy` crate

---

## 附录：示例文件完整内容

```starlark
# Example policy to illustrate syntax; not comprehensive and not recommended for actual use.

prefix_rule(
    pattern = ["git", "reset", "--hard"],
    decision = "forbidden",
    justification = "destructive operation",
    match = [
        ["git", "reset", "--hard"],
    ],
    not_match = [
        ["git", "reset", "--keep"],
        "git reset --merge",
    ],
)

prefix_rule(
    pattern = ["ls"],
    match = [
        ["ls"],
        ["ls", "-l"],
        ["ls", "-a", "."],
    ],
)

prefix_rule(
    pattern = ["cat"],
    match = [
        ["cat", "file.txt"],
        ["cat", "-n", "README.md"],
    ],
)

prefix_rule(
    pattern = ["cp"],
    decision = "prompt",
    match = [
        ["cp", "foo", "bar"],
        "cp -r src dest",
    ],
)

prefix_rule(
    pattern = ["head"],
    match = [
        ["head", "README.md"],
        ["head", "-n", "5", "CHANGELOG.md"],
    ],
    not_match = [
        ["hea", "-n", "1,5p", "CHANGELOG.md"],
    ],
)

prefix_rule(
    pattern = ["printenv"],
    match = [
        ["printenv"],
        ["printenv", "PATH"],
    ],
    not_match = [
        ["print", "-0"],
    ],
)

prefix_rule(
    pattern = ["pwd"],
    match = [
        ["pwd"],
    ],
)

prefix_rule(
    pattern = ["which"],
    match = [
        ["which", "python3"],
        ["which", "-a", "python3"],
    ],
)
```

---

*文档生成时间: 2026-03-23*
*基于 commit: 当前工作目录*
