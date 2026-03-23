# 研究文档：codex-rs/execpolicy/tests/basic.rs

## 概述

本文档是对 `codex-rs/execpolicy/tests/basic.rs` 文件的深入研究分析。该文件是 Codex 执行策略（execpolicy）crate 的核心测试文件，测试了基于 Starlark 的命令执行策略引擎的各个功能点。

---

## 1. 场景与职责

### 1.1 所在模块定位

`codex-execpolicy` 是 Codex CLI 的命令执行策略引擎，负责：
- **命令执行权限控制**：决定命令是允许执行、需要用户确认，还是禁止执行
- **策略规则解析**：使用 Starlark 语言定义策略规则
- **网络访问控制**：管理网络访问的允许/拒绝策略
- **主机可执行文件映射**：管理可执行文件路径的别名解析

### 1.2 测试文件职责

`basic.rs` 作为主要的集成测试文件，承担以下职责：

| 职责 | 说明 |
|------|------|
| 功能回归测试 | 验证核心策略匹配逻辑的正确性 |
| 规则解析测试 | 验证 Starlark 策略文件的解析 |
| 决策计算测试 | 验证 Allow/Prompt/Forbidden 决策的计算 |
| 边界条件测试 | 验证空输入、无效输入等边界情况 |
| 跨平台测试 | 支持 Windows 和 Unix 系统的路径处理 |

### 1.3 调用关系

```
调用方（上游）：
├── codex-rs/core/src/exec_policy.rs      # 核心执行策略管理器
├── codex-rs/core/src/network_proxy_loader.rs  # 网络代理配置加载
├── codex-rs/cli/src/main.rs              # CLI 入口
└── codex-execpolicy CLI (src/main.rs)    # 独立命令行工具

被测试对象（本 crate）：
├── src/policy.rs    # Policy 结构体和评估逻辑
├── src/parser.rs    # Starlark 策略解析器
├── src/rule.rs      # 规则定义和匹配逻辑
├── src/decision.rs  # 决策枚举
├── src/amend.rs     # 策略修改功能
└── src/error.rs     # 错误类型定义
```

---

## 2. 功能点目的

### 2.1 核心功能点清单

| 测试功能 | 测试目的 | 对应测试函数 |
|---------|---------|-------------|
| 前缀规则追加 | 验证动态添加允许规则并去重 | `append_allow_prefix_rule_dedupes_existing_rule` |
| 网络规则编译 | 验证网络规则解析为域名列表 | `network_rules_compile_into_domain_lists` |
| 网络规则验证 | 验证通配符主机名被拒绝 | `network_rule_rejects_wildcard_hosts` |
| 基本匹配 | 验证简单前缀规则匹配 | `basic_match` |
| 禁止理由 | 验证规则可附带说明理由 | `justification_is_attached_to_forbidden_matches` |
| 允许理由 | 验证允许规则也可附带理由 | `justification_can_be_used_with_allow_decision` |
| 理由验证 | 验证空理由被拒绝 | `justification_cannot_be_empty` |
| 动态添加规则 | 验证运行时添加前缀规则 | `add_prefix_rule_extends_policy` |
| 空前缀拒绝 | 验证空前缀被拒绝 | `add_prefix_rule_rejects_empty_prefix` |
| 多文件解析 | 验证多个策略文件合并 | `parses_multiple_policy_files` |
| 首词别名 | 验证首词别名展开为多规则 | `only_first_token_alias_expands_to_multiple_rules` |
| 尾部别名 | 验证尾部别名不笛卡尔展开 | `tail_aliases_are_not_cartesian_expanded` |
| 示例验证 | 验证 match/not_match 示例 | `match_and_not_match_examples_are_enforced` |
| 严格决策 | 验证最严格决策优先 | `strictest_decision_wins_across_matches` |
| 多命令决策 | 验证多命令的聚合决策 | `strictest_decision_across_multiple_commands` |
| 启发式回退 | 验证无匹配时使用启发式 | `heuristics_match_is_returned_when_no_policy_matches` |
| 主机可执行路径 | 验证主机可执行文件路径解析 | `parses_host_executable_paths` |
| 路径验证 | 验证非绝对路径被拒绝 | `host_executable_rejects_non_absolute_path` |
| 名称验证 | 验证名称不能包含路径分隔符 | `host_executable_rejects_name_with_path_separator` |
| 基名验证 | 验证路径基名必须匹配 | `host_executable_rejects_path_with_wrong_basename` |
| 定义覆盖 | 验证后定义覆盖先定义 | `host_executable_last_definition_wins` |
| 路径解析 | 验证主机可执行文件解析 | `host_executable_resolution_uses_basename_rule_when_allowed` |
| 示例解析 | 验证示例中的路径解析 | `prefix_rule_examples_honor_host_executable_resolution` |
| 空允许列表 | 验证空允许列表行为 | `host_executable_resolution_respects_explicit_empty_allowlist` |
| 路径忽略 | 验证不在允许列表的路径被忽略 | `host_executable_resolution_ignores_path_not_in_allowlist` |
| 回退机制 | 验证无映射时的回退 | `host_executable_resolution_falls_back_without_mapping` |
| 精确匹配优先 | 验证精确匹配不被覆盖 | `host_executable_resolution_does_not_override_exact_match` |

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 决策枚举（Decision）

