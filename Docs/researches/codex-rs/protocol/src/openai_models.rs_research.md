# openai_models.rs 研究文档

## 场景与职责

`openai_models.rs` 是 Codex 协议库中的核心模型元数据定义模块，负责定义与 OpenAI API 交互所需的所有模型相关类型。这些类型在 Codex 核心、TUI、App Server 和 SDK 之间共享，是模型选择、配置和升级功能的类型基础。

**核心职责：**
- 定义模型推理努力级别（ReasoningEffort）枚举
- 定义输入模态（InputModality）类型
- 定义模型预设（ModelPreset）和模型信息（ModelInfo）结构
- 提供模型升级路径和迁移配置
- 支持模型个性（Personality）和指令模板

## 功能点目的

### 1. 推理努力级别 (ReasoningEffort)

**目的：** 控制模型推理的深度和质量，对应 OpenAI API 的 reasoning effort 参数。

**级别定义：**
```rust
pub enum ReasoningEffort {
    None,
    Minimal,
    Low,
    Medium,  // 默认
    High,
    XHigh,
}
```

**使用场景：**
- 用户可通过配置选择不同的推理深度
- 模型升级时可能需要映射不同模型支持的推理级别

### 2. 模型元数据结构

#### ModelPreset

**目的：** 客户端使用的模型预设配置，包含 UI 展示所需的全部信息。

**关键字段：**
- `id` / `model`: 模型标识符
- `display_name` / `description`: UI 展示信息
- `default_reasoning_effort`: 默认推理级别
- `supported_reasoning_efforts`: 支持的推理级别列表
- `supports_personality`: 是否支持个性配置
- `upgrade`: 升级路径配置
- `show_in_picker`: 是否在模型选择器中显示
- `input_modalities`: 支持的输入模态

#### ModelInfo

**目的：** 服务端 `/models` 端点返回的完整模型元数据。

**关键字段：**
- `slug`: 模型唯一标识
- `shell_type`: 支持的 shell 工具类型
- `truncation_policy`: 上下文截断策略
- `context_window`: 上下文窗口大小
- `auto_compact_token_limit`: 自动压缩阈值
- `effective_context_window_percent`: 有效上下文窗口百分比
- `experimental_supported_tools`: 实验性支持的工具列表

### 3. 模型升级系统

**目的：** 支持用户从旧模型平滑迁移到新模型。

**关键结构：**
```rust
pub struct ModelUpgrade {
    pub id: String,                                    // 目标模型 ID
    pub reasoning_effort_mapping: Option<HashMap<ReasoningEffort, ReasoningEffort>>, // 推理级别映射
    pub migration_config_key: String,                  // 配置迁移键
    pub model_link: Option<String>,                    // 模型文档链接
    pub upgrade_copy: Option<String>,                  // 升级说明文案
    pub migration_markdown: Option<String>,            // 迁移指南（Markdown）
}
```

### 4. 模型指令模板系统

**目的：** 支持基于个性（Personality）的动态指令生成。

**工作原理：**
1. `ModelMessages` 包含 `instructions_template`（含 `{{ personality }}` 占位符）
2. `ModelInstructionsVariables` 提供不同个性的具体指令内容
3. `get_model_instructions()` 方法根据选择的个性填充模板

## 具体技术实现

### 关键数据结构详解

#### ReasoningEffortPreset

```rust
pub struct ReasoningEffortPreset {
    pub effort: ReasoningEffort,
    pub description: String,  // UI 展示的描述文本
}
```

#### TruncationPolicyConfig

```rust
pub struct TruncationPolicyConfig {
    pub mode: TruncationMode,  // Bytes 或 Tokens
    pub limit: i64,
}

impl TruncationPolicyConfig {
    pub const fn bytes(limit: i64) -> Self { ... }
    pub const fn tokens(limit: i64) -> Self { ... }
}
```

#### ModelInfo 的自动压缩阈值计算

```rust
pub fn auto_compact_token_limit(&self) -> Option<i64> {
    let context_limit = self.context_window.map(|cw| (cw * 9) / 10);  // 默认 90%
    let config_limit = self.auto_compact_token_limit;
    
    if let Some(context_limit) = context_limit {
        return Some(config_limit.map_or(context_limit, |l| l.min(context_limit)));
    }
    config_limit
}
```

### 序列化与类型安全

**serde 配置：**
- 使用 `#[serde(rename_all = "lowercase")]` 确保与 OpenAI API 的兼容性
- 使用 `#[serde(default = "...")]` 提供向后兼容的默认值
- 使用 `#[serde(skip_serializing_if = "Option::is_none")]` 减少传输数据量

**strum 宏：**
- `EnumIter`: 支持遍历所有枚举变体
- `Display`: 支持格式化输出

**ts-rs 集成：**
- 所有类型派生 `TS`，自动生成 TypeScript 类型定义
- 支持前端类型安全

### 模型升级推理级别映射

