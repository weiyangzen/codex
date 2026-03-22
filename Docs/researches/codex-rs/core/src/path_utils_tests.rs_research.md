# path_utils_tests.rs 深度研究文档

## 场景与职责

`path_utils_tests.rs` 是 `path_utils.rs` 的配套测试模块，提供对路径处理工具的单元测试覆盖。测试验证符号链接解析、WSL 路径处理和 Windows 路径简化等功能。

## 功能点目的

### 1. 符号链接循环检测测试 (`symlink_cycles_fall_back_to_root_write_path`)
- **目的**：验证循环符号链接的检测和安全回退
- **测试场景**：创建相互指向的符号链接 A→B→A，验证返回根路径作为写入路径

### 2. WSL 驱动器路径小写转换测试 (`wsl_mnt_drive_paths_lowercase`)
- **目的**：验证 WSL 挂载的 Windows 驱动器路径转换为小写
- **测试场景**：`/mnt/C/Users/Dev` 应转换为 `/mnt/c/users/dev`

### 3. WSL 非驱动器路径保持测试 (`wsl_non_drive_paths_unchanged`)
- **目的**：验证非驱动器挂载路径保持不变
- **测试场景**：`/mnt/cc/Users/Dev`（双字母）保持不变

### 4. WSL 非挂载路径保持测试 (`wsl_non_mnt_paths_unchanged`)
- **目的**：验证非 `/mnt` 路径保持不变
- **测试场景**：`/home/Dev` 保持不变

### 5. Windows UNC 路径简化测试 (`windows_verbatim_paths_are_simplified`)
- **目的**：验证 Windows UNC（verbatim）路径被简化
- **测试场景**：`\\?\D:\c\x\worktrees\2508\swift-base` 简化为 `D:\c\x\worktrees\2508\swift-base`

### 6. 非 Windows 路径保持测试 (`non_windows_paths_are_unchanged`)
- **目的**：验证非 Windows 平台不修改路径
- **测试场景**：Windows 风格路径在非 Windows 平台保持不变

## 具体技术实现

### 测试结构

```rust
// Unix 特定符号链接测试
#[cfg(unix)]
mod symlinks {
    use super::super::resolve_symlink_write_paths;
    use pretty_assertions::assert_eq;
    use std::os::unix::fs::symlink;
    // ...
}

// Linux 特定 WSL 测试
#[cfg(target_os = "linux")]
mod wsl {
    use super::super::normalize_for_wsl_with_flag;
    use pretty_assertions::assert_eq;
    use std::path::PathBuf;
    // ...
}

// 原生工作目录测试（跨平台）
mod native_workdir {
    use super::super::normalize_for_native_workdir_with_flag;
    use pretty_assertions::assert_eq;
    use std::path::PathBuf;
    // ...
}
```

### 符号链接测试

```rust
#[cfg(unix)]
#[test]
fn symlink_cycles_fall_back_to_root_write_path() -> std::io::Result<()> {
    let dir = tempfile::tempdir()?;
    let a = dir.path().join("a");
    let b = dir.path().join("b");

    // 创建循环：a → b → a
    symlink(&b, &a)?;
    symlink(&a, &b)?;

    let resolved = resolve_symlink_write_paths(&a)?;

    // 检测到循环，read_path 为 None，write_path 为原始路径
    assert_eq!(resolved.read_path, None);
    assert_eq!(resolved.write_path, a);
    Ok(())
}
```

### WSL 路径测试

```rust
#[cfg(target_os = "linux")]
#[test]
fn wsl_mnt_drive_paths_lowercase() {
    let normalized = normalize_for_wsl_with_flag(PathBuf::from("/mnt/C/Users/Dev"), true);
    assert_eq!(normalized, PathBuf::from("/mnt/c/users/dev"));
}

#[cfg(target_os = "linux")]
#[test]
fn wsl_non_drive_paths_unchanged() {
    let path = PathBuf::from("/mnt/cc/Users/Dev");
    let normalized = normalize_for_wsl_with_flag(path.clone(), true);
    assert_eq!(normalized, path);
}

#[cfg(target_os = "linux")]
#[test]
fn wsl_non_mnt_paths_unchanged() {
    let path = PathBuf::from("/home/Dev");
    let normalized = normalize_for_wsl_with_flag(path.clone(), true);
    assert_eq!(normalized, path);
}
```

