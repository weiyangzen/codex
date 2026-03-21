# DIR codex-rs/execpolicy/examples 深度研究

## 概述

`codex-rs/execpolicy/examples` 目录包含 Codex 执行策略引擎的示例策略文件。该目录仅包含一个文件 `example.codexpolicy`，它展示了 Starlark 语法的执行策略规则定义方式。

---

## 场景与职责

### 定位与用途

- **示例教育作用**: `example.codexpolicy` 作为官方示例，展示如何使用 Starlark 语法编写执行策略规则
- **语法参考**: 为开发者提供 `prefix_rule` 函数的完整用法示例
- **测试辅助**: 被测试用例和 CLI 工具引用，用于验证解析器行为

### 使用场景

1. **开发参考**: 开发者在编写自定义策略文件时的语法模板
2. **CLI 测试**: 通过 `codex execpolicy check` 命令测试策略评估
3. **集成测试**: 测试套件使用示例验证解析和匹配逻辑

---

## 功能点目的

### example.codexpolicy 结构分析

该示例文件展示了以下核心功能：

#### 1. 禁止规则 (Forbidden Rule)
```starlark
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
```
**目的**: 展示如何禁止危险操作（如 `git reset --hard`），并提供：
- `justification`: 解释为何禁止，用于用户提示
- `match`: 验证规则确实匹配预期命令
- `not_match`: 验证规则不应对类似但安全的命令生效

#### 2. 允许规则 (Allow Rule - 默认)
```starlark
prefix_rule(
    pattern = ["ls"],
    match = [
        ["ls"],
        ["ls", "-l"],
        ["ls", "-a", "."],
    ],
)
```
**目的**: 展示默认 `decision = "allow"` 的简洁写法，无需显式声明决策类型。

#### 3. 提示规则 (Prompt Rule)
```starlark
prefix_rule(
    pattern = ["cp"],
    decision = "prompt",
    match = [
        ["cp", "foo", "bar"],
        "cp -r src dest",
    ],
)
```
**目的**: 展示如何对潜在风险操作（如文件复制）要求用户确认。

#### 4. 混合示例格式
示例文件展示了两种 `match`/`not_match` 格式：
- **数组格式**: `["git", "reset", "--hard"]` - 精确控制每个 token
- **字符串格式**: `"git reset --merge"` - 使用 shlex 分词的便捷写法

---

## 具体技术实现

### 1. 策略解析流程

```
example.codexpolicy
       ↓
PolicyParser::parse()  [parser.rs:58-79]
       ↓
Starlark AST 解析 (AstModule::parse)
       ↓
policy_builtins 模块执行
       ↓
PrefixRule 对象创建
       ↓
示例验证 (validate_match_examples / validate_not_match_examples)
       ↓
Policy 对象构建
```

### 2. 关键数据结构

#### PrefixRule (rule.rs:111-115)
```rust
pub struct PrefixRule {
    pub pattern: PrefixPattern,      // 匹配模式
    pub decision: Decision,          // allow | prompt | forbidden
    pub justification: Option<String>, // 人类可读的理由
}
```

#### PrefixPattern (rule.rs:39-43)
```rust
pub struct PrefixPattern {
    pub first: Arc<str>,                    // 第一个 token（用于索引）
    pub rest: Arc<[PatternToken]>,          // 后续 token 模式
}
```

#### PatternToken (rule.rs:15-19)
```rust
pub enum PatternToken {
    Single(String),       // 单值匹配
    Alts(Vec<String>),    // 多选一匹配
}
```

### 3. 决策枚举 (decision.rs)

```rust
pub enum Decision {
    Allow,      // 直接允许执行
    Prompt,     // 需要用户确认
    Forbidden,  // 禁止执行
}
```

决策优先级：`Forbidden > Prompt > Allow`

### 4. 匹配算法

**前缀匹配** (policy.rs:297-305):
```rust
fn match_exact_rules(&self, cmd: &[String]) -> Option<Vec<RuleMatch>> {
    let first = cmd.first()?;
    Some(
        self.rules_by_program
            .get_vec(first)
            .map(|rules| rules.iter().filter_map(|rule| rule.matches(cmd)).collect())
            .unwrap_or_default(),
    )
}
```

**匹配逻辑** (rule.rs:46-59):
```rust
pub fn matches_prefix(&self, cmd: &[String]) -> Option<Vec<String>> {
    let pattern_length = self.rest.len() + 1;
    if cmd.len() < pattern_length || cmd[0] != self.first.as_ref() {
        return None;
    }
    for (pattern_token, cmd_token) in self.rest.iter().zip(&cmd[1..pattern_length]) {
        if !pattern_token.matches(cmd_token) {
            return None;
        }
    }
    Some(cmd[..pattern_length].to_vec())
}
```

### 5. 示例验证机制

解析时延迟验证 (parser.rs:75-78):
```rust
self.builder
    .borrow()
    .validate_pending_examples_from(pending_validation_count)?;
```

验证逻辑 (rule.rs:246-279, 282-306):
- `validate_match_examples`: 确保所有 `match` 示例至少匹配一个规则
- `validate_not_match_examples`: 确保所有 `not_match` 示例不匹配任何规则

---

## 关键代码路径与文件引用

### 核心文件关系图

