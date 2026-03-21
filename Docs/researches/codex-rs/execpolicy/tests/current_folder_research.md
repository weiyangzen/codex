# 研究报告：codex-rs/execpolicy/tests

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 目录定位
`codex-rs/execpolicy/tests/` 是 `codex-execpolicy` crate 的集成测试目录，包含对执行策略引擎的完整功能测试。

### 核心职责
1. **策略解析测试**：验证 Starlark 语法的策略文件解析
2. **规则匹配测试**：验证前缀规则、网络规则的匹配逻辑
3. **决策评估测试**：验证 Allow/Prompt/Forbidden 决策的正确性
4. **Host Executable 解析测试**：验证绝对路径到基础名称的映射
5. **规则修改测试**：验证运行时添加规则的功能

### 在架构中的位置
```
┌─────────────────────────────────────────────────────────────┐
│                      Codex CLI / Core                        │
│                   (exec_policy.rs 调用方)                     │
├─────────────────────────────────────────────────────────────┤
│                  codex-execpolicy (本 crate)                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Parser    │  │   Policy    │  │   Rule Matching     │  │
│  │  (parser.rs)│  │ (policy.rs) │  │    (rule.rs)        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│              tests/basic.rs (本目录测试文件)                  │
│     - 集成测试所有公共 API                                   │
│     - 验证端到端策略评估流程                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. 策略规则解析与构建
- **目的**：验证 Starlark 格式的策略文件能被正确解析为内部数据结构
- **测试覆盖**：
  - `prefix_rule` 函数解析
  - `network_rule` 函数解析
  - `host_executable` 函数解析
  - 多文件策略合并

### 2. 命令前缀匹配
- **目的**：验证命令与规则模式的匹配逻辑
- **测试覆盖**：
  - 基础前缀匹配 (`["git", "status"]`)
  - 多选项模式 (`["npm", ["i", "install"]]`)
  - 第一 token 别名展开 (`[["bash", "sh"], ["-c", "-l"]]`)

### 3. 决策优先级
- **目的**：验证多个匹配规则时的决策合并逻辑
- **关键规则**：`Forbidden > Prompt > Allow`
- **测试覆盖**：
  - 单命令多规则匹配
  - 多命令批量评估 (`check_multiple`)

### 4. Host Executable 解析
- **目的**：验证绝对路径程序名到基础名称的映射
- **测试覆盖**：
  - 启用/禁用解析选项
  - 允许列表过滤
  - 精确匹配优先

### 5. 规则修改 (Amend)
- **目的**：验证运行时添加规则的功能
- **测试覆盖**：
  - 添加前缀规则
  - 去重逻辑
  - 网络规则添加

### 6. 示例验证 (match/not_match)
- **目的**：验证策略文件中声明的示例在加载时被验证
- **测试覆盖**：
  - 正向示例必须匹配
  - 反向示例必须不匹配

---

## 具体技术实现

### 关键数据结构

#### 1. 决策枚举 (`Decision`)
```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum Decision {
    Allow,      // 允许执行
    Prompt,     // 需要用户确认
    Forbidden,  // 禁止执行
}
```
- **排序意义**：`Forbidden > Prompt > Allow`，用于多规则决策合并

#### 2. 规则匹配结果 (`RuleMatch`)
```rust
pub enum RuleMatch {
    PrefixRuleMatch {
        matched_prefix: Vec<String>,
        decision: Decision,
        resolved_program: Option<AbsolutePathBuf>,
        justification: Option<String>,
    },
    HeuristicsRuleMatch {
        command: Vec<String>,
        decision: Decision,
    },
}
```

#### 3. 前缀规则 (`PrefixRule`)
```rust
pub struct PrefixRule {
    pub pattern: PrefixPattern,
    pub decision: Decision,
    pub justification: Option<String>,
}

pub struct PrefixPattern {
    pub first: Arc<str>,              // 第一 token，用于索引
    pub rest: Arc<[PatternToken]>,    // 后续 tokens
}

pub enum PatternToken {
    Single(String),
    Alts(Vec<String>),  // 多选项，如 ["-c", "-l"]
}
```

#### 4. 网络规则 (`NetworkRule`)
```rust
pub struct NetworkRule {
    pub host: String,
    pub protocol: NetworkRuleProtocol,
    pub decision: Decision,
    pub justification: Option<String>,
}

pub enum NetworkRuleProtocol {
    Http,
    Https,
    Socks5Tcp,
    Socks5Udp,
}
```

### 关键流程

#### 策略评估流程
```
┌─────────────────┐
│   Policy.check  │
│  (command: &[String])
└────────┬────────┘
         ▼
┌─────────────────────────────┐
│  matches_for_command_with_options
└────────┬────────────────────┘
         ▼
┌─────────────────────────────┐     ┌─────────────────────────┐
│    match_exact_rules        │────▶│  返回匹配的规则列表      │
│  (精确匹配第一 token)         │     │  (通过 rules_by_program   │
└────────┬────────────────────┘     │   MultiMap 索引)         │
         │ 无匹配                    └─────────────────────────┘
         ▼
