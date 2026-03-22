# ResidencyRequirement 研究文档

## 场景与职责

`ResidencyRequirement` 是 Codex App Server Protocol v2 中用于定义数据驻留要求的枚举类型。它指定了数据必须存储和处理的地理区域，主要用于满足合规性要求（如 GDPR、数据主权法规等）。

该类型在配置要求（`ConfigRequirements`）中使用，允许管理员强制要求 Codex 在特定区域处理数据。

## 功能点目的

1. **合规性支持**：满足数据主权和隐私法规要求
2. **地理限制**：限制数据处理的地理位置
3. **策略执行**：作为配置要求的一部分强制执行
4. **审计追踪**：支持合规审计和报告

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ResidencyRequirement {
    Us,
}
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/ResidencyRequirement.ts)
export type ResidencyRequirement = "us";
```

### 字段说明

| 变体 | 说明 |
|------|------|
| `Us` | 数据必须驻留在美国境内 |

### 使用上下文

```rust
// 在 ConfigRequirements 中使用
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ConfigRequirements {
    #[experimental(nested)]
    pub allowed_approval_policies: Option<Vec<AskForApproval>>,
    pub allowed_sandbox_modes: Option<Vec<SandboxMode>>,
    pub allowed_web_search_modes: Option<Vec<WebSearchMode>>,
    pub feature_requirements: Option<BTreeMap<String, bool>>,
    pub enforce_residency: Option<ResidencyRequirement>,
    #[experimental("configRequirements/read.network")]
    pub network: Option<NetworkRequirements>,
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 850-855)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ResidencyRequirement.ts`

### 相关类型
- `ConfigRequirements`: 包含 `enforce_residency` 字段
- `ConfigRequirementsReadResponse`: 配置要求读取响应

### 使用场景
- `requirements.toml` 配置文件中的驻留要求
- MDM（移动设备管理）推送的配置策略
- 企业合规策略配置

## 依赖与外部交互

### 内部依赖
- `serde`: 序列化/反序列化（使用 `camelCase` 命名）
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**配置要求示例**:
```json
{
    "config": {
        "allowedSandboxModes": ["read-only", "workspace-write"],
        "enforceResidency": "us"
    }
}
```

## 风险、边界与改进建议

### 当前限制
1. **单一选项**：目前仅支持 `Us`，不支持其他区域（如 EU、UK、AU 等）
2. **无细化控制**：无法指定具体的数据中心或区域
3. **无验证机制**：类型本身不验证实际的数据驻留位置

### 边界情况
1. **多区域部署**：在多个区域部署时的处理策略
2. **故障转移**：主区域不可用时是否允许切换到其他区域
3. **数据复制**：备份和复制数据的驻留要求

### 扩展建议

1. **添加更多区域**：
   ```rust
   pub enum ResidencyRequirement {
       Us,      // 美国
       Eu,      // 欧盟
       Uk,      // 英国
       Au,      // 澳大利亚
       Ca,      // 加拿大
       De,      // 德国
       // ...
   }
   ```

2. **细化到数据中心级别**：
   ```rust
   pub enum ResidencyRequirement {
       Us,
       UsRegion(String),  // 如 "us-west-1", "us-east-1"
   }
   ```

3. **添加多区域支持**：
   ```rust
   pub struct ResidencyRequirement {
       pub primary: Region,
       pub allowed_failover: Vec<Region>,
   }
   ```

4. **添加验证级别**：
   ```rust
   pub enum ResidencyRequirement {
       Us,
       Eu,
       Strict(Box<ResidencyRequirement>),  // 严格模式，不允许任何例外
   }
   ```

### 兼容性注意
- 使用 `camelCase` 命名确保与 TypeScript 惯例一致
- 单值枚举使用字符串类型在 TypeScript 中表示
- 未来添加变体时，应确保向后兼容

### 实施考虑
1. **基础设施支持**：需要相应区域的基础设施部署
2. **网络路由**：确保流量路由到正确的区域
3. **数据同步**：跨区域数据同步的合规性处理
4. **监控审计**：实施监控和审计机制验证合规性

### 相关法规
- **GDPR**：欧盟通用数据保护条例
- **CCPA**：加州消费者隐私法案
- **数据主权法**：各国数据本地化要求
