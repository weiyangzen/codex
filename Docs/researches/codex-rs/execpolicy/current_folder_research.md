# codex-rs/execpolicy 深度研究文档

## 1. 场景与职责

### 1.1 模块定位
`codex-execpolicy` 是 Codex CLI 的命令执行策略引擎，负责：
- **命令执行授权决策**：判断一个 shell 命令是否应该被执行（Allow/Prompt/Forbidden）
- **安全沙箱策略支撑**：为命令执行提供细粒度的权限控制基础
- **用户策略配置解析**：解析用户定义的 `.rules` 策略文件（Starlark 语法）
- **运行时策略评估**：在命令执行前快速评估匹配规则

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| **安全策略执行** | 阻止危险命令（如 `rm -rf /`）或提示用户确认 |
| **自动化审批** | 允许安全命令（如 `ls`, `pwd`）无需用户确认直接执行 |
| **网络访问控制** | 控制对外部域名的 HTTP/HTTPS/SOCKS5 访问权限 |
| **项目级策略** | 通过 `requirements.toml` 定义项目特定的执行限制 |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                     Codex CLI / TUI                          │
├─────────────────────────────────────────────────────────────┤
│  codex-rs/core/src/exec_policy.rs (ExecPolicyManager)       │
│  ├─ 加载策略文件 → codex-execpolicy PolicyParser            │
│  ├─ 评估命令 → Policy.check()                               │
│  └─ 动态修改策略 → amend.rs                                 │
├─────────────────────────────────────────────────────────────┤
│  codex-rs/execpolicy (本模块)                                │
│  ├─ parser.rs: Starlark 语法解析                             │
│  ├─ policy.rs: 策略存储与匹配                                │
│  ├─ rule.rs: 规则定义（PrefixRule, NetworkRule）            │
│  ├─ decision.rs: 决策枚举（Allow/Prompt/Forbidden）         │
│  ├─ amend.rs: 策略文件追加修改                               │
│  └─ execpolicycheck.rs: CLI 检查工具                         │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 核心功能

| 功能 | 目的 | 关键文件 |
|------|------|----------|
| **前缀规则匹配** | 基于命令前缀模式匹配决策 | `rule.rs`, `policy.rs` |
| **网络规则** | 控制对外部服务的网络访问 | `rule.rs`, `parser.rs` |
| **主机可执行文件解析** | 支持绝对路径到 basename 的回退匹配 | `policy.rs`, `executable_name.rs` |
| **策略文件解析** | 解析 Starlark 格式的 `.rules` 文件 | `parser.rs` |
| **策略动态修改** | 运行时追加规则到策略文件 | `amend.rs` |
| **示例验证** | 策略加载时验证 `match`/`not_match` 示例 | `rule.rs`, `parser.rs` |

### 2.2 决策类型

```rust
// decision.rs
pub enum Decision {
    Allow,      // 直接执行，无需确认
    Prompt,     // 需要用户确认
    Forbidden,  // 禁止执行
}
```

决策优先级（严格程度）：`Forbidden > Prompt > Allow`

### 2.3 规则类型

| 规则类型 | 说明 | 语法示例 |
|----------|------|----------|
| **PrefixRule** | 前缀匹配规则 | `prefix_rule(pattern=["git", "status"], decision="allow")` |
| **NetworkRule** | 网络访问规则 | `network_rule(host="api.github.com", protocol="https", decision="allow")` |
| **HostExecutable** | 限定可执行文件路径 | `host_executable(name="git", paths=["/usr/bin/git"])` |

---

## 3. 具体技术实现

### 3.1 数据结构

#### 3.1.1 Policy（策略）

```rust
// policy.rs
pub struct Policy {
    // 按程序名索引的规则表（MultiMap 支持一个程序名对应多条规则）
    rules_by_program: MultiMap<String, RuleRef>,
    // 网络访问规则列表
    network_rules: Vec<NetworkRule>,
    // 主机可执行文件路径映射（basename → 允许的绝对路径列表）
    host_executables_by_name: HashMap<String, Arc<[AbsolutePathBuf]>>,
}
```

