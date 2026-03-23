# config.md 研究文档

## 场景与职责

config.md 是 Codex CLI 项目的配置文档，提供全面的配置选项说明。该文档涵盖了从基础配置到高级配置的各个方面，包括 MCP 服务器连接、通知、SQLite 状态数据库、自定义 CA 证书等。

**适用场景：**
- 用户需要配置 Codex CLI 的行为
- 开发者需要了解配置选项的详细说明
- 系统管理员需要配置企业环境（代理、自定义证书等）

## 功能点目的

### 1. 配置文档入口
- 提供基础、高级配置和完整配置参考的链接
- 指向 OpenAI 开发者门户的官方文档

### 2. MCP 服务器连接
- **配置位置**：`~/.codex/config.toml`
- **功能**：允许 Codex 连接到外部的 MCP（Model Context Protocol）服务器
- **文档**：https://developers.openai.com/codex/config-reference

### 3. Apps（Connectors）功能
- **使用方式**：在 composer 中使用 `$` 插入 ChatGPT connector
- **命令**：`/apps` 列出可用和已安装的应用
- **显示规则**：已连接的应用优先显示并标记为已连接

### 4. 通知钩子（Notify）
- **功能**：代理完成一轮操作后运行通知钩子
- **配置**：参见官方配置参考
- **客户端标识**：TUI 报告 `codex-tui`，app server 报告 `clientInfo.name`

### 5. JSON Schema
- **位置**：`codex-rs/core/config.schema.json`
- **用途**：`config.toml` 的 JSON Schema 定义

### 6. SQLite 状态数据库
- **配置键**：`sqlite_home`
- **环境变量**：`CODEX_SQLITE_HOME`
- **默认值**：
  - WorkspaceWrite 沙盒会话：临时目录
  - 其他模式：`CODEX_HOME`

### 7. 自定义 CA 证书
- **环境变量**：`CODEX_CA_CERTIFICATE`
- **回退**：`SSL_CERT_FILE`
- **系统证书**：如果以上都未设置，使用系统根证书
- **优先级**：`CODEX_CA_CERTIFICATE` > `SSL_CERT_FILE` > 系统证书
- **支持特性**：
  - 多证书 PEM 文件
  - OpenSSL `TRUSTED CERTIFICATE` 标签
  - 忽略 `X509 CRL` 部分
  - 空/不可读/格式错误的文件会报告用户友好的错误

### 8. Notices（通知标志）
- **存储位置**：`[notice]` 配置表
- **用途**：存储"不再显示"的 UI 提示标志

### 9. Plan 模式默认值
- **配置键**：`plan_mode_reasoning_effort`
- **功能**：设置 Plan 模式的默认推理努力级别
- **默认值**：`medium`
- **特殊值**：`none` 表示"无推理"

### 10. Realtime 启动指令
- **配置键**：`experimental_realtime_start_instructions`
- **功能**：替换 realtime 激活时的内置开发者消息
- **注意**：仅影响提示历史中的消息，不影响后端设置

### 11. Ctrl+C/Ctrl+D 退出提示
- **功能**：使用约 1 秒的双击提示（`ctrl + c again to quit`）

## 具体技术实现

### 配置加载优先级

```
1. 命令行参数（最高优先级）
2. 环境变量
3. 配置文件 (~/.codex/config.toml)
4. 默认值（最低优先级）
```

### 配置结构示例

```toml
[features]
js_repl = true

[tui]
alternate_screen = "auto"

[notice]
some_flag = true

# 其他配置...
sqlite_home = "/path/to/sqlite"
plan_mode_reasoning_effort = "medium"
experimental_realtime_start_instructions = "..."
```

### CA 证书加载流程

```
检查 CODEX_CA_CERTIFICATE
    ↓
如果设置：加载指定 PEM 文件
    ↓
如果未设置：检查 SSL_CERT_FILE
    ↓
如果设置：加载 SSL_CERT_FILE
    ↓
如果都未设置：使用系统根证书
```

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/config.md` | 本文档 |
| `/home/sansha/Github/codex/codex-rs/core/config.schema.json` | JSON Schema 定义 |
| `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` | 配置类型定义（推测） |
| `/home/sansha/Github/codex/codex-rs/core/src/config.rs` | 配置解析实现（推测） |

### 引用关系

- 官方文档链接：
  - https://developers.openai.com/codex/config-basic
  - https://developers.openai.com/codex/config-advanced
  - https://developers.openai.com/codex/config-reference

## 依赖与外部交互

### 内部依赖

1. **配置解析库**
   - TOML 解析
   - JSON Schema 验证

2. **证书处理**
   - OpenSSL 或 rustls 用于证书加载
   - PEM 文件解析

3. **SQLite**
   - 状态数据库存储

### 外部依赖

1. **OpenAI 开发者门户**
   - 详细配置文档

2. **MCP 服务器**
   - 外部工具服务器连接

3. **企业代理/网关**
   - 可能需要自定义 CA 证书

## 风险、边界与改进建议

### 潜在风险

1. **证书配置错误**
   - 自定义 CA 证书配置错误会导致连接失败
   - 建议：提供证书验证工具和详细错误信息

2. **配置版本兼容性**
   - 配置选项可能随版本变化
   - 建议：在 Schema 中包含版本信息

3. **敏感信息泄露**
   - 配置文件中可能包含敏感信息（API 密钥等）
   - 建议：提供配置文件权限检查

### 边界情况

1. **多配置文件**
   - 项目级 vs 用户级配置的优先级

2. **环境变量覆盖**
   - 环境变量与配置文件的冲突处理

3. **动态配置更新**
   - 运行时配置变更的支持

### 改进建议

1. **配置验证工具**
   - 提供 `codex config validate` 命令
   - 检查配置语法和值的有效性

2. **配置模板生成**
   - 提供 `codex config init` 命令
   - 交互式生成配置文件

3. **文档增强**
   - 添加更多配置示例
   - 提供常见场景的完整配置

4. **安全配置**
   - 敏感配置项加密支持
   - 配置文件权限检查

5. **配置热重载**
   - 支持运行时配置更新
   - 提供配置变更通知
