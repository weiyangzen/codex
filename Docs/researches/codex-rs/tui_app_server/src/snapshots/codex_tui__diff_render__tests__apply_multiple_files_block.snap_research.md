# Research: codex_tui__diff_render__tests__apply_multiple_files_block.snap

## 场景与职责

本快照文件测试 Diff 渲染器中多文件变更的渲染效果。当一次操作涉及多个文件时，需要汇总显示并展示每个文件的详细变更。

## 功能点目的

验证多文件变更的 diff 渲染：
- 显示总体变更统计（文件数、总行变更）
- 每个文件的独立变更摘要
- 层级缩进显示文件关系

## 具体技术实现

### 渲染输出格式

```
"• Edited 2 files (+2 -1)                                                        "
"  └ a.txt (+1 -1)                                                               "
"    1 -one                                                                      "
"    1 +one changed                                                              "
"                                                                                "
"  └ b.txt (+1 -0)                                                               "
"    1 +new                                                                      "
```

### 层级结构

```
• Edited 2 files (+2 -1)          <- 总摘要
  └ a.txt (+1 -1)                 <- 文件1摘要
    1 -one                        <- 文件1删除行
    1 +one changed                <- 文件1添加行
                                  <- 空行分隔
  └ b.txt (+1 -0)                 <- 文件2摘要
    1 +new                        <- 文件2添加行
```

### 关键数据结构

```rust
pub struct MultiFileDiffSummary {
    pub total_files: usize,
    pub total_additions: usize,
    pub total_deletions: usize,
    pub file_summaries: Vec<DiffSummary>,
}

impl MultiFileDiffSummary {
    fn render(&self, width: u16) -> Vec<Line<'static>> {
        let mut lines = vec![];
        
        // 总摘要行
        lines.push(format!(
            "• Edited {} files (+{} -{})",
            self.total_files,
            self.total_additions,
            self.total_deletions
        ));
        
        // 每个文件的详细内容
        for summary in &self.file_summaries {
            lines.push(format!("  └ {} (+{} -{})", 
                summary.path, 
                summary.additions, 
                summary.deletions
            ));
            // ... 添加文件内容行
        }
        
        lines
    }
}
```

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/diff_render.rs`
- **测试函数**: `apply_multiple_files_block`
- **树形渲染**: `render::line_utils::prefix_lines`

## 依赖与外部交互

- **变更聚合**: 将多个 FileChange 聚合成统一视图
- **路径排序**: 按路径字母顺序或变更类型排序
- **折叠/展开**: 支持用户交互折叠单个文件

## 风险、边界与改进建议

### 边界情况

1. **大量文件**: 数十个文件的显示性能
2. **混合变更类型**: 添加、删除、编辑混合的场景
3. **深层目录**: 长路径的显示截断

### 风险点

1. **性能**: 大量文件的语法高亮可能耗时
2. **可读性**: 文件过多时难以浏览

### 改进建议

1. 添加文件折叠/展开功能
2. 按目录分组显示
3. 添加文件类型过滤
4. 支持仅显示变更摘要模式（不显示详细内容）
5. 添加搜索/过滤功能
