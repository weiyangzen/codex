# ResidencyRequirement 研究文档

## 场景与职责

`ResidencyRequirement` 是 Codex 系统中用于强制数据驻留（Data Residency）合规要求的枚举类型。它定义了网络流量必须路由到的地理区域，确保用户数据不会离开指定的地理边界，满足数据主权和合规性要求。

**核心职责：**
- 定义数据驻留的地理区域要求
- 强制网络流量路由到指定区域的服务器
- 支持企业级合规需求（如 GDPR、数据本地化法规）

**使用场景：**
- 企业用户要求数据必须存储在美国境内
- 满足特定国家/地区的数据本地化法规
- 云部署时的多区域合规配置

## 功能点目的

| 值 | 说明 |
|------|------|
| `"us"` | 要求所有网络流量必须路由到美国区域 |

**当前限制：**
- 目前仅支持 `"us"` 一个值
- 设计为可扩展枚举，未来可添加更多区域（如 `"eu"`、`"apac"` 等）

**设计目的：**
1. **合规保证**：确保用户数据不会意外传输到非授权区域
2. **企业就绪**：满足企业客户的合规审计要求
3. **可扩展性**：枚举设计便于未来支持更多地理区域

## 具体技术实现

### TypeScript 定义
```typescript
export type ResidencyRequirement = "us";
```

### Rust 源码定义
位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ResidencyRequirement {
    Us,
}
```

位于 `codex-rs/config/src/config_requirements.rs`：

```rust
#[derive(Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ResidencyRequirement {
    Us,
}
```

### 配置集成
在 `ConfigRequirements` 中的使用：
```rust
pub struct ConfigRequirements {
    // ...
    pub enforce_residency: ConstrainedWithSource<Option<ResidencyRequirement>>,
    // ...
}
```

在 `ConfigRequirementsToml` 中的定义：
```rust
pub struct ConfigRequirementsToml {
    // ...
    pub enforce_residency: Option<ResidencyRequirement>,
    // ...
}
```

## 关键代码路径与文件引用

### 定义位置
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 协议层枚举定义 |
| `codex-rs/config/src/config_requirements.rs` | 配置层枚举定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ResidencyRequirement.ts` | 生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/ConfigRequirementsReadResponse.json` | JSON Schema |

### 使用位置
| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/default_client.rs` | 默认 HTTP 客户端设置驻留要求 |
| `codex-rs/core/src/config/mod.rs` | 配置结构体中的 enforce_residency 字段 |
| `codex-rs/core/src/config_loader/mod.rs` | 配置加载器处理驻留要求 |
| `codex-rs/config/src/lib.rs` | 配置库导出 |
| `codex-rs/tui/src/debug_config.rs` | TUI 调试配置展示 |
| `codex-rs/tui_app_server/src/debug_config.rs` | TUI App Server 调试配置 |

### API 响应结构
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ConfigRequirementsReadResponse {
    #[experimental(nested)]
    pub requirements: Option<ConfigRequirements>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ConfigRequirements {
    // ...
    pub enforce_residency: Option<ResidencyRequirement>,
    // ...
}
```

## 依赖与外部交互

### 内部依赖
- `codex_config::Constrained`：约束值包装器
- `codex_config::ConstrainedWithSource`：带来源的约束值

### 外部交互
1. **与 HTTP 客户端的交互**：
   - 在 `default_client.rs` 中设置 `residency_requirement`
   - 影响 HTTP 请求的头部或路由决策

2. **与后端 API 的交互**：
   - 通过特定头部或 URL 参数告知后端所需的驻留区域
   - 后端根据要求将请求路由到相应区域的服务器

3. **配置来源**：
   - MDM（移动设备管理）配置
   - 云要求（Cloud Requirements）
   - 系统 `requirements.toml` 文件

### 配置加载流程
```rust
// 从 requirements.toml 加载
let enforce_residency: Option<ResidencyRequirement> = toml.enforce_residency;

// 包装为带约束的值
let constrained = Constrained::new(required, move |candidate| {
    if candidate == &required {
        Ok(())
    } else {
        Err(ConstraintError::InvalidValue { ... })
    }
})?;
```

## 风险、边界与改进建议

### 潜在风险
1. **单点故障**：目前仅支持 `"us"`，如果美国区域服务不可用，无法满足其他区域的合规要求
2. **配置绕过**：如果 HTTP 客户端未正确实现驻留要求，可能导致数据泄露
3. **第三方服务**：调用的第三方 API 可能不受驻留要求约束

### 边界情况
1. **未配置驻留要求**：`None` 表示无驻留限制，数据可能路由到任何区域
2. **冲突配置**：多个配置层可能指定不同的驻留要求，需要明确的优先级规则
3. **动态切换**：运行时切换驻留区域可能导致数据不一致

### 改进建议
1. **扩展区域支持**：
   - 添加 `"eu"`（欧洲）、`"apac"`（亚太）等区域
   - 支持多区域优先级配置

2. **更细粒度控制**：
   ```rust
   pub enum ResidencyRequirement {
       Us,
       Eu,
       Apac,
       Specific(String), // 自定义区域标识
   }
   ```

3. **强制验证**：
   - 在 HTTP 客户端层强制验证所有请求符合驻留要求
   - 对不合规的请求抛出错误或警告

4. **审计和监控**：
   - 记录所有跨区域的数据传输尝试
   - 提供合规性报告功能

5. **UI 提示**：
   - 在 TUI/IDE 中显示当前驻留配置
   - 当操作可能违反驻留要求时给出警告

6. **文档完善**：
   - 明确说明哪些操作受驻留要求约束
   - 提供企业合规配置指南

### 配置示例
```toml
# requirements.toml
enforce_residency = "us"

# 或从 MDM 配置
# com.codex:enforce_residency = "us"
```
