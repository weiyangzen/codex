# SkillSummary.ts 研究文档

## 场景与职责

`SkillSummary.ts` 定义了技能摘要的数据结构，用于在技能列表中提供精简的技能信息。这是 `SkillMetadata` 的简化版本，优化了传输和展示性能，适用于只需要基本信息的场景。

## 功能点目的

该类型用于：
1. **列表展示**：在技能列表中显示精简信息
2. **性能优化**：减少不必要的数据传输
3. **快速浏览**：让用户快速了解可用技能
4. **延迟加载**：详细信息可在需要时单独获取

## 具体技术实现

### 数据结构定义

```typescript
import type { SkillInterface } from "./SkillInterface";

export type SkillSummary = { 
  name: string,                          // 技能名称
  description: string,                   // 技能描述
  shortDescription: string | null,       // 简短描述
  interface: SkillInterface | null,      // 界面配置
  path: string                           // 技能文件路径
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| name | string | 技能唯一标识名 |
| description | string | 技能的详细描述 |
| shortDescription | string \| null | 简短描述，用于列表展示 |
| interface | SkillInterface \| null | UI 展示配置 |
| path | string | 技能定义文件的路径 |

### 与 SkillMetadata 的区别

| 字段 | SkillSummary | SkillMetadata |
|------|--------------|---------------|
| name | ✓ | ✓ |
| description | ✓ | ✓ |
| shortDescription | ✓ (nullable) | ✓ (optional) |
| interface | ✓ (nullable) | ✓ (optional) |
| path | ✓ | ✓ |
| dependencies | ✗ | ✓ (optional) |
| scope | ✗ | ✓ |
| enabled | ✗ | ✓ |

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillSummary {
    pub name: String,
    pub description: String,
    pub short_description: Option<String>,
    pub interface: Option<SkillInterface>,
    pub path: String,
}
```

### 从 SkillMetadata 转换

```rust
impl From<SkillMetadata> for SkillSummary {
    fn from(metadata: SkillMetadata) -> Self {
        Self {
            name: metadata.name,
            description: metadata.description,
            short_description: metadata.short_description,
            interface: metadata.interface,
            path: metadata.path,
        }
    }
}
```

### 在 PluginReadResponse 中的使用

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginReadResponse {
    pub plugin: PluginDetail,
    pub skills: Vec<SkillSummary>,  // 使用 SkillSummary 而非 SkillMetadata
}
```

### 使用场景

#### 技能列表

```typescript
// 获取技能列表，使用 SkillSummary 减少数据传输
const response: SkillsListResponse = await api.skills.list({
  cwds: ["/home/user/project"]
});

// 显示技能列表
response.data.forEach(entry => {
  entry.skills.forEach(skill => {
    console.log(skill.name, skill.shortDescription);
  });
});
```

#### 插件详情

```typescript
// 获取插件详情，包含关联的技能摘要
const response: PluginReadResponse = await api.plugins.read({
  name: "my-plugin"
});

// 显示插件关联的技能
response.skills.forEach(skill => {
  renderSkillCard(skill);
});
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SkillSummary.ts`

### Rust 协议定义
- V2 API：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 服务端实现
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`
- 技能远程：`codex-rs/core/src/skills/remote.rs`

### 相关类型
- SkillInterface：`codex-rs/app-server-protocol/schema/typescript/v2/SkillInterface.ts`
- SkillMetadata：`codex-rs/app-server-protocol/schema/typescript/v2/SkillMetadata.ts`
- PluginReadResponse：`codex-rs/app-server-protocol/schema/typescript/v2/PluginReadResponse.ts`

## 依赖与外部交互

### 上游依赖
- SkillMetadata：从完整元数据转换而来
- 技能加载：在加载过程中生成摘要

### 下游消费
- 插件系统：显示插件关联的技能
- 技能发现：快速浏览可用技能

### 数据流

```
SkillMetadata (完整)
    ↓ 转换
SkillSummary (精简)
    ↓ 传输
客户端列表展示
    ↓ 用户选择
获取完整 SkillMetadata (如需要)
```

## 风险、边界与改进建议

### 边界情况
1. **信息不足**：摘要可能缺少用户决策所需的关键信息
2. **状态丢失**：不包含 enabled 状态，无法判断技能是否可用
3. **作用域丢失**：不包含 scope 信息

### 潜在风险
1. **重复请求**：用户可能需要额外请求获取完整信息
2. **数据不一致**：摘要和完整数据可能不同步
3. **缓存问题**：摘要缓存可能导致显示过期信息

### 改进建议
1. **增量加载**：支持按需加载额外字段
2. **缓存策略**：为摘要添加版本信息支持缓存验证
3. **字段选择**：支持客户端指定需要的字段
4. **批量获取**：支持批量获取多个技能的完整信息
5. **实时更新**：当技能状态变化时推送更新
