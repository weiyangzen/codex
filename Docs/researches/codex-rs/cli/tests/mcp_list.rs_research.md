# mcp_list.rs 研究文档

## 场景与职责

`mcp_list.rs` 是 Codex CLI 的集成测试文件，负责测试 `codex mcp list` 和 `codex mcp get` 命令的功能。这些命令用于查看已配置的 MCP（Model Context Protocol）服务器信息，支持人类可读的表格格式和机器可读的 JSON 格式输出。

**主要测试场景：**
- 验证空状态列表显示友好提示
- 验证列表和获取命令输出预期格式（文本和 JSON）
- 验证禁用服务器显示单行简化输出
- 验证环境变量脱敏显示（`TOKEN=*****`）
- 验证 JSON 输出结构符合协议规范

## 功能点目的

### 1. MCP 服务器信息查看

`mcp list` 和 `mcp get` 命令允许用户：

- **查看所有服务器**：以表格形式列出配置的 MCP 服务器
- **查看单个服务器**：显示详细配置信息
- **检查认证状态**：显示 OAuth 认证状态
- **导出配置**：通过 `--json` 标志导出机器可读格式

### 2. 安全显示

敏感信息在显示时会被脱敏：
- 环境变量值显示为 `*****`
- Bearer Token 环境变量名显示，值不显示
- HTTP 头值显示为 `*****`

### 3. 格式支持

- **文本格式**：人类可读的表格，适合终端查看
- **JSON 格式**：结构化数据，适合脚本处理

## 具体技术实现

### 测试结构

```rust
#[test]
fn list_shows_empty_state() -> Result<()>

#[tokio::test]
async fn list_and_get_render_expected_output() -> Result<()>

#[tokio::test]
async fn get_disabled_server_shows_single_line() -> Result<()>
```

### 关键流程

#### 测试 1：空状态显示

```rust
let mut cmd = codex_command(codex_home.path())?;
let output = cmd.args(["mcp", "list"]).output()?;
assert!(output.status.success());
let stdout = String::from_utf8(output.stdout)?;
assert!(stdout.contains("No MCP servers configured yet."));
```

#### 测试 2：列表和获取详细输出

**准备测试数据：**
```rust
// 添加服务器
let mut add = codex_command(codex_home.path())?;
add.args([
    "mcp", "add", "docs",
    "--env", "TOKEN=secret",
    "--",
    "docs-server", "--port", "4000",
]).assert().success();

// 修改配置添加 env_vars
let mut servers = load_global_mcp_servers(codex_home.path()).await?;
let docs_entry = servers.get_mut("docs").expect("docs server should exist");
match &mut docs_entry.transport {
    McpServerTransportConfig::Stdio { env_vars, .. } => {
        *env_vars = vec!["APP_TOKEN".to_string(), "WORKSPACE_ID".to_string()];
    }
    other => panic!("unexpected transport: {other:?}"),
}
ConfigEditsBuilder::new(codex_home.path())
    .replace_mcp_servers(&servers)
    .apply_blocking()?;
```

**验证列表输出：**
```rust
let mut list_cmd = codex_command(codex_home.path())?;
let list_output = list_cmd.args(["mcp", "list"]).output()?;
let stdout = String::from_utf8(list_output.stdout)?;

// 验证表头
assert!(stdout.contains("Name"));
assert!(stdout.contains("Status"));
assert!(stdout.contains("Auth"));

// 验证服务器信息
assert!(stdout.contains("docs"));
assert!(stdout.contains("docs-server"));
assert!(stdout.contains("enabled"));

// 验证环境变量脱敏
assert!(stdout.contains("TOKEN=*****"));
assert!(stdout.contains("APP_TOKEN=*****"));
assert!(stdout.contains("WORKSPACE_ID=*****"));
```

**验证 JSON 输出：**
```rust
let mut list_json_cmd = codex_command(codex_home.path())?;
let json_output = list_json_cmd.args(["mcp", "list", "--json"]).output()?;
let stdout = String::from_utf8(json_output.stdout)?;
let parsed: JsonValue = serde_json::from_str(&stdout)?;

assert_eq!(parsed, json!([
    {
        "name": "docs",
        "enabled": true,
        "disabled_reason": null,
        "transport": {
            "type": "stdio",
            "command": "docs-server",
            "args": ["--port", "4000"],
            "env": { "TOKEN": "secret" },
            "env_vars": ["APP_TOKEN", "WORKSPACE_ID"],
            "cwd": null
        },
        "startup_timeout_sec": null,
        "tool_timeout_sec": null,
        "auth_status": "unsupported"
    }
]));
```

**验证 get 输出：**
```rust
let mut get_cmd = codex_command(codex_home.path())?;
let get_output = get_cmd.args(["mcp", "get", "docs"]).output()?;
let stdout = String::from_utf8(get_output.stdout)?;

assert!(stdout.contains("docs"));
assert!(stdout.contains("transport: stdio"));
assert!(stdout.contains("command: docs-server"));
assert!(stdout.contains("args: --port 4000"));
assert!(stdout.contains("env: TOKEN=*****"));
assert!(stdout.contains("enabled: true"));
assert!(stdout.contains("remove: codex mcp remove docs"));
```

