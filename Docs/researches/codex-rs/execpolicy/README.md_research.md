# codex-rs/execpolicy/README.md 研究文档

## 场景与职责

`README.md` 是 `codex-execpolicy` crate 的用户文档，面向开发者和终端用户，说明该组件的功能、使用方法和策略语法。该 crate 是 Codex 项目的执行策略引擎，提供基于 Starlark 的策略规则定义和命令执行决策能力。

### 核心定位
- **策略引擎**: 基于前缀规则（prefix-rule）评估命令执行权限
- **CLI 工具**: 提供 `codex execpolicy check` 命令进行策略验证
- **安全网关**: 决定命令是允许执行（Allow）、需要确认（Prompt）还是禁止（Forbidden）

## 功能点目的

### 1. 策略规则系统

#### Prefix Rule（前缀规则）
```starlark
prefix_rule(
    pattern = ["cmd", ["alt1", "alt2"]],  # 有序令牌，列表表示替代选项
    decision = "prompt",                    # allow | prompt | forbidden
    justification = "explain why this rule exists",
    match = [["cmd", "alt1"], "cmd alt2"],           # 必须匹配的正例
    not_match = [["cmd", "oops"], "cmd alt3"],       # 必须不匹配的反例
)
```

**设计意图**:
- `pattern`: 定义命令前缀匹配模式，支持替代选项（alternatives）
- `decision`: 默认 `allow`，可显式指定为 `prompt` 或 `forbidden`
- `justification`: 人类可读的理由说明，用于提示或拒绝消息
- `match`/`not_match`: 加载时验证的示例（类似单元测试）

#### Host Executable（主机可执行文件）
```starlark
host_executable(
    name = "git",
    paths = [
        "/opt/homebrew/bin/git",
        "/usr/bin/git",
    ],
)
```

**设计意图**:
- 限制哪些绝对路径可以通过 basename 回退匹配
- 增强安全性：防止恶意二进制利用 basename 规则

### 2. 匹配语义

文档明确说明了匹配优先级：

1. **精确匹配优先**: `/usr/bin/git status` 优先匹配第一个令牌为 `/usr/bin/git` 的规则
2. **Basename 回退**: 无精确匹配时，可回退到 `git` 的规则（需启用 `--resolve-host-executables`）
3. **Host Executable 限制**: 如果定义了 `host_executable(name="git")`，只允许列出的路径回退

### 3. CLI 接口

```bash
# 基本用法
codex execpolicy check --rules path/to/policy.rules git status

# 启用主机可执行文件解析
--resolve-host-executables

# 美化 JSON 输出
--pretty

# 多策略文件合并（按顺序评估）
--rules file1.rules --rules file2.rules
```

### 4. 响应格式

```json
{
  "matchedRules": [
    {
      "prefixRuleMatch": {
        "matchedPrefix": ["<token>", "..."],
        "decision": "allow|prompt|forbidden",
        "resolvedProgram": "/absolute/path/to/program",
        "justification": "..."
      }
    }
  ],
  "decision": "allow|prompt|forbidden"
}
```

**关键设计**:
- `matchedRules` 包含所有匹配的规则（可能多条）
- `decision` 是所有匹配规则中最严格的（`forbidden > prompt > allow`）
- `resolvedProgram` 仅在 basename 回退匹配时填充

## 具体技术实现

### 策略解析流程

```
.rules 文件
    │
    ▼
Starlark 解析器 (starlark crate)
    │
    ▼
PolicyBuilder (parser.rs)
    ├── prefix_rule() ──► PrefixRule ──► rules_by_program
    ├── network_rule() ──► NetworkRule ──► network_rules
    └── host_executable() ──► host_executables_by_name
    │
    ▼
示例验证 (validate_match_examples / validate_not_match_examples)
    │
    ▼
Policy 对象
```

### 规则匹配算法

```rust
// policy.rs: matches_for_command_with_options
fn matches_for_command_with_options(cmd, heuristics_fallback, options) {
    // 1. 尝试精确匹配
    let matched_rules = match_exact_rules(cmd);
    
    // 2. 如未匹配且启用 resolve_host_executables，尝试 basename 回退
    if matched_rules.is_empty() && options.resolve_host_executables {
        matched_rules = match_host_executable_rules(cmd);
    }
    
    // 3. 如仍未匹配，使用启发式回退
    if matched_rules.is_empty() {
        matched_rules = vec![HeuristicsRuleMatch {
            decision: heuristics_fallback(cmd)
        }];
    }
    
    matched_rules
}
```

### 决策聚合逻辑

```rust
// Evaluation::from_matches
let decision = matched_rules
    .iter()
    .map(RuleMatch::decision)
    .max();  // Forbidden > Prompt > Allow
```

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 | 关键类型/函数 |
|------|------|--------------|
| `src/parser.rs` | Starlark 解析 | `PolicyParser`, `policy_builtins` |
| `src/policy.rs` | 策略存储和评估 | `Policy`, `Evaluation`, `MatchOptions` |
| `src/rule.rs` | 规则定义 | `PrefixRule`, `NetworkRule`, `RuleMatch`, `PatternToken` |
| `src/decision.rs` | 决策枚举 | `Decision` |
| `src/execpolicycheck.rs` | CLI 实现 | `ExecPolicyCheckCommand` |
| `src/amend.rs` | 策略修改 | `blocking_append_allow_prefix_rule` |

