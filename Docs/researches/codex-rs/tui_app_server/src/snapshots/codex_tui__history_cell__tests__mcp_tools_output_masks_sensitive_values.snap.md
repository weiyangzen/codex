# MCP Tools 输出敏感信息脱敏测试快照研究文档

## 场景与职责

本快照测试验证 MCP (Model Context Protocol) 工具输出功能中的**敏感信息安全脱敏机制**。当用户执行 `/mcp` 命令查看已配置的 MCP 服务器列表时，系统需要展示服务器配置详情，但必须对敏感信息（如认证令牌、API 密钥等）进行脱敏处理，以防止凭据泄露。

该功能属于 TUI (Terminal User Interface) 的历史记录单元格渲染系统，负责将 MCP 服务器配置以用户友好的格式展示，同时确保安全性。

## 功能点目的

### 核心功能
1. **敏感信息脱敏**：自动检测并掩码处理环境变量值、HTTP 头中的敏感信息
2. **多传输协议支持**：支持 Stdio 和 StreamableHTTP 两种 MCP 服务器传输配置展示
3. **结构化信息展示**：清晰展示服务器状态、认证状态、命令/URL、环境变量、工具列表、资源等

### 安全目标
- 环境变量值显示为 `*****` 掩码
- HTTP 头值显示为 `*****` 掩码
- 保留环境变量名和头名称用于识别
- 区分直接配置的 HTTP 头和通过环境变量引用的 HTTP 头

## 具体技术实现

### 数据结构

```rust
// MCP 服务器传输配置枚举
types::McpServerTransportConfig {
    Stdio {
        command: String,
        args: Vec<String>,
        env: Option<HashMap<String, String>>,  // 敏感：需要脱敏
        env_vars: Vec<String>,
        cwd: Option<PathBuf>,
    },
    StreamableHttp {
        url: String,
        http_headers: Option<HashMap<String, String>>,      // 敏感：需要脱敏
        env_http_headers: Option<HashMap<String, String>>,  // 环境变量名，不脱敏
        bearer_token_env_var: Option<String>,
    }
}
```

### 关键渲染逻辑

位于 `codex-rs/tui/src/history_cell.rs` 的 `new_mcp_tools_output` 函数（行 1800-1965）：

```rust
pub(crate) fn new_mcp_tools_output(
    config: &Config,
    tools: HashMap<String, codex_protocol::mcp::Tool>,
    resources: HashMap<String, Vec<Resource>>,
    resource_templates: HashMap<String, Vec<ResourceTemplate>>,
    auth_statuses: &HashMap<String, McpAuthStatus>,
) -> PlainHistoryCell
```

### 脱敏实现细节

1. **Stdio 环境变量脱敏**（行 1872-1875）：
```rust
let env_display = format_env_display(env.as_ref(), env_vars);
if env_display != "-" {
    lines.push(vec!["    • Env: ".into(), env_display.into()].into());
}
```
使用 `format_env_display` 函数将值替换为 `*****`

2. **HTTP 头脱敏**（行 1884-1895）：
```rust
if let Some(headers) = http_headers.as_ref() && !headers.is_empty() {
    let mut pairs: Vec<_> = headers.iter().collect();
    pairs.sort_by(|(a, _), (b, _)| a.cmp(b));
    let display = pairs
        .into_iter()
        .map(|(name, _)| format!("{name}=*****"))  // 值脱敏
        .collect::<Vec<_>>()
        .join(", ");
    lines.push(vec!["    • HTTP headers: ".into(), display.into()].into());
}
```

3. **环境变量 HTTP 头不脱敏**（行 1896-1907）：
```rust
if let Some(headers) = env_http_headers.as_ref() && !headers.is_empty() {
    let display = pairs
        .into_iter()
        .map(|(name, var)| format!("{name}={var}"))  // 显示变量名
        .collect::<Vec<_>>()
        .join(", ");
    lines.push(vec!["    • Env HTTP headers: ".into(), display.into()].into());
}
```

### 测试用例构造

位于 `history_cell.rs` 测试模块（行 2871-2962）：

