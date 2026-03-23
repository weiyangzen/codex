# custom_prompts.rs 研究文档

## 场景与职责

`custom_prompts.rs` 是 Codex 协议层中负责**自定义提示词（Custom Prompts）**功能的基础类型定义模块。自定义提示词允许用户定义可复用的提示模板，通过斜杠命令（slash commands）快速调用。

在 Codex 的整体架构中，该模块：
- 定义自定义提示词的数据结构
- 提供提示词命令的命名空间常量
- 支持配置文件中的提示词定义
- 被 TUI 和核心层用于提示词管理和渲染

## 功能点目的

### CustomPrompt 结构体

定义单个自定义提示词的完整信息：
```rust
pub struct CustomPrompt {
    pub name: String,                  // 提示词名称（唯一标识）
    pub path: PathBuf,                 // 提示词文件路径
    pub content: String,               // 提示词内容
    pub description: Option<String>,   // 描述信息
    pub argument_hint: Option<String>, // 参数提示（如需要参数）
}
```

### PROMPTS_CMD_PREFIX 常量

定义自定义提示词斜杠命令的命名空间前缀：
```rust
pub const PROMPTS_CMD_PREFIX: &str = "prompts";
```

**使用形式**（在代码中构造）：
- 命令令牌：`"{PROMPTS_CMD_PREFIX}:name"` → `"prompts:my_prompt"`
- 完整斜杠前缀：`"/{PROMPTS_CMD_PREFIX}:"` → `"/prompts:"`

**示例**: 用户输入 `/prompts:code_review` 触发名为 `code_review` 的自定义提示词

## 具体技术实现

### 派生宏组合

```rust
#[derive(Serialize, Deserialize, Debug, Clone, JsonSchema, TS)]
pub struct CustomPrompt {
    pub name: String,
    pub path: PathBuf,
    pub content: String,
    pub description: Option<String>,
    pub argument_hint: Option<String>,
}
```

**派生 trait 说明：**
- `Serialize`/`Deserialize`: JSON/TOML 序列化支持
- `Debug`: 调试输出
- `Clone`: 值语义复制
- `JsonSchema`: 生成 JSON Schema 文档
- `TS`: 生成 TypeScript 类型定义

### 序列化行为

- 所有字段均参与序列化
- `description` 和 `argument_hint` 为可选字段
- 支持从配置文件（如 config.toml）反序列化

## 关键代码路径与文件引用

### 本文件位置
```
codex-rs/protocol/src/custom_prompts.rs
```

### 被引用位置
通过 `lib.rs` 导出：
```rust
// codex-rs/protocol/src/lib.rs
pub mod custom_prompts;
```

在 `protocol.rs` 中导入使用：
```rust
use crate::custom_prompts::CustomPrompt;
```

### 跨 crate 使用场景
- **配置加载**: 从用户配置中解析自定义提示词列表
- **TUI 补全**: 在斜杠命令输入时提供提示词补全
- **提示词执行**: 将提示词内容注入到对话上下文

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型绑定 |

### 内部依赖
- `std::path::PathBuf` - 文件路径表示

### 相关文件
- 提示词定义文件（用户自定义的 `.md` 或 `.txt` 文件）
- 配置文件（`config.toml`）中的 `prompts` 部分

## 风险、边界与改进建议

### 当前风险

1. **路径处理**: `path` 字段存储的是文件系统路径，跨平台使用时可能存在路径分隔符问题
2. **内容大小**: `content` 字段为 `String`，大提示词可能占用较多内存
3. **命名冲突**: `name` 字段作为标识符，需要确保全局唯一性

### 边界情况

1. **空内容**: `content` 为空字符串时的处理
2. **无效路径**: `path` 指向不存在的文件
3. **特殊字符**: `name` 中包含冒号或其他特殊字符时的命令解析

### 改进建议

1. **路径规范化**: 添加路径规范化处理，确保跨平台兼容性
   ```rust
   impl CustomPrompt {
       pub fn normalized_path(&self) -> PathBuf {
           // 规范化路径分隔符
       }
   }
   ```

2. **验证逻辑**: 添加提示词结构验证
   ```rust
   impl CustomPrompt {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.name.is_empty() {
               return Err(ValidationError::EmptyName);
           }
           if self.content.is_empty() {
               return Err(ValidationError::EmptyContent);
           }
           Ok(())
       }
   }
   ```

3. **延迟加载**: 对于大提示词，考虑使用 `Arc<str>` 或延迟加载机制

4. **命令格式常量**: 添加辅助方法生成完整命令
   ```rust
   impl CustomPrompt {
       pub fn slash_command(&self) -> String {
           format!("/{PROMPTS_CMD_PREFIX}:{}", self.name)
       }
   }
   ```

5. **参数处理**: 如果支持参数化提示词，添加参数解析和替换逻辑
   ```rust
   pub fn render_with_args(&self, args: &[String]) -> String {
       // 参数替换逻辑
   }
   ```

### 测试建议

当前文件无内嵌测试，建议添加：
- 序列化/反序列化测试
- 边界情况测试（空名称、空内容）
- 命令格式生成测试

### 文档建议

1. 添加使用示例，展示如何在配置中定义自定义提示词
2. 说明斜杠命令的完整语法
3. 描述与 Skill 系统的区别和联系
