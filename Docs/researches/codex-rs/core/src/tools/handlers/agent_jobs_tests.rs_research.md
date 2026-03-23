# agent_jobs_tests.rs 深度研究文档

## 场景与职责

`agent_jobs_tests.rs` 是 `agent_jobs.rs` 的单元测试模块，负责验证 CSV 处理、模板渲染、CSV 转义等核心工具函数的正确性。该测试文件作为内联测试模块（`#[cfg(test)] mod tests`）被包含在 `agent_jobs.rs` 中。

## 功能点目的

### 测试覆盖范围

1. **CSV 解析测试** - 验证 `parse_csv` 函数对复杂 CSV 格式的处理能力
2. **CSV 转义测试** - 验证 `csv_escape` 函数对特殊字符的正确转义
3. **模板渲染测试** - 验证 `render_instruction_template` 的占位符替换逻辑
4. **表头验证测试** - 验证 `ensure_unique_headers` 对重复列名的检测

## 具体技术实现

### 测试用例详情

#### 1. `parse_csv_supports_quotes_and_commas`
```rust
#[test]
fn parse_csv_supports_quotes_and_commas() {
    let input = "id,name\n1,\"alpha, beta\"\n2,gamma\n";
    let (headers, rows) = parse_csv(input).expect("csv parse");
    assert_eq!(headers, vec!["id".to_string(), "name".to_string()]);
    assert_eq!(
        rows,
        vec![
            vec!["1".to_string(), "alpha, beta".to_string()],
            vec!["2".to_string(), "gamma".to_string()]
        ]
    );
}
```
**测试目的：** 验证 CSV 解析器正确处理带引号的字段（包含逗号的情况）

#### 2. `csv_escape_quotes_when_needed`
```rust
#[test]
fn csv_escape_quotes_when_needed() {
    assert_eq!(csv_escape("simple"), "simple");
    assert_eq!(csv_escape("a,b"), "\"a,b\"");
    assert_eq!(csv_escape("a\"b"), "\"a\"\"b\"");
}
```
**测试目的：** 验证 CSV 转义逻辑
- 简单字符串：无需转义
- 包含逗号：整体加引号
- 包含引号：引号转义为双引号

#### 3. `render_instruction_template_expands_placeholders_and_escapes_braces`
```rust
#[test]
fn render_instruction_template_expands_placeholders_and_escapes_braces() {
    let row = json!({
        "path": "src/lib.rs",
        "area": "test",
        "file path": "docs/readme.md",
    });
    let rendered = render_instruction_template(
        "Review {path} in {area}. Also see {file path}. Use {{literal}}.",
        &row,
    );
    assert_eq!(
        rendered,
        "Review src/lib.rs in test. Also see docs/readme.md. Use {literal}."
    );
}
```
**测试目的：** 验证模板渲染
- 普通占位符替换：`{path}` → `src/lib.rs`
- 带空格列名：`{file path}` → `docs/readme.md`
- 双大括号转义：`{{literal}}` → `{literal}`

#### 4. `render_instruction_template_leaves_unknown_placeholders`
```rust
#[test]
fn render_instruction_template_leaves_unknown_placeholders() {
    let row = json!({"path": "src/lib.rs"});
    let rendered = render_instruction_template("Check {path} then {missing}", &row);
    assert_eq!(rendered, "Check src/lib.rs then {missing}");
}
```
**测试目的：** 验证未知占位符保持原样，不报错

#### 5. `ensure_unique_headers_rejects_duplicates`
```rust
#[test]
fn ensure_unique_headers_rejects_duplicates() {
    let headers = vec!["path".to_string(), "path".to_string()];
    let Err(err) = ensure_unique_headers(headers.as_slice()) else {
        panic!("expected duplicate header error");
    };
    assert_eq!(
        err,
        FunctionCallError::RespondToModel("csv header path is duplicated".to_string())
    );
}
```
**测试目的：** 验证重复表头检测和错误返回

## 关键代码路径与文件引用

| 测试函数 | 被测函数 | 所在文件 |
|---------|---------|---------|
| `parse_csv_supports_quotes_and_commas` | `parse_csv` | agent_jobs.rs:1103 |
| `csv_escape_quotes_when_needed` | `csv_escape` | agent_jobs.rs:1211 |
| `render_instruction_template_*` | `render_instruction_template` | agent_jobs.rs:1032 |
| `ensure_unique_headers_rejects_duplicates` | `ensure_unique_headers` | agent_jobs.rs:1057 |

## 依赖与外部交互

### 测试依赖

```rust
use super::*;  // 引入 agent_jobs.rs 的所有私有函数
use pretty_assertions::assert_eq;  // 更好的差异输出
use serde_json::json;  // JSON 构造宏
```

## 风险、边界与改进建议

### 测试覆盖缺口

1. **缺少集成测试**
   - 没有测试完整的 `spawn_agents_on_csv` 流程
   - 没有测试 `run_agent_job_loop` 并发逻辑
   - 没有测试数据库交互

2. **缺少边界测试**
   - 空 CSV 文件处理
   - 超大 CSV 文件处理
   - 特殊字符编码（UTF-8 BOM 等）
   - 模板注入攻击防护

3. **缺少错误场景测试**
   - 文件不存在场景
   - 权限不足场景
   - 数据库错误场景
   - Agent 启动失败场景

### 改进建议

1. **添加集成测试**
   ```rust
   #[tokio::test]
   async fn test_spawn_agents_on_csv_full_flow() {
       // 使用内存数据库和 Mock AgentControl
   }
   ```

2. **添加边界测试**
   ```rust
   #[test]
   fn parse_csv_empty_file() { ... }
   
   #[test]
   fn parse_csv_unicode_bom() { ... }
   
   #[test]
   fn render_instruction_template_empty_row() { ... }
   ```

3. **添加并发测试**
   ```rust
   #[tokio::test]
   async fn run_agent_job_loop_concurrency_limit() { ... }
   ```

4. **测试组织优化**
   - 当前测试文件较小（62 行），可保持内联
   - 如测试增长，建议拆分为 `agent_jobs_integration_tests.rs`
