# Unified Exec Footer - Render Many Sessions Research Document

## 场景与职责

此快照测试验证 `UnifiedExecFooter` 在存在大量（123个）后台终端会话时的渲染行为。这是测试组件在处理极端数据量时的性能和显示正确性。

### 核心场景
- **大量后台会话**：123 个并发运行的后台终端进程
- **有限显示宽度**：50 字符宽度
- **预期行为**：正确显示会话数量，提供查看和管理命令提示

## 功能点目的

### 1. 后台进程汇总
- **目的**：向用户展示当前运行的后台终端会话数量
- **场景**：用户使用 `/ps` 或类似命令启动多个长时间运行的任务
- **价值**：避免用户忘记正在运行的后台进程

### 2. 极端数量处理
- **目的**：验证组件在处理大量数据时的稳定性
- **边界**：123 个会话远超正常使用场景
- **验证**：数字正确显示，消息格式正确

### 3. 命令提示
- **目的**：提供管理后台进程的快捷方式
- **命令**：
  - `/ps` - 查看所有进程
  - `/stop` - 关闭进程

## 具体技术实现

### 测试代码分析
```rust
#[test]
fn render_many_sessions() {
    let mut footer = UnifiedExecFooter::new();
    
    // 创建 123 个后台进程
    footer.set_processes((0..123).map(|idx| format!("cmd {idx}")).collect());
    
    let width = 50;
    let height = footer.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    footer.render(Rect::new(0, 0, width, height), &mut buf);
    
    assert_snapshot!("render_many_sessions", format!("{buf:?}"));
}
```

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

### 关键观察
1. **数量正确显示**：`123` 准确显示
2. **复数形式正确**：`terminals`（不是 `terminal`）
3. **消息截断**：由于宽度限制（50字符），消息被截断
   - 完整消息应为：`123 background terminals running · /ps to view · /stop to close`
   - 实际显示：`123 background terminals running · /ps to view ·`（`/stop` 部分被截断）
4. **样式**：使用 `DIM`（暗淡）修饰符，表示这是次要信息
5. **缩进**：2 个空格缩进，与底部面板其他元素对齐

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui/src/bottom_pane/unified_exec_footer.rs` - UnifiedExecFooter 实现

### 核心实现

#### 数据结构（lines 16-19）
```rust
pub(crate) struct UnifiedExecFooter {
    processes: Vec<String>,  // 存储进程名称列表
}
```

#### 进程设置（lines 28-34）
```rust
pub(crate) fn set_processes(&mut self, processes: Vec<String>) -> bool {
    if self.processes == processes {
        return false;  // 无变化，避免不必要的重绘
    }
    self.processes = processes;
    true  // 返回 true 表示需要重绘
}
```

#### 摘要文本生成（lines 45-55）
```rust
pub(crate) fn summary_text(&self) -> Option<String> {
    if self.processes.is_empty() {
        return None;  // 无进程时不显示
    }

    let count = self.processes.len();
    let plural = if count == 1 { "" } else { "s" };  // 复数处理
    Some(format!(
        "{count} background terminal{plural} running · /ps to view · /stop to close"
    ))
}
```

#### 渲染实现（lines 57-82）
```rust
fn render_lines(&self, width: u16) -> Vec<Line<'static>> {
    if width < 4 {
        return Vec::new();  // 宽度不足时不渲染
    }
    let Some(summary) = self.summary_text() else {
        return Vec::new();
    };
    let message = format!("  {summary}");  // 添加 2 空格缩进
    let (truncated, _, _) = take_prefix_by_width(&message, width as usize);
    vec![Line::from(truncated.dim())]  // 应用暗淡样式
}

