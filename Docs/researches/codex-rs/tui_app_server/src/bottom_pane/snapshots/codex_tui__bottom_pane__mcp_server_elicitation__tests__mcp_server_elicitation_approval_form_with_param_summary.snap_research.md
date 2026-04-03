# MCP Server Elicitation Approval Form With Param Summary Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `mcp_server_elicitation.rs` 模块的测试快照，用于验证**MCP 服务器请求表单（带参数摘要）的渲染**。当 MCP 服务器需要用户批准执行某个操作并显示参数时，展示此界面。

### 业务场景
- MCP 服务器（如 Calendar）请求执行操作
- 需要显示操作参数供用户确认
- 用户需要批准或拒绝该请求

### MCP Elicitation 特性
- 显示服务器名称和操作描述
- 列出关键参数及其值
- 提供批准/拒绝选项
- 支持长文本截断

## 功能点目的

### 核心功能
1. **操作描述**：清晰描述要执行的操作
2. **参数展示**：显示关键参数及其值
3. **用户决策**：提供批准或拒绝的选项
4. **信息截断**：长文本自动截断并显示省略号

### 用户体验目标
- **透明度**：用户清楚知道将要执行什么操作
- **参数可见**：关键参数一目了然
- **快速决策**：提供明确的批准/拒绝选项

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct McpServerElicitationView {
    server_name: String,
    operation: String,
    params: Vec<(String, String)>,  // 参数名和值
    approval_form: ApprovalForm,
}

pub(crate) struct ApprovalForm {
    options: Vec<ApprovalOption>,
    selected_idx: usize,
}
```

### 渲染逻辑
```rust
impl Renderable for McpServerElicitationView {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 字段计数
        format!("  Field {}/{}", self.current_field, self.total_fields)
            .render(header_area, buf);
        
        // 操作描述
        self.operation.render(description_area, buf);
        
        // 参数列表
        for (name, value) in &self.params {
            let display_value = if value.len() > max_value_len {
                format!("{}...", &value[..max_value_len - 3])
            } else {
                value.clone()
            };
            
            format!("  {}: {}", name, display_value)
                .render(param_area, buf);
        }
        
        // 批准选项
        for (idx, option) in self.approval_form.options.iter().enumerate() {
            let prefix = if idx == self.approval_form.selected_idx {
                "› "
            } else {
                "  "
            };
            format!("{}{}  {}", prefix, option.label, option.description)
                .render(option_area, buf);
        }
        
        // 底部提示
        "  enter to submit | esc to cancel".dim()
            .render(hint_area, buf);
    }
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs`
- **测试函数**: `mcp_server_elicitation_approval_form_with_param_summary` (行 1-19 快照)

### 渲染输出分析
```
                                                                                                                        
  Field 1/1                                                                                                              
  Allow Calendar to create an event                                                                                      
                                                                                                                        
  Calendar: primary                                                                                                      
  Title: Roadmap review                                                                                                 
  Notes: This is a deliberately long note that should truncate bef...                                                    
                                                                                                                        
  › 1. Allow   Run the tool and continue.                                                                               
    2. Cancel  Cancel this tool call                                                                                     
                                                                                                                        
                                                                                                                        
                                                                                                                        
                                                                                                                        
  enter to submit | esc to cancel
```

- 字段计数（多字段时显示）
- 操作描述
- 参数列表（长值截断）
- 批准选项（带描述）
- 底部操作提示

## 依赖与外部交互

### 内部依赖
- `McpServerElicitationView` - MCP 服务器请求视图
- `ApprovalForm` - 批准表单

### 外部交互
- **MCP 客户端**：接收服务器请求
- **MCP 服务器**：发送请求并等待响应
- **审批系统**：处理用户决策

## 风险、边界与改进建议

### 潜在风险
1. **参数篡改**：显示的参数与实际执行的参数不一致
2. **信息泄露**：敏感参数可能被显示
3. **社会工程**：恶意服务器可能诱导用户批准危险操作

### 边界情况
1. **大量参数**：参数过多时的显示策略
2. **长参数名**：参数名过长时的处理
3. **空参数**：参数值为空时的显示

### 改进建议
1. **敏感参数隐藏**：自动隐藏或脱敏敏感信息
2. **参数验证**：显示参数的合法性检查
3. **操作预览**：显示操作执行后的预期效果
4. **历史记录**：显示类似操作的历史记录
5. **风险评级**：根据操作类型显示风险等级

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs`
