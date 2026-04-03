# SkillToolDependency.ts 研究文档

## 场景与职责

`SkillToolDependency.ts` 定义了技能工具依赖的数据结构，用于声明技能所依赖的外部工具或服务。这是 Codex 技能系统依赖管理的核心组件，确保技能所需的工具在运行时可用。

## 功能点目的

该类型用于：
1. **依赖声明**：技能声明其所需的工具依赖
2. **自动安装**：支持自动安装或配置依赖的工具
3. **传输配置**：定义工具调用的传输方式（stdio、HTTP 等）
4. **文档生成**：为技能用户提供依赖说明

## 具体技术实现

### 数据结构定义

```typescript
export type SkillToolDependency = { 
  type: string,            // 依赖类型
  value: string,           // 依赖值/标识
  description?: string,    // 描述说明
  transport?: string,      // 传输方式
  command?: string,        // 命令（stdio 传输）
  url?: string             // URL（HTTP 传输）
};
```

### 字段详解

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| type | string | 是 | 依赖类型，如 "mcp", "cli", "service" |
| value | string | 是 | 依赖标识，如工具名称或 ID |
| description | string | 否 | 依赖的描述说明 |
| transport | string | 否 | 传输协议，如 "stdio", "http", "sse" |
| command | string | 否 | stdio 传输时的启动命令 |
| url | string | 否 | HTTP 传输时的端点 URL |

### Rust 协议定义

在 `codex-rs/protocol/src/protocol.rs` 中：

```rust
#[derive(
    Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema, TS,
)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillToolDependency {
    pub r#type: String,
    pub value: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transport: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}
```

### 核心技能依赖类型

在 `codex-rs/core/src/skills/model.rs` 中：

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillToolDependency {
    pub r#type: String,
    pub value: String,
    pub description: Option<String>,
    pub transport: Option<String>,
    pub command: Option<String>,
    pub url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillDependencies {
    pub tools: Vec<SkillToolDependency>,
}
```

### SKILL.json 配置示例

```json
{
  "name": "database-helper",
  "dependencies": {
    "tools": [
      {
        "type": "mcp",
        "value": "postgres",
        "description": "PostgreSQL database access",
        "transport": "stdio",
        "command": "npx -y @modelcontextprotocol/server-postgres"
      },
      {
        "type": "cli",
        "value": "jq",
        "description": "JSON processing tool"
      },
      {
        "type": "service",
        "value": "redis",
        "description": "Redis cache server",
        "transport": "http",
        "url": "http://localhost:6379"
      }
    ]
  }
}
```

### MCP 依赖处理

在 `codex-rs/core/src/mcp/skill_dependencies.rs` 中：

```rust
pub async fn resolve_skill_mcp_dependencies(
    skill: &SkillMetadata,
    mcp_manager: &McpManager,
) -> Result<Vec<McpServerConfig>, SkillDependencyError> {
    let mut configs = Vec::new();
    
    if let Some(deps) = &skill.dependencies {
        for tool_dep in &deps.tools {
            if tool_dep.r#type == "mcp" {
                let config = McpServerConfig {
                    transport: parse_transport(&tool_dep.transport, &tool_dep.command, &tool_dep.url)?,
                    // ...
                };
                configs.push(config);
            }
        }
    }
    
    Ok(configs)
}
```

### 依赖验证

```rust
pub fn validate_tool_dependency(dep: &SkillToolDependency) -> Result<(), String> {
    match dep.r#type.as_str() {
        "mcp" | "cli" | "service" => {
            // 验证必需字段
            if dep.transport.is_some() {
                match dep.transport.as_deref() {
                    Some("stdio") if dep.command.is_none() => {
                        return Err("stdio transport requires 'command'".to_string());
                    }
                    Some("http") | Some("sse") if dep.url.is_none() => {
                        return Err("http/sse transport requires 'url'".to_string());
                    }
                    _ => {}
                }
            }
            Ok(())
        }
        _ => Err(format!("Unknown dependency type: {}", dep.r#type)),
    }
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SkillToolDependency.ts`

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/protocol.rs`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 核心技能实现
- 技能模型：`codex-rs/core/src/skills/model.rs`
- 技能加载器：`codex-rs/core/src/skills/loader.rs`
- 加载器测试：`codex-rs/core/src/skills/loader_tests.rs`

### MCP 集成
- MCP 依赖：`codex-rs/core/src/mcp/skill_dependencies.rs`
- MCP 依赖测试：`codex-rs/core/src/mcp/skill_dependencies_tests.rs`

### 服务端集成
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 客户端消费
- TUI 应用：`codex-rs/tui_app_server/src/app.rs`
- 技能助手：`codex-rs/tui/src/chatwidget/skills.rs`
- TUI App Server 技能：`codex-rs/tui_app_server/src/chatwidget/skills.rs`

### 相关类型
- SkillDependencies：`codex-rs/app-server-protocol/schema/typescript/v2/SkillDependencies.ts`
- SkillMetadata：`codex-rs/app-server-protocol/schema/typescript/v2/SkillMetadata.ts`

## 依赖与外部交互

### 上游依赖
- SKILL.json：从技能配置文件中读取依赖声明
- MCP 规范：MCP 类型的依赖遵循 Model Context Protocol

### 下游消费
- MCP 管理器：配置和启动 MCP 服务器
- 工具注册：将依赖的工具注册到工具系统
- 环境检查：验证依赖工具是否可用

### 依赖类型支持

| 类型 | 说明 | 必需字段 |
|------|------|---------|
| mcp | MCP 服务器 | transport + (command \| url) |
| cli | 命令行工具 | value |
| service | 外部服务 | transport + url |

## 风险、边界与改进建议

### 边界情况
1. **循环依赖**：技能 A 依赖 B，B 又依赖 A
2. **版本冲突**：不同技能依赖同一工具的不同版本
3. **平台差异**：某些工具可能只在特定平台可用

### 潜在风险
1. **命令注入**：command 字段可能包含恶意命令
2. **网络风险**：url 可能指向恶意服务
3. **资源耗尽**：大量 MCP 服务器可能耗尽系统资源

### 改进建议
1. **版本约束**：添加版本要求字段（如 ">=1.0.0"）
2. **沙箱执行**：在隔离环境中执行依赖的命令
3. **健康检查**：定期验证依赖工具的健康状态
4. **自动安装**：支持自动安装缺失的 CLI 工具
5. **依赖图**：可视化展示技能依赖关系
6. **冲突解决**：自动检测和解决依赖冲突
