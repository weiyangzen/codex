# CollaborationMode.ts 研究文档

## 场景与职责

`CollaborationMode.ts` 定义了 Codex 会话的协作模式类型，用于配置 AI 助手的行为方式。协作模式决定了 AI 在对话中的角色、使用的模型、推理努力程度等关键参数，是 Codex 个性化配置的核心类型。

**核心职责：**
- 定义协作模式的结构
- 关联模式类型（ModeKind）和具体设置（Settings）
- 支持 "plan" 和 "default" 两种预设模式

## 功能点目的

1. **模式化协作**
   - 提供预设的协作模式，简化用户配置
   - "plan" 模式用于规划和设计阶段
   - "default" 模式用于常规对话

2. **配置封装**
   - 将模型选择、推理努力程度、开发者指令等封装在一起
   - 便于切换和分享配置

3. **个性化体验**
   - 不同场景使用不同的协作模式
   - 支持自定义模式设置

## 具体技术实现

### 类型定义

```typescript
import type { ModeKind } from "./ModeKind";
import type { Settings } from "./Settings";

/**
 * Collaboration mode for a Codex session.
 */
export type CollaborationMode = { 
  mode: ModeKind, 
  settings: Settings, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `mode` | `ModeKind` | 协作模式类型（`"plan"` 或 `"default"`） |
| `settings` | `Settings` | 模式的具体设置 |

### 关联类型

- **`ModeKind`**: 模式类型枚举（`"plan" | "default"`）
- **`Settings`**: 设置类型，包含：
  - `model`: 模型名称
  - `reasoning_effort`: 推理努力程度
  - `developer_instructions`: 开发者指令

### 生成信息

- **生成工具**: [ts-rs](https://github.com/Aleph-Alpha/ts-rs)
- **源文件**: `codex_protocol::config_types::CollaborationMode`
- **Rust 类型**: `CollaborationMode`
- **序列化**: 使用 camelCase 命名

### Rust 源类型定义

```rust
// 来自 codex_protocol crate
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
pub struct CollaborationMode {
    pub mode: ModeKind,
    pub settings: Settings,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
pub enum ModeKind {
    Plan,
    Default,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
pub struct Settings {
    pub model: String,
    pub reasoning_effort: Option<ReasoningEffort>,
    pub developer_instructions: Option<String>,
}
```

## 关键代码路径与文件引用

### 使用场景

1. **会话启动**
   - 在 `ThreadStartParams` 中指定协作模式
   - 影响新会话的初始行为

2. **配置管理**
   - 在配置文件中定义协作模式预设
   - 与 `ProfileV2` 类型相关

3. **模式切换**
   - 会话中动态切换协作模式
   - 改变 AI 的行为方式

### 相关类型

- **`ModeKind`**: 模式类型枚举（`./ModeKind.ts`）
- **`Settings`**: 设置类型（`./Settings.ts`）
- **`ReasoningEffort`**: 推理努力程度（`./ReasoningEffort.ts`）
- **`ProfileV2`**: v2 配置中的 profile 类型

### 使用示例

```typescript
const collaborationMode: CollaborationMode = {
  mode: "plan",
  settings: {
    model: "gpt-5",
    reasoning_effort: "high",
    developer_instructions: "You are a helpful coding assistant focused on architecture and design."
  }
};
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 路径 | 说明 |
|------|------|------|
| `ModeKind` | `./ModeKind` | 模式类型 |
| `Settings` | `./Settings` | 模式设置 |

### 下游使用者

| 使用者 | 路径 | 用途 |
|--------|------|------|
| `ThreadStartParams` | `./v2/ThreadStartParams` | 会话启动参数 |
| `ProfileV2` | `./v2/ProfileV2` | 配置 profile |
| 配置系统 | - | 协作模式预设 |

### 序列化格式示例

```json
{
  "mode": "plan",
  "settings": {
    "model": "gpt-5",
    "reasoning_effort": "high",
    "developer_instructions": "Focus on system architecture and design patterns."
  }
}
```

## 风险、边界与改进建议

### 风险点

1. **模式定义局限**
   - 目前只有两种预设模式（plan/default）
   - 可能无法满足所有用户需求

2. **设置冲突**
   - `settings` 中的配置可能与其他配置冲突
   - 需要明确的优先级规则

3. **模型可用性**
   - `settings.model` 指定的模型可能不可用
   - 需要处理模型不存在的情况

### 边界情况

1. **空设置**
   - `settings` 字段为空的处理
   - 是否应该使用默认值

2. **未知模式**
   - 收到未知 `ModeKind` 值的处理
   - 向后兼容性考虑

3. **设置验证**
   - `model` 名称格式验证
   - `reasoning_effort` 值范围验证

### 改进建议

1. **扩展预设模式**
   - 添加更多预设模式：
     - `"review"`: 代码审查模式
     - `"debug"`: 调试模式
     - `"learn"`: 教学模式

2. **自定义模式支持**
   - 允许用户创建和保存自定义模式
   - 支持模式导入/导出

3. **设置继承**
   - 支持模式设置的继承机制
   - 基础模式 + 自定义覆盖

4. **动态模式切换**
   - 支持会话中无缝切换模式
   - 保持上下文连续性

5. **模式推荐**
   - 根据用户输入自动推荐合适的模式
   - 基于历史使用数据学习偏好

6. **与 v2 API 深度集成**
   - 在更多 v2 API 中支持协作模式
   - 如 `TurnStartParams` 中支持模式覆盖