┌─────────────────────────────┐     ┌─────────────────────────┐
│ match_host_executable_rules │────▶│ 解析绝对路径为基础名称    │
│ (如果 resolve_host_executables│    │ 匹配 basename 规则       │
│  选项启用)                   │    │ 添加 resolved_program    │
└────────┬────────────────────┘     └─────────────────────────┘
         │ 无匹配
         ▼
┌─────────────────────────────┐
│   HeuristicsRuleMatch       │
│  (使用 fallback 函数决策)    │
└─────────────────────────────┘
```

#### 策略解析流程 (Starlark)
```
┌─────────────────┐
│ PolicyParser::  │
│    parse()      │
└────────┬────────┘
         ▼
┌─────────────────────────────┐
│  AstModule::parse()         │  Starlark AST 解析
└────────┬────────────────────┘
         ▼
┌─────────────────────────────┐
│  Evaluator::eval_module()   │
│  注册 policy_builtins       │
│  - prefix_rule              │
│  - network_rule             │
│  - host_executable          │
└────────┬────────────────────┘
         ▼
┌─────────────────────────────┐
│ validate_pending_examples   │
│ 验证 match/not_match 示例   │
└────────┬────────────────────┘
         ▼
┌─────────────────────────────┐
│      PolicyBuilder::build   │
└─────────────────────────────┘
```

### 匹配算法

#### 前缀匹配 (`PrefixPattern::matches_prefix`)
```rust
pub fn matches_prefix(&self, cmd: &[String]) -> Option<Vec<String>> {
    let pattern_length = self.rest.len() + 1;
    // 1. 检查命令长度和第一 token
    if cmd.len() < pattern_length || cmd[0] != self.first.as_ref() {
        return None;
    }
    // 2. 逐个检查后续 token
    for (pattern_token, cmd_token) in self.rest.iter().zip(&cmd[1..pattern_length]) {
        if !pattern_token.matches(cmd_token) {
            return None;
        }
    }
    // 3. 返回匹配的前缀
    Some(cmd[..pattern_length].to_vec())
}
```

#### 决策合并 (`Evaluation::from_matches`)
```rust
fn from_matches(matched_rules: Vec<RuleMatch>) -> Self {
    // 使用 max() 获取最严格的决策
    let decision = matched_rules.iter()
        .map(RuleMatch::decision)
        .max()
        .expect("matched_rules must be non-empty");
    Self { decision, matched_rules }
}
```

---

## 关键代码路径与文件引用

### 测试文件
| 文件 | 行数 | 描述 |
|------|------|------|
| `tests/basic.rs` | ~963 | 主要集成测试文件，包含 30+ 个测试用例 |

### 被测试的源文件
| 文件 | 描述 |
|------|------|
| `src/lib.rs` | 模块导出和公共 API 定义 |
| `src/policy.rs` | `Policy` 结构体和评估逻辑 |
| `src/parser.rs` | Starlark 策略解析器 |
| `src/rule.rs` | 规则定义和匹配逻辑 |
| `src/decision.rs` | `Decision` 枚举 |
| `src/error.rs` | 错误类型定义 |
| `src/amend.rs` | 运行时规则修改 |
| `src/executable_name.rs` | 可执行文件名处理 |
| `src/execpolicycheck.rs` | CLI 命令实现 |

### 核心测试用例分类

#### 1. 规则修改测试
- `append_allow_prefix_rule_dedupes_existing_rule`：验证规则去重

#### 2. 网络规则测试
- `network_rules_compile_into_domain_lists`：网络规则编译为域名列表
- `network_rule_rejects_wildcard_hosts`：拒绝通配符主机名

#### 3. 基础匹配测试
- `basic_match`：基础前缀匹配
- `justification_is_attached_to_forbidden_matches`：禁止规则的理由附加
- `justification_can_be_used_with_allow_decision`：允许规则的理由
- `justification_cannot_be_empty`：空理由验证

#### 4. 规则添加测试
- `add_prefix_rule_extends_policy`：动态添加前缀规则
- `add_prefix_rule_rejects_empty_prefix`：拒绝空前缀

#### 5. 多文件策略测试
- `parses_multiple_policy_files`：多文件策略合并

#### 6. 别名展开测试
- `only_first_token_alias_expands_to_multiple_rules`：第一 token 别名展开
- `tail_aliases_are_not_cartesian_expanded`：尾部别名不笛卡尔展开

#### 7. 示例验证测试
- `match_and_not_match_examples_are_enforced`：match/not_match 示例强制验证

#### 8. 决策优先级测试
- `strictest_decision_wins_across_matches`：最严格决策优先
- `strictest_decision_across_multiple_commands`：多命令批量评估

#### 9. 启发式回退测试
- `heuristics_match_is_returned_when_no_policy_matches`：无匹配时使用启发式

#### 10. Host Executable 测试
- `parses_host_executable_paths`：解析主机可执行路径
- `host_executable_rejects_non_absolute_path`：拒绝非绝对路径
- `host_executable_rejects_name_with_path_separator`：拒绝含路径分隔符的名称
- `host_executable_rejects_path_with_wrong_basename`：拒绝错误基础名的路径
- `host_executable_last_definition_wins`：最后定义优先
- `host_executable_resolution_uses_basename_rule_when_allowed`：允许时使用基础名规则
- `prefix_rule_examples_honor_host_executable_resolution`：示例遵守解析
- `host_executable_resolution_respects_explicit_empty_allowlist`：空允许列表
- `host_executable_resolution_ignores_path_not_in_allowlist`：忽略不在允许列表的路径
- `host_executable_resolution_falls_back_without_mapping`：无映射时回退
- `host_executable_resolution_does_not_override_exact_match`：不覆盖精确匹配

---

## 依赖与外部交互

### 内部依赖
| Crate | 用途 |
|-------|------|
| `codex-utils-absolute-path` | `AbsolutePathBuf` 类型，处理绝对路径 |

### 外部依赖
| Crate | 用途 |
|-------|------|
| `starlark` | Starlark 语言解析和执行 |
| `multimap` | `MultiMap` 数据结构，支持一个 key 对应多个 value |
| `serde`/`serde_json` | 序列化/反序列化 |
| `shlex` | Shell 风格的字符串分割和拼接 |
| `anyhow` | 错误处理 |
| `thiserror` | 自定义错误类型 |
| `clap` | CLI 参数解析 |

### 测试依赖
| Crate | 用途 |
|-------|------|
| `tempfile` | 临时目录创建 |
| `pretty_assertions` | 美观的断言输出 |

### 调用方 (反向依赖)
| Crate | 文件 | 用途 |
|-------|------|------|
| `codex-core` | `src/exec_policy.rs` | 执行策略管理器 |
| `codex-cli` | `src/main.rs` | CLI 集成 |

---

## 风险、边界与改进建议

### 已知风险

#### 1. Starlark 解析依赖
- **风险**：`starlark` crate 是复杂的外部依赖，版本升级可能引入不兼容变更
- **缓解**：测试覆盖了主要语法，升级时需全量测试

#### 2. 路径处理平台差异
- **风险**：Windows 和 Unix 的路径处理逻辑不同，测试中有条件编译
- **代码位置**：`executable_name.rs` 中的 `executable_lookup_key`
- **缓解**：测试使用 `host_absolute_path` 和 `host_executable_name` 辅助函数处理平台差异

#### 3. 规则匹配性能
- **风险**：`rules_by_program` 使用 `MultiMap`，规则量大时可能影响性能
- **缓解**：当前设计针对的是中小型策略文件，未做性能基准测试

### 边界情况

#### 1. 空命令处理
```rust
// policy.rs:91-94
let (first_token, rest) = prefix
    .split_first()
    .ok_or_else(|| Error::InvalidPattern("prefix cannot be empty".to_string()))?;
