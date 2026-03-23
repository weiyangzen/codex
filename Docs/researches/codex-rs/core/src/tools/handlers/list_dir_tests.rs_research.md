# list_dir_tests.rs 研究文档

## 场景与职责

`list_dir_tests.rs` 是 `list_dir.rs` 的配套测试模块，通过 `#[path = "list_dir_tests.rs"]` 在 `list_dir.rs` 中条件编译引入。该测试文件负责验证目录列表工具的各种功能场景，确保文件系统遍历、分页、排序等核心行为的正确性。

**测试覆盖范围：**
- 目录结构遍历（单层、多层递归）
- 文件类型识别（文件、目录、符号链接）
- 分页参数（offset、limit）
- 深度控制（depth）
- 排序一致性
- 边界条件（大数值、空结果等）

## 功能点目的

### 1. 基础功能测试 (`lists_directory_entries`)
验证基本的目录遍历功能：
- 创建嵌套目录结构（3 层深度）
- 创建普通文件
- 在 Unix 系统上创建符号链接
- 验证输出格式和排序

### 2. 错误处理测试 (`errors_when_offset_exceeds_entries`)
验证当 offset 超过实际条目数时的错误处理：
- 返回明确的错误信息
- 错误类型为 `FunctionCallError::RespondToModel`

### 3. 深度控制测试 (`respects_depth_parameter`)
验证 `depth` 参数的有效性：
- depth=1：仅顶层目录
- depth=2：包含一级子目录
- depth=3：包含二级子目录

### 4. 分页功能测试 (`paginates_in_sorted_order`)
验证分页在排序后的列表上工作：
- 第一页返回前 N 个条目
- 第二页返回后续条目
- 中间页显示 "More than X entries found"

### 5. 边界条件测试
- `handles_large_limit_without_overflow`：验证 `usize::MAX` 不会导致溢出
- `indicates_truncated_results`：验证超过 limit 时的提示信息
- `truncation_respects_sorted_order`：验证截断保持排序顺序

## 具体技术实现

### 测试框架

```rust
use super::*;  // 导入 list_dir.rs 的所有内容
use pretty_assertions::assert_eq;  // 提供更好的 diff 输出
use tempfile::tempdir;  // 创建临时目录
```

### 测试模式

**标准测试结构：**
```rust
#[tokio::test]
async fn test_name() {
    // 1. 创建临时目录
    let temp = tempdir().expect("create tempdir");
    let dir_path = temp.path();
    
    // 2. 设置测试数据
    tokio::fs::create_dir(&sub_dir).await.expect("create sub dir");
    tokio::fs::write(file_path, b"content").await.expect("write file");
    
    // 3. 执行被测函数
    let entries = list_dir_slice(dir_path, 1, 20, 3)
        .await
        .expect("list directory");
    
    // 4. 验证结果
    assert_eq!(entries, expected);
}
```

### 平台特定测试

**Unix 符号链接测试：**
```rust
#[cfg(unix)]
{
    use std::os::unix::fs::symlink;
    let link_path = dir_path.join("link");
    symlink(dir_path.join("entry.txt"), &link_path).expect("create symlink");
}

// 验证时区分平台
#[cfg(unix)]
let expected = vec![...];  // 包含 link@

#[cfg(not(unix))]
let expected = vec![...];  // 不包含符号链接
```

### 关键测试用例详解

**1. 基础列表测试**
```rust
#[tokio::test]
async fn lists_directory_entries() {
    // 创建结构：
    // /
    //   entry.txt
    //   link@ -> entry.txt (Unix only)
    //   nested/
    //     child.txt
    //     deeper/
    //       grandchild.txt
    
    // 期望输出（按字母排序）：
    // entry.txt
    // link@          (Unix only)
    // nested/
    //   child.txt
    //   deeper/
    //     grandchild.txt
}
```

**2. 深度控制测试**
```rust
async fn respects_depth_parameter() {
    // depth=1: ["nested/", "root.txt"]
    // depth=2: ["nested/", "  child.txt", "  deeper/", "root.txt"]
    // depth=3: ["nested/", "  child.txt", "  deeper/", "    grandchild.txt", "root.txt"]
}
```

