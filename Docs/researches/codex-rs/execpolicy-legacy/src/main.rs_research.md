# main.rs 研究文档

## 场景与职责

`main.rs` 是 `codex-execpolicy-legacy` crate 的 CLI 入口，负责：

1. **命令行解析**：使用 clap 解析用户输入
2. **策略加载**：加载默认策略或自定义策略文件
3. **命令验证**：调用策略引擎验证命令
4. **结果输出**：以 JSON 格式输出验证结果
5. **退出码管理**：根据验证结果设置进程退出码

该文件提供了策略引擎的用户界面，使开发者和系统管理员可以通过命令行使用策略验证功能。

## 功能点目的

### 1. CLI 参数结构

**Args 结构**：
```rust
#[derive(Parser, Deserialize, Debug)]
pub struct Args {
    #[clap(long)]
    pub require_safe: bool,  // 要求安全才返回 0

    #[clap(long, short = 'p')]
    pub policy: Option<PathBuf>,  // 自定义策略文件

    #[command(subcommand)]
    pub command: Command,
}
```

**Command 枚举**：
```rust
#[derive(Clone, Debug, Deserialize, Subcommand)]
pub enum Command {
    Check { command: Vec<String> },  // 直接检查命令
    CheckJson { exec: ExecArg },      // 从 JSON 检查
}
```

### 2. 退出码定义

```rust
const MATCHED_BUT_WRITES_FILES_EXIT_CODE: i32 = 12;
const MIGHT_BE_SAFE_EXIT_CODE: i32 = 13;
const FORBIDDEN_EXIT_CODE: i32 = 14;
```

退出码策略：
- `0`：成功（safe 或 match 且未要求 safe）
- `12`：匹配但可能写文件（`--require-safe` 时）
- `13`：无法验证（`--require-safe` 时）
- `14`：禁止（`--require-safe` 时）
- `1`：其他错误（如解析失败）

### 3. 结果输出格式

**Output 枚举**：
```rust
#[derive(Debug, Serialize)]
#[serde(tag = "result")]
pub enum Output {
    #[serde(rename = "safe")]
    Safe { r#match: ValidExec },
    #[serde(rename = "match")]
    Match { r#match: ValidExec },
    #[serde(rename = "forbidden")]
    Forbidden { reason: String, cause: Forbidden },
    #[serde(rename = "unverified")]
    Unverified { error: Error },
}
```

## 具体技术实现

### 主流程

**main() 函数**：
```rust
fn main() -> Result<()> {
    env_logger::init();
    let args = Args::parse();
    
    // 加载策略
    let policy = match args.policy {
        Some(policy) => load_custom_policy(&policy),
        None => get_default_policy(),
    }?;
    
    // 解析命令
    let exec = match args.command {
        Command::Check { command } => parse_command(command),
        Command::CheckJson { exec } => exec,
    };
    
    // 检查并输出
    let (output, exit_code) = check_command(&policy, exec, args.require_safe);
    println!("{}", serde_json::to_string(&output)?);
    std::process::exit(exit_code);
}
```

### 策略加载

```rust
let policy = match args.policy {
    Some(policy) => {
        let policy_source = policy.to_string_lossy().to_string();
        let unparsed_policy = std::fs::read_to_string(policy)?;
        let parser = PolicyParser::new(&policy_source, &unparsed_policy);
        parser.parse()
    }
    None => get_default_policy(),
};
```

### 命令解析

**Check 子命令**：
```rust
Command::Check { command } => match command.split_first() {
    Some((first, rest)) => ExecArg {
        program: first.to_string(),
        args: rest.to_vec(),
    },
    None => {
        eprintln!("no command provided");
        std::process::exit(1);
    }
}
```

**CheckJson 子命令**：
```rust
Command::CheckJson { exec } => exec
```

使用自定义反序列化器：
```rust
#[serde(deserialize_with = "deserialize_from_json")]
exec: ExecArg
```

### 检查逻辑

**check_command()**：
```rust
fn check_command(
    policy: &Policy,
    ExecArg { program, args }: ExecArg,
    check: bool,
) -> (Output, i32) {
    let exec_call = ExecCall { program, args };
    match policy.check(&exec_call) {
        Ok(MatchedExec::Match { exec }) => {
            if exec.might_write_files() {
                let exit_code = if check { 12 } else { 0 };
                (Output::Match { r#match: exec }, exit_code)
            } else {
                (Output::Safe { r#match: exec }, 0)
            }
        }
        Ok(MatchedExec::Forbidden { reason, cause }) => {
            let exit_code = if check { 14 } else { 0 };
            (Output::Forbidden { reason, cause }, exit_code)
        }
        Err(err) => {
            let exit_code = if check { 13 } else { 0 };
            (Output::Unverified { error: err }, exit_code)
        }
    }
}
```

### JSON 反序列化

**deserialize_from_json()**：
```rust
fn deserialize_from_json<'de, D>(deserializer: D) -> Result<ExecArg, D::Error>
where
    D: de::Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    let decoded = serde_json::from_str(&s)
        .map_err(|e| serde::de::Error::custom(format!("JSON parse error: {e}")))?;
    Ok(decoded)
}
```

