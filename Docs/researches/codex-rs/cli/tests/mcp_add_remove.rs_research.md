# mcp_add_remove.rs 研究文档

## 场景与职责

`mcp_add_remove.rs` 是 Codex CLI 的集成测试文件，负责测试 `codex mcp add` 和 `codex mcp remove` 命令的功能。这些命令用于管理 MCP（Model Context Protocol）服务器配置，允许用户添加、配置和移除外部工具服务器。

**主要测试场景：**
- 验证添加和移除 MCP 服务器更新全局配置
- 验证环境变量配置保持键顺序和值
- 验证 Streamable HTTP 服务器添加（无令牌）
- 验证 Streamable HTTP 服务器添加（带自定义环境变量）
- 验证已移除的 `--with-bearer-token` 标志被拒绝
- 验证不能同时指定命令和 URL

## 功能点目的

### 1. MCP 服务器管理

MCP（Model Context Protocol）是 Codex 与外部工具集成的协议。`mcp add/remove` 命令允许用户：

- **添加 Stdio 服务器**：通过命令行启动的本地 MCP 服务器
- **添加 HTTP 服务器**：通过 URL 访问的远程 MCP 服务器
- **配置环境变量**：为服务器设置运行环境
- **配置认证**：设置 OAuth 或 Bearer Token 认证

### 2. 配置持久化

MCP 服务器配置持久化到 `~/.codex/config.toml`：

```toml
[mcp_servers.docs]
command = "docs-server"
args = ["--port", "4000"]
env = { TOKEN = "secret" }

[mcp_servers.github]
url = "https://example.com/mcp"
bearer_token_env_var = "GITHUB_TOKEN"
```

## 具体技术实现

### 测试结构

```rust
#[tokio::test]
async fn add_and_remove_server_updates_global_config() -> Result<()>

#[tokio::test]
async fn add_with_env_preserves_key_order_and_values() -> Result<()>

#[tokio::test]
async fn add_streamable_http_without_manual_token() -> Result<()>

#[tokio::test]
async fn add_streamable_http_with_custom_env_var() -> Result<()>

#[tokio::test]
async fn add_streamable_http_rejects_removed_flag() -> Result<()>

#[tokio::test]
async fn add_cant_add_command_and_url() -> Result<()>
```

### 关键流程

#### 测试 1：添加和移除 Stdio 服务器

```rust
// 添加服务器
let mut add_cmd = codex_command(codex_home.path())?;
add_cmd
    .args(["mcp", "add", "docs", "--", "echo", "hello"])
    .assert()
    .success()
    .stdout(contains("Added global MCP server 'docs'."));

// 验证配置
let servers = load_global_mcp_servers(codex_home.path()).await?;
assert_eq!(servers.len(), 1);
let docs = servers.get("docs").expect("server should exist");
match &docs.transport {
    McpServerTransportConfig::Stdio { command, args, env, env_vars, cwd } => {
        assert_eq!(command, "echo");
        assert_eq!(args, &vec!["hello".to_string()]);
        assert!(env.is_none());
        assert!(env_vars.is_empty());
        assert!(cwd.is_none());
    }
    other => panic!("unexpected transport: {other:?}"),
}
assert!(docs.enabled);

// 移除服务器
let mut remove_cmd = codex_command(codex_home.path())?;
remove_cmd
    .args(["mcp", "remove", "docs"])
    .assert()
    .success()
    .stdout(contains("Removed global MCP server 'docs'."));

// 验证移除
let servers = load_global_mcp_servers(codex_home.path()).await?;
assert!(servers.is_empty());
```

#### 测试 2：带环境变量的配置

```rust
add_cmd.args([
    "mcp", "add", "envy",
    "--env", "FOO=bar",
    "--env", "ALPHA=beta",
    "--",
    "python", "server.py",
]);

// 验证环境变量保持顺序
let env = match &envy.transport {
    McpServerTransportConfig::Stdio { env: Some(env), .. } => env,
    other => panic!("unexpected transport: {other:?}"),
};
assert_eq!(env.len(), 2);
assert_eq!(env.get("FOO"), Some(&"bar".to_string()));
assert_eq!(env.get("ALPHA"), Some(&"beta".to_string()));
```

#### 测试 3：Streamable HTTP 服务器

```rust
add_cmd.args(["mcp", "add", "github", "--url", "https://example.com/mcp"]);

// 验证 HTTP 配置
match &github.transport {
    McpServerTransportConfig::StreamableHttp { url, bearer_token_env_var, http_headers, env_http_headers } => {
        assert_eq!(url, "https://example.com/mcp");
        assert!(bearer_token_env_var.is_none());
        assert!(http_headers.is_none());
        assert!(env_http_headers.is_none());
    }
    other => panic!("unexpected transport: {other:?}"),
}

// 验证不创建凭证文件
assert!(!codex_home.path().join(".credentials.json").exists());
assert!(!codex_home.path().join(".env").exists());
```