```
- 空前缀会被拒绝

#### 2. 决策回退
```rust
// policy.rs:285-294
if matched_rules.is_empty() && let Some(heuristics_fallback) = heuristics_fallback {
    vec![RuleMatch::HeuristicsRuleMatch { ... }]
}
```
- 无规则匹配时必须提供 fallback，否则返回空

#### 3. Host Executable 解析边界
- 绝对路径必须有效
- 基础名必须与 `host_executable` 定义匹配
- 空允许列表表示禁止所有路径

### 改进建议

#### 1. 测试覆盖
- **现状**：测试覆盖了主要功能，但缺少性能测试和模糊测试
- **建议**：
  - 添加大型策略文件的加载性能测试
  - 添加模糊测试验证解析器健壮性

#### 2. 错误信息
- **现状**：Starlark 错误信息有时难以理解
- **建议**：改进错误信息的可读性，特别是行号和列号定位

#### 3. 文档
- **现状**：README 提供了基础用法，但缺少内部实现文档
- **建议**：
  - 添加架构设计文档
  - 添加规则匹配算法的详细说明

#### 4. 功能扩展
- **建议**：
  - 支持正则表达式模式匹配
  - 支持规则优先级/权重
  - 支持规则条件（如时间、环境变量）

### 代码质量观察

#### 优点
1. **类型安全**：大量使用 `AbsolutePathBuf` 避免路径问题
2. **错误处理**：使用 `thiserror` 定义清晰的错误类型
3. **测试全面**：覆盖了正常路径和多种边界情况
4. **平台兼容**：正确处理 Windows/Unix 差异

#### 可改进点
1. **测试组织**：`basic.rs` 接近 1000 行，可按功能拆分为多个文件
2. **辅助函数**：测试中的 `host_absolute_path` 等辅助函数可提取到测试库
3. **文档注释**：部分复杂测试用例缺少详细注释说明测试意图

---

## 总结

`codex-rs/execpolicy/tests/` 目录包含对执行策略引擎的全面集成测试。测试覆盖了策略解析、规则匹配、决策评估、Host Executable 解析和运行时规则修改等核心功能。测试设计良好，考虑了平台差异和边界情况，是保障策略引擎正确性的重要防线。

该测试套件与 `codex-core` 中的 `exec_policy.rs` 紧密配合，共同构成了 Codex CLI 的命令执行安全机制。