**3. 分页测试**
```rust
async fn paginates_in_sorted_order() {
    // 目录：a/, b/
    // 每个子目录包含一个文件
    
    // Page 1 (offset=1, limit=2):
    // ["a/", "  a_child.txt", "More than 2 entries found"]
    
    // Page 2 (offset=3, limit=2):
    // ["b/", "  b_child.txt"]
}
```

**4. 大数值边界测试**
```rust
async fn handles_large_limit_without_overflow() {
    // 使用 usize::MAX 作为 limit
    // 验证：offset=2 时正确返回从第2个开始的条目
    // 不会 panic 或溢出
}
```

## 依赖与外部交互

### 测试依赖

| 依赖 | 版本/来源 | 用途 |
|------|----------|------|
| `super::*` | 被测模块 | 导入 `list_dir.rs` 的所有导出内容 |
| `pretty_assertions::assert_eq` | crates.io | 提供结构化的 diff 输出 |
| `tempfile::tempdir` | crates.io | 创建隔离的临时目录 |
| `tokio::fs` | tokio | 异步文件操作 |

### 被测函数

测试直接调用 `list_dir.rs` 的内部函数：
```rust
// 被测函数（pub(crate) 级别）
async fn list_dir_slice(
    path: &Path,
    offset: usize,
    limit: usize,
    depth: usize,
) -> Result<Vec<String>, FunctionCallError>
```

**注意：** 测试不通过 `ToolHandler::handle` 调用，而是直接测试内部函数，这是单元测试的常见模式。

## 风险、边界与改进建议

### 当前测试覆盖情况

| 功能 | 覆盖状态 | 说明 |
|------|----------|------|
| 基本目录遍历 | ✅ | `lists_directory_entries` |
| 文件类型识别 | ⚠️ | 仅测试符号链接，未测试 "Other" 类型 |
| 深度控制 | ✅ | `respects_depth_parameter` |
| 分页 | ✅ | `paginates_in_sorted_order` |
| 错误处理 | ✅ | `errors_when_offset_exceeds_entries` |
| 大数值处理 | ✅ | `handles_large_limit_without_overflow` |
| 结果截断提示 | ✅ | `indicates_truncated_results` |
| 排序一致性 | ✅ | `truncation_respects_sorted_order` |

### 测试盲点

1. **绝对路径验证**
   - 未测试传入相对路径时的错误处理
   - 未测试空路径处理

2. **权限错误**
   - 未测试无权限访问目录的场景
   - 未测试部分子目录无权限的场景

3. **特殊文件名**
   - 未测试包含特殊字符的文件名
   - 未测试超长文件名截断
   - 未测试非 UTF-8 文件名

4. **并发安全**
   - 未测试目录在遍历过程中被修改的场景

### 改进建议

1. **添加错误场景测试**
```rust
#[tokio::test]
async fn rejects_relative_path() {
    let result = list_dir_slice(Path::new("./relative"), 1, 10, 2).await;
    assert!(matches!(result, Err(FunctionCallError::RespondToModel(_))));
}

#[tokio::test]
async fn rejects_zero_offset() {
    let temp = tempdir().unwrap();
    let result = list_dir_slice(temp.path(), 0, 10, 2).await;
    assert!(matches!(result, Err(FunctionCallError::RespondToModel(msg)) 
        if msg.contains("offset must be")));
}
```

2. **添加特殊文件名测试**
```rust
#[tokio::test]
async fn handles_special_characters_in_names() {
    // 测试包含空格、换行、Unicode 的文件名
}

#[tokio::test]
async fn handles_long_names() {
    // 测试超过 500 字符的文件名截断
}
```

3. **添加并发修改测试**
```rust
#[tokio::test]
async fn handles_directory_modified_during_listing() {
    // 测试遍历过程中文件被删除的场景
}
```

### 测试运行

```bash
# 运行特定测试
cargo test -p codex-core lists_directory_entries

# 运行所有 list_dir 测试
cargo test -p codex-core list_dir

# 运行带输出
cargo test -p codex-core list_dir -- --nocapture
```

### 与主模块的集成

测试模块通过以下方式与主模块关联：
```rust
// list_dir.rs 末尾
#[cfg(test)]
#[path = "list_dir_tests.rs"]
mod tests;
```

这种组织方式：
- 保持主文件整洁
- 测试代码与实现代码分离
- 条件编译，仅在测试时包含
