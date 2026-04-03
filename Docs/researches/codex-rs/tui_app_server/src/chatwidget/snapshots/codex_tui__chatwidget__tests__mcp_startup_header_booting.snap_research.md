# Snapshot Research: mcp_startup_header_booting

## 场景与职责

此快照测试验证 MCP（Model Context Protocol）服务器启动时的引导状态显示。当 Codex 启动时，需要初始化配置的 MCP 服务器，此功能确保用户了解 MCP 服务器的启动进度。

测试场景：
- Codex 会话开始
- 系统开始初始化配置的 MCP 服务器
- TUI 在状态栏显示 MCP 服务器启动状态
- 用户可以看到哪些 MCP 服务器正在启动

## 功能点目的

1. **启动状态可视化**：显示 MCP 服务器正在启动的状态
2. **进度反馈**：让用户知道系统正在初始化
3. **服务器识别**：显示正在启动的 MCP 服务器名称
4. **中断提示**：提供中断启动的快捷键提示

## 具体技术实现

### 关键流程

```
会话开始 → McpStartupUpdate(Starting) → 状态栏显示 "Booting MCP server" → McpStartupComplete → 清除状态
```

### MCP 启动事件数据结构

```rust
// MCP 启动更新事件
McpStartupUpdateEvent {
    server: String,           // MCP 服务器名称
    status: McpStartupStatus, // 启动状态
}

// MCP 启动状态
enum McpStartupStatus {
    Starting,      // 正在启动
    Ready,         // 已就绪
    Failed(String), // 启动失败（含错误信息）
}

// MCP 启动完成事件
McpStartupCompleteEvent {
    ready: Vec<String>,   // 已就绪的服务器列表
    failed: Vec<String>,  // 启动失败的服务器列表
}
```

### ChatWidget MCP 状态管理

```rust
struct ChatWidget {
    // 跟踪每个服务器的 MCP 启动状态
    mcp_startup_status: Option<HashMap<String, McpStartupStatus>>,
    // ...
}

fn handle_mcp_startup_update(&mut self, event: McpStartupUpdateEvent) {
    // 初始化状态映射
    let status_map = self.mcp_startup_status.get_or_insert_with(HashMap::new);
    
    // 更新服务器状态
    status_map.insert(event.server, event.status);
    
    // 更新任务运行状态（显示旋转器）
    self.update_task_running_state();
}

fn handle_mcp_startup_complete(&mut self, event: McpStartupCompleteEvent) {
    // 清除启动状态
    self.mcp_startup_status = None;
    
    // 更新任务运行状态
    self.update_task_running_state();
}
```

### 状态栏渲染

```rust
fn render_status_line(&self) -> Vec<Line> {
    if let Some(status_map) = &self.mcp_startup_status {
        for (server, status) in status_map {
            if matches!(status, McpStartupStatus::Starting) {
                return vec![
                    Line::from(vec![
                        "• Booting MCP server: ".into(),
                        server.clone().cyan(),
                        " (0s • esc to interrupt)".dim(),
                    ]),
                ];
            }
        }
    }
    // ...
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义和快照断言 |
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主逻辑，处理 MCP 启动事件 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 底部面板，渲染状态栏 |
| `codex-protocol/src/protocol.rs` | MCP 相关协议事件定义 |

### 关键函数

- `ChatWidget::handle_codex_event()` - 处理 McpStartupUpdate 和 McpStartupComplete 事件
- `ChatWidget::update_task_running_state()` - 更新任务运行状态
- `ChatWidget::render()` - 渲染主界面

### 测试代码位置

```rust
// codex-rs/tui/src/chatwidget/tests.rs
async fn mcp_startup_header_booting_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.show_welcome_banner = false;

    // 模拟 MCP 服务器启动更新
    chat.handle_codex_event(Event {
        id: "mcp-1".into(),
        msg: EventMsg::McpStartupUpdate(McpStartupUpdateEvent {
            server: "alpha".into(),
            status: McpStartupStatus::Starting,
        }),
    });

    let height = chat.desired_height(80);
    let mut terminal = ratatui::Terminal::new(ratatui::backend::TestBackend::new(80, height))
        .expect("create terminal");
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw chat widget");
    assert_snapshot!("mcp_startup_header_booting", terminal.backend());
}
```

## 依赖与外部交互

### 内部依赖

- `codex_protocol::protocol::McpStartupUpdateEvent` - MCP 启动更新事件
- `codex_protocol::protocol::McpStartupCompleteEvent` - MCP 启动完成事件
- `codex_protocol::protocol::McpStartupStatus` - MCP 启动状态枚举

### 外部交互

- **MCP 服务器**：实际的 MCP 服务器进程
- **codex-core**：协调 MCP 服务器启动流程

## 风险、边界与改进建议

### 潜在风险

1. **启动超时**：MCP 服务器启动可能超时，需要处理超时场景
2. **多次启动**：配置变更可能导致 MCP 服务器多次启动
3. **资源泄漏**：启动失败的 MCP 服务器可能留下僵尸进程

### 边界情况

- 多个 MCP 服务器同时启动
- MCP 服务器启动过程中用户中断
- MCP 服务器启动失败后的重试
- 网络问题导致的 MCP 服务器连接失败

### 改进建议

1. **显示优化**：
   - 显示多个 MCP 服务器的启动进度
   - 添加启动进度条
   - 显示已就绪和待启动的服务器数量

2. **错误处理**：
   - 启动失败时显示详细的错误信息
   - 提供重试启动的快捷方式
   - 允许用户跳过失败的 MCP 服务器

3. **交互改进**：
   - 支持在启动过程中动态添加/移除 MCP 服务器
   - 提供 MCP 服务器配置查看和编辑
   - 添加 MCP 服务器状态监控

4. **可观测性**：
   - 记录 MCP 服务器启动日志
   - 提供 MCP 服务器性能指标
   - 添加 MCP 服务器健康检查

---

**快照内容**：
```
"                                                                                "
"• Booting MCP server: alpha (0s • esc to interrupt)                             "
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  ? for shortcuts                                            100% context left  "
```

**说明**：
- 第一行为空行
- 第二行显示 MCP 服务器启动状态：
  - `• Booting MCP server:` 表示正在启动 MCP 服务器
  - `alpha` 是 MCP 服务器的名称
  - `(0s • esc to interrupt)` 显示已用时间和中断快捷键
- 中间空行分隔状态栏和输入区域
- `› Ask Codex to do anything` 是输入提示
- 最后一行显示快捷键提示和上下文信息
- 整体布局清晰，用户可以快速了解系统状态和操作方式