#### 3.1.2 PrefixRule（前缀规则）

```rust
// rule.rs
pub struct PrefixRule {
    pub pattern: PrefixPattern,     // 匹配模式
    pub decision: Decision,         // 决策
    pub justification: Option<String>, // 理由说明
}

pub struct PrefixPattern {
    pub first: Arc<str>,            // 第一个 token（用于索引）
    pub rest: Arc<[PatternToken]>,  // 后续 token 模式
}

pub enum PatternToken {
    Single(String),                 // 固定字符串
    Alts(Vec<String>),              // 多选一（如 ["-c", "-l"]）
}
```

#### 3.1.3 RuleMatch（匹配结果）

```rust
// rule.rs
pub enum RuleMatch {
    PrefixRuleMatch {
        matched_prefix: Vec<String>,
        decision: Decision,
        resolved_program: Option<AbsolutePathBuf>,
        justification: Option<String>,
    },
    HeuristicsRuleMatch {           // 启发式回退匹配
        command: Vec<String>,
        decision: Decision,
    },
}
```

### 3.2 关键流程

#### 3.2.1 策略解析流程

```
PolicyParser::parse(policy_identifier, policy_file_contents)
    │
    ├─ 1. AstModule::parse()  // Starlark AST 解析
    ├─ 2. 注册内置函数 (policy_builtins)
    │   ├─ prefix_rule()
    │   ├─ network_rule()
    │   └─ host_executable()
    ├─ 3. Evaluator::eval_module()  // 执行 Starlark 代码
    └─ 4. validate_pending_examples()  // 验证 match/not_match 示例
```

**代码路径**: `parser.rs:58-79`

#### 3.2.2 命令评估流程

```
Policy::check(cmd, heuristics_fallback)
    │
    ├─ matches_for_command_with_options()
    │   ├─ 1. match_exact_rules(cmd)  // 精确匹配（第一 token 完全匹配）
    │   ├─ 2. match_host_executable_rules(cmd)  // 主机可执行文件回退匹配
    │   └─ 3. HeuristicsRuleMatch（无匹配时使用启发式回退）
    │
    └─ Evaluation::from_matches(matched_rules)
        └─ 取所有匹配规则中决策最严格的（max by Decision 的 Ord）
```

**代码路径**: `policy.rs:188-295`

#### 3.2.3 主机可执行文件解析流程

```
match_host_executable_rules(["/usr/bin/git", "status"])
    │
    ├─ 1. 解析第一 token 为 AbsolutePathBuf
    ├─ 2. executable_path_lookup_key() → "git"（basename）
    ├─ 3. 检查 host_executables_by_name["git"] 是否存在
    │   ├─ 存在 → 验证 /usr/bin/git 是否在允许列表中
    │   └─ 不存在 → 允许所有路径
    ├─ 4. 用 basename "git" 查找规则
    └─ 5. 匹配成功后标记 resolved_program
```

**代码路径**: `policy.rs:307-334`

### 3.3 协议/格式

#### 3.3.1 Starlark 策略文件格式

```starlark
# prefix_rule: 前缀匹配规则
prefix_rule(
    pattern = ["git", ["status", "diff"]],  # 第一个 token 固定，第二个可多选
    decision = "allow",                       # allow | prompt | forbidden
    justification = "safe read-only command", # 理由（可选）
    match = [["git", "status"], "git diff"],  # 必须匹配此规则的示例
    not_match = ["git push"],                 # 必须不匹配此规则的示例
)

# network_rule: 网络访问规则
network_rule(
    host = "api.github.com",
    protocol = "https",  # http | https | socks5_tcp | socks5_udp
    decision = "allow",
    justification = "GitHub API access",
)

# host_executable: 限定可执行文件路径
host_executable(
    name = "git",
    paths = [
        "/opt/homebrew/bin/git",
        "/usr/bin/git",
    ],
)
```