```rust
#[tokio::test]
async fn mcp_tools_output_masks_sensitive_values() {
    // 配置 Stdio 服务器，包含敏感 TOKEN
    let mut env = HashMap::new();
    env.insert("TOKEN".to_string(), "secret".to_string());
    let stdio_config = McpServerConfig {
        transport: McpServerTransportConfig::Stdio {
            command: "docs-server".to_string(),
            env: Some(env),  // TOKEN=secret
            env_vars: vec!["APP_TOKEN".to_string()],
            ...
        },
        ...
    };
    
    // 配置 HTTP 服务器，包含敏感头
    let mut headers = HashMap::new();
    headers.insert("Authorization".to_string(), "Bearer secret".to_string());
    let http_config = McpServerConfig {
        transport: McpServerTransportConfig::StreamableHttp {
            url: "https://example.com/mcp".to_string(),
            http_headers: Some(headers),  // Authorization=Bearer secret
            env_http_headers: Some(env_headers),  // X-API-Key=API_KEY_ENV
            ...
        },
        ...
    };
}
```

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格渲染，包含 `new_mcp_tools_output` 函数 |
| `codex-core/src/config/types.rs` | MCP 配置类型定义（McpServerConfig, McpServerTransportConfig） |
| `codex-utils-cli/src/format_env_display.rs` | 环境变量脱敏格式化工具 |

### 关键函数
| 函数 | 位置 | 职责 |
|-----|------|------|
| `new_mcp_tools_output` | `history_cell.rs:1800` | 主渲染函数，生成 MCP 工具输出 |
| `format_env_display` | `codex-utils-cli` | 格式化环境变量，脱敏敏感值 |
| `empty_mcp_output` | `history_cell.rs:1780` | 空 MCP 配置时的默认输出 |

### 快照输出示例
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

## 依赖与外部交互

### 内部依赖
- `codex_core::config::Config` - 应用配置
- `codex_core::config::types::McpServerTransportConfig` - MCP 传输配置
- `codex_core::mcp::McpManager` - MCP 管理器
- `codex_protocol::protocol::McpAuthStatus` - 认证状态枚举
- `codex_utils_cli::format_env_display::format_env_display` - 脱敏工具

### 外部协议
- **MCP (Model Context Protocol)**: OpenAI 定义的协议，用于扩展 Codex 功能
- **传输协议**: Stdio (本地进程) 和 StreamableHTTP (远程 HTTP)

### 数据流
```
Config (mcp_servers)
    ↓
McpManager::effective_servers()
    ↓
new_mcp_tools_output() → 脱敏处理 → PlainHistoryCell
    ↓
TUI 渲染
```

## 风险、边界与改进建议

### 安全风险
1. **脱敏规则不完善**: 当前仅对特定字段脱敏，新型敏感信息可能泄露
2. **日志泄露**: 确保脱敏后的数据不会在其他日志中泄露原始值
3. **截图分享**: 用户截图分享时，脱敏机制是最后一道防线

### 边界情况
1. **空值处理**: 环境变量值为空字符串时的展示
2. **特殊字符**: 环境变量名或头名称包含特殊字符的转义
3. **超长值**: 极长的环境变量值在脱敏前的内存处理
4. **Unicode**: 多字节字符在脱敏时的宽度计算

### 改进建议

#### 高优先级
1. **统一脱敏框架**: 建立统一的敏感信息识别和脱敏框架，而非硬编码
   ```rust
   trait SensitiveDataMasker {
       fn mask(&self, key: &str, value: &str) -> String;
   }
   ```

2. **可配置脱敏规则**: 允许用户配置额外的敏感字段模式
   ```rust
   struct MaskingConfig {
       sensitive_keys: Vec<Regex>,  // 如 /(?i)(token|key|secret|password)/
       mask_char: char,
   }
   ```

#### 中优先级
3. **部分脱敏**: 对于长值，考虑保留前后部分字符便于调试
   ```
   Authorization=Be*****et
   ```

4. **审计日志**: 记录脱敏操作，便于安全审计

#### 低优先级
5. **交互式展示**: 支持按键展开查看完整值（需二次确认）
6. **复制保护**: 防止脱敏区域被复制粘贴

### 测试建议
1. 增加模糊测试，随机生成环境变量名/值验证脱敏
2. 增加回归测试，确保新增字段自动应用脱敏规则
3. 增加性能测试，验证大量 MCP 服务器配置时的渲染性能
