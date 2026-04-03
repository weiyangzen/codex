# ToolRequestUserInputOption 类型研究报告

## 场景与职责

`ToolRequestUserInputOption` 是一个 **EXPERIMENTAL** 类型，用于定义 `request_user_input` 工具中的单个可选选项。它表示向用户展示的选择题选项，包含标签和描述信息。

**核心使用场景：**

1. **确认对话框**："是"/"否" 或 "确认"/"取消" 类型的二元选择
2. **操作选择**：用户从多个预定义操作中选择（如 "运行测试"/"查看日志"/"跳过"）
3. **配置选择**：从多个配置选项中选择（如 "使用默认模型"/"使用轻量级模型"）
4. **分类选择**：对内容进行标记或分类

**典型使用场景：**
```
AI: "我找到了多个可能的解决方案，请选择您想要的："
  - [选项A] 快速修复（可能不够完善）
  - [选项B] 完整修复（需要更多时间）
  - [选项C] 跳过此问题
```

## 功能点目的

该类型的设计目的包括：

1. **标准化选项格式**：统一选项的数据结构，便于客户端渲染
2. **可访问性支持**：通过 `label`（简短）和 `description`（详细）支持不同展示需求
3. **自描述性**：每个选项都包含足够的信息让用户做出明智选择
4. **UI 无关性**：纯数据结构，可被任何类型的客户端（TUI、GUI、Web）渲染

**字段设计意图：**

| 字段 | 目的 |
|------|------|
| `label` | 简短标识符，通常作为选项值和简短显示文本 |
| `description` | 详细说明，帮助用户理解选择此选项的后果 |

## 具体技术实现

### 数据结构定义

**TypeScript 定义（生成代码）：**
```typescript
/**
 * EXPERIMENTAL. Defines a single selectable option for request_user_input.
 */
export type ToolRequestUserInputOption = { 
  label: string, 
  description: string, 
};
```

**Rust 源定义：**
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL. Defines a single selectable option for request_user_input.
pub struct ToolRequestUserInputOption {
    pub label: String,
    pub description: String,
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `label` | `String` / `string` | 是 | 选项的简短标识符，通常作为选项的值 |
| `description` | `String` / `string` | 是 | 选项的详细描述，向用户解释此选项的含义 |

### 关联类型

| 类型 | 关系 | 说明 |
|------|------|------|
| `ToolRequestUserInputQuestion` | 父容器 | 包含 `options: Option<Vec<ToolRequestUserInputOption>>` |
| `ToolRequestUserInputAnswer` | 对应答案 | 用户选择的 `label` 值会出现在 `answers` 数组中 |
| `ToolRequestUserInputParams` | 请求参数 | 包含问题列表，每个问题可能有选项 |

### 使用模式

```rust
// 典型使用示例
let options = vec![
    ToolRequestUserInputOption {
        label: "yes".to_string(),
        description: "Execute the command with elevated privileges".to_string(),
    },
    ToolRequestUserInputOption {
        label: "no".to_string(),
        description: "Skip this operation and continue".to_string(),
    },
];
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 5665-5672) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ToolRequestUserInputOption.ts` | TypeScript 类型定义（自动生成） |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 5686) | 作为 `ToolRequestUserInputQuestion` 的字段类型 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ToolRequestUserInputQuestion.ts` | 导入并作为字段类型使用 |
| `codex-rs/app-server/tests/suite/v2/request_user_input.rs` | 测试中使用 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 渲染选项 |

### 序列化示例

```json
{
  "label": "run_tests",
  "description": "Run the test suite to verify the changes"
}
```

在完整问题中的使用：
```json
{
  "id": "action_choice",
  "header": "Choose Action",
  "question": "What would you like to do with this file?",
  "isOther": false,
  "isSecret": false,
  "options": [
    {
      "label": "edit",
      "description": "Open the file in the editor"
    },
    {
      "label": "view",
      "description": "Display the file contents"
    },
    {
      "label": "skip",
      "description": "Skip this file and continue"
    }
  ]
}
```

## 依赖与外部交互

### 内部依赖

```
ToolRequestUserInputOption
  ├── serde (Serialize, Deserialize)
  ├── schemars (JsonSchema)
  └── ts_rs (TS)
