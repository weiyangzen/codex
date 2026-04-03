# MCP Tools Output Masks Sensitive Values - Technical Research Document

## Snapshot File
`codex_tui_app_server__history_cell__tests__mcp_tools_output_masks_sensitive_values.snap`

## Snapshot Content
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

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **`/mcp` 命令输出中敏感值的脱敏处理**。当显示 MCP 服务器配置时，敏感信息（如 Token、API Key）应该被掩码显示。

### 1.2 业务职责
- **敏感信息保护**: 脱敏显示密码、Token 等
- **配置可见性**: 显示配置项名称，隐藏具体值
- **安全合规**: 防止敏感信息泄露

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 元素 | 原始值 | 显示值 | 目的 |
|------|--------|--------|------|
| Token | `TOKEN=abc123` | `TOKEN=*****` | 保护访问令牌 |
| HTTP Header | `Authorization=Bearer xxx` | `Authorization=*****` | 保护认证信息 |
| API Key | `X-API-Key=secret` | `X-API-Key=API_KEY_ENV` | 显示环境变量名 |

### 2.2 脱敏策略
- 完全替换为 `*****`
- 环境变量引用保持可见
- 只掩码值，保留键名

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 脱敏逻辑
```rust
fn mask_sensitive_value(key: &str, value: &str) -> String {
    // 环境变量引用不脱敏
    if value.starts_with('$') || value.starts_with("$") {
        return value.to_string();
    }
    
    // 敏感键名列表
    let sensitive_keys = ["token", "password", "secret", "key", "auth"];
    
    if sensitive_keys.iter().any(|k| key.to_lowercase().contains(k)) {
        format!("{}=*****", key)
    } else {
        format!("{}={}", key, value)
    }
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/history_cell.rs` | MCP 工具输出单元格 |

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 安全考虑
| 敏感项 | 处理方式 |
|--------|---------|
| Token | 完全掩码 |
| Password | 完全掩码 |
| API Key | 完全掩码 |
| 环境变量名 | 显示名称，不显示值 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 风险
| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 误脱敏 | 非敏感值被误脱敏 | 精确匹配敏感键名 |
| 漏脱敏 | 敏感值未被脱敏 | 维护敏感键名列表 |

### 6.2 改进建议
1. **配置化**: 允许用户配置敏感键名
2. **审计日志**: 记录敏感信息访问
3. **临时显示**: 支持临时显示真实值

---

## 7. 相关文档链接

- [MCP Tools Output](../codex_tui_app_server__history_cell__tests__mcp_tools_output_from_statuses_renders_status_only_servers.snap_research.md)