```rust
// src/decision.rs
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Decision {
    Allow,      // 允许执行
    Prompt,     // 需要用户确认
    Forbidden,  // 禁止执行
}
```

**排序语义**：`Forbidden > Prompt > Allow`，用于多规则匹配时选择最严格的决策。

#### 3.1.2 策略结构（Policy）

```rust
// src/policy.rs
#[derive(Clone, Debug)]
pub struct Policy {
    rules_by_program: MultiMap<String, RuleRef>,  // 按首词索引的规则
    network_rules: Vec<NetworkRule>,              // 网络规则列表
    host_executables_by_name: HashMap<String, Arc<[AbsolutePathBuf]>>,  // 主机可执行文件映射
}
```

#### 3.1.3 规则匹配结果（RuleMatch）

```rust
// src/rule.rs
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RuleMatch {
    PrefixRuleMatch {
        matched_prefix: Vec<String>,           // 匹配的前缀
        decision: Decision,                    // 决策
        resolved_program: Option<AbsolutePathBuf>,  // 解析后的程序路径
        justification: Option<String>,         // 理由说明
    },
    HeuristicsRuleMatch {
        command: Vec<String>,                  // 命令
        decision: Decision,                    // 决策
    },
}
```

#### 3.1.4 前缀规则（PrefixRule）

```rust
// src/rule.rs
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PrefixRule {
    pub pattern: PrefixPattern,      // 匹配模式
    pub decision: Decision,          // 决策
    pub justification: Option<String>,  // 理由
}

pub struct PrefixPattern {
    pub first: Arc<str>,             // 首词（固定）
    pub rest: Arc<[PatternToken]>,   // 剩余词（可含替代）
}

pub enum PatternToken {
    Single(String),                  // 单值
    Alts(Vec<String>),              // 多值替代
}
```

### 3.2 关键流程

#### 3.2.1 策略匹配流程

```
命令输入
    │
    ▼
┌─────────────────────────────────────┐
│ 1. 精确匹配（Exact Match）          │
│    - 使用首词查找 rules_by_program  │
│    - 检查所有规则是否匹配           │
└─────────────────────────────────────┘
    │
    ├─ 匹配成功 ──► 返回匹配规则列表
    │
    ▼ 匹配失败
┌─────────────────────────────────────┐
│ 2. 主机可执行文件解析（可选）       │
│    - 解析绝对路径                   │
│    - 查找基名规则                   │
│    - 检查 host_executable 允许列表  │
└─────────────────────────────────────┘
    │
    ├─ 匹配成功 ──► 返回带 resolved_program 的匹配
    │
    ▼ 匹配失败
┌─────────────────────────────────────┐
│ 3. 启发式回退                       │
│    - 调用 heuristics_fallback 函数  │
│    - 返回 HeuristicsRuleMatch       │
└─────────────────────────────────────┘
```

#### 3.2.2 Starlark 策略解析流程

```
策略文件内容
    │
    ▼
┌─────────────────────────────────────┐
│ AstModule::parse()                  │
│ - 使用 Extended Dialect             │
│ - 启用 F-strings                    │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ Evaluator::eval_module()            │
│ - 注册 policy_builtins              │
│ - 执行 Starlark 代码                │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 构建 Policy                         │
│ - 收集所有规则                      │
│ - 验证 match/not_match 示例         │
└─────────────────────────────────────┘
```

#### 3.2.3 决策计算流程