#### 测试 4：带 Bearer Token 的 HTTP 服务器

```rust
add_cmd.args([
    "mcp", "add", "issues",
    "--url", "https://example.com/issues",
    "--bearer-token-env-var", "GITHUB_TOKEN",
]);

assert_eq!(bearer_token_env_var.as_deref(), Some("GITHUB_TOKEN"));
```

#### 测试 5：拒绝已移除的标志

```rust
add_cmd.args([
    "mcp", "add", "github",
    "--url", "https://example.com/mcp",
    "--with-bearer-token",  // 已移除的标志
]);

add_cmd.assert().failure().stderr(contains("--with-bearer-token"));
```

#### 测试 6：互斥参数验证

```rust
add_cmd.args([
    "mcp", "add", "github",
    "--url", "https://example.com/mcp",
    "--command",  // 与 --url 互斥
    "--",
    "echo", "hello",
]);

add_cmd.assert().failure().stderr(contains("unexpected argument '--command' found"));
```

### 核心数据结构

**MCP 服务器配置（`codex-rs/core/src/config/types.rs`）：**

```rust
pub struct McpServerConfig {
    pub transport: McpServerTransportConfig,
    pub enabled: bool,
    pub required: bool,
    pub disabled_reason: Option<McpServerDisabledReason>,
    pub startup_timeout_sec: Option<Duration>,
    pub tool_timeout_sec: Option<Duration>,
    pub enabled_tools: Option<Vec<String>>,
    pub disabled_tools: Option<Vec<String>>,
    pub scopes: Option<Vec<String>>,
    pub oauth_resource: Option<String>,
}

pub enum McpServerTransportConfig {
    Stdio {
        command: String,
        args: Vec<String>,
        env: Option<HashMap<String, String>>,
        env_vars: Vec<String>,
        cwd: Option<PathBuf>,
    },
    StreamableHttp {
        url: String,
        bearer_token_env_var: Option<String>,
        http_headers: Option<HashMap<String, String>>,
        env_http_headers: Option<HashMap<String, String>>,
    },
}
```

### 命令参数定义

**AddArgs（`codex-rs/cli/src/mcp_cmd.rs`）：**

```rust
#[derive(Debug, clap::Parser)]
#[command(override_usage = "codex mcp add [OPTIONS] <NAME> (--url <URL> | -- <COMMAND>...)")]
pub struct AddArgs {
    pub name: String,
    #[command(flatten)]
    pub transport_args: AddMcpTransportArgs,
}

#[derive(Debug, clap::Args)]
#[command(
    group(
        ArgGroup::new("transport")
            .args(["command", "url"])
            .required(true)
            .multiple(false)
    )
)]
pub struct AddMcpTransportArgs {
    #[command(flatten)]
    pub stdio: Option<AddMcpStdioArgs>,
    #[command(flatten)]
    pub streamable_http: Option<AddMcpStreamableHttpArgs>,
}

#[derive(Debug, clap::Args)]
pub struct AddMcpStdioArgs {
    #[arg(trailing_var_arg = true, num_args = 0..)]
    pub command: Vec<String>,
    
    #[arg(long, value_parser = parse_env_pair, value_name = "KEY=VALUE")]
    pub env: Vec<(String, String)>,
}

#[derive(Debug, clap::Args)]
pub struct AddMcpStreamableHttpArgs {
    #[arg(long)]
    pub url: String,
    
    #[arg(long = "bearer-token-env-var", value_name = "ENV_VAR", requires = "url")]
    pub bearer_token_env_var: Option<String>,
}
```

### 配置编辑流程

**添加服务器（`codex-rs/cli/src/mcp_cmd.rs`）：**

```rust
async fn run_add(config_overrides: &CliConfigOverrides, add_args: AddArgs) -> Result<()> {
    // 验证并加载配置
    let config = Config::load_with_cli_overrides(overrides).await?;
    
    // 验证服务器名称
    validate_server_name(&name)?;
    
    // 加载现有服务器配置
    let codex_home = find_codex_home()?;
    let mut servers = load_global_mcp_servers(&codex_home).await?;
    
    // 构建传输配置
    let transport = match transport_args { ... };
    
    // 创建服务器配置
    let new_entry = McpServerConfig {
        transport: transport.clone(),
        enabled: true,
        required: false,
        disabled_reason: None,
        startup_timeout_sec: None,
        tool_timeout_sec: None,
        enabled_tools: None,
        disabled_tools: None,
        scopes: None,
        oauth_resource: None,
    };
    
    // 更新配置
    servers.insert(name.clone(), new_entry);
    ConfigEditsBuilder::new(&codex_home)
        .replace_mcp_servers(&servers)
        .apply()
        .await?;
    
    println!("Added global MCP server '{name}'.");
    
    // 自动触发 OAuth 登录（如果支持）
    match oauth_login_support(&transport).await {
        McpOAuthLoginSupport::Supported(oauth_config) => { ... }
        McpOAuthLoginSupport::Unsupported => {}
        McpOAuthLoginSupport::Unknown(_) => { ... }
    }
    
    Ok(())
}
```