#### 测试 3：禁用服务器显示

```rust
// 添加并禁用服务器
let mut add = codex_command(codex_home.path())?;
add.args(["mcp", "add", "docs", "--", "docs-server"]).assert().success();

let mut servers = load_global_mcp_servers(codex_home.path()).await?;
let docs = servers.get_mut("docs").expect("docs server should exist");
docs.enabled = false;
ConfigEditsBuilder::new(codex_home.path())
    .replace_mcp_servers(&servers)
    .apply_blocking()?;

// 验证禁用状态显示
let mut get_cmd = codex_command(codex_home.path())?;
let get_output = get_cmd.args(["mcp", "get", "docs"]).output()?;
let stdout = String::from_utf8(get_output.stdout)?;
assert_eq!(stdout.trim_end(), "docs (disabled)");
```

### 核心数据结构

**JSON 输出结构：**

```rust
// 列表项结构
{
    "name": String,
    "enabled": bool,
    "disabled_reason": Option<String>,
    "transport": McpTransportJson,
    "startup_timeout_sec": Option<f64>,
    "tool_timeout_sec": Option<f64>,
    "auth_status": String,  // "unsupported", "authenticated", "unauthenticated"
}

// Stdio 传输
{
    "type": "stdio",
    "command": String,
    "args": Vec<String>,
    "env": Option<HashMap<String, String>>,
    "env_vars": Vec<String>,
    "cwd": Option<String>,
}

// StreamableHttp 传输
{
    "type": "streamable_http",
    "url": String,
    "bearer_token_env_var": Option<String>,
    "http_headers": Option<HashMap<String, String>>,
    "env_http_headers": Option<HashMap<String, String>>,
}
```

### 输出格式化

**列表表格格式（`codex-rs/cli/src/mcp_cmd.rs`）：**

```rust
// Stdio 服务器表格
// Name  Command      Args        Env          Cwd  Status   Auth
// docs  docs-server  --port 4000  TOKEN=*****  -    enabled  Unsupported

// HTTP 服务器表格
// Name  Url                     Bearer Token Env Var  Status   Auth
// api   https://example.com/mcp  GITHUB_TOKEN          enabled  Authenticated
```

**环境变量脱敏：**

```rust
fn format_env_display(env: Option<&HashMap<String, String>>, env_vars: &[String]) -> String {
    let mut parts = Vec::new();
    
    // 显式环境变量
    if let Some(env) = env {
        for (key, _) in env {
            parts.push(format!("{key}=*****"));
        }
    }
    
    // 引用环境变量
    for var in env_vars {
        parts.push(format!("{var}=*****"));
    }
    
    if parts.is_empty() { "-".to_string() } else { parts.join(", ") }
}
```

### 命令实现

**列表命令（`run_list`）：**

```rust
async fn run_list(config_overrides: &CliConfigOverrides, list_args: ListArgs) -> Result<()> {
    // 加载配置
    let config = Config::load_with_cli_overrides(overrides).await?;
    let mcp_manager = McpManager::new(Arc::new(PluginsManager::new(config.codex_home.clone())));
    let mcp_servers = mcp_manager.effective_servers(&config, /*auth*/ None);
    
    // 计算认证状态
    let auth_statuses = compute_auth_statuses(mcp_servers.iter(), config.mcp_oauth_credentials_store_mode).await;
    
    if list_args.json {
        // JSON 输出
        let json_entries: Vec<_> = entries.into_iter().map(|(name, cfg)| {
            serde_json::json!({
                "name": name,
                "enabled": cfg.enabled,
                "disabled_reason": cfg.disabled_reason.as_ref().map(ToString::to_string),
                "transport": transport_to_json(&cfg.transport),
                "startup_timeout_sec": cfg.startup_timeout_sec.map(|t| t.as_secs_f64()),
                "tool_timeout_sec": cfg.tool_timeout_sec.map(|t| t.as_secs_f64()),
                "auth_status": auth_status,
            })
        }).collect();
        println!("{}", serde_json::to_string_pretty(&json_entries)?);
    } else {
        // 表格输出
        print_stdio_table(&stdio_rows);
        print_http_table(&http_rows);
    }
    Ok(())
}
```

**获取命令（`run_get`）：**