**FromStr 实现**：
```rust
impl FromStr for ExecArg {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        serde_json::from_str(s).map_err(Into::into)
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/execpolicy-legacy/src/main.rs`

### 依赖文件
- `codex-rs/execpolicy-legacy/src/lib.rs`：库公共 API
- `codex-rs/execpolicy-legacy/src/policy.rs`：Policy::check()
- `codex-rs/execpolicy-legacy/src/program.rs`：MatchedExec, Forbidden
- `codex-rs/execpolicy-legacy/src/valid_exec.rs`：ValidExec
- `codex-rs/execpolicy-legacy/src/exec_call.rs`：ExecCall
- `codex-rs/execpolicy-legacy/src/error.rs`：Error

### 外部 crate
- `clap`：命令行解析
- `serde` / `serde_json`：JSON 序列化
- `anyhow`：错误处理

### 执行流程

```
用户输入
  └── cargo run -- check ls -l foo
      └── Args::parse()
          ├── require_safe: false
          ├── policy: None
          └── command: Check { command: ["ls", "-l", "foo"] }
              └── main()
                  ├── get_default_policy()
                  │   └── include_str!("default.policy")
                  │       └── PolicyParser::parse()
                  ├── parse_command()
                  │   └── ExecArg { program: "ls", args: ["-l", "foo"] }
                  ├── check_command()
                  │   ├── policy.check(&ExecCall { ... })
                  │   │   └── MatchedExec::Match { exec }
                  │   ├── exec.might_write_files() -> false
                  │   └── (Output::Safe { ... }, 0)
                  └── println!(json)
                      └── exit(0)
```

## 依赖与外部交互

### 外部 crate
- `clap`：命令行解析
  - `Parser`, `Subcommand` derive 宏
  - `trailing_var_arg` 属性
- `serde` / `serde_json`：JSON 处理
  - `Serialize`, `Deserialize` derive 宏
  - `Deserializer` trait
- `anyhow`：错误处理
  - `Result` 类型别名
- `starlark`：Starlark 错误转换
  - `Error::into_anyhow()`

### 内部依赖
- 库公共 API（通过 `codex_execpolicy_legacy` crate）

## 风险、边界与改进建议

### 风险点

1. **退出码冲突**
   - 使用 12, 13, 14 作为自定义退出码
   - 可能与 shell 或其他工具冲突
   - 建议：使用 100+ 的退出码

2. **JSON 解析错误处理**
   ```rust
   // CheckJson 的反序列化错误可能不够友好
   serde_json::from_str(&s).map_err(...)
   ```

3. **策略文件读取错误**
   ```rust
   std::fs::read_to_string(policy)?
   // 错误直接传播，可能包含敏感路径信息
   ```

4. **命令解析歧义**
   ```rust
   // cargo run -- check -- -l foo
   // 可能被解析为选项而非参数
   ```

### 边界情况

1. **空命令**
   ```rust
   cargo run -- check
   // -> "no command provided"
   // -> exit(1)
   ```

2. **只有程序名**
   ```rust
   cargo run -- check ls
   // -> 验证 ls 无参数调用
   ```

3. **JSON 输入格式错误**
   ```rust
   cargo run -- check-json '{invalid}'
   // -> JSON parse error
   ```

4. **策略文件不存在**
   ```rust
   cargo run -- -p /nonexistent.policy check ls
   // -> IO error
   ```

### 改进建议

1. **子命令增强**
   ```rust
   #[derive(Subcommand)]
   pub enum Command {
       Check { ... },
       CheckJson { ... },
       ValidatePolicy { path: PathBuf },  // 验证策略文件语法
       ListPrograms,  // 列出默认策略支持的程序
       Explain { program: String, args: Vec<String> },  // 解释为什么命令被接受/拒绝
   }
   ```

2. **输出格式选项**
   ```rust
   #[clap(long)]
   pub output_format: OutputFormat,  // json, yaml, pretty
   ```

3. **日志级别控制**
   ```rust
   #[clap(long, short)]
   pub verbose: bool,
   ```

4. **配置文件支持**
   ```rust
   // 支持 ~/.config/codex/policy.toml
   let config = Config::load()?;
   ```

5. **交互模式**
   ```rust
   Command::Interactive,  // 交互式验证多个命令
   ```

6. **错误改进**
   ```rust
   // 更友好的错误消息
   eprintln!("Error: {}", e);
   eprintln!("\nHint: Use 'check-json' for complex arguments");
   ```

7. **测试覆盖**
   - 添加 CLI 集成测试
   - 测试各种退出码
   - 测试 JSON 输入/输出

8. **文档改进**
   ```rust
   /// Check a command for safety
   /// 
   /// Examples:
   ///   codex-execpolicy-legacy check ls -l
   ///   codex-execpolicy-legacy check -- cp -r src dest
   ///   echo '{"program":"ls","args":["-l"]}' | codex-execpolicy-legacy check-json
   #[clap(name = "check")]
   Check { ... }
   ```
