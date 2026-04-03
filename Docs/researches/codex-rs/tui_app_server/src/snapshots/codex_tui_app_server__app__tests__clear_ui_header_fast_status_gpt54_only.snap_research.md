# Clear UI Header with Fast Status for GPT-5.4 - Technical Research Document

## Snapshot File
`codex_tui_app_server__app__tests__clear_ui_header_fast_status_gpt54_only.snap`

## Snapshot Content
```
╭────────────────────────────────────────────────────╮
│ >_ OpenAI Codex (v<VERSION>)                       │
│                                                    │
│ model:     gpt-5.4 xhigh   fast   /model to change │
│ directory: /tmp/project                            │
╰────────────────────────────────────────────────────╯
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 `/clear` 命令执行后的 UI 头部显示，特别是当使用 GPT-5.4 模型且启用了 Fast 状态时的显示效果。这是 `clear_ui_after_long_transcript_fresh_header_only` 测试的变体，专注于特定模型配置下的头部渲染。

### 1.2 业务职责
- **Fast 状态显示**: 当使用支持 Fast 模式的模型时，在模型名称后显示 "fast" 标识
- **推理努力程度显示**: 显示当前模型的推理努力程度（xhigh）
- **头部信息完整性**: 确保清理后的头部包含所有关键会话信息

### 1.3 使用场景
1. 用户使用 GPT-5.4 模型且启用了 Fast 模式
2. 执行 `/clear` 或 `Ctrl+L` 清理屏幕
3. 验证头部正确显示 Fast 状态标识

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 组件 | 内容 | 目的 |
|------|------|------|
| 模型信息 | `gpt-5.4 xhigh` | 显示模型名称和推理努力程度 |
| Fast 标识 | `fast` | 标识当前启用了 Fast 服务模式 |
| 修改提示 | `/model to change` | 提示用户如何切换模型 |

### 2.2 Fast 服务模式
Fast 服务是 OpenAI API 的一项功能，提供：
- 优先处理请求
- 更快的响应时间
- 按使用量计费

当 `service_tier` 设置为 `"fast"` 时，UI 会在模型信息旁显示 "fast" 标识。

### 2.3 推理努力程度
- `low`: 快速响应，适合简单任务
- `medium`: 平衡模式
- `high`: 深度推理，适合复杂任务
- `xhigh`: 最高级别推理

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 头部生成逻辑
```rust
// app.rs:1402-1418
fn clear_ui_header_lines_with_version(
    &self,
    width: u16,
    version: &'static str,
) -> Vec<Line<'static>> {
    history_cell::SessionHeaderHistoryCell::new(
        self.chat_widget.current_model().to_string(),
        self.chat_widget.current_reasoning_effort(),
        self.chat_widget.should_show_fast_status(
            self.chat_widget.current_model(),
            self.chat_widget.current_service_tier(),
        ),
        self.config.cwd.clone(),
        version,
    )
    .display_lines(width)
}
```

### 3.2 Fast 状态检测
```rust
// chatwidget.rs
fn should_show_fast_status(&self, model: &str, service_tier: Option<ServiceTier>) -> bool {
    // 仅对特定模型显示 Fast 状态
    matches!(model, "gpt-5.4" | "gpt-5.3-codex") &&
    matches!(service_tier, Some(ServiceTier::Fast))
}
```

### 3.3 测试实现
```rust
// app.rs:7710-7740
async fn render_clear_ui_header_fast_status_gpt54_only() -> String {
    let mut app = make_test_app().await;
    
    // 设置 GPT-5.4 模型和 Fast 服务
    app.chat_widget.set_model("gpt-5.4");
    app.chat_widget.set_reasoning_effort(Some(ReasoningEffort::XHigh));
    app.chat_widget.set_service_tier(Some(ServiceTier::Fast));
    
    let rendered = app
        .clear_ui_header_lines_with_version(80, "<VERSION>")
        .iter()
        .map(|line| line.spans.iter().map(|span| span.content.as_ref()).collect::<String>())
        .collect::<Vec<_>>()
        .join("\n");
    
    // 验证 Fast 标识显示
    assert!(rendered.contains("fast"));
    assert!(rendered.contains("xhigh"));
    
    rendered
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/app.rs` | 清理逻辑、头部生成 |
| `codex-rs/tui_app_server/src/history_cell.rs` | SessionHeaderHistoryCell 实现 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 模型状态管理 |

### 4.2 调用链
```
/clear 命令
  └── App::clear_terminal_ui()
        └── App::queue_clear_ui_header()
              └── SessionHeaderHistoryCell::new()
                    ├── current_model()           // "gpt-5.4"
                    ├── current_reasoning_effort() // XHigh
                    ├── should_show_fast_status() // true
                    └── display_lines()
```

### 4.3 SessionHeaderHistoryCell 渲染
```rust
// history_cell.rs:1311-1380
impl HistoryCell for SessionHeaderHistoryCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 构建模型信息行
        let mut model_spans = vec![
            Span::from("model: ").dim(),
            Span::styled(self.model.clone(), self.model_style),
        ];
        
        // 添加推理努力程度
        if let Some(effort) = self.reasoning_effort {
            model_spans.push(Span::from(format!(" {:?}", effort)).dim());
        }
        
        // 添加 Fast 标识
        if self.show_fast_status {
            model_spans.push(Span::from(" fast").green());
        }
        
        // 添加修改提示
        model_spans.push(Span::from(" /model to change").dim());
        
        // ...
    }
}
```

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 内部依赖
| 模块 | 用途 |
|------|------|
| `codex_protocol::ServiceTier` | Fast 服务等级枚举 |
| `codex_protocol::ReasoningEffort` | 推理努力程度枚举 |
| `ratatui::style::Style` | 样式应用（绿色 Fast 标识）|

### 5.2 配置依赖
```rust
// 依赖的 App 状态
self.chat_widget.current_model()           // "gpt-5.4"
self.chat_widget.current_reasoning_effort() // Some(XHigh)
self.chat_widget.current_service_tier()     // Some(Fast)
```

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 已知风险
| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 标识冲突 | Fast 标识与推理努力程度可能产生视觉拥挤 | 使用空格分隔，绿色高亮区分 |
| 模型更新 | 新模型可能需要添加 to Fast 状态显示列表 | 维护 should_show_fast_status 函数 |

### 6.2 边界情况
1. **非 Fast 模式**: 不显示 "fast" 标识
2. **不支持 Fast 的模型**: 即使 service_tier=Fast 也不显示
3. **未知模型**: 默认不显示 Fast 标识

### 6.3 改进建议
1. **动态 Fast 状态**: 根据 API 响应实时更新 Fast 状态
2. **Fast 模式提示**: 添加悬停提示说明 Fast 模式的含义
3. **成本估算**: 显示 Fast 模式的预估成本差异
4. **配置持久化**: 记住用户的 Fast 模式偏好

### 6.4 相关测试
- `clear_ui_after_long_transcript_fresh_header_only`: 基础清理头部测试
- `clear_ui_header_fast_status_gpt54_only`: GPT-5.4 Fast 状态测试（本测试）

---

## 7. 相关文档链接

- [AGENTS.md](../../../../../../AGENTS.md) - 项目开发指南
- [Session Header Cell](../codex_tui_app_server__app__tests__clear_ui_after_long_transcript_fresh_header_only.snap_research.md) - 基础头部测试文档
