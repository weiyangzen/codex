# codex-rs/execpolicy/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust 项目 `codex-execpolicy` crate 的构建清单文件，定义了 crate 的元数据、依赖关系、构建配置和输出目标。该 crate 是 Codex 项目的执行策略引擎，负责：

1. 解析基于 Starlark 的执行策略规则文件（`.rules`）
2. 评估命令是否符合安全策略（Allow/Prompt/Forbidden）
3. 提供 CLI 工具进行策略检查和验证
4. 支持运行时动态修改策略（amend）

## 功能点目的

### 1. 双目标构建配置
- **库目标 (`lib`)**: `codex_execpolicy` - 供其他 crate 链接使用
- **二进制目标 (`bin`)**: `codex-execpolicy` - 独立 CLI 工具

### 2. 策略引擎核心功能
- 基于前缀的规则匹配（`prefix_rule`）
- 网络访问规则（`network_rule`）
- 主机可执行文件解析（`host_executable`）
- 决策评估（Allow/Prompt/Forbidden）

### 3. 策略文件修改支持
- 运行时添加允许规则（`blocking_append_allow_prefix_rule`）
- 运行时添加网络规则（`blocking_append_network_rule`）

## 具体技术实现

### 包元数据

```toml
[package]
name = "codex-execpolicy"
version.workspace = true      # 继承工作区版本
edition.workspace = true      # 继承工作区 Rust 版本（2021）
license.workspace = true      # 继承工作区许可证
description = "Codex exec policy: prefix-based Starlark rules for command decisions."
```

### 构建目标配置

#### 库目标
```toml
[lib]
name = "codex_execpolicy"     # 库 crate 名称
path = "src/lib.rs"           # 入口文件
```

**导出 API**（`src/lib.rs` 中）：
- `Policy` / `PolicyParser` - 策略解析和存储
- `Decision` - 决策枚举（Allow/Prompt/Forbidden）
- `Rule` / `RuleMatch` - 规则定义和匹配结果
- `ExecPolicyCheckCommand` - CLI 命令结构
- `blocking_append_*` - 策略修改函数

#### 二进制目标
```toml
[[bin]]
name = "codex-execpolicy"     # 可执行文件名
path = "src/main.rs"          # CLI 入口
```

### 依赖分析

#### 运行时依赖

| 依赖 | 用途 | 关键使用位置 |
|------|------|-------------|
| `anyhow` | 错误处理 | `parser.rs`, `execpolicycheck.rs` |
| `clap` | CLI 参数解析 | `main.rs`, `execpolicycheck.rs` |
| `codex-utils-absolute-path` | 绝对路径类型 | `policy.rs`, `rule.rs`, `parser.rs` |
| `multimap` | 多值哈希表（一个程序名对应多条规则） | `policy.rs` |
| `serde` / `serde_json` | 序列化（JSON 输出） | `decision.rs`, `rule.rs`, `execpolicycheck.rs` |
| `shlex` | Shell 风格字符串解析 | `parser.rs`, `rule.rs` |
| `starlark` | Starlark 语言解析 | `parser.rs` |
| `thiserror` | 错误类型定义 | `error.rs` |

#### 开发依赖

| 依赖 | 用途 |
|------|------|
| `pretty_assertions` | 测试断言美化输出 |
| `tempfile` | 测试临时文件/目录 |

### 关键依赖详解

#### starlark
- **版本**: 工作区统一管理
- **用途**: 解析 `.rules` 策略文件中的 Starlark 语法
- **关键代码**: `parser.rs` 中的 `PolicyParser::parse()` 方法
- **性能考量**: Starlark 解析器较重，策略文件在加载时一次性解析，运行时只进行规则匹配

#### multimap
- **用途**: `Policy.rules_by_program` 使用 `MultiMap<String, RuleRef>`
- **原因**: 一个程序名（如 `"git"`）可能对应多条规则（如 `"git status"`, `"git commit"`）

#### codex-utils-absolute-path
- **用途**: 类型安全的绝对路径处理
- **关键场景**: `host_executable` 路径验证、`resolved_program` 字段

## 关键代码路径与文件引用

### 核心模块依赖图

```
lib.rs (公共 API 导出)
├── decision.rs ──────┐
├── error.rs ─────────┤
├── rule.rs ──────────┼──► policy.rs ◄───┐
├── parser.rs ────────┤       ▲          │
├── execpolicycheck.rs┘       │          │
├── amend.rs                  │          │
├── executable_name.rs        │          │
└── main.rs (CLI 入口)        │          │
                              │          │
        ┌─────────────────────┘          │
        │                                │
        ▼                                │
   Policy 评估逻辑 ◄─────────────────────┘
   (matches_for_command, check, etc.)
```

