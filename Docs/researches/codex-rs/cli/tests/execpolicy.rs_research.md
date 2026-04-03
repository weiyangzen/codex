# execpolicy.rs 研究文档

## 场景与职责

`execpolicy.rs` 是 Codex CLI 的集成测试文件，负责测试 `codex execpolicy check` 命令的功能。该命令用于评估命令执行策略（Execution Policy），决定特定命令是否被允许执行。

**主要测试场景：**
- 验证执行策略检查命令能够正确匹配前缀规则
- 验证策略决策输出格式符合预期 JSON 结构
- 验证策略规则中的 justification 字段能够正确传递

## 功能点目的

### 1. 命令执行策略检查

Codex 的执行策略系统用于控制哪些命令可以被安全执行。`execpolicy check` 命令允许用户：

- **预检查命令**：在实际执行前验证命令是否符合策略
- **调试策略**：验证自定义策略规则是否按预期工作
- **CI/CD 集成**：在自动化流程中验证命令合规性

### 2. 策略规则匹配

支持基于前缀的规则匹配：
- 匹配命令前缀（如 `["git", "push"]`）
- 返回决策结果（`allowed`, `forbidden`, `review-required`）
- 提供匹配规则的详细信息

## 具体技术实现

### 测试结构

```rust
#[test]
fn execpolicy_check_matches_expected_json() -> Result<(), Box<dyn std::error::Error>>

#[test]
fn execpolicy_check_includes_justification_when_present() -> Result<(), Box<dyn std::error::Error>>
```

### 关键流程

#### 测试 1：基本策略匹配

1. **创建策略文件**
   ```rust
   let policy_path = codex_home.path().join("rules").join("policy.rules");
   fs::write(&policy_path, r#"
prefix_rule(
    pattern = ["git", "push"],
    decision = "forbidden",
)
"#)?;
   ```

2. **执行策略检查命令**
   ```rust
   let output = Command::new(codex_utils_cargo_bin::cargo_bin("codex")?)
       .env("CODEX_HOME", codex_home.path())
       .args([
           "execpolicy",
           "check",
           "--rules",
           policy_path.to_str().unwrap(),
           "git", "push", "origin", "main",
       ])
       .output()?;
   ```

3. **验证 JSON 输出**
   ```rust
   let result: serde_json::Value = serde_json::from_slice(&output.stdout)?;
   assert_eq!(result, json!({
       "decision": "forbidden",
       "matchedRules": [
           {
               "prefixRuleMatch": {
                   "matchedPrefix": ["git", "push"],
                   "decision": "forbidden"
               }
           }
       ]
   }));
   ```

#### 测试 2：带 Justification 的规则

与测试 1 类似，但验证 `justification` 字段：

```rust
prefix_rule(
    pattern = ["git", "push"],
    decision = "forbidden",
    justification = "pushing is blocked in this repo",
)
```

期望输出包含：
```json
{
    "prefixRuleMatch": {
        "matchedPrefix": ["git", "push"],
        "decision": "forbidden",
        "justification": "pushing is blocked in this repo"
    }
}
```

### 策略规则格式

**DSL 语法：**
```
prefix_rule(
    pattern = ["command", "subcommand", ...],
    decision = "forbidden" | "allowed" | "review-required",
    justification = "optional explanation string",
)
```

### 命令行接口

```bash
codex execpolicy check --rules <RULES_FILE>... [--pretty] [--resolve-host-executables] <COMMAND>...
```

参数说明：
- `--rules`: 策略规则文件路径（可重复）
- `--pretty`: 美化 JSON 输出
- `--resolve-host-executables`: 根据 basename 规则解析绝对路径
- `COMMAND`: 要检查的命令及参数

