# 研究文档: exploring_step1_start_ls.snap

## 场景与职责

该快照文件测试"探索模式"（Exploring）的第一步：开始执行 `ls` 命令时的状态渲染。

## 功能点目的

1. **探索模式UI**: 显示命令开始执行的状态
2. **活动指示**: 表明命令正在运行
3. **命令分组**: 将相关命令分组在"Exploring"标题下

## 具体技术实现

### 事件序列

```rust
// Step 1: 开始执行命令
begin_exec(&mut chat, "call-ls", "ls -la");
```

### 渲染输出

```
• Exploring
  └ List ls -la
```

### 状态管理

- 创建新的活动单元格（active cell）
- 显示旋转的活动指示器
- 命令归类为"List"类型

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (探索模式测试序列)
- **命令分类**: 根据命令类型显示不同动词（List/Read/Run等）
- **活动单元格**: `active_cell` 管理

## 依赖与外部交互

1. **codex-shell-command**: 命令解析和分类

## 风险、边界与改进建议

### 改进建议
1. 添加命令执行时间显示
2. 提供取消运行中命令的选项