```rust
// src/policy.rs
fn from_matches(matched_rules: Vec<RuleMatch>) -> Evaluation {
    // 取所有匹配规则中最严格的决策
    let decision = matched_rules.iter().map(RuleMatch::decision).max();
    Self {
        decision: decision.expect("matched_rules must be non-empty"),
        matched_rules,
    }
}
```

### 3.3 协议与命令

#### 3.3.1 Starlark 内置函数

| 函数 | 参数 | 用途 |
|-----|------|------|
| `prefix_rule()` | pattern, decision, justification, match, not_match | 定义前缀规则 |
| `network_rule()` | host, protocol, decision, justification | 定义网络规则 |
| `host_executable()` | name, paths | 定义主机可执行文件映射 |

#### 3.3.2 策略文件示例

```starlark
# 前缀规则示例
prefix_rule(
    pattern = ["git", "status"],
    decision = "allow",
    justification = "Safe git command",
    match = [["git", "status"]],
    not_match = [["git", "status", "--force"]],
)

# 网络规则示例
network_rule(
    host = "api.github.com",
    protocol = "https",
    decision = "allow",
    justification = "GitHub API access",
)

# 主机可执行文件示例
host_executable(
    name = "git",
    paths = [
        "/usr/bin/git",
        "/opt/homebrew/bin/git",
    ],
)
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件结构

```
codex-rs/execpolicy/
├── src/
│   ├── lib.rs           # 模块导出
│   ├── main.rs          # CLI 入口
│   ├── policy.rs        # Policy 结构体和评估 (375 lines)
│   ├── parser.rs        # Starlark 解析器 (473 lines)
│   ├── rule.rs          # 规则定义 (306 lines)
│   ├── decision.rs      # 决策枚举 (27 lines)
│   ├── error.rs         # 错误类型 (101 lines)
│   ├── amend.rs         # 策略修改 (338 lines)
│   ├── execpolicycheck.rs  # CLI 检查命令 (95 lines)
│   └── executable_name.rs  # 可执行文件名处理 (29 lines)
├── tests/
│   └── basic.rs         # 本测试文件 (963 lines)
├── Cargo.toml
├── BUILD.bazel
└── README.md
```

### 4.2 关键代码路径

| 功能 | 文件 | 行号范围 |
|-----|------|---------|
| 策略匹配核心 | `src/policy.rs` | 188-295 |
| 主机可执行文件解析 | `src/policy.rs` | 307-334 |
| 决策计算 | `src/policy.rs` | 365-374 |
| Starlark 解析 | `src/parser.rs` | 58-84 |
| prefix_rule 内置函数 | `src/parser.rs` | 349-408 |
| network_rule 内置函数 | `src/parser.rs` | 410-435 |
| host_executable 内置函数 | `src/parser.rs` | 437-472 |
| 前缀模式匹配 | `src/rule.rs` | 46-59 |
| 规则匹配 | `src/rule.rs` | 229-243 |
| 网络规则主机规范化 | `src/rule.rs` | 156-212 |
| 策略追加 | `src/amend.rs` | 66-194 |

### 4.3 测试文件关键路径

| 测试功能 | 行号范围 |
|---------|---------|
| 辅助函数定义 | 25-83 |
| 规则追加测试 | 85-101 |
| 网络规则测试 | 103-140 |
| 基本匹配测试 | 142-228 |
| 动态规则添加 | 249-293 |
| 多文件解析 | 295-373 |
| 别名处理 | 375-508 |
| 示例验证 | 510-554 |
| 决策优先级 | 556-645 |
| 启发式回退 | 647-663 |
| 主机可执行文件 | 665-767 |
| 路径解析 | 769-962 |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| Crate | 用途 | 版本来源 |
|-------|------|---------|
| `starlark` | Starlark 语言解析和执行 | workspace |
| `multimap` | 多值哈希表（rules_by_program） | workspace |
| `serde` | 序列化/反序列化 | workspace |
| `serde_json` | JSON 处理 | workspace |
| `shlex` | Shell 词法分析 | workspace |
| `codex_utils_absolute_path` | 绝对路径类型 | workspace |
| `anyhow` | 错误处理 | workspace |
| `clap` | CLI 参数解析 | workspace |
| `thiserror` | 错误类型定义 | workspace |

### 5.2 测试依赖

| Crate | 用途 |
|-------|------|
| `pretty_assertions` | 美观的断言输出 |
| `tempfile` | 临时目录/文件创建 |

### 5.3 下游使用者

| Crate | 使用方式 |
|-------|---------|
| `codex-core` | `ExecPolicyManager` 管理策略加载和评估 |
| `codex-cli` | 通过 `execpolicy check` 子命令调用 |
| `codex-network-proxy` | 使用网络规则进行访问控制 |
| `codex-protocol` | 定义 `ExecPolicyAmendment` 等类型 |

### 5.4 跨平台处理

```rust
// tests/basic.rs:42-60
fn host_absolute_path(segments: &[&str]) -> String {
    let mut path = if cfg!(windows) {
        PathBuf::from(r"C:\")
    } else {
        PathBuf::from("/")
    };
    for segment in segments {
        path.push(segment);
    }
    path.to_string_lossy().into_owned()
}

fn host_executable_name(name: &str) -> String {
    if cfg!(windows) {
        format!("{name}.exe")
    } else {
        name.to_string()
    }
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 严重程度 |
|-----|------|---------|
| Starlark 注入 | 策略文件使用 Starlark 语言，理论上可能执行任意代码 | 中 |
| 路径遍历 | 主机可执行文件路径验证需确保绝对路径 | 低 |
| 竞争条件 | 策略文件追加使用文件锁，但并发修改仍可能有问题 | 低 |
| 性能问题 | 大量规则时线性扫描可能影响性能 | 低 |

### 6.2 边界条件

| 边界 | 处理方式 |
|-----|---------|
| 空命令 | 返回空匹配列表 |
| 空前缀 | `add_prefix_rule` 返回 `InvalidPattern` 错误 |
| 空理由 | 解析时拒绝空或全空白理由 |
| 通配符主机 | `network_rule` 拒绝含 `*` 的主机名 |
| 相对路径 | `host_executable` 拒绝非绝对路径 |
| Windows 路径 | 正确处理 `.exe` 后缀和大小写 |

### 6.3 改进建议

#### 6.3.1 性能优化

```rust
// 当前：线性扫描所有规则
// 建议：考虑使用 Trie 树优化前缀匹配

pub struct Policy {
    // 当前实现
    rules_by_program: MultiMap<String, RuleRef>,
    
    // 建议：添加 Trie 索引
    // rule_trie: Trie<String, Vec<RuleRef>>,
}
```

#### 6.3.2 错误处理增强

```rust
// 当前：部分错误缺少位置信息
// 建议：为所有解析错误添加 ErrorLocation

pub enum Error {
    // 现有错误...
    
    // 建议：统一添加位置信息
    #[error("invalid pattern element: {message}")]
    InvalidPattern {
        message: String,
        location: Option<ErrorLocation>,  // 统一添加
    },
}
```

#### 6.3.3 测试覆盖

| 缺失测试 | 建议 |
|---------|------|
| 并发策略修改 | 添加多线程追加规则测试 |
| 大规模规则集 | 添加性能基准测试 |
| 模糊测试 | 对解析器进行 fuzzing |
| 内存安全 | 使用 miri 测试 unsafe 代码 |

#### 6.3.4 代码组织

```
建议重构：
├── src/
│   ├── lib.rs
│   ├── main.rs
│   ├── policy/
│   │   ├── mod.rs       # Policy 结构体
│   │   ├── evaluation.rs # 评估逻辑
│   │   └── matching.rs   # 匹配逻辑
│   ├── rule/
│   │   ├── mod.rs
│   │   ├── prefix.rs    # PrefixRule
│   │   ├── network.rs   # NetworkRule
│   │   └── match.rs     # RuleMatch
│   ├── parser/
│   │   ├── mod.rs
│   │   ├── starlark.rs  # Starlark 解析
│   │   └── validation.rs # 示例验证
│   └── ...
```

### 6.4 安全注意事项

1. **策略文件权限**：确保 `.rules` 文件只能由授权用户写入
2. **路径验证**：`host_executable` 已验证绝对路径，但需持续审计
3. **网络规则**：禁止通配符主机名是正确的安全决策
4. **Starlark 沙箱**：当前使用标准 Starlark，考虑使用受限 Dialect

---

## 7. 总结

`codex-rs/execpolicy/tests/basic.rs` 是一个全面的测试文件，覆盖了执行策略引擎的核心功能。测试设计良好，涵盖了：

- **功能测试**：验证所有主要功能点
- **边界测试**：验证错误处理和边界条件
- **跨平台测试**：支持 Windows 和 Unix
- **集成测试**：验证端到端场景

该测试文件与实现代码保持同步，为策略引擎的正确性提供了有力保障。
