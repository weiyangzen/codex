# Research: codex_tui__diff_render__tests__add_details.snap

## 场景与职责

本快照文件测试 Diff 渲染器中 "Add"（添加文件）操作的详细视图。当 Codex 创建新文件时，需要以统一的 diff 格式展示变更内容。

## 功能点目的

验证添加文件时的 diff 渲染：
- 显示文件变更摘要（+2 -0 表示添加2行，删除0行）
- 行号右对齐显示
- 新增行使用 `+` 前缀标识
- 语法高亮（如适用）

## 具体技术实现

### 渲染输出格式

```
"• Proposed Change README.md (+2 -0)                                             "
"    1     +first line                                                           "
"    2     +second line                                                          "
```

### 关键组件

1. **变更标题**: `• Proposed Change README.md (+2 -0)`
   - `•` 表示变更点
   - `Proposed Change` 表示提议的变更
   - `(+2 -0)` 统计信息：添加2行，删除0行

2. **内容行**: `    1     +first line`
   - `    1` 右对齐行号（4字符宽度）
   - `     ` 间隔
   - `+` 添加标记
   - `first line` 内容

### 数据结构

```rust
// FileChange 枚举
pub enum FileChange {
    Add { path: String, content: String },
    Delete { path: String, content: String },
    Update { path: String, diff: String },
}

// DiffSummary 结构体
pub struct DiffSummary {
    pub path: PathBuf,
    pub change_type: ChangeType,
    pub additions: usize,
    pub deletions: usize,
}
```

### 样式处理

- **添加行**: 绿色背景（深色主题）或浅绿色背景（亮色主题）
- **行号**: 独立背景色以区分内容
- **语法高亮**: 根据文件扩展名启用

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/diff_render.rs`
- **测试函数**: `add_details`
- **相关模块**: `render::highlight` 语法高亮

## 依赖与外部交互

- **diff 库**: `diffy` 处理 diff 格式
- **语法高亮**: `syntect` 提供代码高亮
- **颜色主题**: `DiffTheme` 适配终端背景

## 风险、边界与改进建议

### 边界情况

1. **大文件**: 大文件添加可能导致内存和性能问题
2. **二进制文件**: 二进制文件内容不应以文本 diff 显示
3. **长行**: 超长行需要截断或换行处理

### 风险点

1. **编码问题**: 非 UTF-8 文件内容可能导致渲染错误
2. **终端宽度**: 窄终端上行号和内容可能重叠

### 改进建议

1. 对大文件添加分页或折叠支持
2. 二进制文件显示哈希值而非内容
3. 添加文件类型图标区分不同文件
4. 支持折叠/展开详细内容