### 关键类型关系

```rust
// decision.rs
pub enum Decision {
    Allow,     // 允许执行
    Prompt,    // 需要用户确认
    Forbidden, // 禁止执行
}

// rule.rs
pub struct PrefixRule {
    pub pattern: PrefixPattern,     // 前缀匹配模式
    pub decision: Decision,         // 决策
    pub justification: Option<String>, // 理由说明
}

pub struct NetworkRule {
    pub host: String,               // 目标主机
    pub protocol: NetworkRuleProtocol, // 协议
    pub decision: Decision,
    pub justification: Option<String>,
}

pub enum RuleMatch {
    PrefixRuleMatch { ... },
    HeuristicsRuleMatch { ... },  // 启发式回退匹配
}

// policy.rs
pub struct Policy {
    rules_by_program: MultiMap<String, RuleRef>,
    network_rules: Vec<NetworkRule>,
    host_executables_by_name: HashMap<String, Arc<[AbsolutePathBuf]>>,
}

pub struct Evaluation {
    pub decision: Decision,
    pub matched_rules: Vec<RuleMatch>,
}
```

## 依赖与外部交互

### 被依赖关系

#### codex-rs/cli (Cargo.toml)
```toml
codex-execpolicy = { workspace = true }
```
- 使用 `ExecPolicyCheckCommand` 提供 `codex execpolicy check` 子命令
- 在 `main.rs` 中通过 `run_execpolicycheck()` 调用

#### codex-rs/core (Cargo.toml)
```toml
codex-execpolicy = { workspace = true }
```
- 使用 `Policy`, `PolicyParser`, `Decision`, `RuleMatch`, `NetworkRuleProtocol`
- 在 `exec_policy.rs` 中实现 `ExecPolicyManager` 进行策略管理
- 调用 `blocking_append_allow_prefix_rule` 和 `blocking_append_network_rule` 修改策略

### 外部工具集成

#### CLI 使用示例
```bash
# 检查命令是否符合策略
cargo run -p codex-execpolicy -- check --rules path/to/policy.rules git status

# 启用主机可执行文件解析
codex execpolicy check --rules policy.rules --resolve-host-executables /usr/bin/git status
```

## 风险、边界与改进建议

### 风险点

1. **Starlark 依赖重量**
   - `starlark` crate 编译时间较长
   - 运行时内存占用相对较高
   - 建议：考虑预编译策略文件或缓存解析结果

2. **并发修改策略文件**
   - `amend.rs` 使用文件锁（`file.lock()`）但注释说明需要 `spawn_blocking`
   - 多进程并发修改可能存在竞态条件
   - 建议：考虑使用原子文件写入或更健壮的并发控制

3. **Windows 路径处理**
   - `executable_name.rs` 中有条件编译处理 Windows 可执行文件后缀
   - 测试覆盖可能不足（CI 主要在 Linux/macOS 运行）

### 边界条件

1. **策略文件语法**
   - 仅支持 Starlark 子集（`prefix_rule`, `network_rule`, `host_executable`）
   - 不支持用户自定义函数或复杂逻辑

2. **规则匹配顺序**
   - 先精确匹配完整路径
   - 再尝试 `host_executable` 回退到 basename 匹配
   - 最后使用启发式回退（heuristics fallback）

3. **决策优先级**
   - 多条规则匹配时，取最严格的决策：`Forbidden > Prompt > Allow`

### 改进建议

1. **性能优化**
   - 添加策略文件缓存机制，避免重复解析
   - 考虑使用 `Arc<str>` 替代 `String` 减少内存拷贝（已在 `PrefixPattern.first` 中使用）

2. **功能扩展**
   - 支持正则表达式规则（当前仅支持前缀匹配）
   - 支持规则优先级/权重
   - 支持策略文件热重载（当前需要重启服务）

3. **可观测性**
   - 添加 `tracing` 日志记录规则匹配过程
   - 提供策略评估详细日志（用于调试复杂策略）

4. **测试增强**
   - 添加更多边界条件测试（空规则、极大规则文件等）
   - 添加 Windows 平台的 CI 测试
   - 添加性能基准测试

5. **文档改进**
   - 在 `README.md` 中添加更多策略编写示例
   - 提供策略最佳实践指南
