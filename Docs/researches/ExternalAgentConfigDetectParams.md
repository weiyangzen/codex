# ExternalAgentConfigDetectParams 研究文档

## 1. 场景与职责

### 1.1 使用场景

`ExternalAgentConfigDetectParams` 是 Codex App-Server Protocol v2 API 中用于**检测外部 Agent 配置**的请求参数结构体。主要应用于以下场景：

1. **用户首次迁移**：当用户从其他 AI Agent（如 Claude Code）切换到 Codex 时，系统需要检测用户现有的配置文件中是否存在可迁移的内容
2. **多工作区检测**：支持在多个代码仓库（repo）中批量检测是否存在 `.claude/settings.json`、`.claude/skills/`、`CLAUDE.md` 等外部 Agent 配置文件
3. **用户主目录检测**：检测用户主目录下的全局配置（如 `~/.claude/settings.json`、`~/.claude/CLAUDE.md`）

### 1.2 职责范围

该结构体的核心职责是：
- 定义检测范围：指定需要扫描的工作目录列表
- 控制检测深度：决定是否包含用户主目录级别的配置
- 作为 `externalAgentConfig/detect` RPC 方法的输入参数

---

## 2. 功能点目的

### 2.1 设计目标

| 目标 | 说明 |
|------|------|
| **简化迁移流程** | 让用户能够一键发现并迁移其他 Agent 的配置，降低切换成本 |
| **精准定位** | 通过 `cwds` 参数支持仓库级别的精准检测，避免全磁盘扫描 |
| **灵活控制** | 通过 `includeHome` 参数让用户决定是否包含全局配置 |

### 2.2 与其他 Agent 的兼容性

当前主要支持与 **Claude Code** 的配置互操作：
- 检测 `~/.claude/settings.json` → 迁移到 `~/.codex/config.toml`
- 检测 `~/.claude/skills/` → 迁移到 `~/.agents/skills/`
- 检测 `CLAUDE.md` → 迁移到 `AGENTS.md`

---

## 3. 具体技术实现

### 3.1 数据结构定义

**JSON Schema 定义** (`codex-rs/app-server-protocol/schema/json/v2/ExternalAgentConfigDetectParams.json`):

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "cwds": {
      "description": "Zero or more working directories to include for repo-scoped detection.",
      "items": {
        "type": "string"
      },
      "type": ["array", "null"]
    },
    "includeHome": {
      "description": "If true, include detection under the user's home (~/.claude, ~/.codex, etc.).",
      "type": "boolean"
    }
  },
  "title": "ExternalAgentConfigDetectParams",
  "type": "object"
}
```

**Rust 结构体定义** (`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 900-910 行):

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ExternalAgentConfigDetectParams {
    /// If true, include detection under the user's home (~/.claude, ~/.codex, etc.).
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub include_home: bool,
    /// Zero or more working directories to include for repo-scoped detection.
    #[ts(optional = nullable)]
    pub cwds: Option<Vec<PathBuf>>,
}
```

### 3.2 字段详解

| 字段名 | 类型 | 必需 | 默认值 | 说明 |
|--------|------|------|--------|------|
| `includeHome` | `boolean` | 否 | `false` | 是否检测用户主目录下的全局配置 |
| `cwds` | `string[] \| null` | 否 | `null` | 工作目录列表，用于仓库级别的检测 |

### 3.3 序列化行为

- `include_home`: 使用 `#[serde(default, skip_serializing_if = "std::ops::Not::not")]`，默认值为 `false`，当值为 `false` 时不会序列化到 JSON
- `cwds`: 使用 `#[ts(optional = nullable)]`，在 TypeScript 中表现为可选的 nullable 字段

### 3.4 协议集成

在 `common.rs` 中注册为 RPC 方法参数 (`client_request_definitions!` 宏):

```rust
ExternalAgentConfigDetect => "externalAgentConfig/detect" {
    params: v2::ExternalAgentConfigDetectParams,
    response: v2::ExternalAgentConfigDetectResponse,
},
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 作用 |
|----------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ExternalAgentConfigDetectParams.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (900-910行) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` (481-484行) | RPC 方法注册 |
| `codex-rs/app-server/src/external_agent_config_api.rs` (28-63行) | API 实现，参数处理逻辑 |
| `codex-rs/core/src/external_agent_config.rs` (14-17, 57-74行) | 核心检测逻辑，参数转换 |

### 4.2 TypeScript 类型定义

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/schema/typescript/v2/ExternalAgentConfigDetectParams.ts` | TypeScript 类型定义 |

### 4.3 调用流程

```
Client Request
    ↓
externalAgentConfig/detect RPC
    ↓
ExternalAgentConfigDetectParams (反序列化)
    ↓
ExternalAgentConfigApi::detect() (app-server)
    ↓
ExternalAgentConfigDetectOptions (转换为 Core 类型)
    ↓
ExternalAgentConfigService::detect() (core)
    ↓
文件系统扫描逻辑
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖项 | 说明 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型生成 |
| `std::path::PathBuf` | 路径处理 |

### 5.2 相关类型

- `ExternalAgentConfigDetectOptions` (`codex-rs/core/src/external_agent_config.rs`): Core 层的检测选项，与 `ExternalAgentConfigDetectParams` 结构相似但位于不同 crate

### 5.3 转换逻辑

在 `external_agent_config_api.rs` 中完成 Protocol 类型到 Core 类型的转换：

```rust
ExternalAgentConfigDetectOptions {
    include_home: params.include_home,
    cwds: params.cwds,
}
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

| 风险点 | 说明 | 缓解措施 |
|--------|------|----------|
| **路径注入** | `cwds` 字段接受用户输入的路径，可能存在路径遍历风险 | Core 层使用 `find_repo_root()` 进行路径验证和规范化 |
| **性能问题** | 大量 `cwds` 或深层目录结构可能导致检测耗时过长 | 建议客户端限制 `cwds` 数量，或实现超时机制 |
| **并发安全** | 多线程同时检测和导入可能导致文件竞争 | 当前实现未加锁，依赖文件系统原子操作 |

### 6.2 边界情况

1. **空 `cwds` + `includeHome: false`**: 返回空结果，无检测行为
2. **不存在的路径**: `find_repo_root()` 会返回 `None`，跳过该路径
3. **非目录路径**: 自动获取父目录作为检测根
4. **相对路径**: 会基于当前工作目录转换为绝对路径

### 6.3 改进建议

1. **添加最大深度限制**: 防止在极深层目录结构中递归过深
   ```rust
   // 建议添加 max_depth 参数
   pub max_depth: Option<usize>,
   ```

2. **添加超时控制**: 防止检测操作阻塞过久
   ```rust
   pub timeout_ms: Option<u64>,
   ```

3. **支持更多 Agent 类型**: 目前仅支持 Claude Code，可扩展支持其他 Agent
   ```rust
   pub agent_types: Option<Vec<String>>, // ["claude", "cursor", "windsurf"]
   ```

4. **添加排除模式**: 允许用户指定不需要检测的路径模式
   ```rust
   pub exclude_patterns: Option<Vec<String>>, // ["**/node_modules/**"]
   ```

5. **增强错误报告**: 当前仅返回成功结果，建议添加详细的错误信息
   ```rust
   pub struct ExternalAgentConfigDetectResponse {
       pub items: Vec<ExternalAgentConfigMigrationItem>,
       pub errors: Vec<DetectionError>, // 新增
   }
   ```
