# Research: MCP Tools Output Masks Sensitive Values Snapshot

## 场景与职责

此快照测试验证 Codex TUI 在展示 MCP 服务器配置信息时的敏感数据脱敏能力。当用户执行 `/mcp` 命令查看已配置的 MCP 服务器时，UI 需要自动隐藏敏感信息（如 API 密钥、令牌等），防止敏感数据泄露。

## 功能点目的

1. **敏感信息脱敏**：自动识别并隐藏敏感配置值
2. **配置信息展示**：清晰展示 MCP 服务器的配置详情
3. **安全与透明平衡**：在保护敏感信息的同时提供足够的配置可见性

## 具体技术实现

### MCP 服务器配置结构

```rust
// codex_core::config::types::McpServerTransportConfig
pub enum McpServerTransportConfig {
    Stdio {
        command: String,
        args: Vec<String>,
        env: Option<HashMap<String, String>>,  // 需要脱敏
        env_vars: Vec<String>,
        cwd: Option<PathBuf>,
    },
    StreamableHttp {
        url: String,
        bearer_token_env_var: Option<String>,
        http_headers: Option<HashMap<String, String>>,  // 需要脱敏
        env_http_headers: Option<HashMap<String, String>>,
    },
}
```

### 脱敏展示实现

```rust
// history_cell.rs:1799-1965
pub(crate) fn new_mcp_tools_output(
    config: &Config,
    tools: HashMap<String, codex_protocol::mcp::Tool>,
    resources: HashMap<String, Vec<Resource>>,
    resource_templates: HashMap<String, Vec<ResourceTemplate>>,
    auth_statuses: &HashMap<String, McpAuthStatus>,
) -> PlainHistoryCell {
    // ...
    
    match &cfg.transport {
        McpServerTransportConfig::Stdio { env, env_vars, .. } => {
            // ...
            let env_display = format_env_display(env.as_ref(), env_vars);
            // env_display 会自动脱敏敏感值
            if env_display != "-" {
                lines.push(vec!["    • Env: ".into(), env_display.into()].into());
            }
        }
        McpServerTransportConfig::StreamableHttp { 
            url, 
            http_headers, 
            env_http_headers, 
            .. 
        } => {
            lines.push(vec!["    • URL: ".into(), url.clone().into()].into());
            
            // HTTP headers 脱敏
            if let Some(headers) = http_headers.as_ref() && !headers.is_empty() {
                let mut pairs: Vec<_> = headers.iter().collect();
                pairs.sort_by(|(a, _), (b, _)| a.cmp(b));
                let display = pairs
                    .into_iter()
                    .map(|(name, _)| format!("{name}=*****"))  // 值脱敏为 *****
                    .collect::<Vec<_>>()
                    .join(", ");
                lines.push(vec!["    • HTTP headers: ".into(), display.into()].into());
            }
            
            // Env HTTP headers 显示变量名而非值
            if let Some(headers) = env_http_headers.as_ref() && !headers.is_empty() {
                let display = pairs
                    .into_iter()
                    .map(|(name, var)| format!("{name}={var}"))  // 显示变量名
                    .collect::<Vec<_>>()
                    .join(", ");
                lines.push(vec!["    • Env HTTP headers: ".into(), display.into()].into());
            }
        }
    }
    // ...
}
```

### 环境变量脱敏函数

```rust
// codex_utils_cli::format_env_display
pub fn format_env_display(
    env: Option<&HashMap<String, String>>,
    env_vars: &[String],
) -> String {
    // 合并 env 和 env_vars 中的变量
    // 敏感值替换为 *****
    // 返回格式化字符串
}
```

### 测试场景

```rust
// history_cell.rs:2871-2962
#[tokio::test]
async fn mcp_tools_output_masks_sensitive_values() {
    let mut config = test_config().await;
    
    // 配置 Stdio 服务器，包含敏感 env
    let mut env = HashMap::new();
    env.insert("TOKEN".to_string(), "secret".to_string());
    let stdio_config = McpServerConfig {
        transport: McpServerTransportConfig::Stdio {
            command: "docs-server".to_string(),
            args: vec![],
            env: Some(env),
            env_vars: vec!["APP_TOKEN".to_string()],
            cwd: None,
        },
        // ...
    };
    
    // 配置 HTTP 服务器，包含敏感 headers
    let mut headers = HashMap::new();
    headers.insert("Authorization".to_string(), "Bearer secret".to_string());
    let http_config = McpServerConfig {
        transport: McpServerTransportConfig::StreamableHttp {
            url: "https://example.com/mcp".to_string(),
            bearer_token_env_var: Some("MCP_TOKEN".to_string()),
            http_headers: Some(headers),
            env_http_headers: Some(env_headers),
        },
        // ...
    };
    
    // 验证敏感值被脱敏
    let cell = new_mcp_tools_output(&config, tools, ..., &auth_statuses);
    let rendered = render_lines(&cell.display_lines(120)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 输出格式

```
/mcp

