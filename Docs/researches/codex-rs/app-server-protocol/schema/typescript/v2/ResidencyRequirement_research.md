# ResidencyRequirement 研究文档

## 场景与职责

`ResidencyRequirement` 是 Codex app-server-protocol v2 协议中的数据驻留要求类型，用于指定 AI 模型处理请求时的数据驻留区域。该类型主要满足企业级用户对数据主权和合规性的要求，确保敏感数据在特定地理区域内处理。

在 Codex 的合规体系中，`ResidencyRequirement` 承担以下职责：
1. **数据主权**：确保数据在指定地理区域内处理
2. **合规性**：满足 GDPR、数据本地化等法规要求
3. **企业策略**：支持企业级数据驻留策略配置
4. **请求路由**：影响 API 请求的路由目标

## 功能点目的

### 核心功能
- **区域指定**：指定数据必须驻留的地理区域
- **HTTP 头映射**：转换为 HTTP 请求头 `OpenAI-Residency-Region`
- **配置约束**：作为 `ConfigRequirements` 的一部分进行约束

### 设计意图
- **简单枚举**：当前仅支持 `"us"`，但设计为枚举便于扩展
- **与核心协议对齐**：与 `CoreResidencyRequirement` 保持一致
- **合规优先**：确保数据驻留要求被严格遵守

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`ResidencyRequirement.ts`）：
```typescript
export type ResidencyRequirement = "us";
```

**Rust 定义**（`v2.rs` 行 853-856）：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ResidencyRequirement {
    Us,
}
```

### 关键值说明

| 值 | 说明 | HTTP 头值 |
|----|------|-----------|
| `"us"` | 美国区域 | `"us"` |

### HTTP 头转换

在 `default_client.rs` 行 226：
```rust
pub fn set_default_client_residency_requirement(
    enforce_residency: Option<ResidencyRequirement>,
) {
    // ...
}

// 转换为 HTTP 头
ResidencyRequirement::Us => HeaderValue::from_static("us"),
```

### 配置约束

在 `ConfigRequirements` 中使用（行 829）：
```rust
pub struct ConfigRequirements {
    // ...
    pub enforce_residency: Option<ResidencyRequirement>,
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 853-856
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/ResidencyRequirement.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ConfigRequirementsReadResponse.json`

### 使用位置
- **ConfigRequirements**：`v2.rs` 行 829 - 配置要求的一部分
- **default_client.rs**：行 84, 226 - 设置和转换驻留要求
- **config_api.rs**：行 217-220 - API 层转换

### 相关类型
- `ConfigRequirements`：包含 `enforce_residency` 字段（行 823-832）
- `CoreResidencyRequirement`：核心协议中的对应类型（`config/src/config_requirements.rs` 行 464-467）
- `Constrained<Option<ResidencyRequirement>>`：带约束的驻留要求（`core/src/config/mod.rs` 行 275）

### 配置层级

```
ConfigRequirements
  └── enforce_residency: Option<ResidencyRequirement>
        └── ResidencyRequirement::Us
              └── HTTP Header: "OpenAI-Residency-Region: us"
```

## 依赖与外部交互

### 依赖项
- `serde`：序列化/反序列化支持
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `CoreResidencyRequirement`（核心配置）：`config/src/config_requirements.rs`

### 下游使用
- `ConfigRequirements`：配置要求类型
- `ConfigRequirementsReadResponse`：配置要求读取响应
- HTTP 客户端：转换为请求头发送到 API

### 协议集成
- 通过 `configRequirements/read` RPC 方法获取
- 转换为 HTTP 头发送到 OpenAI API
- 影响模型请求的路由和处理位置

## 风险、边界与改进建议

### 潜在风险
1. **区域单一**：当前仅支持 `"us"`，限制了国际用户的使用
2. **强制要求**：如果强制要求但服务不可用，可能导致请求失败
3. **传播问题**：驻留要求可能在请求链中丢失

### 边界情况
1. **未配置**：`enforce_residency` 为 `null` 时的默认行为
2. **服务不可用**：指定区域的服务暂时不可用
3. **跨区域调用**：子代理调用时的驻留要求传递

### 改进建议
1. **扩展区域支持**：
   ```rust
   pub enum ResidencyRequirement {
       Us,      // 美国
       Eu,      // 欧盟
       Uk,      // 英国
       Ca,      // 加拿大
       Au,      // 澳大利亚
       // ... 更多区域
   }
   ```

2. **增强配置选项**：
   ```rust
   pub struct ResidencyConfig {
       /// 主要驻留区域
       pub primary: ResidencyRequirement,
       /// 备用区域（当主要区域不可用时）
       pub fallback: Option<ResidencyRequirement>,
       /// 是否严格强制（失败时拒绝而非回退）
       pub strict: bool,
   }
   ```

3. **验证和监控**：
   - 添加驻留要求的验证机制
   - 监控驻留要求的遵守情况
   - 提供驻留审计日志

4. **用户体验**：
   - 在 UI 中显示当前数据驻留区域
   - 提供区域选择界面
   - 显示区域相关的性能影响

5. **企业功能**：
   - 支持按项目/团队设置不同的驻留要求
   - 与企业的数据治理策略集成
   - 提供驻留合规报告

6. **文档完善**：
   - 明确各区域的数据处理范围
   - 说明驻留要求对功能和性能的影响
   - 提供合规性指南
