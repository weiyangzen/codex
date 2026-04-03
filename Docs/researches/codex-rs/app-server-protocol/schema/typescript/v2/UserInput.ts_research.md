# UserInput.ts Research Document

## 场景与职责

`UserInput` 是 App-Server Protocol v2 中定义用户输入内容的核心 discriminated union（可辨识联合）类型。它在以下场景中发挥关键作用：

1. **多模态输入支持**: 支持文本、图片、本地图片、技能引用、提及等多种输入形式
2. **富文本编辑**: 支持在文本中嵌入特殊元素（通过 `text_elements`）
3. **技能系统集成**: 允许用户通过 `@skill` 语法引用和激活技能
4. **上下文引用**: 支持通过 `@mention` 引用对话历史或其他上下文
5. **跨平台兼容**: 统一处理来自 TUI、Web、CLI 等不同客户端的输入

## 功能点目的

该联合类型的核心目的是：

- **输入抽象**: 为所有形式的用户输入提供统一的类型封装
- **类型安全**: 通过 discriminated union 确保类型安全，编译器可以正确推断各变体的字段
- **扩展性**: 易于添加新的输入类型而无需破坏现有代码
- **序列化友好**: 支持 JSON 序列化，便于网络传输
- **UI 渲染指导**: 为客户端提供渲染输入内容所需的全部信息

## 具体技术实现

### TypeScript 类型定义

```typescript
export type UserInput = 
  | { "type": "text", text: string, text_elements: Array<TextElement> }
  | { "type": "image", url: string }
  | { "type": "localImage", path: string }
  | { "type": "skill", name: string, path: string }
  | { "type": "mention", name: string, path: string };
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum UserInput {
    Text {
        text: String,
        /// UI-defined spans within `text` used to render or persist special elements.
        #[serde(default)]
        text_elements: Vec<TextElement>,
    },
    Image {
        url: String,
    },
    LocalImage {
        path: PathBuf,
    },
    Skill {
        name: String,
        path: PathBuf,
    },
    Mention {
        name: String,
        path: String,
    },
}
```

### 变体详解

| 变体 | `type` 值 | 字段 | 用途 |
|-----|----------|------|------|
| **Text** | `"text"` | `text: string`, `text_elements: TextElement[]` | 纯文本输入，支持富文本元素 |
| **Image** | `"image"` | `url: string` | 网络图片，通过 URL 引用 |
| **LocalImage** | `"localImage"` | `path: string` | 本地图片，通过文件路径引用 |
| **Skill** | `"skill"` | `name: string`, `path: string` | 技能引用，激活特定技能 |
| **Mention** | `"mention"` | `name: string`, `path: string` | 提及引用，引用对话历史或其他实体 |

### TextElement 结构

```typescript
export type TextElement = {
  byteRange: ByteRange,    // 在父文本中的字节范围
  placeholder: string | null,  // 可选的人类可读占位符
};
```

`text_elements` 用于标记文本中的特殊区域，例如：
- 技能引用标记（`@skill`）
- 提及标记（`@mention`）
- 代码块、链接等富文本元素

### 核心层转换

Rust 实现提供了与核心层类型的双向转换：

```rust
impl UserInput {
    pub fn into_core(self) -> CoreUserInput {
        match self {
            UserInput::Text { text, text_elements } => 
                CoreUserInput::Text { text, text_elements: ... },
            UserInput::Image { url } => 
                CoreUserInput::Image { image_url: url },
            UserInput::LocalImage { path } => 
                CoreUserInput::LocalImage { path },
            UserInput::Skill { name, path } => 
                CoreUserInput::Skill { name, path },
            UserInput::Mention { name, path } => 
                CoreUserInput::Mention { name, path },
        }
    }
}
```

### 字符计数辅助方法