🔌  MCP Tools

  • docs
    • Status: enabled
    • Auth: Unsupported
    • Command: docs-server
    • Env: TOKEN=*****, APP_TOKEN=*****
    • Tools: list
    • Resources: (none)
    • Resource templates: (none)

  • http
    • Status: enabled
    • Auth: Unsupported
    • URL: https://example.com/mcp
    • HTTP headers: Authorization=*****
    • Env HTTP headers: X-API-Key=API_KEY_ENV
    • Tools: ping
    • Resources: (none)
    • Resource templates: (none)
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | MCP 工具输出展示，测试位于 line 2871-2962 |
| `codex-rs/core/src/config/types.rs` | `McpServerTransportConfig` 定义 |
| `codex-utils-cli/src/format_env_display.rs` | 环境变量脱敏格式化 |
| `codex-protocol/src/mcp.rs` | MCP 协议类型定义 |

### 脱敏流程

```
/mcp 命令执行
    ↓
new_mcp_tools_output(config, tools, resources, templates, auth_statuses)
    ↓
遍历 effective_servers
    ↓
match transport:
    Stdio:
        format_env_display(env, env_vars)
            ↓
            敏感值 → "*****"
    StreamableHttp:
        http_headers: {name}=*****
        env_http_headers: {name}={var_name}
    ↓
构建 PlainHistoryCell
    ↓
渲染脱敏后的配置
```

## 依赖与外部交互

### 外部依赖

- `codex_core::config::Config`: 配置管理
- `codex_core::mcp::McpManager`: MCP 服务器管理
- `codex_protocol::mcp::{Tool, Resource, ResourceTemplate}`: MCP 类型

### 内部工具

```rust
// codex_utils_cli::format_env_display
pub fn format_env_display(
    env: Option<&HashMap<String, String>>,
    env_vars: &[String],
) -> String;
```

## 风险、边界与改进建议

### 潜在风险

1. **脱敏不完全**：新类型的敏感字段可能被遗漏
2. **误脱敏**：非敏感值被错误识别为敏感值
3. **信息泄露**：通过变量名可能推断敏感信息用途

### 边界情况

1. **空敏感值**：`TOKEN=` 的处理
2. **特殊字符**：敏感值中包含特殊字符的转义
3. **长敏感值**：极长的令牌值的截断展示
4. **多行敏感值**：包含换行符的敏感值

### 改进建议

1. **增强脱敏规则**：
   - 基于正则表达式的敏感键名匹配（`(?i)(token|key|secret|password)`）
   - 值模式检测（高熵字符串、JWT 格式等）
2. **可配置脱敏**：
   - 允许用户配置哪些字段需要脱敏
   - 提供 "显示敏感值" 的确认选项
3. **审计日志**：
   - 记录敏感值查看操作
   - 通知管理员敏感配置访问
4. **安全增强**：
   - 内存中敏感值加密存储
   - 自动清理敏感值的屏幕缓冲区
5. **用户体验**：
   - 提供 "复制值" 按钮（带确认）
   - 显示敏感值长度提示（如 "***** (32 chars)"）
6. **合规性**：
   - 符合 SOC2、GDPR 等合规要求
   - 支持敏感数据分类标签

### 相关测试

- `empty_mcp_output`：无 MCP 服务器配置场景
- 其他配置展示测试

### 安全最佳实践

```rust
// 建议的敏感键名匹配模式
const SENSITIVE_KEY_PATTERNS: &[&str] = &[
    r"(?i)password",
    r"(?i)secret",
    r"(?i)token",
    r"(?i)key$",
    r"(?i)api[_-]?key",
    r"(?i)bearer",
    r"(?i)authorization",
    r"(?i)private",
    r"(?i)credential",
];

// JWT 检测
const JWT_PATTERN: &str = r"^[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]{2,}$";
```
