# grep_files_tests.rs 深度研究文档

## 场景与职责

`grep_files_tests.rs` 是 `grep_files.rs` 的单元测试模块，负责验证文件搜索功能的正确性。该测试文件作为内联测试模块被包含在 `grep_files.rs` 中。

## 功能点目的

### 测试覆盖范围

1. **结果解析测试** - 验证 `parse_results` 对 ripgrep 输出的解析
2. **搜索功能测试** - 验证 `run_rg_search` 的完整搜索流程
3. **过滤功能测试** - 验证 glob 过滤功能
4. **限制功能测试** - 验证结果数量限制
5. **空结果测试** - 验证无匹配场景处理

## 具体技术实现

### 测试用例详情

#### 1. `parses_basic_results`

```rust
#[test]
fn parses_basic_results() {
    let stdout = b"/tmp/file_a.rs\n/tmp/file_b.rs\n";
    let parsed = parse_results(stdout, 10);
    assert_eq!(
        parsed,
        vec!["/tmp/file_a.rs".to_string(), "/tmp/file_b.rs".to_string()]
    );
}
```

**测试目的：** 验证基本结果解析功能

#### 2. `parse_truncates_after_limit`

```rust
#[test]
fn parse_truncates_after_limit() {
    let stdout = b"/tmp/file_a.rs\n/tmp/file_b.rs\n/tmp/file_c.rs\n";
    let parsed = parse_results(stdout, 2);
    assert_eq!(
        parsed,
        vec!["/tmp/file_a.rs".to_string(), "/tmp/file_b.rs".to_string()]
    );
}
```

**测试目的：** 验证结果数量限制生效

#### 3. `run_search_returns_results`

```rust
#[tokio::test]
async fn run_search_returns_results() -> anyhow::Result<()> {
    if !rg_available() {
        return Ok(());  // 跳过测试
    }
    let temp = tempdir().expect("create temp dir");
    let dir = temp.path();
    std::fs::write(dir.join("match_one.txt"), "alpha beta gamma").unwrap();
    std::fs::write(dir.join("match_two.txt"), "alpha delta").unwrap();
    std::fs::write(dir.join("other.txt"), "omega").unwrap();

    let results = run_rg_search("alpha", None, dir, 10, dir).await?;
    assert_eq!(results.len(), 2);
    assert!(results.iter().any(|path| path.ends_with("match_one.txt")));
    assert!(results.iter().any(|path| path.ends_with("match_two.txt")));
    Ok(())
}
```

**测试目的：** 验证完整搜索流程，匹配包含 "alpha" 的文件

#### 4. `run_search_with_glob_filter`

```rust
#[tokio::test]
async fn run_search_with_glob_filter() -> anyhow::Result<()> {
    if !rg_available() {
        return Ok(());
    }
    let temp = tempdir().expect("create temp dir");
    let dir = temp.path();
    std::fs::write(dir.join("match_one.rs"), "alpha beta gamma").unwrap();
    std::fs::write(dir.join("match_two.txt"), "alpha delta").unwrap();

    let results = run_rg_search("alpha", Some("*.rs"), dir, 10, dir).await?;
    assert_eq!(results.len(), 1);
    assert!(results.iter().all(|path| path.ends_with("match_one.rs")));
    Ok(())
}
```

**测试目的：** 验证 glob 过滤功能，只返回 `.rs` 文件

#### 5. `run_search_respects_limit`

```rust
#[tokio::test]
async fn run_search_respects_limit() -> anyhow::Result<()> {
    if !rg_available() {
        return Ok(());
    }
    let temp = tempdir().expect("create temp dir");
    let dir = temp.path();
    std::fs::write(dir.join("one.txt"), "alpha one").unwrap();
    std::fs::write(dir.join("two.txt"), "alpha two").unwrap();
    std::fs::write(dir.join("three.txt"), "alpha three").unwrap();

    let results = run_rg_search("alpha", None, dir, 2, dir).await?;
    assert_eq!(results.len(), 2);
    Ok(())
}
```

**测试目的：** 验证搜索时结果数量限制生效

#### 6. `run_search_handles_no_matches`

```rust
#[tokio::test]
async fn run_search_handles_no_matches() -> anyhow::Result<()> {
    if !rg_available() {
        return Ok(());
    }
    let temp = tempdir().expect("create temp dir");
    let dir = temp.path();
    std::fs::write(dir.join("one.txt"), "omega").unwrap();

    let results = run_rg_search("alpha", None, dir, 5, dir).await?;
    assert!(results.is_empty());
    Ok(())
}
```

**测试目的：** 验证无匹配时返回空列表

#### 7. `rg_available`（辅助函数）

```rust
fn rg_available() -> bool {
    StdCommand::new("rg")
        .arg("--version")
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}
```

**用途：** 检测 ripgrep 是否安装，未安装时跳过测试

## 关键代码路径与文件引用

| 测试函数 | 被测函数 | 所在文件 |
|---------|---------|---------|
| `parses_basic_results` | `parse_results` | grep_files.rs:155 |
| `parse_truncates_after_limit` | `parse_results` | grep_files.rs:155 |
| `run_search_returns_results` | `run_rg_search` | grep_files.rs:110 |
| `run_search_with_glob_filter` | `run_rg_search` | grep_files.rs:110 |
| `run_search_respects_limit` | `run_rg_search` | grep_files.rs:110 |
| `run_search_handles_no_matches` | `run_rg_search` | grep_files.rs:110 |

## 依赖与外部交互

### 测试依赖

```rust
use super::*;  // 引入 grep_files.rs 的所有私有函数
use std::process::Command as StdCommand;  // 同步命令检测 rg
use tempfile::tempdir;  // 临时目录
```

### 外部依赖

| Crate/工具 | 用途 |
|------------|------|
| `tempfile` | 创建临时测试目录 |
| `ripgrep` (系统命令) | 实际搜索执行 |
| `anyhow` | 测试错误处理 |

## 风险、边界与改进建议

### 测试覆盖缺口

1. **缺少错误场景测试**
   - 无效正则表达式
   - 路径不存在
   - 权限不足
   - ripgrep 未安装（已处理，跳过测试）

2. **缺少边界测试**
   - 空目录搜索
   - 超大文件搜索
   - 特殊字符文件名
   - 二进制文件处理

3. **缺少 Handler 层测试**
   - `GrepFilesHandler::handle` 完整流程
   - 参数验证（空 pattern、limit=0）

### 改进建议

1. **添加错误场景测试**
   ```rust
   #[tokio::test]
   async fn run_search_invalid_pattern() {
       // 测试无效正则
   }
   
   #[tokio::test]
   async fn run_search_nonexistent_path() {
       // 测试路径不存在
   }
   ```

2. **添加边界测试**
   ```rust
   #[tokio::test]
   async fn run_search_empty_directory() {
       // 测试空目录
   }
   
   #[tokio::test]
   async fn run_search_special_chars_in_filename() {
       // 测试特殊字符文件名
   }
   ```

3. **改进测试稳定性**
   - 当前测试依赖系统 ripgrep
   - 考虑使用 mock 或内嵌测试数据

4. **测试组织建议**
   - 当前测试文件 95 行，可保持内联
   - 如添加更多集成测试，建议拆分为独立文件
