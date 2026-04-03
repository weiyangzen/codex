# codex-rs/core/config.schema.json 研究文档

## 场景与职责

`config.schema.json` 是 Codex 配置文件 (`~/.codex/config.toml`) 的 JSON Schema 定义，用于：
- **配置验证**：确保用户配置符合预期结构
- **IDE 支持**：为编辑器提供自动补全和类型检查
- **文档生成**：作为配置选项的权威参考

该文件由 `codex-write-config-schema` 二进制工具自动生成，源数据来自 Rust 类型定义（使用 `schemars` derive 宏）。

## 功能点目的

### 1. Schema 基础结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "additionalProperties": false,
  "title": "ConfigToml",
  "type": "object"
}
```

- **Draft-07**：使用 JSON Schema Draft 7 标准
- **`additionalProperties: false`**：禁止未定义的属性，确保配置严格
- **根类型**：`ConfigToml` - 配置文件的根结构

### 2. 定义分区 (definitions)

Schema 包含 80+ 个类型定义，按功能域组织：

| 定义类别 | 示例 | 数量 |
|----------|------|------|
| 配置容器 | `ConfigToml`, `ConfigProfile` | 5+ |
| 模型/提供商 | `ModelProviderInfo`, `ReasoningEffort` | 10+ |
| 沙箱/权限 | `SandboxMode`, `FilesystemPermissionToml` | 15+ |
| TUI/UX | `Tui`, `AltScreenMode`, `NotificationMethod` | 10+ |
| 工具/集成 | `ToolsToml`, `RawMcpServerConfig` | 10+ |
| 实验性功能 | `RealtimeToml`, `MemoriesToml` | 8+ |
| 其他 | `OtelConfigToml`, `SkillsConfig` | 15+ |

### 3. 核心配置属性

根 `ConfigToml` 包含 80+ 个顶级属性：

```json
{
  "properties": {
    "model": { "type": "string" },
    "approval_policy": { "$ref": "#/definitions/AskForApproval" },
    "sandbox_mode": { "$ref": "#/definitions/SandboxMode" },
    "features": { ... },
    "mcp_servers": { ... },
    // ... 更多
  }
}
```

## 具体技术实现

### 类型定义详解

#### 3.1 绝对路径类型

```json
"AbsolutePathBuf": {
  "description": "A path that is guaranteed to be absolute and normalized...",
  "type": "string"
}
```

- 包装类型，确保路径绝对且规范化
- 反序列化时需要设置基础路径（通过 `AbsolutePathBufGuard`）

#### 3.2 枚举类型

```json
"SandboxMode": {
  "enum": ["read-only", "workspace-write", "danger-full-access"],
  "type": "string"
}
```

- 沙箱模式的三个选项
- 字符串枚举，大小写敏感

#### 3.3 复杂对象

```json
"ModelProviderInfo": {
  "additionalProperties": false,
  "properties": {
    "name": { "type": "string" },
    "base_url": { "type": "string" },
    "env_key": { "type": "string" },
    "requires_openai_auth": { "type": "boolean", "default": false },
    // ... 更多属性
  },
  "required": ["name"]
}
```

- 自定义模型提供商配置
- 只有 `name` 是必需的

#### 3.4 OneOf/AnyOf 联合类型

```json
"AskForApproval": {
  "oneOf": [
    { "enum": ["untrusted"], "type": "string" },
    { "enum": ["on-failure"], "type": "string" },
    { "enum": ["on-request"], "type": "string" },
    { "enum": ["never"], "type": "string" },
    {
      "additionalProperties": false,
      "properties": {
        "granular": { "$ref": "#/definitions/GranularApprovalConfig" }
      },
      "required": ["granular"],
      "type": "object"
    }
  ]
}
```

- 支持字符串简写或对象形式
- `"untrusted"`, `"on-failure"`, `"on-request"`, `"never"` 或 `{ "granular": {...} }`

### 4. 特殊配置域

#### 4.1 特性标志 (Features)

```json
"features": {
  "additionalProperties": false,
  "properties": {
    "apply_patch_freeform": { "type": "boolean" },
    "apps": { "type": "boolean" },
    "artifact": { "type": "boolean" },
    // ... 50+ 个特性标志
  }
}
```

- 50+ 个实验性和稳定特性开关
- 包括：`multi_agent`, `memories`, `web_search`, `realtime_conversation` 等

#### 4.2 MCP 服务器配置

```json
"RawMcpServerConfig": {
  "properties": {
    "command": { "type": "string" },
    "args": { "type": "array", "items": { "type": "string" } },
    "env": { "type": "object" },
    "url": { "type": "string" },
    "bearer_token": { "type": "string" },
    // ...
  }
}
```

- 支持 stdio 和 HTTP 两种传输方式
- OAuth 配置：`scopes`, `oauth_resource`

#### 4.3 权限配置

```json
"PermissionProfileToml": {
  "properties": {
    "filesystem": { "$ref": "#/definitions/FilesystemPermissionsToml" },
    "network": { "$ref": "#/definitions/NetworkToml" }
  }
}
```

- 文件系统权限：读/写/无访问
- 网络权限：域名白名单/黑名单、代理设置

#### 4.4 TUI 配置

```json
"Tui": {
  "properties": {
    "alternate_screen": { "$ref": "#/definitions/AltScreenMode" },
    "animations": { "type": "boolean", "default": true },
    "notifications": { "$ref": "#/definitions/Notifications" },
    "theme": { "type": "string" }
  }
}
```

- 备用屏幕模式（解决 Zellij 等终端复用器的滚动问题）
- 动画、通知、主题设置

### 5. 默认值处理

```json
"approval_policy": {
  "default": null,
  "allOf": [{ "$ref": "#/definitions/AskForApproval" }]
}
```

- 使用 `default` 关键字指定默认值
- `null` 表示使用系统默认

## 关键代码路径与文件引用

### Schema 生成流程

```
Rust 类型定义
    ↓ (schemars::JsonSchema derive)
