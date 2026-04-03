# 模型推理选择弹出框测试研究文档

## 场景与职责

本测试验证 `tui_app_server` 中模型推理努力级别（Reasoning Effort）选择弹出框的渲染。当用户选择支持推理努力配置的模型时，系统会显示一个弹出框让用户选择推理深度级别（Low、Medium、High、Extra High），不同级别影响模型的推理深度和响应速度。

## 功能点目的

1. **推理级别选择**: 允许用户选择模型的推理努力级别
2. **性能权衡**: 让用户在响应速度和推理深度之间权衡
3. **模型能力展示**: 展示当前模型支持的推理能力
4. **当前设置指示**: 显示当前选中的推理级别

## 具体技术实现

### 测试流程

```rust
async fn model_reasoning_selection_popup_snapshot() {
    // 1. 创建 ChatWidget 实例，指定使用 gpt-5.1-codex-max 模型
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.1-codex-max")).await;

    // 2. 设置 ChatGPT 认证
    set_chatgpt_auth(&mut chat);
    
    // 3. 设置当前推理努力级别为 High
    chat.set_reasoning_effort(Some(ReasoningEffortConfig::High));

    // 4. 获取模型预设并打开推理选择弹出框
    let preset = get_available_model(&chat, "gpt-5.1-codex-max");
    chat.open_reasoning_popup(preset);

    // 5. 渲染并验证弹出框
    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("model_reasoning_selection_popup", popup);
}
```

### 关键数据结构

- **`ReasoningEffortConfig`**: 推理努力配置
  - `Low`: 快速响应，轻度推理
  - `Medium`: 平衡速度和推理深度（默认）
  - `High`: 更深入的推理，适合复杂问题
  - `XHigh`: 额外深入的推理，适合最复杂的问题

- **`ReasoningEffortPreset`**: 推理努力预设
  - `effort`: 推理级别
  - `description`: 级别描述

- **`ModelPreset`**: 模型预设（相关字段）
  - `supported_reasoning_efforts`: 支持的推理努力级别列表
  - `default_reasoning_effort`: 默认推理努力级别

### 渲染输出格式

```
  Select Reasoning Level for gpt-5.1-codex-max

  1. Low               Fast responses with lighter reasoning
  2. Medium (default)  Balances speed and reasoning depth for everyday tasks
› 3. High (current)    Greater reasoning depth for complex problems
  4. Extra high        Extra high reasoning depth for complex problems

  Press enter to confirm or esc to go back
```

### UI 元素说明

- **Select Reasoning Level for gpt-5.1-codex-max**: 标题，显示当前模型名称
- **1. Low**: 选项编号和级别名称
- **Fast responses with lighter reasoning**: 级别描述
- **(default)**: 标记默认选项
- **(current)**: 标记当前选中选项
- **›**: 光标指示当前聚焦选项
- **Press enter to confirm or esc to go back**: 操作提示

## 关键代码路径与文件引用

### 测试文件
- **`codex-rs/tui_app_server/src/chatwidget/tests.rs`** (行 8627-8639)
  - 测试函数 `model_reasoning_selection_popup_snapshot`
  - 设置 High 推理级别并验证弹出框渲染

### 相关测试
- **`model_reasoning_selection_popup_extra_high_warning_snapshot`** (行 8641-8653)
  - 测试 Extra High 级别的警告显示
- **`reasoning_popup_shows_extra_high_with_space`** (行 8655-8673)
  - 验证 "Extra high" 正确显示为空格分隔
- **`single_reasoning_option_skips_selection`** (行 8675-8705)
  - 测试单选项时跳过选择

### 辅助函数
- **`set_chatgpt_auth`**: 设置 ChatGPT 认证状态
- **`get_available_model`**: 获取可用模型预设
- **`render_bottom_popup`**: 渲染底部弹出框

### 源文件
- **`codex-rs/tui_app_server/src/chatwidget.rs`**
  - `open_reasoning_popup` 方法打开推理选择弹出框
  - `set_reasoning_effort` 设置当前推理努力级别
  - `current_collaboration_mode` 中的推理配置

### 相关模块
- **`codex-rs/tui_app_server/src/bottom_pane/reasoning_popup.rs`**（如果存在）
  - 推理选择弹出框 UI 组件

### 协议定义
- **`codex-protocol/src/openai_models.rs`**
  - `ReasoningEffortConfig` 枚举定义
  - `ReasoningEffortPreset` 结构定义
  - `ModelPreset` 中的推理相关字段

### Snapshot 文件
- **`codex-rs/tui_app_server/src/chatwidget/snapshots/codex_tui_app_server__chatwidget__tests__model_reasoning_selection_popup.snap`**

## 依赖与外部交互

### 内部依赖
| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理推理选择 |
| `ModelCatalog` | 模型目录，提供模型预设 |
| `BottomPane` | 底部面板，显示弹出框 |
| `CollaborationMode` | 协作模式，包含推理配置 |

### 配置选项
| 选项 | 描述 |
|------|------|
| `reasoning_effort` | 当前推理努力级别 |
| `supported_reasoning_efforts` | 模型支持的推理级别列表 |
| `default_reasoning_effort` | 模型默认推理级别 |

### 测试辅助函数
- `make_chatwidget_manual`: 创建测试用的 ChatWidget 实例
- `set_chatgpt_auth`: 设置 ChatGPT 认证
- `get_available_model`: 获取指定模型的预设
- `render_bottom_popup`: 渲染底部弹出框

## 风险、边界与改进建议

### 潜在风险
1. **级别不匹配**: 选择的推理级别与模型实际能力不匹配
2. **成本影响**: 高级别推理可能增加 API 成本
3. **响应延迟**: 高级别推理可能导致响应时间过长

### 边界情况
1. **单选项模型**: 仅支持单一推理级别的模型
2. **不支持推理**: 完全不支持推理配置的模型
3. **动态切换**: 回合进行中切换推理级别
4. **模型切换**: 切换模型时保留推理级别设置

### 改进建议
1. **成本提示**: 显示不同推理级别的大致成本差异
2. **响应时间预估**: 提供不同级别的预期响应时间
3. **智能推荐**: 根据任务复杂度推荐合适的推理级别
4. **快捷切换**: 添加快捷键快速切换常用级别
5. **使用统计**: 显示各推理级别的使用统计
6. **模型对比**: 支持对比不同推理级别的输出差异
