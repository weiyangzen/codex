# 研究文档：stderr_tail_more_than_five_lines_snapshot.snap

## 场景与职责

此快照测试验证当 stderr 输出超过 5 行时的尾部显示逻辑。大量错误输出应该被截断，只显示开头和结尾，中间用省略号表示。

## 功能点目的

1. **输出截断**：防止大量错误输出淹没界面
2. **首尾显示**：保留输出的开头和结尾，便于理解错误
3. **省略指示**：用 `… +N lines` 明确表示有省略内容

## 具体技术实现

### 快照输出分析

```
• Ran seq 1 10 1>&2 && false
  └ 1
    2
    … +6 lines
    9
    10
```

显示逻辑：
- 显示前 2 行
- 省略中间 6 行
- 显示最后 2 行
- 总共 10 行输出

### 尾部显示逻辑

```rust
const STDERR_HEAD_LINES: usize = 2;
const STDERR_TAIL_LINES: usize = 2;
const STDERR_MAX_LINES_BEFORE_TRUNCATION: usize = 5;

fn render_stderr_truncated(lines: &[String]) -> Vec<Line> {
    let mut result = vec![];
    
    if lines.len() <= STDERR_MAX_LINES_BEFORE_TRUNCATION {
        // 不需要截断
        for line in lines {
            result.push(Line::from(line.as_str()));
        }
    } else {
        // 显示头部
        for line in &lines[..STDERR_HEAD_LINES] {
            result.push(Line::from(line.as_str()));
        }
        
        // 省略指示
        let omitted = lines.len() - STDERR_HEAD_LINES - STDERR_TAIL_LINES;
        result.push(Line::from(format!("… +{omitted} lines")));
        
        // 显示尾部
        for line in &lines[lines.len() - STDERR_TAIL_LINES..] {
            result.push(Line::from(line.as_str()));
        }
    }
    
    result
}
```

## 关键代码路径与文件引用

1. **输出截断**：
   - `crate::exec_cell::output_lines`
   - `crate::text_formatting::truncate_text`

2. **错误输出处理**：
   - `codex-rs/tui/src/exec_cell.rs`

## 依赖与外部交互

### 相关常量
- `TOOL_CALL_MAX_LINES` - 工具调用最大行数限制

## 风险、边界与改进建议

### 潜在风险
1. **关键错误丢失**：截断可能隐藏关键错误信息
2. **上下文丢失**：省略部分可能包含重要上下文

### 边界情况
1. 正好 5 行输出（不截断）
2. 6 行输出（刚好触发截断）
3. 输出包含空行

### 改进建议
1. 添加展开功能，查看完整输出
2. 支持搜索 stderr 内容
3. 添加错误级别过滤
4. 支持配置截断行数