```

### 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| AI 模型 | 工具调用参数 | 模型生成选项列表 |
| 客户端 UI | 渲染 | 将选项渲染为按钮、单选框等 |
| 用户 | 交互 | 选择一个或多个选项 |

### UI 渲染建议

```typescript
// 示例：在 React 中渲染选项
function OptionsRenderer({ options }: { options: ToolRequestUserInputOption[] }) {
  return (
    <div className="options-list">
      {options.map(option => (
        <button key={option.label} value={option.label}>
          <strong>{option.label}</strong>
          <span>{option.description}</span>
        </button>
      ))}
    </div>
  );
}
```

## 风险、边界与改进建议

### 潜在风险

1. **实验性 API 不稳定**：标记为 EXPERIMENTAL，未来可能变更
2. **label 冲突**：同一问题的多个选项可能有相同的 label，导致答案歧义
3. **描述过长**：description 可能过长，影响 UI 展示
4. **空值处理**：当前设计不允许空字符串，但未在类型层面强制

### 边界情况

| 场景 | 当前行为 | 潜在问题 |
|------|----------|----------|
| 空 label | 允许 | 可能导致答案无法识别 |
| 空 description | 允许 | 用户可能不理解选项含义 |
| 重复 label | 允许 | 答案无法区分选择了哪个选项 |
| 超长 description | 无限制 | UI 展示问题 |

### 改进建议

1. **添加验证**：实现选项验证：
   ```rust
   impl ToolRequestUserInputOption {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.label.is_empty() {
               return Err(ValidationError::EmptyLabel);
           }
           if self.description.is_empty() {
               return Err(ValidationError::EmptyDescription);
           }
           if self.label.len() > 100 {
               return Err(ValidationError::LabelTooLong);
           }
           if self.description.len() > 500 {
               return Err(ValidationError::DescriptionTooLong);
           }
           Ok(())
       }
   }
   ```

2. **添加唯一性检查**：在 `ToolRequestUserInputQuestion` 中验证 label 唯一性：
   ```rust
   pub fn validate_options(&self) -> Result<(), ValidationError> {
       if let Some(options) = &self.options {
           let mut labels = HashSet::new();
           for option in options {
               if !labels.insert(&option.label) {
                   return Err(ValidationError::DuplicateLabel);
               }
           }
       }
       Ok(())
   }
   ```

3. **添加图标/颜色支持**：考虑添加可选的 UI 提示：
   ```rust
   pub struct ToolRequestUserInputOption {
       pub label: String,
       pub description: String,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub icon: Option<String>, // emoji 或 icon 名称
       #[serde(skip_serializing_if = "Option::is_none")]
       pub severity: Option<Severity>, // info, warning, danger
   }
   ```

4. **支持快捷键**：添加键盘快捷键支持：
   ```rust
   pub struct ToolRequestUserInputOption {
       pub label: String,
       pub description: String,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub shortcut: Option<char>, // 如 'y' 表示按 y 选择
   }
   ```

5. **支持默认选项**：标记某个选项为默认选中：
   ```rust
   pub struct ToolRequestUserInputOption {
       pub label: String,
       pub description: String,
       #[serde(default)]
       pub is_default: bool,
   }
   ```

6. **添加 disabled 状态**：支持禁用某些选项：
   ```rust
   pub struct ToolRequestUserInputOption {
       pub label: String,
       pub description: String,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub disabled_reason: Option<String>, // None 表示可用，Some 表示禁用并显示原因
   }
   ```

7. **国际化支持**：考虑添加多语言支持：
   ```rust
   pub struct ToolRequestUserInputOption {
       pub label: String,
       pub description: String,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub i18n_key: Option<String>,
   }
   ```

### 设计模式建议

**选项分组**：
```rust
pub struct ToolRequestUserInputOptionGroup {
    pub group_name: String,
    pub options: Vec<ToolRequestUserInputOption>,
}
```

**嵌套选项**：
```rust
pub struct ToolRequestUserInputOption {
    pub label: String,
    pub description: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sub_options: Option<Vec<ToolRequestUserInputOption>>,
}
```

### 实验性状态说明

作为实验性 API，建议：
- 在文档中明确标注实验性状态
- 收集实际使用反馈以完善设计
- 考虑与现有 UI 框架的兼容性
- 准备向后兼容的迁移路径