#### 3.3.2 CLI 输出格式（JSON）

```json
{
  "matchedRules": [
    {
      "prefixRuleMatch": {
        "matchedPrefix": ["git", "status"],
        "decision": "allow",
        "resolvedProgram": "/usr/bin/git",
        "justification": "safe read-only command"
      }
    }
  ],
  "decision": "allow"
}
```

### 3.4 命令行工具

```bash
# 检查命令是否符合策略
codex execpolicy check \
  --rules path/to/policy.rules \
  --resolve-host-executables \
  --pretty \
  git status
```

**实现文件**: `execpolicycheck.rs`, `main.rs`

---

## 4. 关键代码路径与文件引用

### 4.1 核心模块

| 文件 | 职责 | 关键类型/函数 |
|------|------|---------------|
| `src/lib.rs` | 模块导出 | 公共 API 入口 |
| `src/policy.rs` | 策略存储与评估 | `Policy`, `Evaluation`, `MatchOptions` |
| `src/rule.rs` | 规则定义与匹配 | `PrefixRule`, `NetworkRule`, `RuleMatch`, `PatternToken` |
| `src/parser.rs` | Starlark 解析 | `PolicyParser`, `policy_builtins` |
| `src/decision.rs` | 决策枚举 | `Decision` |
| `src/amend.rs` | 策略文件修改 | `blocking_append_allow_prefix_rule`, `blocking_append_network_rule` |
| `src/execpolicycheck.rs` | CLI 检查命令 | `ExecPolicyCheckCommand` |
| `src/executable_name.rs` | 可执行文件名处理 | `executable_lookup_key` |
| `src/error.rs` | 错误定义 | `Error`, `ErrorLocation` |

### 4.2 测试文件

| 文件 | 测试内容 |
|------|----------|
| `tests/basic.rs` | 集成测试：规则匹配、网络规则、主机可执行文件解析、示例验证 |
| `src/amend.rs` (mod tests) | 单元测试：策略文件追加、去重、格式处理 |

### 4.3 示例文件

| 文件 | 说明 |
|------|------|
| `examples/example.codexpolicy` | 示例策略文件，展示各种规则语法 |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| Crate | 用途 |
|-------|------|
| `starlark` | Starlark 语言解析与执行（Google 的 Python 子集） |
| `multimap` | 一个键对应多个值的 HashMap |
| `serde`/`serde_json` | 序列化/反序列化 |
| `shlex` | Shell 风格的字符串分割 |
| `codex-utils-absolute-path` | 绝对路径类型 |
| `anyhow` | 错误处理 |
| `clap` | CLI 参数解析 |
| `thiserror` | 自定义错误类型 |

### 5.2 调用方（上游）

| 模块 | 用途 |
|------|------|
| `codex-rs/core/src/exec_policy.rs` | `ExecPolicyManager` 使用 `PolicyParser` 加载策略，使用 `Policy.check()` 评估命令 |
| `codex-rs/core/src/tools/sandboxing.rs` | 使用 `ExecApprovalRequirement` 决定是否需要审批 |
| `codex-rs/config/src/requirements_exec_policy.rs` | 将 TOML 配置转换为 `Policy` |
| `codex-rs/cli/tests/execpolicy.rs` | 集成测试 CLI 的 execpolicy 子命令 |

### 5.3 被调用方（下游）

| 模块 | 说明 |
|------|------|
| `codex-utils-absolute-path` | 路径类型定义 |

### 5.4 交互时序

