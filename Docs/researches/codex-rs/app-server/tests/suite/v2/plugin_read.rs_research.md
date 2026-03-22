# plugin_read.rs 研究文档

## 场景与职责

`plugin_read.rs` 是 Codex App Server v2 API 的集成测试文件，专注于**插件详情读取（Plugin Read）**功能的端到端测试。与 `plugin_list` 提供插件列表概览不同，`plugin_read` 提供单个插件的完整详细信息，包括技能（Skills）、应用（Apps）、MCP 服务器等组件的详细内容。

该测试文件的核心职责包括：
1. 验证插件详情查询返回完整的插件信息
2. 验证插件包内容（bundle contents）正确解析
3. 验证插件界面元数据（interface metadata）正确返回
4. 验证向后兼容性（如 `defaultPrompt` 字符串格式）
5. 验证错误处理（插件不存在、清单缺失等）

## 功能点目的

### 1. 完整插件详情查询 (`plugin_read_returns_plugin_details_with_bundle_contents`)
- **目的**：验证 `plugin/read` API 返回插件的完整详细信息
- **业务价值**：
  - 客户端可以展示插件详情页面
  - 支持插件管理（启用/禁用、配置）
  - 显示插件包含的技能、应用和 MCP 服务器
- **关键验证点**：
  - 基本信息：`marketplace_name`, `marketplace_path`, `id`, `name`
  - 状态信息：`installed`, `enabled`, `install_policy`, `auth_policy`
  - 界面元数据：`display_name`, `category`, `default_prompt` 等
  - 技能列表：解析 `skills/` 目录下的 `SKILL.md` 文件
  - 应用列表：解析 `.app.json` 文件
  - MCP 服务器：解析 `.mcp.json` 文件

### 2. 向后兼容 (`plugin_read_accepts_legacy_string_default_prompt`)
- **目的**：验证 `defaultPrompt` 字段支持旧版字符串格式
- **业务价值**：保持与旧插件的兼容性
- **关键验证点**：
  - 字符串 `"prompt"` 转换为 `["prompt"]`
  - 数组格式保持不变

### 3. 插件不存在处理 (`plugin_read_returns_invalid_request_when_plugin_is_missing`)
- **目的**：验证查询不存在的插件返回适当的错误
- **业务价值**：提供清晰的错误反馈
- **关键验证点**：
  - 错误码：`-32600`（Invalid Request）
  - 错误消息包含 `plugin \`{name}\` was not found`

### 4. 清单缺失处理 (`plugin_read_returns_invalid_request_when_plugin_manifest_is_missing`)
- **目的**：验证插件目录存在但 `plugin.json` 缺失时返回错误
- **业务价值**：确保插件完整性检查
- **关键验证点**：
  - 错误码：`-32600`
  - 错误消息包含 `missing or invalid .codex-plugin/plugin.json`

## 具体技术实现

### 核心数据结构

#### PluginReadParams（请求参数）
```rust
pub struct PluginReadParams {
    pub marketplace_path: AbsolutePathBuf,  // 市场配置文件路径
    pub plugin_name: String,                 // 插件名称
}
```

#### PluginReadResponse（响应）
```rust
pub struct PluginReadResponse {
    pub plugin: PluginDetail,
}
```

#### PluginDetail（插件详情）
```rust
pub struct PluginDetail {
    pub marketplace_name: String,
    pub marketplace_path: AbsolutePathBuf,
    pub summary: ConfiguredMarketplacePlugin,  // 包含基本信息的摘要
    pub description: Option<String>,           // 详细描述
    pub skills: Vec<SkillMetadata>,            // 技能列表
    pub apps: Vec<AppMetadata>,                // 应用列表
    pub mcp_servers: Vec<String>,              // MCP 服务器名称列表
}
```

#### SkillMetadata（技能元数据）
```rust
pub struct SkillMetadata {
    pub name: String,           // 格式: "{plugin}:{skill}"
    pub description: String,    // 从 SKILL.md 解析
    // ... 其他字段
}
```

#### AppMetadata（应用元数据）
```rust
pub struct AppMetadata {
    pub id: String,
    pub name: String,
    pub install_url: Option<String>,  // 格式: "https://chatgpt.com/apps/{app}/{id}"
    // ... 其他字段
}
```

### 插件包结构

插件目录预期结构：
```
{plugin_root}/
├── .codex-plugin/
│   └── plugin.json          # 插件清单（必需）
├── skills/
│   └── {skill_name}/
│       └── SKILL.md         # 技能定义
├── .app.json                # 应用配置（可选）
└── .mcp.json                # MCP 服务器配置（可选）
```

### 文件解析流程

