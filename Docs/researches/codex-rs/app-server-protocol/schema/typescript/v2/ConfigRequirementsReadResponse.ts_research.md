# ConfigRequirementsReadResponse.ts Research Document

## 场景与职责

`ConfigRequirementsReadResponse` 是 Codex App-Server V2 API 中用于返回配置要求查询结果的响应类型。它是 `configRequirements/read` RPC 方法的返回类型，用于向客户端传递当前生效的配置约束和强制要求。

该类型的典型使用场景包括：
- **客户端初始化**: 应用启动时获取配置约束，以调整可用选项
- **配置界面渲染**: 根据允许的配置值动态生成设置界面
- **策略合规检查**: 客户端预先验证用户输入是否符合要求
- **管理界面展示**: 向管理员显示当前生效的企业策略

## 功能点目的

`ConfigRequirementsReadResponse` 的主要目的是：

1. **封装配置要求**: 将 `ConfigRequirements` 包装在标准响应结构中
2. **支持空值语义**: 通过 `null` 值明确表示没有配置任何要求
3. **提供扩展性**: 为未来可能增加的响应字段预留空间
4. **保持一致性**: 遵循 V2 API 的响应命名规范 (`*Response` 后缀)

## 具体技术实现

### 数据结构定义

```typescript
import type { ConfigRequirements } from "./ConfigRequirements";

export type ConfigRequirementsReadResponse = { 
  /**
   * Null if no requirements are configured (e.g. no requirements.toml/MDM entries).
   */
  requirements: ConfigRequirements | null, 
};
```

### 关键字段说明

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `requirements` | `ConfigRequirements \| null` | 配置要求对象。如果为 `null`，表示没有配置任何要求（例如没有 requirements.toml 文件或 MDM 配置） |

### 空值语义

该类型的关键设计决策是使用 `null` 而非可选字段或空对象来表示"无要求"：

- **`null`**: 明确表示没有配置要求，客户端可以自由使用所有配置选项
- **`ConfigRequirements` 对象**: 包含具体的限制和要求，客户端必须遵守

这种设计避免了歧义：
```typescript
// 明确的空值语义
{ requirements: null }  // 无限制
{ requirements: { allowedSandboxModes: [], ... } }  // 明确限制（即使限制为空数组）
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ConfigRequirementsReadResponse.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 对应 Rust 结构体：`ConfigRequirementsReadResponse` (行 857-864)
  - 标记为实验性 API: `#[experimental(nested)]`

### 依赖类型

| 类型 | 文件路径 | 说明 |
|------|----------|------|
| `ConfigRequirements` | `v2/ConfigRequirements.ts` | 配置要求详情 |

### 相关类型

| 类型 | 说明 |
|------|------|
| `ConfigRequirements` | 内嵌的实际配置要求数据 |
| `NetworkRequirements` | 实验性的网络相关配置要求 |

## 依赖与外部交互

### 上游依赖

1. **ts-rs 生成**: 该文件由 Rust 的 `ts-rs` 库自动生成
2. **实验性 API 标记**: 整个响应类型被标记为实验性，可能在后续版本中调整

### 下游使用

1. **客户端初始化**: 应用启动时调用 `configRequirements/read` 获取此响应
2. **UI 适配**: 根据响应内容调整设置界面的可用选项
3. **本地验证**: 在发送配置更新前进行客户端预验证

### RPC 方法映射

```
RPC Method: configRequirements/read
Params: {} (无参数)
Response: ConfigRequirementsReadResponse
```

## 风险、边界与改进建议

### 潜在风险

1. **实验性 API 不稳定**: 该类型被标记为实验性，未来可能有破坏性变更
2. **缓存过期**: 客户端可能缓存响应结果，而服务器端要求已变更
3. **空值处理不当**: 开发者可能混淆 `null` 和 `{}` 的语义

### 边界情况

1. **部分配置**: 
   - `ConfigRequirements` 的每个字段都可以是 `null`
   - 需要递归检查每个子字段才能确定完整约束

2. **动态变更**: 
   - 配置要求可能在运行时通过 MDM 更新
   - 客户端需要定期刷新或监听变更通知

3. **网络要求实验性字段**:
   - Rust 源码中包含实验性的 `network` 字段
   - TypeScript 类型中尚未暴露，未来可能添加

### 改进建议

1. **添加时间戳**: 增加 `lastUpdated` 字段帮助客户端判断缓存是否过期
2. **变更通知**: 当配置要求变更时主动推送通知，而非依赖客户端轮询
3. **来源标识**: 增加 `source` 字段标识要求来自 MDM、requirements.toml 还是其他来源
4. **版本控制**: 添加 `version` 字段便于 API 演进
5. **详细错误信息**: 当配置违反要求时，返回更详细的违规说明

### 代码示例

```typescript
// 示例：处理配置要求响应
async function loadConfigRequirements(): Promise<void> {
  const response: ConfigRequirementsReadResponse = 
    await rpc.call('configRequirements/read', {});
  
  if (response.requirements === null) {
    // 无限制，启用所有功能
    enableAllFeatures();
    return;
  }
  
  const { requirements } = response;
  
  // 应用审批策略限制
  if (requirements.allowedApprovalPolicies !== null) {
    filterApprovalPolicyOptions(requirements.allowedApprovalPolicies);
  }
  
  // 应用沙箱模式限制
  if (requirements.allowedSandboxModes !== null) {
    filterSandboxModeOptions(requirements.allowedSandboxModes);
  }
  
  // 应用功能要求
  if (requirements.featureRequirements !== null) {
    applyFeatureRequirements(requirements.featureRequirements);
  }
  
  // 检查数据驻留要求
  if (requirements.enforceResidency !== null) {
    showResidencyComplianceIndicator(requirements.enforceResidency);
  }
}
```

### 与 ConfigRequirements 的关系

```
ConfigRequirementsReadResponse
└── requirements: ConfigRequirements | null
    ├── allowedApprovalPolicies
    ├── allowedSandboxModes
    ├── allowedWebSearchModes
    ├── featureRequirements
    └── enforceResidency
```

这种包装器模式在 V2 API 中很常见，为将来扩展响应字段提供灵活性。