```
Codex CLI 启动
    │
    ▼
ExecPolicyManager::load(config_stack)
    │
    ├─ 遍历配置层，收集 *.rules 文件
    ├─ PolicyParser::parse() 解析每个文件
    │   └─ starlark::AstModule::parse() → eval_module()
    └─ 合并 requirements.toml 中的策略
    │
    ▼
执行命令前
    │
    ▼
ExecPolicyManager::create_exec_approval_requirement_for_command()
    │
    ├─ Policy::check_multiple_with_options(commands)
    │   ├─ 精确匹配 rules_by_program
    │   ├─ 主机可执行文件回退匹配
    │   └─ 启发式回退（无匹配时）
    │
    └─ 根据决策返回:
        ├─ ExecApprovalRequirement::Skip (Allow)
        ├─ ExecApprovalRequirement::NeedsApproval (Prompt)
        └─ ExecApprovalRequirement::Forbidden (Forbidden)
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| **Starlark 注入** | 策略文件执行 Starlark 代码，恶意文件可能利用内置函数 | 仅解析白名单内置函数，无文件系统/网络访问 |
| **规则优先级混淆** | 多条规则匹配时取最严格决策，可能与用户预期不符 | 清晰的 `justification` 说明，JSON 输出所有匹配规则 |
| **主机可执行文件绕过** | 未配置 `host_executable` 时，任意路径的同名程序都能匹配 | 敏感环境应始终配置 `host_executable` |
| **并发修改冲突** | `amend.rs` 使用文件锁，但跨进程/机器无协调 | 文档建议单用户环境使用，并发场景谨慎 |

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 空策略 | 所有命令无匹配，依赖启发式回退 |
| 规则冲突 | 取决策最严格的（Forbidden > Prompt > Allow） |
| 示例验证失败 | 策略加载时 panic，阻止启动 |
| 绝对路径命令 | 先尝试精确匹配，再尝试 basename 回退（需开启 `resolve_host_executables`） |
| Windows 可执行文件 | 自动去除 `.exe`/`.cmd`/`.bat`/`.com` 后缀进行匹配 |
| 网络规则通配符 | **明确禁止**，必须使用具体域名 |

### 6.3 改进建议

| 优先级 | 建议 | 理由 |
|--------|------|------|
| **高** | 添加规则性能监控 | 策略复杂时匹配可能成为瓶颈 |
| **中** | 支持规则热重载 | 无需重启 CLI 即可更新策略 |
| **中** | 更丰富的规则类型 | 如正则匹配、参数值范围检查 |
| **低** | Web UI 策略编辑器 | 降低用户编写 Starlark 的门槛 |
| **低** | 策略版本控制与迁移 | 策略格式升级时的兼容性处理 |

### 6.4 代码质量观察

| 方面 | 评价 |
|------|------|
| **测试覆盖** | 良好，`tests/basic.rs` 覆盖主要场景，包含边界测试 |
| **错误处理** | 完善，使用 `thiserror` 定义具体错误类型，带位置信息 |
| **文档** | README 详细，代码注释充分 |
| **并发安全** | `amend.rs` 使用文件锁，但 `Policy` 本身不可变，需外部同步（`ArcSwap`） |
| **性能** | 规则查找 O(1)（HashMap），匹配 O(pattern_len)，适合高频调用 |

---

## 7. 附录

### 7.1 文件清单

```
codex-rs/execpolicy/
├── BUILD.bazel              # Bazel 构建配置
├── Cargo.toml               # Rust 包配置
├── README.md                # 使用文档
├── examples/
│   └── example.codexpolicy  # 示例策略文件
├── src/
│   ├── lib.rs               # 模块入口
│   ├── main.rs              # CLI 入口
│   ├── amend.rs             # 策略文件追加修改
│   ├── decision.rs          # 决策枚举
│   ├── error.rs             # 错误类型
│   ├── execpolicycheck.rs   # CLI 检查命令
│   ├── executable_name.rs   # 可执行文件名处理
│   ├── parser.rs            # Starlark 解析器
│   ├── policy.rs            # 策略存储与评估
│   └── rule.rs              # 规则定义
└── tests/
    └── basic.rs             # 集成测试
```

### 7.2 相关文档

- `codex-rs/execpolicy/README.md` - 官方使用文档
- `codex-rs/core/src/exec_policy.rs` - 核心集成代码
- `codex-rs/config/src/requirements_exec_policy.rs` - TOML 配置集成
