# ConfigReadParams.ts 研究文档

## 场景与职责

`ConfigReadParams` 是 Codex App-Server Protocol v2 中用于配置读取请求的参数类型。它在以下场景中发挥作用：

1. **配置查询**：获取当前生效的配置及配置层信息
2. **项目级配置**：根据指定工作目录获取项目相关的分层配置
3. **配置调试**：获取完整的配置层信息用于排查配置问题
4. **配置同步**：获取配置状态以便在多设备间同步

## 功能点目的

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `includeLayers` | `boolean` | 是 | 是否在响应中包含完整的配置层列表 |
| `cwd` | `string \| null` | 否 | 可选的工作目录，用于解析项目配置层 |

### 参数组合行为

| `includeLayers` | `cwd` | 行为 |
|---|---|---|
| `true` | 指定 | 返回指定目录视角的完整配置，包含所有层 |
| `true` | `null` | 返回当前会话视角的完整配置，包含所有层 |
| `false` | 指定 | 返回指定目录视角的合并配置，不含层详情 |
| `false` | `null` | 返回当前会话视角的合并配置，不含层详情 |

## 具体技术实现

### TypeScript 定义
```typescript
export type ConfigReadParams = { 
  includeLayers: boolean, 
  /**
   * Optional working directory to resolve project config layers. If specified,
   * return the effective config as seen from that directory (i.e., including any
   * project layers between `cwd` and the project/repo root).
   */
  cwd?: string | null, 
};
```

### Rust 源定义
在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ConfigReadParams {
    #[serde(default)]
    pub include_layers: bool,
    /// Optional working directory to resolve project config layers.
    #[ts(optional = nullable)]
    pub cwd: Option<String>,
}
```

### 关键特性
1. **可选字段**：`cwd` 使用 `#[ts(optional = nullable)]` 标记为可选且可为 null
2. **默认值**：`include_layers` 默认为 `false`（通过 `#[serde(default)]`）

## 关键代码路径与文件引用

### 生成源文件
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 796-807)
- **生成工具**: ts-rs

### API 端点
- **方法**: `config/read`
- **请求类型**: `ConfigReadParams`
- **响应类型**: `ConfigReadResponse`

### 服务端实现
- `codex-rs/app-server/src/config_api.rs` - 配置 API 处理
- `codex-rs/core/src/config/service.rs` - 配置服务核心

### 使用示例
```rust
// 在 common.rs 中的 API 定义
ConfigRead => "config/read" {
    params: v2::ConfigReadParams,
    response: v2::ConfigReadResponse,
}
```

## 依赖与外部交互

### 独立类型
该类型无外部类型依赖，为基础参数结构。

### 响应类型
**ConfigReadResponse**:
```typescript
export type ConfigReadResponse = { 
  config: Config,                                    // 合并后的配置
  origins: { [key: string]?: ConfigLayerMetadata },  // 配置项来源映射
  layers: Array<ConfigLayer> | null,                // 完整层列表（仅当 includeLayers=true）
};
```

### 使用示例
```typescript
// 基本配置查询
const basicParams: ConfigReadParams = {
  includeLayers: false
};

// 完整配置查询（用于调试）
const debugParams: ConfigReadParams = {
  includeLayers: true
};

// 项目级配置查询
const projectParams: ConfigReadParams = {
  includeLayers: true,
  cwd: "/path/to/project"
};

// 预期响应
const response: ConfigReadResponse = {
  config: {
    model: "gpt-4",
    sandbox_mode: "workspace-write",
    // ... 其他配置
  },
  origins: {
    "model": { name: { type: "user", file: "~/.codex/config.toml" }, version: "v1" },
    "sandbox_mode": { name: { type: "project", dotCodexFolder: "/project/.codex" }, version: "v1" }
  },
  layers: [
    { name: { type: "system", ... }, version: "v1", config: {...}, disabledReason: null },
    { name: { type: "user", ... }, version: "v2", config: {...}, disabledReason: null },
    { name: { type: "project", ... }, version: "v1", config: {...}, disabledReason: null }
  ]
};
```

## 风险、边界与改进建议

### 潜在风险
1. **路径遍历**：`cwd` 参数如果未正确验证，可能存在安全风险
2. **性能问题**：`includeLayers: true` 时，深层嵌套项目可能返回大量层数据
3. **敏感信息泄漏**：响应中的 `layers` 可能包含敏感配置（如 API key）
4. **并发一致性**：配置可能在读取过程中被修改，导致响应不一致

### 边界情况
1. **无效 cwd**：指向不存在目录或文件的路径
2. **权限不足**：无法访问某些配置层文件
3. **循环项目配置**：项目配置形成循环引用
4. **空配置**：没有任何配置层时的默认行为

### 改进建议

#### 功能增强
1. **配置过滤**：添加 `filter` 参数只返回特定键的配置
```typescript
export type ConfigReadParams = { 
  includeLayers: boolean,
  cwd?: string | null,
  filter?: string[];  // 只返回这些键的配置
};
```

2. **配置差异**：添加 `sinceVersion` 参数获取自某版本以来的变更
```typescript
export type ConfigReadParams = { 
  includeLayers: boolean,
  cwd?: string | null,
  sinceVersion?: string;  // 只返回自该版本以来的变更
};
```

3. **配置验证**：添加 `validate` 选项验证配置有效性
```typescript
export type ConfigReadParams = { 
  includeLayers: boolean,
  cwd?: string | null,
  validate?: boolean;  // 验证配置并返回错误列表
};
```

#### 安全改进
1. **敏感字段过滤**：自动过滤或脱敏敏感配置字段
2. **访问控制**：基于用户身份限制可读取的配置层
3. **审计日志**：记录配置读取操作

#### 性能优化
1. **增量响应**：支持增量配置更新
2. **层缓存**：缓存配置层避免重复读取
3. **流式响应**：大量层数据时支持流式传输

### 最佳实践
1. 仅在需要调试时使用 `includeLayers: true`
2. 始终验证 `cwd` 参数的有效性
3. 在生产环境中考虑缓存配置读取结果
4. 对敏感配置进行脱敏处理后再记录日志
