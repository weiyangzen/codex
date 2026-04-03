# Status Line Setup View Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `status_line_setup.rs` 模块的测试快照，用于验证**状态栏设置视图的渲染**。当用户执行 `/statusline` 命令时，显示此界面配置状态栏显示的项目。

### 业务场景
- 用户想要自定义状态栏显示的信息
- 用户想要添加或移除状态栏项目
- 用户想要调整状态栏项目的顺序

### 状态栏设置特性
- 显示所有可用状态栏项目
- 使用复选框表示启用状态
- 支持搜索过滤
- 实时预览当前配置的效果

## 功能点目的

### 核心功能
1. **项目列表**：显示所有可用状态栏项目
2. **启用/禁用**：切换项目的显示状态
3. **顺序调整**：调整项目的显示顺序
4. **实时预览**：显示当前配置的效果

### 用户体验目标
- **即时反馈**：更改立即在预览中体现
- **状态清晰**：一眼看出哪些项目已启用
- **便捷操作**：支持键盘和鼠标操作

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct StatusLineSetupView {
    items: Vec<StatusLineItem>,
    search_query: String,
    selected_idx: usize,
    preview_value: Line<'static>,  // 运行时预览值
}

pub(crate) struct StatusLineItem {
    pub id: String,
    pub label: String,
    pub description: String,
    pub enabled: bool,
}
```

### 渲染逻辑
```rust
impl Renderable for StatusLineSetupView {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 标题
        "  Configure Status Line".bold().render(title_area, buf);
        "  Select which items to display in the status line.".dim()
            .render(subtitle_area, buf);
        
        // 搜索框
        if self.is_searchable {
            Line::from(format!("> {}", self.search_query)).render(search_area, buf);
        }
        
        // 项目列表
        for (idx, item) in self.visible_items().iter().enumerate() {
            let checkbox = if item.enabled { "[x]" } else { "[ ]" };
            let prefix = if idx == self.selected_idx { "› " } else { "  " };
            
            let line = format!(
                "{}{} {:<25} {}",
                prefix,
                checkbox,
                item.label,
                truncate(&item.description, desc_width)
            );
            
            line.render(row_area, buf);
        }
        
        // 实时预览
        self.preview_value.render(preview_area, buf);
        
        // 底部提示
        "  Use ↑↓ to navigate, ←→ to move, space to select, enter to confirm, esc"
            .dim()
            .render(hint_area, buf);
    }
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/status_line_setup.rs`
- **测试函数**: `setup_view_snapshot_uses_runtime_preview_values` (行 365 附近)

### 渲染输出分析
```
                                                                        
  Configure Status Line                                                 
  Select which items to display in the status line.                      
                                                                        
  Type to search                                                        
  >                                                                     
› [x] model-name            Current model name                           
  [x] current-dir           Current working directory                   
  [x] git-branch            Current Git branch (omitted when unavaila…  
  [ ] model-with-reasoning  Current model name with reasoning level     
  [ ] project-root          Project root directory (omitted when unav…  
  [ ] context-remaining     Percentage of context window remaining (o…  
  [ ] context-used          Percentage of context window used (omitte…  
  [ ] five-hour-limit       Remaining usage on 5-hour usage limit (om…  
                                                                        
  gpt-5-codex · ~/codex-rs · jif/statusline-preview                      
  Use ↑↓ to navigate, ←→ to move, space to select, enter to confirm, esc
```

- 标题和说明
- 搜索框
- 状态栏项目列表（带复选框）
- 实时预览（显示当前模型、目录、分支）
- 底部操作提示

## 依赖与外部交互

### 内部依赖
- `StatusLineSetupView` - 状态栏设置视图
- `StatusLineItem` - 状态栏项目定义

### 外部交互
- **配置系统**：保存状态栏配置
- **运行时信息**：获取模型名称、当前目录、Git 分支等
- **Git 集成**：获取当前分支信息

## 风险、边界与改进建议

### 潜在风险
1. **信息过载**：启用过多项目可能导致状态栏拥挤
2. **性能影响**：某些项目（如 Git 分支）的获取可能影响性能
3. **隐私泄露**：当前目录等信息可能暴露敏感路径

### 边界情况
1. **Git 不可用**：非 Git 仓库时的分支显示
2. **长路径**：非常长的路径可能导致截断
3. **特殊字符**：路径中的特殊字符处理

### 改进建议
1. **自定义格式**：允许用户自定义每个项目的显示格式
2. **条件显示**：根据上下文条件显示项目
3. **颜色配置**：允许自定义项目颜色
4. **分隔符选择**：允许选择不同的项目分隔符
5. **导出/导入**：支持配置的导出和导入

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/status_line_setup.rs`
