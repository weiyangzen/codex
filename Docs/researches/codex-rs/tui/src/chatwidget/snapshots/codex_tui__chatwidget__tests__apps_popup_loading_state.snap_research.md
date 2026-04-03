# 研究文档: apps_popup_loading_state.snap

## 场景与职责

该快照文件测试应用/连接器（Apps/Connectors）弹窗的加载状态渲染。当用户打开应用列表时，在数据加载完成前显示此状态。

## 功能点目的

1. **加载反馈**: 向用户表明应用列表正在加载
2. **防止重复请求**: 加载状态防止用户重复触发加载操作
3. **用户体验**: 提供视觉反馈减少等待焦虑

## 具体技术实现

### 加载状态触发

```rust
chat.on_connectors_loaded(
    Ok(ConnectorsSnapshot {
        connectors: vec![...],  // 部分数据
    }),
    false,  // is_final = false，表示非最终数据
);
```

### 渲染输出

```
Loading installed and available apps...
```

### 状态管理

```rust
struct ConnectorsCacheState {
    Loading,           // 加载中
    Ready(snapshot),   // 加载完成
    Error(String),     // 加载失败
}
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 6737-6828)
- **连接器管理**: `codex-chatgpt/src/connectors/`
- **状态管理**: `ChatWidget.connectors_cache`

## 依赖与外部交互

1. **codex-chatgpt**: 提供连接器API客户端
2. **tokio**: 异步加载处理

## 风险、边界与改进建议

### 风险
- 长时间加载可能导致用户认为应用卡住
- 网络超时处理不当

### 边界情况
- 空应用列表的处理
- 网络错误后的重试机制
- 部分加载失败的处理

### 改进建议
1. 添加加载进度指示器
2. 实现加载超时和错误重试
3. 显示已加载/总数统计
4. 添加取消加载的选项
