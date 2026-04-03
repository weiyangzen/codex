# Skills Toggle View Basic Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `skills_toggle_view.rs` 模块的测试快照，用于验证**技能开关视图的基本渲染**。当用户执行 `/skills` 命令时，显示此界面启用或禁用特定技能。

### 业务场景
- 用户想要启用某个技能（如 Repo Scout）
- 用户想要禁用不常用的技能
- 用户想要查看所有可用技能

### 技能开关特性
- 显示技能名称和描述
- 使用复选框表示启用状态
- 支持搜索过滤
- 自动保存更改

## 功能点目的

### 核心功能
1. **技能列表**：显示所有可用技能
2. **状态切换**：启用或禁用技能
3. **搜索过滤**：快速找到特定技能
4. **自动保存**：更改自动生效

### 用户体验目标
- **快速管理**：用户可以高效管理技能
- **状态清晰**：一眼看出哪些技能已启用
- **即时反馈**：更改立即生效

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct SkillsToggleView {
    skills: Vec<SkillToggleItem>,
    search_query: String,
    selected_idx: usize,
}

pub(crate) struct SkillToggleItem {
    pub name: String,
    pub description: String,
    pub enabled: bool,
}
```

### 渲染逻辑
```rust
impl Renderable for SkillsToggleView {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 标题
        "  Enable/Disable Skills".bold().render(title_area, buf);
        "  Turn skills on or off. Your changes are saved automatically.".dim()
            .render(subtitle_area, buf);
        
        // 搜索框
        if self.is_searchable {
            Line::from(format!("> {}", self.search_query)).render(search_area, buf);
        }
        
        // 技能列表
        for (idx, skill) in self.visible_skills().iter().enumerate() {
            let checkbox = if skill.enabled { "[x]" } else { "[ ]" };
            let prefix = if idx == self.selected_idx { "› " } else { "  " };
            
            let line = format!(
                "{}{} {}  {}",
                prefix,
                checkbox,
                skill.name,
                skill.description
            );
            
            line.render(row_area, buf);
        }
        
        // 底部提示
        "  Press space or enter to toggle; esc to close".dim()
            .render(hint_area, buf);
    }
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/skills_toggle_view.rs`
- **测试函数**: `skills_toggle_basic` (行 439 附近)

### 渲染输出分析
```
                                                                        
  Enable/Disable Skills                                                 
  Turn skills on or off. Your changes are saved automatically.          
                                                                        
  Type to search skills                                                 
  >                                                                     
› [x] Repo Scout        Summarize the repo layout                        
  [ ] Changelog Writer  Draft release notes                              
                                                                        
  Press space or enter to toggle; esc to close
```

- 标题和说明
- 搜索框
- 技能列表（带复选框）
- 底部操作提示

## 依赖与外部交互

### 内部依赖
- `SkillsToggleView` - 技能开关视图
- `SkillToggleItem` - 技能项定义

### 外部交互
- **技能注册表**：获取可用技能列表
- **配置系统**：保存技能启用状态
- **技能管理器**：启用/禁用技能

## 风险、边界与改进建议

### 潜在风险
1. **依赖关系**：禁用某个技能可能影响依赖它的功能
2. **状态同步**：多设备间的技能状态同步
3. **性能影响**：大量技能时的渲染性能

### 边界情况
1. **无技能**：没有可用技能时的显示
2. **搜索无结果**：搜索无匹配时的显示
3. **技能冲突**：互斥技能的启用状态

### 改进建议
1. **依赖提示**：显示技能的依赖关系
2. **批量操作**：支持全选/全不选
3. **技能分组**：按类别分组显示技能
4. **使用统计**：显示技能使用频率
5. **推荐系统**：根据使用模式推荐技能

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/skills_toggle_view.rs`
