# 模型选择弹出框测试研究文档

## 场景与职责

该 snapshot 测试验证 tui_app_server 的 ChatWidget 能够正确显示模型选择弹出框，允许用户从可用模型列表中选择不同的 AI 模型。

**测试场景**：
1. 用户当前使用 gpt-5-codex 模型
2. 用户已建立线程（thread_id 已设置）
3. 打开模型选择弹出框，显示所有可用模型及其描述

**职责**：确保模型选择界面清晰展示所有可用选项，包括模型名称、描述和默认标记，帮助用户做出明智的模型选择。

## 功能点目的

- **模型发现**：展示所有可用的 AI 模型供用户选择
- **信息展示**：为每个模型提供描述性信息，帮助用户理解模型特点
- **默认指示**：明确标记默认模型，方便用户快速选择
- **向后兼容提示**：告知用户如何通过命令行或配置文件访问旧版模型

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 8332-8339 行

```rust
#[tokio::test]
async fn model_selection_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5-codex")).await;
    chat.thread_id = Some(ThreadId::new());
    chat.open_model_popup();

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("model_selection_popup", popup);
}
```

### 关键实现细节

1. **初始化 ChatWidget**：使用 `make_chatwidget_manual` 创建测试实例，指定当前模型为 gpt-5-codex
2. **设置线程 ID**：模拟已建立会话的状态，某些模型选择功能可能需要活跃会话
3. **打开模型弹出框**：调用 `open_model_popup()` 触发模型选择界面
4. **渲染捕获**：使用 `render_bottom_popup` 在 80 列宽度下渲染弹出框内容

### Snapshot 输出内容

```
Select Model and Effort
Access legacy models by running codex -m <model_name> or in your config.toml

› 1. gpt-5.3-codex (default)  Latest frontier agentic coding model.
  2. gpt-5.4                  Latest frontier agentic coding model.
  3. gpt-5.2-codex            Frontier agentic coding model.
  4. gpt-5.1-codex-max        Codex-optimized flagship for deep and fast reasoning.
  5. gpt-5.2                  Latest frontier model with improvements across knowledge, reasoning and coding
  6. gpt-5.1-codex-mini       Optimized for codex. Cheaper, faster, but less capable.

Press enter to select reasoning effort, or esc to dismiss.
```

## 关键代码路径与文件引用

### 主要代码文件

1. **测试文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 测试函数：`model_selection_popup_snapshot` (第 8332 行)
   - 辅助函数：`make_chatwidget_manual`, `render_bottom_popup`

2. **ChatWidget 实现**：`codex-rs/tui_app_server/src/chatwidget/mod.rs`
   - 方法：`open_model_popup`, `open_model_popup_with_presets`

3. **底部面板**：`codex-rs/tui_app_server/src/bottom_pane/mod.rs`
   - 负责渲染模型选择列表 UI

4. **模型目录**：`codex-rs/tui_app_server/src/model_catalog.rs`
   - 提供可用模型列表
   - 包含模型预设信息（名称、描述、默认推理级别等）

### 相关协议类型

- `ModelPreset`：模型预设配置，包含：
  - `id`：模型唯一标识
  - `model`：模型名称
  - `display_name`：显示名称
  - `description`：模型描述
  - `default_reasoning_effort`：默认推理级别
  - `is_default`：是否为默认模型标记
  - `show_in_picker`：是否在选取器中显示

## 依赖与外部交互

### 内部依赖

| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理模型选择状态 |
| `BottomPane` | 渲染底部弹出框 UI |
| `ModelCatalog` | 提供可用模型列表和配置信息 |
| `ThreadId` | 会话标识，用于模型选择上下文 |

### 外部依赖

- `ratatui`：终端 UI 渲染库
- `insta`：snapshot 测试框架
- `tokio`：异步运行时

### 配置依赖

- 模型配置来自 `ModelCatalog`，基于 `codex_core::test_support::all_model_presets()`
- 协作模式配置影响模型选择行为

## 风险、边界与改进建议

### 潜在风险

1. **模型列表变化**：随着新模型发布或旧模型退役，snapshot 可能需要频繁更新
2. **描述文本长度**：模型描述可能过长，在窄屏幕上显示不完整
3. **默认模型变更**：默认模型改变会影响用户体验和测试稳定性

### 边界情况

1. **隐藏模型**：某些模型可能设置 `show_in_picker = false`，不应出现在列表中（见 `model_picker_hides_show_in_picker_false_models_from_cache` 测试）
2. **无可用模型**：如果模型目录为空或无法加载，需要优雅处理
3. **网络依赖**：模型列表可能需要从服务器获取，离线时的降级处理

### 改进建议

1. **搜索/过滤功能**：添加模型搜索功能，方便用户在长列表中快速找到目标模型
2. **收藏/常用模型**：允许用户标记常用模型，置顶显示
3. **性能指标**：显示各模型的典型响应时间或资源消耗指标
4. **模型对比**：提供模型对比功能，帮助用户选择最适合的模型
5. **最近使用**：显示最近使用的模型，提高选择效率

### 相关测试

- `model_picker_hides_show_in_picker_false_models_from_cache`：验证隐藏模型过滤
- `model_reasoning_selection_popup_snapshot`：模型选择后的推理级别选择
- `reasoning_popup_escape_returns_to_model_popup`：验证 ESC 返回模型选择界面
- `server_overloaded_error_does_not_switch_models`：服务器过载时的模型切换行为