```rust
impl UserInput {
    pub fn text_char_count(&self) -> usize {
        match self {
            UserInput::Text { text, .. } => text.chars().count(),
            _ => 0,
        }
    }
}
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 4041-4115) | Rust 枚举定义及实现 |
| `codex-rs/app-server-protocol/schema/typescript/v2/UserInput.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/UserInput.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `TurnStartParams`, `TurnSteerParams` 等类型的字段 |
| `codex-rs/protocol/src/user_input.rs` | 核心层 `UserInput` 定义 |
| `codex-rs/core/src/mentions.rs` | 提及解析和处理 |
| `codex-rs/tui/src/bottom_pane/request_user_input/` | TUI 输入处理和渲染 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/` | TUI 应用服务器输入处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 服务器端输入处理 |

### 解析流程

```
用户输入文本
    │
    ▼
提及/技能解析 (mentions.rs)
    │
    ▼
转换为 UserInput 数组
    │
    ▼
序列化 → 网络传输 → 反序列化
    │
    ▼
CoreUserInput 转换 → 核心层处理
```

## 依赖与外部交互

### 内部依赖

- **`TextElement`**: 文本输入中的富文本元素标记
- **`ByteRange`**: `TextElement` 中的字节范围定义
- **`CoreUserInput`**: 核心层对应的用户输入类型

### 协议依赖

- 被多个请求参数类型使用：
  - `TurnStartParams.input`
  - `TurnSteerParams.input`
  - `ToolRequestUserInputResponse.input`

### 客户端交互

- **TUI 客户端**: 
  - 解析用户输入中的 `@skill` 和 `@mention`
  - 渲染 `text_elements` 标记的特殊样式
  - 处理图片输入（本地路径或 URL）

- **Web 客户端**: 
  - 支持拖拽图片上传
  - 富文本编辑器集成
  - 技能选择器 UI

## 风险、边界与改进建议

### 潜在风险

1. **路径安全**: `LocalImage` 和 `Skill` 中的 `path` 字段可能包含恶意路径（如 `../../../etc/passwd`）
2. **URL 验证**: `Image` 变体的 URL 需要验证格式和安全性
3. **大文本处理**: 超大 `text` 字段可能导致内存和性能问题
4. **text_elements 一致性**: `text_elements` 的字节范围可能与实际文本不匹配

### 边界情况

1. **空文本**: `Text` 变体中 `text` 为空字符串时的处理
2. **空 elements**: `text_elements` 为空数组（`#[serde(default)]` 确保兼容性）
3. **无效字节范围**: `text_elements` 中的 `byteRange` 超出文本范围
4. **混合输入**: 同一回合中混合多种输入类型的顺序和优先级

### 改进建议

1. **输入验证**: 添加结构化的输入验证：
   ```rust
   impl UserInput {
       pub fn validate(&self) -> Result<(), ValidationError> {
           match self {
               UserInput::Text { text, text_elements } => {
                   // 验证 text_elements 字节范围有效性
               }
               UserInput::LocalImage { path } => {
                   // 验证路径安全性
               }
               // ...
           }
       }
   }
   ```

2. **大小限制**: 添加输入大小限制配置：
   ```rust
   pub struct InputLimits {
       max_text_length: usize,
       max_text_elements: usize,
       max_image_size: usize,
   }
   ```

3. **URL 安全**: 对 `Image` URL 添加安全校验：
   - 协议白名单（https only）
   - 域名限制
   - 内容类型验证

4. **text_elements 规范化**: 添加方法确保字节范围排序且不重叠：
   ```rust
   pub fn normalize_text_elements(elements: &mut Vec<TextElement>) {
       elements.sort_by_key(|e| e.byte_range.start);
       // 合并或报告重叠范围
   }
   ```

5. **新增变体**: 考虑添加更多输入类型：
   - `Audio`: 语音输入
   - `File`: 通用文件附件
   - `Location`: 地理位置

### 测试覆盖

- 单元测试: `codex-rs/core/src/mentions_tests.rs`
- 集成测试: `codex-rs/app-server/tests/suite/v2/request_user_input.rs`
- 建议添加：
  - 输入验证测试
  - 大文本性能测试
  - 路径安全性测试
  - 字节范围边界测试