### Windows 路径测试

```rust
mod native_workdir {
    use super::super::normalize_for_native_workdir_with_flag;
    use pretty_assertions::assert_eq;
    use std::path::PathBuf;

    #[cfg(target_os = "windows")]
    #[test]
    fn windows_verbatim_paths_are_simplified() {
        let path = PathBuf::from(r"\\?\D:\c\x\worktrees\2508\swift-base");
        let normalized = normalize_for_native_workdir_with_flag(path, true);
        assert_eq!(
            normalized,
            PathBuf::from(r"D:\c\x\worktrees\2508\swift-base")
        );
    }

    #[test]
    fn non_windows_paths_are_unchanged() {
        let path = PathBuf::from(r"\\?\D:\c\x\worktrees\2508\swift-base");
        let normalized = normalize_for_native_workdir_with_flag(path.clone(), false);
        assert_eq!(normalized, path);
    }
}
```

## 关键代码路径与文件引用

### 测试函数清单

| 测试函数 | 模块 | 行号 | 测试目标 |
|----------|------|------|----------|
| `symlink_cycles_fall_back_to_root_write_path` | symlinks | 7-21 | 符号链接循环检测 |
| `wsl_mnt_drive_paths_lowercase` | wsl | 30-35 | WSL 驱动器路径小写 |
| `wsl_non_drive_paths_unchanged` | wsl | 37-43 | WSL 非驱动器路径 |
| `wsl_non_mnt_paths_unchanged` | wsl | 45-51 | WSL 非挂载路径 |
| `windows_verbatim_paths_are_simplified` | native_workdir | 59-69 | Windows UNC 简化 |
| `non_windows_paths_are_unchanged` | native_workdir | 71-77 | 非 Windows 路径保持 |

### 被测函数覆盖

| 被测函数 | 测试覆盖 |
|----------|----------|
| `resolve_symlink_write_paths` | `symlink_cycles_fall_back_to_root_write_path` |
| `normalize_for_wsl_with_flag` | `wsl_mnt_drive_paths_lowercase`, `wsl_non_drive_paths_unchanged`, `wsl_non_mnt_paths_unchanged` |
| `normalize_for_native_workdir_with_flag` | `windows_verbatim_paths_are_simplified`, `non_windows_paths_are_unchanged` |

### 平台条件编译

| 测试模块 | 条件 | 说明 |
|----------|------|------|
| `symlinks` | `#[cfg(unix)]` | Unix 符号链接 API |
| `wsl` | `#[cfg(target_os = "linux")]` | Linux WSL 检测 |
| `windows_verbatim_paths_are_simplified` | `#[cfg(target_os = "windows")]` | Windows 特定测试 |

## 依赖与外部交互

### 测试依赖

```rust
// 被测函数
use super::super::resolve_symlink_write_paths;
use super::super::normalize_for_wsl_with_flag;
use super::super::normalize_for_native_workdir_with_flag;

// 断言增强
use pretty_assertions::assert_eq;

// Unix 符号链接
use std::os::unix::fs::symlink;

// 标准库
use std::path::PathBuf;

// 临时目录
tempfile::tempdir
```

### 隐式依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `SymlinkWritePaths` | path_utils | 符号链接解析结果 |
| `tempfile::TempDir` | tempfile crate | 临时测试目录 |

## 风险、边界与改进建议

### 当前测试覆盖 gaps

1. **符号链接测试不完整**
   - 没有测试正常符号链接解析（非循环）
   - 没有测试相对符号链接
   - 没有测试绝对符号链接
   - 没有测试深层符号链接链
   - 没有测试符号链接指向不存在的文件

2. **原子写入测试缺失**
   - 没有测试 `write_atomically`
   - 没有测试并发写入场景
   - 没有测试大文件写入

3. **路径比较测试缺失**
   - 没有测试 `normalize_for_path_comparison`
   - 没有测试相同文件的不同路径表示

