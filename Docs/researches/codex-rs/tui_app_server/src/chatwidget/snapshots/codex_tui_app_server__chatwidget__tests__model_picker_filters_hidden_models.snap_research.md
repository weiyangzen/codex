# 模型选择器过滤隐藏模型测试研究文档

## 场景与职责

本测试验证 `tui_app_server` 中模型选择弹出框对隐藏模型的过滤行为。模型选择器应该只显示 `show_in_picker` 属性为 `true` 的模型，隐藏那些标记为不在选择器中显示的模型（如已弃用或内部测试模型）。

## 功能点目的

1. **模型过滤**: 根据 `show_in_picker` 属性过滤模型列表
2. **用户体验**: 避免向用户展示过多或不适当的模型选项
3. **模型管理**: 支持模型的渐进式发布和弃用
4. **界面整洁**: 保持模型选择界面的简洁性

## 具体技术实现

### 测试流程

```rust
async fn model_picker_filters_hidden_models() {
    // 1. 创建 ChatWidget 实例
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.thread_id = Some(ThreadId::new());

    // 2. 定义模型预设闭包
    let preset = |slug: &str, show_in_picker: bool| ModelPreset {
        id: slug.to_string(),
        model: slug.to_string(),
        display_name: slug.to_string(),
        description: format!("{slug} description"),
        default_reasoning_effort: ReasoningEffortConfig::Medium,
        supported_reasoning_efforts: vec![ReasoningEffortPreset {
            effort: ReasoningEffortConfig::Medium,
            description: "medium".to_string(),
        }],
        supports_personality: false,
        is_default: false,
        upgrade: None,
        show_in_picker,  // 控制是否在模型选择器中显示
        availability_nux: None,
        supported_in_api: true,
        input_modalities: default_input_modalities(),
    };

    // 3. 打开模型弹出框，传入可见和隐藏模型
    chat.open_model_popup_with_presets(vec![
        preset("test-visible-model", true),   // 应该显示
        preset("test-hidden-model", false),   // 应该被过滤
    ]);

    // 4. 渲染并验证弹出框内容
    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("model_picker_filters_hidden_models", popup);
    
    // 5. 断言验证
    assert!(popup.contains("test-visible-model"),
        "expected visible model to appear in picker:\n{popup}");
    assert!(!popup.contains("test-hidden-model"),
        "expected hidden model to be excluded from picker:\n{popup}");
}
```

### 关键数据结构

- **`ModelPreset`**: 模型预设配置
  - `id`: 模型唯一标识
  - `model`: 模型名称
  - `display_name`: 显示名称
  - `description`: 模型描述
  - `show_in_picker`: 是否在选择器中显示
  - `supported_reasoning_efforts`: 支持的推理努力级别
  - `input_modalities`: 支持的输入模态

- **`ReasoningEffortConfig`**: 推理努力配置
  - `Low`, `Medium`, `High`, `XHigh`: 不同推理深度级别

### 渲染输出格式

```
  Select Model and Effort
  Access legacy models by running codex -m <model_name> or in your config.toml

› 1. test-visible-model (current)  test-visible-model description

  Press enter to select reasoning effort, or esc to dismiss.
```

### 过滤逻辑

1. **预设过滤**: `open_model_popup_with_presets` 方法接收模型预设列表
2. **属性检查**: 根据 `show_in_picker` 布尔值决定是否显示
3. **UI 渲染**: 仅渲染通过过滤的模型选项

## 关键代码路径与文件引用

### 测试文件
- **`codex-rs/tui_app_server/src/chatwidget/tests.rs`** (行 8404-8444)
  - 测试函数 `model_picker_filters_hidden_models`
  - 使用闭包创建测试模型预设
  - 验证可见模型显示、隐藏模型被过滤

### 辅助函数
- **`render_bottom_popup`** (行 7303-7332): 渲染底部弹出框并返回字符串
  ```rust
  fn render_bottom_popup(chat: &ChatWidget, width: u16) -> String {
      let height = chat.desired_height(width);
      let area = Rect::new(0, 0, width, height);
      let mut buf = Buffer::empty(area);
      chat.render(area, &mut buf);
      // ... 提取并返回文本内容
  }
  ```

### 源文件
- **`codex-rs/tui_app_server/src/chatwidget.rs`**
  - `open_model_popup_with_presets` 方法打开模型选择弹出框
  - 模型列表过滤逻辑
  - 底部弹出框渲染

### 相关模块
- **`codex-rs/tui_app_server/src/bottom_pane/model_picker.rs`**（如果存在）
  - 模型选择器 UI 组件

### 协议定义
- **`codex-protocol/src/openai_models.rs`**
  - `ModelPreset` 结构定义
  - `ReasoningEffortConfig`, `ReasoningEffortPreset` 定义
  - `InputModality` 输入模态定义

### Snapshot 文件
- **`codex-rs/tui_app_server/src/chatwidget/snapshots/codex_tui_app_server__chatwidget__tests__model_picker_filters_hidden_models.snap`**

## 依赖与外部交互

### 内部依赖
| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理模型选择 |
| `ModelCatalog` | 模型目录，管理可用模型 |
| `BottomPane` | 底部面板，显示弹出框 |
| `ModelPreset` | 模型预设数据结构 |

### 配置选项
| 选项 | 描述 |
|------|------|
| `show_in_picker` | 控制模型是否在选择器中显示 |
| `supported_in_api` | 控制模型是否在 API 中可用 |
| `availability_nux` | 模型可用性新用户体验配置 |

### 测试辅助函数
- `make_chatwidget_manual`: 创建测试用的 ChatWidget 实例
- `render_bottom_popup`: 渲染底部弹出框并提取文本
- `default_input_modalities`: 获取默认输入模态

## 风险、边界与改进建议

### 潜在风险
1. **过滤错误**: 错误地过滤掉应该显示的模型
2. **缓存过期**: 模型列表缓存与服务器不同步
3. **配置漂移**: `show_in_picker` 配置与实际需求不一致

### 边界情况
1. **空列表**: 所有模型都被隐藏时的处理
2. **当前模型隐藏**: 当前使用的模型被标记为隐藏
3. **动态更新**: 模型列表在弹出框打开时更新
4. **搜索过滤**: 结合搜索文本的过滤逻辑

### 改进建议
1. **隐藏原因**: 显示模型被隐藏的原因提示
2. **高级模式**: 提供显示所有模型的"高级模式"选项
3. **模型分组**: 按类别分组显示模型（如 GPT-4、GPT-3.5 等）
4. **搜索增强**: 支持搜索隐藏模型并临时显示
5. **模型推荐**: 根据使用场景推荐合适的模型
6. **弃用提示**: 对即将弃用的模型显示警告