#### plugin.json（插件清单）
```json
{
  "name": "demo-plugin",
  "description": "Longer manifest description",
  "interface": {
    "displayName": "Plugin Display Name",
    "shortDescription": "Short description",
    "longDescription": "Long description",
    "developerName": "OpenAI",
    "category": "Productivity",
    "capabilities": ["Interactive", "Write"],
    "websiteURL": "https://openai.com/",
    "defaultPrompt": ["Prompt 1", "Prompt 2"],
    "brandColor": "#3B82F6",
    "composerIcon": "./assets/icon.png",
    "logo": "./assets/logo.png",
    "screenshots": ["./assets/screenshot1.png"]
  }
}
```

#### SKILL.md（技能定义）
```markdown
---
name: thread-summarizer
description: Summarize email threads
---

# Thread Summarizer
```

#### .app.json（应用配置）
```json
{
  "apps": {
    "gmail": {
      "id": "gmail"
    }
  }
}
```

#### .mcp.json（MCP 服务器配置）
```json
{
  "mcpServers": {
    "demo": {
      "command": "demo-server"
    }
  }
}
```

### 路径解析

#### 资产路径（Assets）
- 相对路径基于插件根目录解析
- 转换为绝对路径返回给客户端
- 示例：`"./assets/icon.png"` → `{plugin_root}/assets/icon.png`

#### 应用安装 URL
- 格式：`https://chatgpt.com/apps/{app_name}/{app_id}`
- 从 `.app.json` 中的应用 ID 构造

## 关键代码路径与文件引用

### 协议定义
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `PluginReadParams`, `PluginReadResponse`, `PluginDetail` 定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | `ClientRequest::PluginRead` 枚举 |

### 核心实现
| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/plugins/manager.rs` | `PluginsManager::read_plugin()` 实现 |
| `codex-rs/core/src/plugins/manifest.rs` | `load_plugin_manifest()` 插件清单加载 |
| `codex-rs/core/src/skills/loader.rs` | 技能加载和解析 |

### API 实现
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/message_processor.rs` | `plugin/read` 请求处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 插件详情查询实现 |

### 测试支持
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/common/mcp_process.rs` | `send_plugin_read_request` 辅助方法 |

## 依赖与外部交互

### 内部依赖
```rust
use codex_app_server_protocol::{
    PluginAuthPolicy, PluginInstallPolicy, PluginReadParams,
    PluginReadResponse, JSONRPCResponse, RequestId,
};
use codex_utils_absolute_path::AbsolutePathBuf;
```

### 关键类型
```rust
use codex_core::plugins::{
    PluginDetail,              // 插件详情
    ConfiguredMarketplacePlugin, // 插件摘要
    PluginManifestInterface,   // 界面元数据
};
use codex_core::skills::SkillMetadata;  // 技能元数据
```

### 测试基础设施
- **TempDir**：临时目录管理
- **McpProcess**：MCP 测试客户端
- **tokio::time::timeout**：异步超时控制

## 风险、边界与改进建议

### 风险点

1. **文件解析失败**
   - `SKILL.md`、`.app.json`、`.mcp.json` 格式错误可能导致解析失败
   - **风险**：部分文件错误可能导致整个插件读取失败
   - **建议**：实现容错解析，跳过无效文件并记录警告

2. **路径安全问题**
   - 资产路径可能包含 `..` 等序列
   - **风险**：路径遍历攻击
   - **建议**：严格验证资产路径在插件目录内

3. **性能问题**
   - 大型插件（多技能、多应用）可能导致读取缓慢
   - **风险**：阻塞其他请求
   - **建议**：添加超时和分页支持

### 边界情况

1. **空插件包**
   - 插件目录存在但无技能、应用或 MCP 服务器
   - **建议**：测试空列表处理

2. **重复名称**
   - 多个技能或应用使用相同名称
   - **建议**：定义重复处理策略（去重或报错）

3. **循环引用**
   - 技能文件可能通过 frontmatter 引用其他资源
   - **建议**：添加引用深度限制

4. **编码问题**
   - 文件可能使用不同编码（UTF-8、UTF-16 等）
   - **建议**：统一使用 UTF-8，检测并转换其他编码

### 改进建议

1. **缓存机制**
   - 插件详情读取涉及多个文件 I/O
   - **建议**：添加缓存层，减少重复读取

2. **增量更新**
   - 当前每次读取都解析所有文件
   - **建议**：支持基于文件修改时间的增量更新

3. **验证增强**
   - 添加 JSON Schema 验证
   - 提供更详细的验证错误信息

4. **国际化支持**
   - 当前界面元数据仅支持英文
   - **建议**：添加多语言支持

5. **版本兼容性**
   - 插件清单可能有不同版本
   - **建议**：实现版本检测和迁移逻辑

6. **遥测**
   - 记录插件读取频率和耗时
   - 帮助识别性能瓶颈

7. **API 扩展**
   - 添加批量读取接口（一次读取多个插件）
   - 支持条件过滤（如仅读取特定类型的组件）
