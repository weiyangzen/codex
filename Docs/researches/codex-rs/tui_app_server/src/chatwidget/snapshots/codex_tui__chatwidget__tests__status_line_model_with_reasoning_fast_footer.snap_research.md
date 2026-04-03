# 研究文档：status_line_model_with_reasoning_fast_footer

## 场景与职责

此 snapshot 测试验证 TUI 状态栏（status line）在显示模型信息、推理级别和快速模式时的渲染效果。测试场景包括：
- 使用 `gpt-5.4` 模型
- 设置推理级别为 `xhigh`（极高）
- 启用 Fast 模式（`fast` 服务层级）
- 显示上下文窗口剩余百分比（100% left）
- 显示当前工作目录（/tmp/project）

该测试确保状态栏能够正确组合多个状态项并以统一的格式呈现给用户。

## 功能点目的

状态栏是 TUI 界面中持续可见的信息区域，其设计目的是：
1. **模型透明度**：让用户清楚当前使用的 AI 模型及其配置
2. **推理级别指示**：显示模型推理努力程度（low/medium/high/xhigh）
3. **服务模式标识**：Fast 模式指示用户正在使用加速推理服务
4. **上下文监控**：实时显示上下文窗口使用情况，防止溢出
5. **位置感知**：显示当前工作目录，帮助用户确认操作路径

这些信息的组合使用户能够在单次扫视中获取关键的运行时上下文。

## 具体技术实现

### 测试设置
```rust
let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.4")).await;
chat.show_welcome_banner = false;
chat.config.cwd = PathBuf::from("/tmp/project");
chat.config.tui_status_line = Some(vec![
    "model-with-reasoning".to_string(),
    "context-remaining".to_string(),
    "current-dir".to_string(),
]);
chat.set_reasoning_effort(Some(ReasoningEffortConfig::XHigh));
chat.set_service_tier(Some(ServiceTier::Fast));
set_chatgpt_auth(&mut chat);
chat.refresh_status_line();
```

### 状态项配置
测试配置了三个状态项：
- `model-with-reasoning`：显示模型名称和推理级别
- `context-remaining`：显示剩余上下文百分比
- `current-dir`：显示当前工作目录

### 渲染输出格式
```
  gpt-5.4 xhigh fast · 100% left · /tmp/project
```

格式解析：
- `gpt-5.4`：模型名称
- `xhigh`：推理级别后缀
- `fast`：Fast 模式标识
- `·`：分隔符（中间点）
- `100% left`：上下文剩余百分比
- `/tmp/project`：当前工作目录

## 关键代码路径与文件引用

### 核心实现文件
1. **`codex-rs/tui/src/bottom_pane/status_line_setup.rs`**
   - 定义 `StatusLineItem` 枚举，包含所有可配置的状态项
   - `ModelWithReasoning` 变体处理模型+推理级别的组合显示
   - `FastMode` 变体处理快速模式指示

2. **`codex-rs/tui/src/bottom_pane/footer.rs`**
   - 实现状态栏的渲染逻辑
   - 处理多个状态项的组合和分隔符插入
   - 管理状态项的截断和布局

3. **`codex-rs/tui/src/chatwidget/tests.rs`**（行 10638-10665）
   - 测试函数 `status_line_model_with_reasoning_fast_footer_snapshot`
   - 验证状态栏的完整渲染输出

### 相关数据结构
```rust
// StatusLineItem 枚举定义
pub(crate) enum StatusLineItem {
    ModelName,
    ModelWithReasoning,  // 本测试使用的项
    CurrentDir,          // 本测试使用的项
    ContextRemaining,    // 本测试使用的项
    FastMode,           // 通过 ServiceTier 隐式显示
    // ... 其他变体
}
```

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `bottom_pane::status_line_setup` | 状态项定义和配置管理 |
| `bottom_pane::footer` | 状态栏渲染实现 |
| `chatwidget::ChatWidget` | 状态管理和事件处理 |

### 配置依赖
- `tui_status_line` 配置项：定义显示哪些状态项及其顺序
- `model` 配置：当前选中的模型
- `reasoning_effort` 配置：推理级别设置
- `service_tier` 配置：服务模式（Fast/Standard）

### 外部服务
- 需要 ChatGPT 认证（`set_chatgpt_auth`）以获取完整的模型信息

## 风险、边界与改进建议

### 潜在风险
1. **截断问题**：当终端宽度不足时，状态项可能被截断，导致信息不完整
2. **分隔符一致性**：分隔符 `·` 需要在所有状态项组合场景中保持一致
3. **推理级别显示**：不同模型的推理级别命名可能不一致（如 `xhigh` vs `maximum`）

### 边界情况
1. **空状态项**：当某个状态项无值时（如未在 git 仓库中），应正确省略该项及其分隔符
2. **超长路径**：工作目录路径过长时应优雅截断
3. **多模式组合**：Fast 模式与推理级别的组合显示逻辑需要保持一致

### 改进建议
1. **动态优先级**：在窄终端中，根据重要性动态隐藏低优先级状态项
2. **颜色编码**：为不同推理级别使用不同颜色（如 xhigh 使用红色警示）
3. **工具提示**：在状态栏项上添加悬停提示，显示更详细的信息
4. **配置验证**：在加载配置时验证状态项名称，提供清晰的错误信息

### 相关测试
- `status_line_model_with_reasoning_fast_footer_snapshot`：本测试文件
- `status_widget_active_snapshot`：状态小部件活动状态测试
- `status_widget_and_approval_modal_snapshot`：状态与模态框组合测试
