# Research: codex_tui__app__tests__clear_ui_header_fast_status_gpt54_only.snap

## 场景与职责

本快照文件测试 TUI 头部区域在特定模型配置（GPT-5.4）下的显示，特别是当模型支持 "fast" 状态指示时的渲染行为。

## 功能点目的

验证头部 UI 在以下场景的正确显示：
- 特定模型版本（gpt-5.4）
- 推理级别（xhigh）
- 快速模式指示（fast）
- 模型切换提示

## 具体技术实现

### UI 布局结构

```
╭────────────────────────────────────────────────────╮
│ >_ OpenAI Codex (v<VERSION>)                       │
│                                                    │
│ model:     gpt-5.4 xhigh   fast   /model to change │
│ directory: /tmp/project                            │
╰────────────────────────────────────────────────────╯
```

### 模型信息格式

模型信息行包含多个部分：
1. **模型名称**: `gpt-5.4`
2. **推理级别**: `xhigh`（extra high reasoning effort）
3. **快速模式**: `fast`（表示支持或启用了快速响应模式）
4. **切换提示**: `/model to change`

### 关键数据结构

```rust
// ReasoningEffort 枚举定义
pub enum ReasoningEffort {
    Low,
    Medium,
    High,
    XHigh,  // 对应快照中的 "xhigh"
}

// ModelPreset 结构体
pub struct ModelPreset {
    pub name: String,
    pub supports_fast_mode: bool,
    pub reasoning_effort: ReasoningEffort,
}
```

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/app.rs`
- **模型定义**: `codex-protocol/src/openai_models.rs`
- **配置类型**: `codex-core/src/config/types.rs`

## 依赖与外部交互

- **模型管理器**: `models_manager` 提供模型预设配置
- **协议类型**: `ReasoningEffort`, `ModelPreset`
- **渲染框架**: `ratatui` 用于文本布局和样式

## 风险、边界与改进建议

### 边界情况

1. **模型信息长度**: gpt-5.4 + xhigh + fast 组合较长，需要足够宽度显示
2. **终端宽度**: 窄终端可能导致信息截断或换行
3. **动态更新**: 模型切换后头部需要实时更新

### 风险点

1. **信息密度**: 单行显示过多信息可能影响可读性
2. **术语一致性**: "xhigh" vs "extra high" 的显示一致性

### 改进建议

1. 考虑使用图标或颜色编码代替文本标签（如 🔥 表示 fast）
2. 添加工具提示（tooltip）显示完整的模型配置信息
3. 支持自定义头部信息格式
4. 在窄终端上考虑折叠或简化显示
