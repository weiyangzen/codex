# MCP Tools Output Masks Sensitive Values Snapshot

## 场景与职责

该快照测试验证 MCP (Model Context Protocol) 工具配置信息的显示功能，特别是敏感信息（如令牌、API 密钥等）的脱敏处理。当用户执行 `/mcp` 命令查看已配置的 MCP 服务器时，系统需要展示服务器详情，但必须保护敏感配置不被泄露。

## 功能点目的

1. **敏感信息脱敏**：自动识别并隐藏敏感配置值，如 `TOKEN=*****`、`APP_TOKEN=*****`
2. **配置透明度**：在保护敏感信息的同时，向用户展示配置的存在和结构
3. **多传输协议支持**：支持 Stdio 和 Streamable HTTP 两种 MCP 服务器传输协议的配置展示
4. **环境变量区分**：区分直接配置的环境变量值 (`env`) 和通过环境变量名引用的变量 (`env_vars`)

## 具体技术实现

### 核心脱敏函数

```rust
// codex-rs/utils/cli/src/format_env_display.rs
pub fn format_env_display(env: Option<&HashMap<String, String>>, env_vars: &[String]) -> String {
    let mut parts: Vec<String> = Vec::new();

    if let Some(map) = env {
        let mut pairs: Vec<_> = map.iter().collect();
        pairs.sort_by(|(a, _), (b, _)| a.cmp(b));
        // 将实际值替换为 *****
        parts.extend(pairs.into_iter().map(|(key, _)| format!("{key}=*****")));
    }

    if !env_vars.is_empty() {
        // env_vars 只包含变量名，同样显示为 *****
        parts.extend(env_vars.iter().map(|var| format!("{var}=*****")));
    }

    if parts.is_empty() {
        "-".to_string()
    } else {
        parts.join(", ")
    }
}
```

### MCP 工具输出渲染

```rust
// 在 history_cell.rs 中的 new_mcp_tools_output 函数
pub(crate) fn new_mcp_tools_output(
    config: &Config,
    tools: HashMap<String, Tool>,
    resources: HashMap<String, Vec<Resource>>,
    resource_templates: HashMap<String, Vec<ResourceTemplate>>,
    auth_statuses: &HashMap<String, McpAuthStatus>,
) -> PlainHistoryCell {
    // ... 渲染逻辑
    
    match &cfg.transport {
        McpServerTransportConfig::Stdio { env, env_vars, .. } => {
            let env_display = format_env_display(env.as_ref(), env_vars);
            if env_display != "-" {
                lines.push(vec!["    • Env: ".into(), env_display.into()].into());
            }
        }
        McpServerTransportConfig::StreamableHttp { http_headers, env_http_headers, .. } => {
            if let Some(headers) = http_headers.as_ref() {
                let display = pairs
                    .into_iter()
                    .map(|(name, _)| format!("{name}=*****"))
                    .collect::<Vec<_>>()
                    .join(", ");
                lines.push(vec!["    • HTTP headers: ".into(), display.into()].into());
            }
            // env_http_headers 显示实际变量名（不脱敏值，因为值在环境中）
            if let Some(headers) = env_http_headers {
                let display = pairs
                    .into_iter()
                    .map(|(name, var)| format!("{name}={var}"))
                    .collect::<Vec<_>>()
                    .join(", ");
                lines.push(vec!["    • Env HTTP headers: ".into(), display.into()].into());
            }
        }
    }
}
```

### 脱敏规则

