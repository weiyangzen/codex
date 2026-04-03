# ResidencyRequirement 研究文档

## 1. 场景与职责

`ResidencyRequirement` 是 Codex app-server-protocol v2 协议中的数据驻留要求类型，用于指定 AI 模型处理请求时的数据驻留区域。该类型主要满足企业级用户对数据主权和合规性的要求，确保敏感数据在特定地理区域内处理。

### 使用场景
- **企业合规**：满足 GDPR、数据本地化法规等合规要求
- **数据主权**：确保数据不离开特定国家/地区
- **安全策略**：限制模型处理请求的地理位置

## 2. 功能点目的

该类型的核心目的是：
1. **合规性支持**：帮助企业满足数据驻留法规要求
2. **地理限制**：将 AI 处理限制在特定区域的数据中心
3. **可扩展设计**：当前仅支持 "us"，为未来扩展预留空间

### 设计考量
- 当前仅支持 `"us"` 值，表明这是一个预留扩展点的设计
- 使用字符串字面量类型而非枚举，便于未来添加新区域

## 3. 具体技术实现

### TypeScript 类型定义
```typescript
export type ResidencyRequirement = "us";
```

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ResidencyRequirement {
    Us,
}
```

### 字段说明
| 值 | 说明 |
|----|------|
| `"us"` | 要求数据在美国境内处理 |

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 850-855)
- **TypeScript 文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ResidencyRequirement.ts`

### 配置使用
- **配置要求**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 829)
  ```rust
  pub enforce_residency: Option<ResidencyRequirement>
  ```
- **配置响应**: `ConfigRequirementsReadResponse` 中作为可选字段

### 核心实现
- **默认客户端**: `codex-rs/core/src/default_client.rs`
  - 行 39: 静态存储驻留要求配置
  - 行 84: 设置驻留要求的公共函数
  - 行 226: 将 `ResidencyRequirement::Us` 转换为 HTTP 头 `"us"`
- **配置模块**: `codex-rs/core/src/config/mod.rs` (行 275)
  - 使用 `Constrained<Option<ResidencyRequirement>>` 包装

### TUI 应用
- **调试配置**: `codex-rs/tui_app_server/src/debug_config.rs` (行 320)
  - `format_residency_requirement` 函数用于格式化显示

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- `codex-rs/app-server-protocol/schema/json/v2/ConfigRequirementsReadResponse.json`

## 5. 依赖与外部交互

### 导入依赖
- 无直接导入的类型

### 被依赖类型
- `ConfigRequirements` - 包含 `enforceResidency` 字段
- `ConfigRequirementsReadResponse` - 配置要求读取响应

### HTTP 集成
- 在 `default_client.rs` 中转换为 HTTP 请求头
- 用于 API 请求时的区域路由

## 6. 风险、边界与改进建议

### 潜在风险
1. **单点限制**：当前仅支持 "us"，限制了非美国用户的使用
2. **配置传播**：配置需要在多个组件间同步，可能出现不一致
3. **API 兼容性**：后端 API 需要支持相应的驻留路由

### 边界情况
- **未配置**：`None` 表示不强制驻留要求
- **未知区域**：未来添加新区域时需要客户端更新
- **网络路由**：实际数据流向需要基础设施支持

### 改进建议
1. **扩展区域支持**：
   - 添加 `"eu"`（欧洲）、`"apac"`（亚太）等区域
   - 考虑国家级别的粒度（如 `"de"`、`"jp"`）

2. **增强类型安全**：
   ```typescript
   // 建议使用枚举或更严格的类型
   export type ResidencyRequirement = "us" | "eu" | "apac";
   ```

3. **配置验证**：
   - 验证请求的区域是否被当前部署支持
   - 提供配置可用性检查 API

4. **文档完善**：
   - 明确说明数据驻留的实际保证级别
   - 说明与 CDN、缓存等基础设施的交互

5. **运行时检查**：
   - 添加运行时验证确保请求被路由到正确区域
   - 提供驻留合规性报告

### 相关配置
```rust
// 在 ConfigRequirements 中的使用
pub struct ConfigRequirements {
    // ... 其他字段
    pub enforce_residency: Option<ResidencyRequirement>,
}
```

### 未来扩展方向
- 支持多区域优先级（首选区域 + 备选区域）
- 支持区域级别的功能差异处理
- 与云服务提供商的区域概念对齐