```
examples/example.codexpolicy
    │
    ▼
codex-rs/execpolicy/src/
    ├── parser.rs          # Starlark 解析器
    │   ├── PolicyParser::parse()
    │   ├── prefix_rule() Starlark builtin
    │   └── parse_examples()
    │
    ├── policy.rs          # 策略执行引擎
    │   ├── Policy::matches_for_command()
    │   ├── Policy::check()
    │   └── Evaluation::from_matches()
    │
    ├── rule.rs            # 规则定义与匹配
    │   ├── PrefixRule
    │   ├── PrefixPattern::matches_prefix()
    │   └── validate_match_examples()
    │
    ├── decision.rs        # 决策枚举
    │   └── Decision::parse()
    │
    └── execpolicycheck.rs # CLI 检查命令
        └── ExecPolicyCheckCommand::run()
```

### 调用链

#### 从 CLI 到示例文件:
```
codex execpolicy check --rules examples/example.codexpolicy git status
    ↓
ExecPolicyCheckCommand::run() [execpolicycheck.rs:43]
    ↓
load_policies() [execpolicycheck.rs:73]
    ↓
PolicyParser::parse() [parser.rs:58]
    ↓
解析 example.codexpolicy 中的 prefix_rule 调用
```

#### 从 core crate 调用:
```
codex-rs/core/src/exec_policy.rs
    ├── ExecPolicyManager::load() [line 214]
    ├── load_exec_policy() [line 487]
    └── PolicyParser::parse()
```

---

## 依赖与外部交互

### 1. 内部依赖

| 依赖 | 用途 |
|------|------|
| `starlark` crate | Starlark 语言解析与执行 |
| `shlex` | Shell 风格字符串分词 |
| `multimap` | 一个程序名映射多个规则 |
| `serde` | JSON 序列化 |
| `codex_utils_absolute_path` | 绝对路径处理 |

### 2. 外部调用方

| 调用方 | 文件路径 | 用途 |
|--------|----------|------|
| CLI | `codex-rs/cli/src/main.rs` | `execpolicy check` 子命令 |
| Core | `codex-rs/core/src/exec_policy.rs` | 执行策略管理器 |
| Tests | `codex-rs/execpolicy/tests/basic.rs` | 单元测试 |

### 3. 被调用方

| 被调用模块 | 功能 |
|------------|------|
| `parser.rs` | 解析 `.codexpolicy` / `.rules` 文件 |
| `policy.rs` | 执行策略评估 |
| `rule.rs` | 规则匹配逻辑 |

---

## 风险、边界与改进建议

### 1. 当前风险

#### 示例文件局限性
- **非生产就绪**: 文件头部明确标注 "not recommended for actual use"
- **覆盖不全**: 仅展示基础 `prefix_rule`，未展示 `network_rule` 和 `host_executable`
- **无网络规则示例**: 缺少 `network_rule()` 的示例用法

#### 验证时错误定位
- 示例验证失败时，错误信息可能指向内部实现而非用户友好的位置 (parser.rs:277-281)

### 2. 边界情况

#### 空模式处理
```rust
// parser.rs:177-181
if tokens.is_empty() {
    Err(Error::InvalidPattern("pattern cannot be empty".to_string()))
}
```

#### 单元素替代自动降级
```rust
// parser.rs:205-210
match tokens.as_slice() {
    [] => Err(...),
    [single] => Ok(PatternToken::Single(single.clone())),
    _ => Ok(PatternToken::Alts(tokens)),
}
```

#### 决策优先级
当多个规则匹配时，取最严格的决策 (policy.rs:365-368):
```rust
let decision = matched_rules.iter().map(RuleMatch::decision).max();
let decision = decision.expect("invariant failed: matched_rules must be non-empty");
```

### 3. 改进建议

#### 示例文件增强
1. **添加网络规则示例**:
```starlark
network_rule(
    host = "api.github.com",
    protocol = "https",
    decision = "allow",
    justification = "Access GitHub API",
)
```

2. **添加 host_executable 示例**:
```starlark
host_executable(
    name = "git",
    paths = ["/usr/bin/git", "/opt/homebrew/bin/git"],
)
```

3. **添加复杂模式示例**:
```starlark
prefix_rule(
    pattern = [["python3", "python"], ["-m", "-c"]],
    decision = "prompt",
)
```

#### 文档改进
- 在示例文件中添加更多注释解释每个规则的设计意图
- 提供从旧版 execpolicy 迁移的指南

#### 测试覆盖
- 当前测试主要位于 `tests/basic.rs`，建议增加边界情况测试
- 添加针对示例文件本身的集成测试

### 4. 与 Legacy 版本对比

| 特性 | 新版 (execpolicy) | 旧版 (execpolicy-legacy) |
|------|-------------------|--------------------------|
| 语法 | Starlark | 自定义 DSL |
| 可扩展性 | 高（支持 host_executable, network_rule） | 低 |
| 示例验证 | 是（match/not_match） | 否 |
| 决策类型 | allow/prompt/forbidden | 类似但语义可能不同 |

---

## 总结

`codex-rs/execpolicy/examples` 目录是执行策略引擎的示例展示窗口。单个示例文件 `example.codexpolicy` 虽然标注为非生产就绪，但完整展示了 `prefix_rule` 的核心语法特性，包括模式匹配、决策类型、理由说明和示例验证。

该示例文件与解析器 (`parser.rs`)、策略引擎 (`policy.rs`) 和规则模块 (`rule.rs`) 紧密配合，构成了 Codex 命令执行安全策略的基础架构。理解此示例有助于开发者编写自定义策略文件，控制 AI 代理可执行的命令范围。

---

*研究日期: 2026-03-21*
*研究范围: codex-rs/execpolicy/examples 目录及其上下文依赖*
