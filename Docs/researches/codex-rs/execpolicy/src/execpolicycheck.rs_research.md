# execpolicycheck.rs 研究文档

## 场景与职责

`execpolicycheck.rs` 是 `codex-execpolicy` crate 的**命令行接口（CLI）实现模块**，提供独立的可执行工具用于策略验证和调试。主要场景包括：

1. **策略开发调试**：策略作者验证规则是否按预期匹配命令
2. **CI/CD 集成**：在持续集成中验证策略变更
3. **运维排查**：检查特定命令会被如何评估
4. **策略审计**：批量检查多个命令的决策结果

该模块将策略引擎封装为可独立运行的 CLI 工具，输出 JSON 格式的评估结果。

## 功能点目的

### 1. `ExecPolicyCheckCommand` - CLI 命令结构

使用 `clap` 派生宏定义命令行参数：

| 参数 | 说明 |
|------|------|
| `-r, --rules <PATH>` | 策略文件路径（可重复，必需）|
| `--pretty` | 美化 JSON 输出 |
| `--resolve-host-executables` | 启用主机可执行文件解析 |
| `COMMAND...` | 要检查的命令（尾部可变参数）|

### 2. 策略加载与评估

- 加载一个或多个策略文件
- 合并为统一策略
- 评估给定命令
- 输出 JSON 结果

### 3. JSON 输出格式化

支持紧凑和美化两种 JSON 输出格式。

## 具体技术实现

### 命令结构定义

```rust
#[derive(Debug, Parser, Clone)]
pub struct ExecPolicyCheckCommand {
    #[arg(short = 'r', long = "rules", value_name = "PATH", required = true)]
    pub rules: Vec<PathBuf>,

    #[arg(long)]
    pub pretty: bool,

    #[arg(long)]
    pub resolve_host_executables: bool,

    #[arg(
        value_name = "COMMAND",
        required = true,
        trailing_var_arg = true,
        allow_hyphen_values = true
    )]
    pub command: Vec<String>,
}
```

关键参数设计：
- `trailing_var_arg = true`：捕获所有剩余参数作为命令
- `allow_hyphen_values = true`：允许命令参数以 `-` 开头（如 `rm -rf`）

### 执行流程

```rust
impl ExecPolicyCheckCommand {
    pub fn run(&self) -> Result<()> {
        // 1. 加载策略
        let policy = load_policies(&self.rules)?;
        
        // 2. 评估命令
        let matched_rules = policy.matches_for_command_with_options(
            &self.command,
            /*heuristics_fallback*/ None,
            &MatchOptions {
                resolve_host_executables: self.resolve_host_executables,
            },
        );
        
        // 3. 格式化输出
        let json = format_matches_json(&matched_rules, self.pretty)?;
        println!("{json}");
        
        Ok(())
    }
}
```

### 策略加载

```rust
pub fn load_policies(policy_paths: &[PathBuf]) -> Result<Policy> {
    let mut parser = PolicyParser::new();
    
    for policy_path in policy_paths {
        // 读取文件
        let policy_file_contents = fs::read_to_string(policy_path)
            .with_context(|| format!("failed to read policy at {}", policy_path.display()))?;
        
        // 解析策略
        let policy_identifier = policy_path.to_string_lossy().to_string();
        parser.parse(&policy_identifier, &policy_file_contents)
            .with_context(|| format!("failed to parse policy at {}", policy_path.display()))?;
    }
    
    Ok(parser.build())
}
```

使用 `anyhow::Context` 为错误添加上下文，帮助用户定位问题。

### JSON 输出结构

```rust
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ExecPolicyCheckOutput<'a> {
    #[serde(rename = "matchedRules")]
    matched_rules: &'a [RuleMatch],
    #[serde(skip_serializing_if = "Option::is_none")]
    decision: Option<Decision>,
}
```

输出示例：

```json
{
  "matchedRules": [
    {
      "prefixRuleMatch": {
        "matchedPrefix": ["git", "status"],
        "decision": "allow",
        "justification": "safe command"
      }
    }
  ],
  "decision": "allow"
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::Decision` | 决策枚举 |
| `crate::MatchOptions` | 匹配选项 |
| `crate::Policy` | 策略类型 |
| `crate::PolicyParser` | 策略解析器 |
| `crate::RuleMatch` | 规则匹配结果 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理和上下文 |
| `clap` | 命令行参数解析 |
| `serde` | JSON 序列化 |

### 调用方

- `main.rs`：CLI 入口点调用
- 外部脚本/工具：直接执行二进制

## 风险、边界与改进建议

### 风险点

1. **无启发式回退**：`heuristics_fallback` 固定为 `None`，无策略匹配时返回空结果而非默认决策
2. **无决策时的处理**：当 `matched_rules` 为空时，`decision` 为 `None`，调用方需要处理这种情况
3. **文件读取错误**：策略文件不存在或不可读时，错误信息可能不够友好

### 边界条件

1. **空命令**：`clap` 确保 `command` 非空（`required = true`）
2. **空策略**：如果没有提供 `--rules`，`clap` 会报错
3. **多个策略文件**：按顺序加载，后加载的规则可能覆盖先加载的
4. **大输出**：大量匹配规则时，JSON 可能很大

### 改进建议

1. **默认决策**：提供 `--default-decision` 参数，在无匹配时使用
2. **批量检查**：支持从文件读取命令列表，批量检查
3. **输出格式**：支持其他输出格式（如 YAML、TOML、表格）
4. **详细模式**：添加 `--verbose` 显示解析过程中的详细信息
5. **统计信息**：添加 `--stats` 显示规则覆盖率等统计
6. **交互模式**：支持交互式输入命令，实时查看结果
7. **配置文件**：支持从配置文件读取默认参数
8. **规则来源**：在输出中显示匹配规则来自哪个策略文件

### 使用示例

```bash
# 基本使用
cargo run -p codex-execpolicy -- check -r default.rules git status

# 美化输出
cargo run -p codex-execpolicy -- check -r default.rules --pretty git status

# 启用主机可执行文件解析
cargo run -p codex-execpolicy -- check -r default.rules --resolve-host-executables /usr/bin/git status

# 多个策略文件
cargo run -p codex-execpolicy -- check -r base.rules -r override.rules git status

# 带横线的命令
cargo run -p codex-execpolicy -- check -r default.rules -- ls -la
```

### 与主 CLI 的关系

`codex-cli` 也提供 `execpolicy check` 子命令，其实现可能复用此模块。独立二进制 `codex-execpolicy` 主要用于：
1. 开发调试
2. 无需完整 Codex CLI 的轻量级场景
3. 自动化脚本中的策略检查