| 配置类型 | 显示方式 | 示例 |
|---------|---------|------|
| `env` (直接值) | `KEY=*****` | `TOKEN=*****` |
| `env_vars` (变量名引用) | `VAR=*****` | `APP_TOKEN=*****` |
| `http_headers` (HTTP 头) | `Header=*****` | `Authorization=*****` |
| `env_http_headers` (环境变量引用) | `Header=$VAR` | `X-API-Key=API_KEY_ENV` |

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/utils/cli/src/format_env_display.rs` | 核心脱敏逻辑实现 |
| `codex-rs/tui/src/history_cell.rs` | MCP 工具输出渲染，调用脱敏函数 |
| `codex-rs/tui/src/history_cell.rs` (line 1799-1965) | `new_mcp_tools_output` 函数 |
| `codex-rs/tui/src/history_cell.rs` (line 2870-2962) | 对应的快照测试 |

### 数据结构

```rust
// McpServerTransportConfig 定义
pub enum McpServerTransportConfig {
    Stdio {
        command: String,
        args: Vec<String>,
        env: Option<HashMap<String, String>>,  // 直接配置的值（需脱敏）
        env_vars: Vec<String>,                  // 环境变量名（需脱敏值）
        cwd: Option<PathBuf>,
    },
    StreamableHttp {
        url: String,
        http_headers: Option<HashMap<String, String>>,      // 直接值（需脱敏）
        env_http_headers: Option<HashMap<String, String>>, // 变量名（显示名）
        bearer_token_env_var: Option<String>,
    },
}
```

## 依赖与外部交互

### 内部依赖

- **codex_utils_cli**: 提供 `format_env_display` 脱敏工具函数
- **codex_core::config**: 提供 `McpServerTransportConfig` 配置类型
- **ratatui**: TUI 渲染框架

### 安全考虑

1. **值脱敏 vs 名脱敏**：
   - 直接配置的值（`env`, `http_headers`）：键和值都显示，但值替换为 `*****`
   - 环境变量引用（`env_vars`, `env_http_headers`）：显示键和变量名，不显示实际值

2. **排序一致性**：脱敏后的输出按键名排序，确保相同配置产生相同的显示

### 测试验证

```rust
#[tokio::test]
async fn mcp_tools_output_masks_sensitive_values() {
    // 配置包含敏感信息
    env.insert("TOKEN".to_string(), "secret".to_string());
    env_vars: vec!["APP_TOKEN".to_string()],
    headers.insert("Authorization".to_string(), "Bearer secret".to_string());
    
    // 验证输出中敏感值被替换为 *****
    // 但 env_http_headers 显示变量名（不脱敏，因为值在 shell 环境中）
}
```

## 风险、边界与改进建议

### 当前风险

1. **部分信息泄露风险**：
   - `env_http_headers` 显示变量名（如 `API_KEY_ENV`），可能泄露配置模式
   - 变量名本身可能包含敏感信息（如 `PRODUCTION_SECRET_KEY`）

2. **脱敏标记一致性**：使用 `*****` 作为脱敏标记，但不同系统可能使用不同标记

3. **大小写敏感**：脱敏逻辑不处理键的大小写，如果配置使用不同大小写可能显示不一致

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| 空 env/headers | 显示 `-` | ✅ 清晰 |
| 键名为空字符串 | 显示 `=*****` | ⚠️ 可能令人困惑 |
| 值包含换行符 | 脱敏后可能显示异常 | ⚠️ 未明确处理 |
| 大量环境变量 | 全部显示，可能换行 | ⚠️ 长列表可读性差 |

### 改进建议

1. **变量名脱敏选项**：
   ```rust
   // 添加配置选项控制是否显示变量名
   pub fn format_env_display(
       env: Option<&HashMap<String, String>>, 
       env_vars: &[String],
       mask_var_names: bool,  // 新增参数
   ) -> String
   ```

2. **分级脱敏**：
   - 高敏感：完全隐藏键和值
   - 中敏感：显示键，隐藏值（当前行为）
   - 低敏感：显示键和部分值（如 `tok_*****`）

3. **可配置脱敏标记**：
   ```rust
   const MASK: &str = std::env::var("CODEX_MASK_STRING").as_deref().unwrap_or("*****");
   ```

4. **截断长列表**：
   ```rust
   const MAX_ENV_DISPLAY: usize = 10;
   // 超过限制时显示 "... and N more"
   ```

5. **审计日志**：记录脱敏信息的访问，用于安全审计

### 测试增强

当前测试仅验证快照匹配。建议增加：
- 测试不同字符集的值脱敏
- 测试极长的键/值处理
- 测试特殊字符（换行、控制字符）的处理
- 测试并发访问下的安全性