**移除服务器：**

```rust
async fn run_remove(config_overrides: &CliConfigOverrides, remove_args: RemoveArgs) -> Result<()> {
    let RemoveArgs { name } = remove_args;
    validate_server_name(&name)?;
    
    let codex_home = find_codex_home()?;
    let mut servers = load_global_mcp_servers(&codex_home).await?;
    
    let removed = servers.remove(&name).is_some();
    
    if removed {
        ConfigEditsBuilder::new(&codex_home)
            .replace_mcp_servers(&servers)
            .apply()
            .await?;
        println!("Removed global MCP server '{name}'.");
    } else {
        println!("No MCP server named '{name}' found.");
    }
    
    Ok(())
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/cli/tests/mcp_add_remove.rs` - 本测试文件

### 被测代码

#### CLI 实现
- `codex-rs/cli/src/mcp_cmd.rs`
  - `McpCli` - MCP 命令组
  - `McpSubcommand::Add` / `McpSubcommand::Remove` - 子命令
  - `AddArgs` / `RemoveArgs` - 参数定义
  - `run_add()` / `run_remove()` - 执行逻辑

#### 配置类型
- `codex-rs/core/src/config/types.rs`
  - `McpServerConfig` - 服务器配置结构
  - `McpServerTransportConfig` - 传输配置枚举
  - `McpServerDisabledReason` - 禁用原因

#### 配置编辑
- `codex-rs/core/src/config/edit.rs`
  - `ConfigEditsBuilder::replace_mcp_servers()` - 替换服务器配置
  - `document_helpers::serialize_mcp_server()` - 序列化

#### 配置加载
- `codex-rs/core/src/config/mod.rs`
  - `load_global_mcp_servers()` - 加载全局配置

### 辅助函数

```rust
fn codex_command(codex_home: &Path) -> Result<assert_cmd::Command> {
    let mut cmd = assert_cmd::Command::new(codex_utils_cargo_bin::cargo_bin("codex")?);
    cmd.env("CODEX_HOME", codex_home);
    Ok(cmd)
}

fn validate_server_name(name: &str) -> Result<()> {
    let is_valid = !name.is_empty()
        && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    if is_valid { Ok(()) } else { bail!("invalid server name '{name}'") }
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `assert_cmd::Command` | 执行 CLI 命令 |
| `predicates::str::contains` | 输出内容匹配 |
| `pretty_assertions::assert_eq` | 美化断言差异 |
| `tempfile::TempDir` | 临时测试环境 |
| `tokio::test` | 异步测试运行时 |

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_core::config::load_global_mcp_servers` | 加载 MCP 配置 |
| `codex_core::config::types::McpServerTransportConfig` | 传输配置类型 |
| `codex_core::config::edit::ConfigEditsBuilder` | 配置编辑 |

### OAuth 集成

- `codex_core::mcp::auth::oauth_login_support()` - 检测 OAuth 支持
- `codex_rmcp_client::perform_oauth_login()` - 执行 OAuth 登录

## 风险、边界与改进建议

### 潜在风险

1. **服务器名称验证**
   - 测试未覆盖无效名称场景
   - 名称格式变更可能影响现有配置

2. **配置格式变更**
   - TOML 序列化格式变更可能影响兼容性
   - 新增字段需要更新测试

3. **OAuth 流程**
   - 测试使用模拟环境，未真实测试 OAuth
   - 实际 OAuth 流程可能因网络问题失败

### 边界情况

当前测试未覆盖：

1. **重复添加**
   ```rust
   // 未测试：同名服务器重复添加的行为
   ```

2. **无效环境变量格式**
   ```rust
   // 未测试：--env INVALID_FORMAT
   ```

3. **超长参数**
   - 超长服务器名称
   - 超长命令/参数

4. **特殊字符**
   - 服务器名称中的特殊字符
   - 环境变量值中的特殊字符

5. **并发编辑**
   - 多进程同时修改配置

### 改进建议

1. **增加测试覆盖**
   ```rust
   // 建议：重复添加测试
   #[tokio::test]
   async fn add_duplicate_server_updates_config() { ... }
   
   // 建议：无效服务器名测试
   #[tokio::test]
   async fn add_invalid_server_name_fails() { ... }
   
   // 建议：超时配置测试
   #[tokio::test]
   async fn add_with_timeout_options() { ... }
   ```

2. **错误场景测试**
   - 配置文件只读
   - 磁盘空间不足
   - 无效 URL 格式

3. **安全测试**
   - 命令注入防护
   - 环境变量泄露检查

4. **性能测试**
   - 大量服务器配置的加载性能

### 相关功能

- `codex mcp list` - 列出配置的服务器
- `codex mcp get` - 查看单个服务器详情
- `codex mcp login` / `codex mcp logout` - OAuth 认证管理
- TUI 中的 MCP 工具调用和批准流程