```rust
fn reasoning_effort_mapping_from_presets(
    presets: &[ReasoningEffortPreset],
) -> Option<HashMap<ReasoningEffort, ReasoningEffort>> {
    let supported: Vec<ReasoningEffort> = presets.iter().map(|p| p.effort).collect();
    let mut map = HashMap::new();
    
    for effort in ReasoningEffort::iter() {
        let nearest = nearest_effort(effort, &supported);  // 找到最接近的支持级别
        map.insert(effort, nearest);
    }
    Some(map)
}
```

映射算法使用基于 `effort_rank` 的最近邻算法：
```rust
fn effort_rank(effort: ReasoningEffort) -> i32 {
    match effort {
        ReasoningEffort::None => 0,
        ReasoningEffort::Minimal => 1,
        ReasoningEffort::Low => 2,
        ReasoningEffort::Medium => 3,
        ReasoningEffort::High => 4,
        ReasoningEffort::XHigh => 5,
    }
}
```

## 关键代码路径与文件引用

### 本文件关键代码

| 行号 | 内容 | 说明 |
|------|------|------|
| 25-50 | `ReasoningEffort` | 推理努力级别枚举 |
| 62-83 | `InputModality` | 输入模态枚举 |
| 94-148 | `ModelPreset` | 模型预设结构 |
| 151-160 | `ModelVisibility` | 模型可见性枚举 |
| 163-185 | `ConfigShellToolType` | Shell 工具类型 |
| 204-232 | `TruncationPolicy` / `TruncationPolicyConfig` | 截断策略 |
| 243-294 | `ModelInfo` | 模型信息结构 |
| 338-394 | `ModelMessages` / `ModelInstructionsVariables` | 指令模板系统 |
| 411-415 | `ModelsResponse` | 模型列表响应 |
| 418-475 | `ModelPreset` 实现块 | 过滤和默认选择逻辑 |

### 依赖关系

**本文件导入：**
```rust
use crate::config_types::Personality;
use crate::config_types::ReasoningSummary;
use crate::config_types::Verbosity;
```

**被导入方：**
- `protocol.rs`: 使用 `ReasoningEffort` 作为 `ReasoningEffortConfig`
- `config_types.rs`: 与 `Personality` 等配置类型交互
- `app-server/src/models.rs`: 模型管理
- `core/src/models_manager/`: 模型管理器
- `tui/src/`, `tui_app_server/src/`: UI 展示

### 调用路径示例

```
ModelInfo::get_model_instructions()
    └── ModelMessages::get_personality_message()
        └── ModelInstructionsVariables::get_personality_message()
            └── 根据 Personality 枚举返回对应文本
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `strum` / `strum_macros` | 枚举工具（遍历、显示） |
| `ts_rs` | TypeScript 类型生成 |
| `tracing` | 日志记录 |

### 内部模块依赖

- `config_types.rs`: `Personality`, `ReasoningSummary`, `Verbosity`

## 风险、边界与改进建议

### 已知风险

1. **向前兼容性**
   - 风险：新增字段可能导致旧客户端无法解析
   - 缓解：使用 `#[serde(default)]` 和 `default_*` 函数

2. **Personality 占位符处理**
   - 风险：如果模板包含 `{{ personality }}` 但变量不完整，会静默回退
   - 代码：行 325-335 的警告日志

3. **模型升级映射的精度损失**
   - 风险：不同模型支持的推理级别可能不完全对应
   - 缓解：使用最近邻算法，但可能不是用户期望的映射

### 边界条件

| 场景 | 行为 |
|------|------|
| `ModelInfo` 缺少 `model_messages` | 回退到 `base_instructions` |
| `Personality::None` | 返回空字符串替换占位符 |
| 模型不支持请求的推理级别 | 使用模型默认值 |
| `context_window` 为 None | `auto_compact_token_limit` 返回配置值或 None |

### 测试覆盖

当前测试包括：
- `reasoning_effort_from_str_accepts_known_values`: 字符串解析
- `get_model_instructions_uses_template_when_placeholder_present`: 模板使用
- `get_model_instructions_always_strips_placeholder`: 占位符处理
- `model_preset_preserves_availability_nux`: NUX 保留

### 改进建议

1. **类型安全增强**
   - 考虑为模型 ID 使用新类型（newtype）模式，避免字符串混淆
   - 使用 `NonZeroI64` 等类型表示必须为正的数字

2. **文档完善**
   - 为每个字段添加更详细的文档注释
   - 添加使用示例

3. **验证增强**
   - 在反序列化时验证字段间的逻辑一致性
   - 例如：`supported_reasoning_efforts` 应该包含 `default_reasoning_effort`

4. **性能优化**
   - `ModelInfo::get_model_instructions()` 每次都进行字符串替换
   - 考虑缓存编译后的模板

5. **错误处理**
   - 当前某些错误只记录警告日志
   - 考虑使用 `Result` 类型让调用者决定如何处理