```rust
async fn run_get(config_overrides: &CliConfigOverrides, get_args: GetArgs) -> Result<()> {
    let config = Config::load_with_cli_overrides(overrides).await?;
    let mcp_manager = McpManager::new(Arc::new(PluginsManager::new(config.codex_home.clone())));
    let mcp_servers = mcp_manager.effective_servers(&config, /*auth*/ None);
    
    let Some(server) = mcp_servers.get(&get_args.name) else {
        bail!("No MCP server named '{name}' found.", name = get_args.name);
    };
    
    if get_args.json {
        // JSON 输出（与列表类似，但单个对象）
    } else if !server.enabled {
        // 禁用状态简化输出
        if let Some(reason) = server.disabled_reason.as_ref() {
            println!("{name} (disabled: {reason})");
        } else {
            println!("{name} (disabled)");
        }
    } else {
        // 详细文本输出
        println!("{}", get_args.name);
        println!("  enabled: {}", server.enabled);
        match &server.transport { ... }
        println!("  remove: codex mcp remove {}", get_args.name);
    }
    Ok(())
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/cli/tests/mcp_list.rs` - 本测试文件

### 被测代码

#### CLI 实现
- `codex-rs/cli/src/mcp_cmd.rs`
  - `McpSubcommand::List` / `McpSubcommand::Get` - 子命令定义
  - `ListArgs` / `GetArgs` - 参数定义
  - `run_list()` - 列表命令实现
  - `run_get()` - 获取命令实现
  - `format_env_display()` - 环境变量格式化

#### 认证状态
- `codex-rs/core/src/mcp/auth.rs`
  - `compute_auth_statuses()` - 计算认证状态
  - `McpAuthStatus` - 认证状态枚举

#### MCP 管理器
- `codex-rs/core/src/mcp/mod.rs`
  - `McpManager::effective_servers()` - 获取有效服务器列表

#### 协议类型
- `codex-rs/protocol/src/protocol.rs`
  - `McpAuthStatus` - 认证状态定义

### 辅助函数

```rust
fn codex_command(codex_home: &Path) -> Result<assert_cmd::Command> {
    let mut cmd = assert_cmd::Command::new(codex_utils_cargo_bin::cargo_bin("codex")?);
    cmd.env("CODEX_HOME", codex_home);
    Ok(cmd)
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `assert_cmd::Command` | 执行 CLI 命令 |
| `predicates::prelude::PredicateBooleanExt` | 谓词组合 |
| `predicates::str::contains` | 输出内容匹配 |
| `pretty_assertions::assert_eq` | 美化断言差异 |
| `serde_json::Value` / `json!` | JSON 处理 |
| `tempfile::TempDir` | 临时测试环境 |
| `tokio::test` | 异步测试运行时 |

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_core::config::edit::ConfigEditsBuilder` | 配置编辑 |
| `codex_core::config::load_global_mcp_servers` | 加载配置 |
| `codex_core::config::types::McpServerTransportConfig` | 传输配置类型 |

## 风险、边界与改进建议

### 潜在风险

1. **输出格式变更**
   - 测试严格匹配输出内容
   - 格式微调可能导致测试失败
   - 建议：使用结构化断言替代字符串匹配

2. **JSON 结构变更**
   - 测试完全匹配 JSON 结构
   - 新增字段会导致断言失败
   - 建议：使用 JSON Schema 验证或部分匹配

3. **认证状态依赖**
   - 测试假设认证状态为 "unsupported"
   - 实际 OAuth 状态可能不同
   - 建议：隔离认证状态或使用 Mock

### 边界情况

当前测试未覆盖：

1. **大量服务器**
   - 未测试列表分页或滚动

2. **超长字段**
   - 超长服务器名称
   - 超长命令/参数列表
   - 大量环境变量

3. **特殊字符**
   - 服务器名称中的 Unicode
   - 环境变量值中的特殊字符

4. **认证状态变化**
   - OAuth 认证过期
   - 认证状态查询失败

5. **多传输类型混合**
   - Stdio 和 HTTP 服务器同时显示

### 改进建议

1. **增加测试覆盖**
   ```rust
   // 建议：大量服务器测试
   #[tokio::test]
   async fn list_many_servers() { ... }
   
   // 建议：混合传输类型测试
   #[tokio::test]
   async fn list_mixed_transports() { ... }
   
   // 建议：禁用原因显示测试
   #[tokio::test]
   async fn get_disabled_server_with_reason() { ... }
   ```

2. **模糊测试**
   - 随机生成服务器配置
   - 验证输出格式始终有效

3. **性能测试**
   - 大量服务器的列表性能
   - JSON 序列化性能

4. **国际化测试**
   - Unicode 服务器名称
   - 不同区域设置的表格对齐

### 相关功能

- `codex mcp add` / `codex mcp remove` - 服务器配置管理
- `codex mcp login` / `codex mcp logout` - 认证管理
- TUI 中的 MCP 工具调用界面
- OAuth 认证流程

### 输出格式规范

**表格对齐规则：**
- 动态计算列宽
- 根据内容最长值调整
- 保持表头与数据对齐

**JSON 输出规范：**
- 使用 `serde_json::to_string_pretty` 美化
- 包含完整的配置信息
- 敏感信息不脱敏（JSON 用于脚本处理）

### 安全考虑

- 文本输出脱敏敏感信息
- JSON 输出保留原始值（用于配置导出）
- 环境变量名显示，值隐藏
