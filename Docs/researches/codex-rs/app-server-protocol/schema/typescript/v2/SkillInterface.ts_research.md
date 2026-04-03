# SkillInterface.ts 研究文档

## 场景与职责

`SkillInterface.ts` 定义了技能界面配置的数据结构，用于描述技能的展示层属性。这是 Codex 技能系统的 UI 组件，控制技能在界面中的显示方式，包括名称、图标、颜色等视觉元素。

## 功能点目的

该类型用于：
1. **技能展示**：定义技能在 UI 中的显示名称和描述
2. **品牌识别**：通过颜色和图标区分不同技能
3. **用户体验**：提供视觉提示帮助用户识别和使用技能
4. **默认提示**：提供技能的默认使用提示

## 具体技术实现

### 数据结构定义

```typescript
export type SkillInterface = { 
  displayName?: string,        // 显示名称
  shortDescription?: string,   // 简短描述
  iconSmall?: string,          // 小图标路径/URL
  iconLarge?: string,          // 大图标路径/URL
  brandColor?: string,         // 品牌颜色（十六进制）
  defaultPrompt?: string       // 默认提示模板
};
```

### 字段详解

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| displayName | string | 否 | 技能在 UI 中显示的名称，如未提供则使用技能名 |
| shortDescription | string | 否 | 技能的简短描述，用于列表展示 |
| iconSmall | string | 否 | 小图标路径（建议 16x16 或 24x24）|
| iconLarge | string | 否 | 大图标路径（建议 48x48 或 64x64）|
| brandColor | string | 否 | 品牌主题色，十六进制格式（如 "#FF5733"）|
| defaultPrompt | string | 否 | 技能的默认提示模板，用户可基于此修改 |

### Rust 协议定义

在 `codex-rs/protocol/src/protocol.rs` 中：

```rust
#[derive(
    Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema, TS,
)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillInterface {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub short_description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon_small: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon_large: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub brand_color: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub default_prompt: Option<String>,
}
```

### 核心技能界面类型

在 `codex-rs/core/src/skills/model.rs` 中：

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillInterface {
    pub display_name: Option<String>,
    pub short_description: Option<String>,
    pub icon_small: Option<PathBuf>,
    pub icon_large: Option<PathBuf>,
    pub brand_color: Option<String>,
    pub default_prompt: Option<String>,
}
```

### SKILL.json 配置示例

```json
{
  "name": "code-review",
  "interface": {
    "displayName": "Code Review",
    "shortDescription": "Review code for quality and best practices",
    "iconSmall": "./icons/review-small.png",
    "iconLarge": "./icons/review-large.png",
    "brandColor": "#4A90D9",
    "defaultPrompt": "Please review this code for: 1) Code quality, 2) Potential bugs, 3) Best practices"
  }
}
```

### 在 SkillMetadata 中的使用

```rust
#[derive(Debug, Clone, PartialEq)]
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    pub short_description: Option<String>,  // 向后兼容
    pub interface: Option<SkillInterface>,
    pub dependencies: Option<SkillDependencies>,
    pub path: String,
    pub scope: SkillScope,
    pub enabled: bool,
}
```

### UI 集成

在 `codex-rs/tui/src/bottom_pane/chat_composer.rs` 中：

```rust
fn render_skill_button(skill: &SkillMetadata) -> Button {
    let display_name = skill.interface
        .as_ref()
        .and_then(|i| i.display_name.as_ref())
        .unwrap_or(&skill.name);
    
    let color = skill.interface
        .as_ref()
        .and_then(|i| i.brand_color.as_ref())
        .and_then(|c| parse_color(c).ok())
        .unwrap_or_default_color();
    
    Button::new(display_name)
        .style(Style::default().fg(color))
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SkillInterface.ts`

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/protocol.rs`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 核心技能实现
- 技能模型：`codex-rs/core/src/skills/model.rs`
- 技能加载器：`codex-rs/core/src/skills/loader.rs`

### 服务端集成
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 客户端消费
- TUI 聊天组件：`codex-rs/tui/src/bottom_pane/chat_composer.rs`
- TUI 技能助手：`codex-rs/tui/src/chatwidget/skills.rs`
- TUI App Server：`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`

### 相关类型
- SkillMetadata：`codex-rs/app-server-protocol/schema/typescript/v2/SkillMetadata.ts`
- SkillSummary：`codex-rs/app-server-protocol/schema/typescript/v2/SkillSummary.ts`

## 依赖与外部交互

### 上游依赖
- SKILL.json：从技能配置文件中读取界面定义
- 资源文件：图标文件需要存在于指定路径

### 下游消费
- UI 渲染：在 TUI 和 IDE 扩展中显示技能
- 提示模板：defaultPrompt 可作为用户输入的起点

### 设计考虑

| 属性 | 用途 | 设计建议 |
|------|------|---------|
| displayName | 按钮/列表显示 | 简洁明了，2-3个词 |
| shortDescription | 工具提示 | 一句话描述用途 |
| iconSmall | 列表/按钮 | 简单图标，高对比度 |
| iconLarge | 详情页 | 更丰富的视觉设计 |
| brandColor | 品牌识别 | 与技能主题相符 |
| defaultPrompt | 用户引导 | 清晰的使用示例 |

## 风险、边界与改进建议

### 边界情况
1. **空界面**：所有字段都是可选的，可能完全为空
2. **无效颜色**：brandColor 可能不是有效的十六进制颜色
3. **图标缺失**：指定的图标路径可能不存在
4. **长文本**：displayName 或 shortDescription 可能过长

### 潜在风险
1. **XSS 风险**：defaultPrompt 如果包含恶意内容可能被注入
2. **路径遍历**：图标路径可能指向敏感文件
3. **性能问题**：大图标文件可能影响加载性能

### 改进建议
1. **颜色验证**：验证 brandColor 是有效的颜色格式
2. **图标缓存**：缓存图标避免重复加载
3. **文本截断**：UI 层处理长文本的截断和省略
4. **国际化**：支持多语言的 displayName 和 description
5. **动态图标**：支持使用 emoji 或字符作为图标
6. **预览模式**：在保存前预览技能的 UI 效果
