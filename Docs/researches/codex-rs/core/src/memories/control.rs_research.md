# control.rs - 研究文档

## 场景与职责

`control.rs` 模块提供记忆根目录的安全清理功能。这是记忆系统中的一个关键安全组件，用于在需要时安全地清除记忆目录内容。

### 核心职责

1. **安全清理**: 清除记忆根目录中的所有内容，同时保留目录本身
2. **符号链接保护**: 拒绝清理符号链接目录，防止意外删除外部文件
3. **递归删除**: 正确处理嵌套目录结构

### 使用场景

- 记忆系统重置时清理旧数据
- 测试环境中准备干净状态
- 用户请求清除记忆历史

## 功能点目的

### `clear_memory_root_contents`

**目的**: 安全地清除记忆根目录中的所有文件和子目录

**安全特性**:
1. **符号链接检查**: 如果根目录是符号链接，拒绝操作
2. **目录创建**: 如果不存在，创建目录
3. **递归清理**: 删除所有子目录和文件

**算法**:
```rust
pub async fn clear_memory_root_contents(memory_root: &Path) -> std::io::Result<()> {
    // 1. 检查是否为符号链接
    match tokio::fs::symlink_metadata(memory_root).await {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                format!("refusing to clear symlinked memory root {}", memory_root.display()),
            ));
        }
        Ok(_) => {}
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
        Err(err) => return Err(err),
    }

    // 2. 确保目录存在
    tokio::fs::create_dir_all(memory_root).await?;

    // 3. 递归删除内容
    let mut entries = tokio::fs::read_dir(memory_root).await?;
    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        let file_type = entry.file_type().await?;
        if file_type.is_dir() {
            tokio::fs::remove_dir_all(path).await?;
        } else {
            tokio::fs::remove_file(path).await?;
        }
    }

    Ok(())
}
```

## 关键代码路径与文件引用

### 函数签名

| 函数 | 行号 | 签名 |
|------|------|------|
| `clear_memory_root_contents` | 3 | `pub(crate) async fn clear_memory_root_contents(memory_root: &Path) -> std::io::Result<()>` |

### 代码流程

```
clear_memory_root_contents
├── 检查符号链接 (行 4-17)
│   ├── 是符号链接 → 返回错误
│   ├── 不存在 → 继续
│   └── 其他错误 → 传播
├── 创建目录 (行 19)
└── 递归删除内容 (行 21-30)
    ├── 读取目录条目
    ├── 判断文件类型
    ├── 目录 → remove_dir_all
    └── 文件 → remove_file
```

## 依赖与外部交互

### 标准库依赖

| 模块 | 用途 |
|------|------|
| `std::path::Path` | 路径处理 |
| `std::io::Error`/`ErrorKind` | 错误处理 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio::fs` | 异步文件系统操作 |

### 调用方

| 模块 | 用途 |
|------|------|
| `memories::mod` | 公开导出 |
| `memories::tests` | 测试中使用 |

## 风险、边界与改进建议

### 已知风险

1. **符号链接目标检查不足**:
   - 仅检查根目录本身是否为符号链接
   - 不检查子目录中的符号链接
   - 如果子目录包含指向外部的符号链接，可能被意外删除

2. **竞争条件**:
   - 检查符号链接和实际删除之间存在时间窗口
   - 恶意用户可能利用 TOCTOU 攻击

3. **权限问题**:
   - 如果某些文件或目录权限不足，删除可能部分失败
   - 没有原子性保证

### 边界条件

1. **空目录**: 正常处理，不执行删除操作
2. **不存在的目录**: 创建新目录
3. **符号链接目录**: 拒绝操作
4. **只读文件**: 删除可能失败（取决于操作系统）

### 改进建议

1. **递归符号链接检查**:
```rust
// 添加递归检查
async fn is_path_inside_root(path: &Path, root: &Path) -> bool {
    let canonical_path = tokio::fs::canonicalize(path).await.ok()?;
    let canonical_root = tokio::fs::canonicalize(root).await.ok()?;
    canonical_path.starts_with(&canonical_root)
}
```

2. **原子性保证**:
   - 考虑使用临时目录和原子重命名
   - 或者在删除前创建备份

3. **更详细的错误信息**:
```rust
// 记录每个删除失败的具体路径
while let Some(entry) = entries.next_entry().await? {
    let path = entry.path();
    if let Err(e) = delete_entry(&path).await {
        tracing::warn!("Failed to delete {}: {}", path.display(), e);
    }
}
```

4. **添加 dry-run 模式**:
   - 允许预览将要删除的内容而不实际删除

5. **添加进度回调**:
   - 对于大目录，提供删除进度反馈

6. **硬链接检查**:
   - 检查文件是否有多个硬链接
   - 避免意外删除共享文件
