# MCP 启动头部引导测试研究文档

## 场景与职责

本测试验证 `tui_app_server` 中 MCP（Model Context Protocol）服务器启动状态的头部展示。当 MCP 服务器正在启动时，系统会在聊天界面的头部显示启动状态，告知用户正在引导的 MCP 服务器名称和已用时间，并提供中断选项。

## 功能点目的

1. **启动状态反馈**: 向用户反馈 MCP 服务器的启动进度
2. **可中断提示**: 告知用户可以按 ESC 键中断启动
3. **时间显示**: 显示启动已用时间
4. **多服务器支持**: 支持显示多个 MCP 服务器的启动状态

## 具体技术实现

### 测试流程

```rust
async fn mcp_startup_header_booting_snapshot() {
    // 1. 创建 ChatWidget 实例
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.show_welcome_banner = false;  // 隐藏欢迎横幅以获得清晰快照

    // 2. 发送 MCP 启动更新事件
    chat.handle_codex_event(Event {
        id: "mcp-1".into(),
        msg: EventMsg::McpStartupUpdate(McpStartupUpdateEvent {
            server: "alpha".into(),
            status: McpStartupStatus::Starting,
        }),
    });

    // 3. 渲染 ChatWidget 并捕获快照
    let height = chat.desired_height(80);
    let mut terminal = ratatui::Terminal::new(ratatui::backend::TestBackend::new(80, height))
        .expect("create terminal");
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw chat widget");
    assert_snapshot!("mcp_startup_header_booting", terminal.backend());
}
```

### 关键数据结构

- **`McpStartupUpdateEvent`**: MCP 启动更新事件
  - `server`: MCP 服务器名称
  - `status`: 启动状态（`Starting`, `Ready`, `Failed` 等）

- **`McpStartupStatus`**: MCP 启动状态枚举
  - `Starting`: 正在启动
  - `Ready`: 已就绪
  - `Failed`: 启动失败
  - `Disabled`: 已禁用

- **`mcp_startup_status`**: ChatWidget 字段
  - 存储当前 MCP 启动状态
  - 用于驱动头部显示

### 渲染输出格式

```
"                                                                                "
"• Booting MCP server: alpha (0s • esc to interrupt)                             "
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  ? for shortcuts                                            100% context left  "
```

### UI 元素说明

- **• Booting MCP server: alpha**: 显示正在启动的 MCP 服务器名称
- **(0s • esc to interrupt)**: 显示已用时间和中断提示
- **› Ask Codex to do anything**: 输入提示
- **? for shortcuts**: 快捷键提示
- **100% context left**: 上下文窗口剩余百分比

## 关键代码路径与文件引用

### 测试文件
- **`codex-rs/tui_app_server/src/chatwidget/tests.rs`** (行 10340-10360)
  - 测试函数 `mcp_startup_header_booting_snapshot`
  - 使用 `TestBackend` 创建终端后端
  - 直接渲染 ChatWidget 并捕获完整 UI 快照

### 源文件
- **`codex-rs/tui_app_server/src/chatwidget.rs`**
  - `mcp_startup_status` 字段管理启动状态
  - `handle_codex_event` 方法处理 `McpStartupUpdate` 事件
  - `update_task_running_state` 同步任务运行状态
  - `render` 方法渲染 MCP 启动头部

### 相关模块
- **`codex-rs/tui_app_server/src/chatwidget/session_header.rs`**
  - 会话头部渲染逻辑
  - MCP 启动状态展示

### 协议定义
- **`codex-protocol/src/protocol.rs`**
  - `McpStartupUpdateEvent` 结构定义
  - `McpStartupStatus` 枚举定义
  - `McpStartupCompleteEvent` 完成事件定义

### Snapshot 文件
- **`codex-rs/tui_app_server/src/chatwidget/snapshots/codex_tui_app_server__chatwidget__tests__mcp_startup_header_booting.snap`**

## 依赖与外部交互

### 内部依赖
| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理 MCP 启动状态 |
| `SessionHeader` | 会话头部组件 |
| `BottomPane` | 底部面板，显示状态信息 |
| `mcp_startup_status` | MCP 启动状态存储 |

### 协议事件
| 事件 | 方向 | 描述 |
|------|------|------|
| `McpStartupUpdate` | Core → TUI | MCP 启动状态更新 |
| `McpStartupComplete` | Core → TUI | MCP 启动完成 |

### 测试辅助
- `TestBackend`: ratatui 测试后端，用于捕获渲染输出
- `Terminal::draw`: 渲染组件到缓冲区
- `chat.desired_height`: 获取组件期望高度

## 风险、边界与改进建议

### 潜在风险
1. **状态竞争**: MCP 启动和回合开始状态竞争
2. **长时间启动**: MCP 服务器启动时间过长影响用户体验
3. **中断处理**: 中断 MCP 启动后的状态恢复

### 边界情况
1. **多服务器启动**: 多个 MCP 服务器同时启动的展示
2. **启动失败**: MCP 服务器启动失败的错误展示
3. **快速完成**: MCP 服务器瞬间完成启动的情况
4. **重复启动**: 同一服务器多次启动更新的处理

### 改进建议
1. **进度指示**: 添加 MCP 服务器启动进度条
2. **服务器详情**: 显示 MCP 服务器的更多详细信息
3. **失败重试**: 提供启动失败后的重试机制
4. **启动日志**: 显示 MCP 服务器启动日志
5. **超时处理**: 添加 MCP 启动超时自动中断
6. **性能优化**: 优化多个 MCP 服务器并行启动的性能