codex-rs/core/src/config/types.rs
    ↓
codex-rs/core/src/config/schema.rs::config_schema()
    ↓
codex-rs/core/src/bin/config_schema.rs (二进制)
    ↓ (cargo run --bin codex-write-config-schema)
codex-rs/core/config.schema.json
```

### 源文件位置

| 文件 | 用途 |
|------|------|
| `src/config/types.rs` | TOML 配置类型定义 |
| `src/config/schema.rs` | Schema 生成逻辑 |
| `src/config/mod.rs` | 配置加载和验证 |
| `src/features.rs` | 特性标志定义 |
| `src/bin/config_schema.rs` | Schema 生成二进制 |

### 关键类型定义

```rust
// src/config/types.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct ConfigToml {
    pub model: Option<String>,
    pub approval_policy: Option<AskForApproval>,
    pub sandbox_mode: Option<SandboxMode>,
    pub features: Option<FeaturesToml>,
    pub mcp_servers: HashMap<String, RawMcpServerConfig>,
    // ...
}
```

### 生成命令

```bash
# justfile
cargo run -p codex-core --bin codex-write-config-schema
```

## 依赖与外部交互

### 生成依赖

| Crate | 用途 |
|-------|------|
| `schemars` | 从 Rust 类型生成 JSON Schema |
| `serde` | 序列化/反序列化 |

### 消费方

| 工具 | 用途 |
|------|------|
| VS Code / IDE | 配置文件的自动补全和验证 |
| `codex-core` | 运行时配置验证 |
| 文档生成 | 配置参考文档 |

### Schema 特性

| 特性 | 说明 |
|------|------|
| `deny_unknown_fields` | 拒绝未知字段，防止拼写错误 |
| `additionalProperties: false` | 严格模式，不允许额外属性 |
| `default` | 指定默认值 |
| `description` | 字段文档说明 |

## 风险、边界与改进建议

### 维护风险

1. **手动同步需求**：
   - 每次修改配置类型后必须运行 `just write-config-schema`
   - AGENTS.md 规则："If you change `ConfigToml` or nested config types, run `just write-config-schema`"
   - 风险：开发者可能忘记更新，导致 Schema 与代码不同步

2. **Schema 体积**：
   - 文件大小：~76KB
   - 定义数量：80+
   - 可能影响 IDE 性能

### 类型限制

1. **绝对路径处理**：
   ```json
   "AbsolutePathBuf": { "type": "string" }
   ```
   - Schema 层面只能验证为字符串
   - 绝对路径验证在 Rust 代码中完成

2. **复杂联合类型**：
   - `oneOf` 在 JSON Schema 中验证错误消息不友好
   - 用户可能困惑于为什么配置被拒绝

### 改进建议

1. **自动化检查**：
   ```bash
   # CI 检查 Schema 是否最新
   just write-config-schema
   git diff --exit-code config.schema.json
   ```

2. **Schema 版本化**：
   ```json
   {
     "$schema": "...",
     "$id": "https://openai.com/codex/config.schema.json#v1.2.3"
   }
   ```

3. **分组文档**：
   - 当前所有定义平铺
   - 建议按功能域分组（使用 `definitions` 嵌套）

4. **示例值**：
   ```json
   "model": {
     "type": "string",
     "examples": ["gpt-5.1-codex-max", "o3"]
   }
   ```

5. **弃用标记**：
   ```json
   "on-failure": {
     "enum": ["on-failure"],
     "description": "DEPRECATED: ..."
   }
   ```

6. **条件验证**：
   - 某些配置组合可能无效
   - 考虑使用 `if/then/else` 添加条件验证

7. **分割大文件**：
   - 考虑按功能域拆分为多个 Schema 文件
   - 使用 `$ref` 引用

### 边界情况

1. **平台特定选项**：
   - Schema 包含所有平台的选项
   - 某些选项在特定平台无效
   - 建议添加平台标记到描述中

2. **实验性功能**：
   - 实验性功能可能在版本间变化
   - 考虑添加稳定性标记

3. **向后兼容**：
   - 重命名字段时需要保留旧名称作为别名
   - Schema 需要支持这种迁移