4. **WSL 测试局限**
   - 只在 Linux 平台运行，实际 WSL 环境测试不足
   - 没有测试 WSL1 vs WSL2 差异

5. **Windows 测试局限**
   - 大部分 Windows 测试只在 Windows 平台运行
   - 没有测试各种 Windows 路径格式

### 改进建议

1. **添加完整符号链接测试**
```rust
#[cfg(unix)]
#[test]
fn normal_symlink_resolution() -> std::io::Result<()> {
    let dir = tempfile::tempdir()?;
    let target = dir.path().join("target");
    let link = dir.path().join("link");
    
    std::fs::write(&target, "content")?;
    symlink(&target, &link)?;
    
    let resolved = resolve_symlink_write_paths(&link)?;
    assert_eq!(resolved.read_path, Some(target));
    assert_eq!(resolved.write_path, target);
    Ok(())
}

#[cfg(unix)]
#[test]
fn relative_symlink_resolution() -> std::io::Result<()> {
    let dir = tempfile::tempdir()?;
    let subdir = dir.path().join("subdir");
    std::fs::create_dir(&subdir)?;
    
    let target = subdir.join("target");
    let link = dir.path().join("link");
    
    std::fs::write(&target, "content")?;
    symlink("subdir/target", &link)?;
    
    let resolved = resolve_symlink_write_paths(&link)?;
    assert_eq!(resolved.read_path, Some(target.canonicalize()?));
    Ok(())
}

#[cfg(unix)]
#[test]
fn dangling_symlink_handling() -> std::io::Result<()> {
    let dir = tempfile::tempdir()?;
    let link = dir.path().join("link");
    
    symlink("nonexistent", &link)?;
    
    let resolved = resolve_symlink_write_paths(&link)?;
    // 应该返回链接本身作为写入路径
    assert_eq!(resolved.write_path, link);
    Ok(())
}
```

2. **添加原子写入测试**
```rust
#[test]
fn write_atomically_creates_file() -> std::io::Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("test.txt");
    
    write_atomically(&path, "content")?;
    
    assert!(path.exists());
    assert_eq!(std::fs::read_to_string(&path)?, "content");
    Ok(())
}

#[test]
fn write_atomically_overwrites_existing() -> std::io::Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("test.txt");
    
    std::fs::write(&path, "old")?;
    write_atomically(&path, "new")?;
    
    assert_eq!(std::fs::read_to_string(&path)?, "new");
    Ok(())
}
```

3. **添加路径比较测试**
```rust
#[test]
fn normalize_for_comparison_same_file() -> std::io::Result<()> {
    let dir = tempfile::tempdir()?;
    let file = dir.path().join("file.txt");
    std::fs::write(&file, "")?;
    
    let path1 = normalize_for_path_comparison(&file)?;
    let path2 = normalize_for_path_comparison(dir.path().join("./file.txt"))?;
    
    assert_eq!(path1, path2);
    Ok(())
}
```

4. **使用 insta snapshot 测试**
   - 对复杂路径结构进行快照测试
   - 便于检测意外的路径处理变化

5. **添加并发测试**
```rust
#[test]
fn concurrent_atomic_writes() -> std::io::Result<()> {
    use std::sync::Arc;
    use std::thread;
    
    let dir = tempfile::tempdir()?;
    let path = Arc::new(dir.path().join("test.txt"));
    let mut handles = vec![];
    
    for i in 0..10 {
        let path = Arc::clone(&path);
        handles.push(thread::spawn(move || {
            write_atomically(&path, &format!("content{}", i))
        }));
    }
    
    for handle in handles {
        handle.join().unwrap()?;
    }
    
    // 文件应该存在且内容完整
    assert!(path.exists());
    Ok(())
}
```

### 测试代码质量建议

1. **提取公共辅助函数**
```rust
fn create_temp_file(dir: &Path, name: &str, content: &str) -> std::io::Result<PathBuf> {
    let path = dir.join(name);
    std::fs::write(&path, content)?;
    Ok(path)
}
```

2. **添加更多文档注释**
   - 解释每个测试的具体场景

3. **使用参数化测试**
   - 使用 `rstest` 测试多种路径格式