impl Renderable for UnifiedExecFooter {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        if area.is_empty() {
            return;
        }
        Paragraph::new(self.render_lines(area.width)).render(area, buf);
    }

    fn desired_height(&self, width: u16) -> u16 {
        self.render_lines(width).len() as u16  // 动态计算高度
    }
}
```

### 依赖模块
- `crate::live_wrap::take_prefix_by_width` - 按宽度截断文本
- `ratatui::widgets::Paragraph` - 段落渲染
- `ratatui::style::Stylize` - 样式应用

## 依赖与外部交互

### 外部接口
| 方法 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `new()` | - | `UnifiedExecFooter` | 创建空实例 |
| `set_processes()` | `Vec<String>` | `bool` | 设置进程列表，返回是否变化 |
| `is_empty()` | - | `bool` | 检查是否有进程 |
| `summary_text()` | - | `Option<String>` | 生成摘要文本 |

### 样式系统
```rust
// 暗淡样式应用
Line::from(truncated.dim())

// 样式属性
modifier: DIM  // 比正常文本稍暗，表示次要信息
```

### 文本截断
```rust
// take_prefix_by_width 函数
// 按显示宽度截断字符串，考虑 Unicode 字符宽度
fn take_prefix_by_width(text: &str, max_width: usize) -> (String, usize, bool) {
    // 返回: (截断后的文本, 实际字节长度, 是否被截断)
}
```

## 风险边界与改进建议

### 潜在风险

1. **宽度计算不准确**
   - **风险**：Unicode 字符（如中文）宽度计算可能不准确
   - **边界**：当前测试使用 ASCII 字符
   - **建议**：添加 Unicode 字符测试

2. **大数量性能**
   - **风险**：`processes.len()` 在极大向量上可能较慢
   - **边界**：123 个元素无性能问题，但 10000+ 可能有问题
   - **建议**：如果进程数量可能极大，考虑使用 `len()` 的缓存

3. **消息截断位置**
   - **风险**：在宽度边界处截断可能切断重要信息
   - **边界**：当前在 `/ps to view ·` 后截断，命令提示不完整
   - **建议**：实现智能截断，优先保留关键命令提示

4. **内存使用**
   - **风险**：存储所有进程名称可能占用较多内存
   - **边界**：仅存储字符串，无其他元数据
   - **建议**：如果内存敏感，考虑仅存储数量

### 改进建议

1. **智能截断**
   ```rust
   fn render_lines(&self, width: u16) -> Vec<Line<'static>> {
       let summary = self.summary_text()?;
       let message = format!("  {summary}");
       
       if message.width() > width as usize {
           // 优先保留关键信息
           let priority_parts = [
               format!("{count} background terminal{plural} running"),
               "· /ps".to_string(),
               "· /stop".to_string(),
           ];
           // 根据宽度选择包含的部分
       }
       // ...
   }
   ```

2. **数量阈值提示**
   ```rust
   // 当数量超过阈值时显示特殊提示
   let count = self.processes.len();
   if count > 100 {
       format!("{count}+ background terminals running...")
   }
   ```

3. **进程详情展开**
   ```rust
   // 支持展开查看具体进程列表
   pub(crate) fn render_expanded(&self, width: u16) -> Vec<Line<'static>> {
       let mut lines = vec![self.render_summary(width)];
       for (i, process) in self.processes.iter().enumerate() {
           lines.push(format!("  {}. {}", i + 1, process).dim());
       }
       lines
   }
   ```

4. **测试增强**
   ```rust
   // 建议添加的测试
   #[test]
   fn render_many_sessions_wide() {
       // 测试足够宽度下的完整消息显示
       let width = 100;
       // ...
   }
   
   #[test]
   fn render_many_sessions_unicode() {
       // 测试包含 Unicode 的进程名称
       footer.set_processes(vec!["进程一".to_string(), "プロセス2".to_string()]);
       // ...
   }
   
   #[test]
   fn render_zero_sessions() {
       // 测试空列表行为
       footer.set_processes(vec![]);
       assert_eq!(footer.desired_height(50), 0);
   }
   ```

5. **国际化支持**
   - 支持复数形式的本地化（不同语言有不同复数规则）
   - 支持命令提示的本地化