### 输出格式

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

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/cli/tests/execpolicy.rs` - 本测试文件

### 被测代码

#### CLI 入口
- `codex-rs/cli/src/main.rs`
  - `Subcommand::Execpolicy` - 子命令路由
  - `run_execpolicycheck()` - 执行策略检查入口

#### 执行策略库
- `codex-rs/execpolicy/src/main.rs` - 独立 CLI 入口
- `codex-rs/execpolicy/src/execpolicycheck.rs` - 核心检查逻辑
- `codex-rs/execpolicy/src/lib.rs` - 库接口

#### 核心数据结构
```rust
// ExecPolicyCheckCommand 定义
pub struct ExecPolicyCheckCommand {
    #[arg(short = 'r', long = "rules", value_name = "PATH", required = true)]
    pub rules: Vec<PathBuf>,
    
    #[arg(long)]
    pub pretty: bool,
    
    #[arg(long)]
    pub resolve_host_executables: bool,
    
    #[arg(value_name = "COMMAND", required = true, trailing_var_arg = true, allow_hyphen_values = true)]
    pub command: Vec<String>,
}
```

### 策略解析与匹配

```rust
// 加载策略
pub fn load_policies(policy_paths: &[PathBuf]) -> Result<Policy> {
    let mut parser = PolicyParser::new();
    for policy_path in policy_paths {
        let policy_file_contents = fs::read_to_string(policy_path)?;
        parser.parse(&policy_identifier, &policy_file_contents)?;
    }
    Ok(parser.build())
}

// 匹配命令
let matched_rules = policy.matches_for_command_with_options(
    &self.command,
    /*heuristics_fallback*/ None,
    &MatchOptions {
        resolve_host_executables: self.resolve_host_executables,
    },
);
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `assert_cmd::Command` | 执行 CLI 命令 |
| `serde_json` | JSON 序列化/反序列化 |
| `tempfile::TempDir` | 创建临时测试环境 |
| `pretty_assertions::assert_eq` | 美化断言差异 |

### 被测二进制

- `codex_utils_cargo_bin::cargo_bin("codex")` - 定位 codex 可执行文件

### 文件系统交互

- 创建临时目录结构
- 写入策略规则文件
- 通过 `CODEX_HOME` 环境变量隔离配置

## 风险、边界与改进建议

### 潜在风险

1. **策略 DSL 变更**
   - 测试硬编码了策略规则语法
   - DSL 语法变更会导致测试失败
   - 建议：使用策略解析器的序列化功能生成测试数据

2. **JSON 格式变更**
   - 测试严格匹配 JSON 结构
   - 新增字段可能导致断言失败
   - 建议：使用部分匹配而非完全相等

3. **平台差异**
   - 路径分隔符在不同平台可能不同
   - 当前测试使用 `PathBuf` 处理，兼容性良好

### 边界情况

当前测试未覆盖：

1. **多规则文件**
   ```rust
   // 未测试：--rules file1 --rules file2
   ```

2. **无匹配规则**
   - 命令不匹配任何规则时的行为

3. **复杂模式匹配**
   - 通配符、正则表达式等高级匹配

4. **错误处理**
   - 无效的策略文件格式
   - 不存在的规则文件

### 改进建议

1. **增加测试覆盖**
   ```rust
   // 建议：无匹配规则测试
   #[test]
   fn execpolicy_check_no_match() { ... }
   
   // 建议：多规则文件测试
   #[test]
   fn execpolicy_check_multiple_rules_files() { ... }
   
   // 建议：--pretty 标志测试
   #[test]
   fn execpolicy_check_pretty_output() { ... }
   ```

2. **模糊匹配测试**
   - 测试部分前缀匹配
   - 测试参数数量变化

3. **性能测试**
   - 大型策略文件的匹配性能
   - 复杂命令的解析性能

4. **安全测试**
   - 验证命令注入防护
   - 测试特殊字符处理

### 相关功能

- 执行策略系统与沙箱策略（Sandbox Policy）配合使用
- 策略决策影响命令的批准流程（Approval Flow）
- 在 TUI 中以交互方式展示策略匹配结果

### 命令可见性

- 命令被标记为 `#[clap(hide = true)]`
- 主要用于内部调试和 CI/CD 集成
- 普通用户通过 TUI 的批准提示间接使用策略系统
