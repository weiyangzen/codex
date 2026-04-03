# 研究文档: mcp_startup_header_booting.snap

## 场景与职责

该快照文件测试 MCP（Model Context Protocol）服务器启动时的标题栏渲染效果。

## 功能点目的

1. **启动状态展示**: 显示MCP服务器正在启动的状态
2. **进度反馈**: 提供服务器启动的进度信息
3. **用户等待**: 告知用户系统正在初始化

## 具体技术实现

### MCP启动事件

```rust
codex_protocol::protocol::McpStartupUpdateEvent {
    status: McpStartupStatus::Booting,
    message: Option<String>,
    progress: Option<f32>,
}
```

### 渲染输出

```
⚙️  Starting MCP servers...
   └─ Loading server: filesystem
   └─ Loading server: github
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **MCP管理**: `codex-core/src/mcp/`
- **启动状态**: `mcp_startup_status` 管理

## 依赖与外部交互

1. **MCP服务器**: 外部工具服务器
2. **进程管理**: 服务器进程启动

## 改进建议
1. 添加启动超时处理
2. 显示每个服务器的启动时间
3. 提供重试失败的选项