### 策略内置函数实现

```rust
// parser.rs: policy_builtins
#[starlark_module]
fn policy_builtins(builder: &mut GlobalsBuilder) {
    fn prefix_rule(...)     // 解析 prefix_rule() 调用
    fn network_rule(...)    // 解析 network_rule() 调用
    fn host_executable(...) // 解析 host_executable() 调用
}
```

### 模式匹配实现

```rust
// rule.rs: PrefixPattern::matches_prefix
fn matches_prefix(&self, cmd: &[String]) -> Option<Vec<String>> {
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

## 依赖与外部交互

### 上游依赖（本 crate 依赖）

| 依赖 | 用途 | 关键使用场景 |
|------|------|-------------|
| `starlark` | 策略文件解析 | `parser.rs` 中的 `AstModule::parse` 和 `Evaluator` |
| `multimap` | 规则存储 | `policy.rs` 中的 `rules_by_program` |
| `serde`/`serde_json` | JSON 序列化 | CLI 输出、规则序列化 |
| `shlex` | Shell 风格分词 | `match`/`not_match` 示例解析 |
| `codex-utils-absolute-path` | 路径安全 | `host_executable` 路径验证 |

### 下游依赖（依赖本 crate 的组件）

#### codex-rs/cli
- **使用方式**: `ExecPolicyCheckCommand` 嵌入到 CLI 子命令
- **代码位置**: `cli/src/main.rs:493-494`
```rust
fn run_execpolicycheck(cmd: ExecPolicyCheckCommand) -> anyhow::Result<()> {
    cmd.run()
}
```

#### codex-rs/core
- **使用方式**: `ExecPolicyManager` 封装策略管理
- **代码位置**: `core/src/exec_policy.rs`
- **关键功能**:
  - 加载和缓存策略文件
  - 评估命令执行权限
  - 动态添加规则（用户批准后）

### 协议集成

`codex_protocol::approvals::ExecPolicyAmendment` 用于在核心和 UI 之间传递策略修改请求：

```rust
// protocol/src/approvals.rs
pub struct ExecPolicyAmendment {
    pub command: Vec<String>,  // 建议添加的规则前缀
}
```

## 风险、边界与改进建议

### 风险点

1. **Starlark 注入风险**
   - 策略文件使用 Starlark 语法，虽然只暴露有限的内置函数，但仍需警惕解析器漏洞
   - 建议：策略文件应来自可信来源，考虑沙箱化解析过程

2. **规则优先级混淆**
   - 文档说明匹配顺序和决策聚合，但用户可能误解
   - 例如：`["git"]` (prompt) + `["git", "commit"]` (forbidden) → `git commit` 结果是 forbidden
   - 建议：CLI 添加 `--verbose` 模式显示匹配的规则链

3. **Host Executable 绕过**
   - 如果未定义 `host_executable`，任何路径的 `git` 都能匹配 `git` 规则
   - 恶意用户可能利用此点放置同名恶意二进制
   - 建议：生产环境强制启用 `host_executable` 验证

### 边界条件

1. **空策略**
   - 无规则时所有命令都走启发式回退
   - 响应中 `matchedRules` 为空，`decision` 省略

2. **规则冲突**
   - 同一前缀多条规则：全部匹配，取最严格决策
   - 不同前缀匹配同一命令：全部返回（如 `git` 和 `git status` 都匹配 `git status`）

3. **示例验证失败**
   - `match` 示例未匹配：解析时报错
   - `not_match` 示例匹配：解析时报错
   - 错误信息包含规则位置和示例详情

### 改进建议

1. **文档增强**
   - 添加策略编写最佳实践（如如何组织规则文件）
   - 提供常见场景的示例策略（如安全开发工作流）
   - 解释 `decision` 聚合的具体算法

2. **CLI 增强**
   - 添加 `execpolicy validate` 子命令仅验证策略文件语法
   - 添加 `execpolicy explain` 子命令解释为什么某命令得到特定决策
   - 支持策略文件热重载（开发模式）

3. **功能扩展**
   - 支持规则组/命名空间，便于管理复杂策略
   - 支持规则继承和覆盖（类似 CSS 的层叠）
   - 支持条件规则（如基于工作目录、环境变量）

4. **安全加固**
   - 策略文件数字签名验证
   - 规则变更审计日志
   - 敏感操作（如 `rm -rf /`）的额外确认

5. **性能优化**
   - 规则索引优化（当前是线性扫描）
   - 策略文件缓存和增量更新
   - 编译时策略验证（proc-macro）

### 已知限制

文档末尾明确标注：
> Note: `execpolicy` commands are still in preview. The API may have breaking changes in the future.

这意味着：
- 策略语法可能变化
- CLI 接口可能变化
- JSON 响应格式可能变化
- 不建议在生产环境硬依赖当前 API
