# Unified Exec Footer Render Many Sessions Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `unified_exec_footer.rs` 模块的测试快照，用于验证**统一执行底部栏在多会话场景下的渲染**。当多个后台终端会话正在运行时，显示此界面。

### 业务场景
- 用户启动了多个后台终端会话
- 需要显示正在运行的会话数量
- 提供查看所有会话的快捷方式

### 统一执行底部栏特性
- 显示后台终端会话数量
- 提供 `/ps` 命令查看所有会话
- 简洁的单行显示

## 功能点目的

### 核心功能
1. **会话计数**：显示后台终端会话数量
2. **查看提示**：提示使用 `/ps` 查看所有会话
3. **简洁显示**：单行显示，不占用过多空间

### 用户体验目标
- **状态感知**：用户知道有后台会话在运行
- **快速访问**：提供查看所有会话的快捷方式
- **不干扰**：简洁显示，不影响主要界面

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct UnifiedExecFooter {
    session_count: usize,
}

impl UnifiedExecFooter {
    pub fn new(session_count: usize) -> Self {
        Self { session_count }
    }
}
```

### 渲染逻辑
```rust
impl Renderable for UnifiedExecFooter {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        let text = format!(
            "  {} background terminal{} running · /ps to view ·",
            self.session_count,
            if self.session_count == 1 { "" } else { "s" }
        );
        
        Line::from(text)
            .dim()
            .render(area, buf);
    }
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/unified_exec_footer.rs`
- **测试函数**: `render_many_sessions` (在 tests 模块中)

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 50, height: 1 },
    content: [
        "  123 background terminals running · /ps to view ·",
    ],
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
    ]
}
```

- 单行显示
- 显示会话数量（123）
- 提示使用 `/ps` 查看
- 灰色显示（不突出）

## 依赖与外部交互

### 内部依赖
- `UnifiedExecFooter` - 统一执行底部栏

### 外部交互
- **会话管理器**：获取后台终端会话数量
- **命令解析器**：处理 `/ps` 命令

## 风险、边界与改进建议

### 潜在风险
1. **数量不准确**：会话数量可能因同步延迟而不准确
2. **性能影响**：频繁更新可能影响性能
3. **信息不足**：仅显示数量，不显示会话详情

### 边界情况
1. **零会话**：没有后台会话时的显示（可能隐藏）
2. **大量会话**：会话数量很大时的显示
3. **会话状态**：会话可能处于不同状态（运行、暂停、错误）

### 改进建议
1. **状态指示**：使用不同颜色表示会话状态
2. **最近活动**：显示最近活动的会话名称
3. **警告阈值**：当会话数量超过阈值时改变颜色
4. **一键管理**：提供一键停止所有会话的选项
5. **会话详情**：悬停时显示会话详情

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/unified_exec_footer.rs`
