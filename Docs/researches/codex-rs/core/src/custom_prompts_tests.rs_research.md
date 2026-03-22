# custom_prompts_tests.rs 研究文档

## 场景与职责

`custom_prompts_tests.rs` 是 `custom_prompts.rs` 的配套测试模块，通过 `#[path = "custom_prompts_tests.rs"]` 内联到主模块中。该测试文件全面验证了自定义 prompt 发现、解析和过滤功能的正确性。

**测试覆盖范围：**
1. 目录边界情况（缺失、空目录）
2. 文件发现和排序
3. 排除列表功能
4. 非 UTF-8 文件处理
5. 符号链接支持（Unix 平台）
6. Frontmatter 解析（YAML-like 元数据）
7. 换行符处理（CRLF vs LF）

---

## 功能点目的

### 测试用例清单

| 测试函数 | 目的 | 关键验证点 |
|---------|------|-----------|
| `empty_when_dir_missing` | 验证缺失目录返回空列表 | 不 panic，优雅处理 |
| `discovers_and_sorts_files` | 验证文件发现和字母排序 | 子目录被忽略，按名称排序 |
| `excludes_builtins` | 验证排除列表功能 | `init.md` 被过滤 |
| `skips_non_utf8_files` | 验证非 UTF-8 文件跳过 | 无效字节序列被正确处理 |
| `discovers_symlinked_md_files` | 验证符号链接支持 | Unix 平台符号链接被正确解析 |
| `parses_frontmatter_and_strips_from_body` | 验证 frontmatter 解析 | 元数据提取，body 分离 |
| `parse_frontmatter_preserves_body_newlines` | 验证 CRLF 换行符保留 | Windows 风格换行符正确处理 |

---

## 具体技术实现

### 测试基础设施

**临时目录创建：**
```rust
use tempfile::tempdir;
let tmp = tempdir().expect("create TempDir");
let dir = tmp.path();
```
- 使用 `tempfile` crate 创建隔离的测试环境
- 自动清理，避免测试间污染

**文件写入：**
```rust
use std::fs;
fs::write(dir.join("b.md"), b"b").unwrap();
```
- 使用标准库 `fs::write` 创建测试文件

**符号链接创建（Unix）：**
```rust
#[cfg(unix)]
std::os::unix::fs::symlink(dir.join("real.md"), dir.join("link.md")).unwrap();
```
- 条件编译仅 Unix 平台
- 验证符号链接被当作独立条目处理

### 关键测试场景

**1. 非 UTF-8 文件测试**
```rust
#[tokio::test]
async fn skips_non_utf8_files() {
    // 有效 UTF-8 文件
    fs::write(dir.join("good.md"), b"hello").unwrap();
    // 无效 UTF-8 内容（孤立的 0xFF 字节）
    fs::write(dir.join("bad.md"), vec![0xFF, 0xFE, b'\n']).unwrap();
    // 验证只有 good.md 被发现
}
```
- 使用 `0xFF, 0xFE` 构造无效 UTF-8 序列
- 验证 `fs::read_to_string` 失败时文件被跳过

**2. Frontmatter 解析测试**
```rust
let text = "---\nname: ignored\ndescription: \"Quick review command\"\nargument-hint: \"[file] [priority]\"\n---\nActual body with $1 and $ARGUMENTS";
```
- 验证 `description` 和 `argument-hint` 提取
- 验证 body 中 frontmatter 分隔符被移除
- 验证变量占位符（`$1`, `$ARGUMENTS`）保留

**3. CRLF 换行符测试**
```rust
let content = "---\r\ndescription: \"Line endings\"\r\nargument_hint: \"[arg]\"\r\n---\r\nFirst line\r\nSecond line\r\n";
```
- 验证 Windows 风格换行符（`\r\n`）正确处理
- 验证 body 中的换行符被保留

---

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/custom_prompts_tests.rs` (95 行)

### 被测试文件
- `/home/sansha/Github/codex/codex-rs/core/src/custom_prompts.rs` - 主实现

### 测试依赖
- `tempfile::tempdir` - 临时目录创建
- `std::fs` - 文件操作
- `tokio::test` - 异步测试运行时

---

## 依赖与外部交互

### 测试框架
| 依赖 | 用途 |
|------|------|
| `tokio::test` | 异步测试支持 |
| `tempfile::tempdir` | 隔离的测试环境 |
| `std::fs` | 文件系统操作 |

### 平台特定代码
- `#[cfg(unix)]` - Unix 平台符号链接测试
- 使用 `std::os::unix::fs::symlink`

---

## 风险、边界与改进建议

### 测试覆盖缺口

1. **并发场景**
   - 无并发调用测试
   - 建议：添加多任务同时调用 `discover_prompts_in` 的测试

2. **大文件处理**
   - 无大文件边界测试
   - 建议：添加大文件（>1MB）行为验证

3. **特殊文件名**
   - 无 Unicode 文件名测试
   - 无包含空格、特殊字符的文件名测试

4. **Frontmatter 边界**
   - 无空 frontmatter 测试（`---\n---\n`）
   - 无嵌套 frontmatter 测试
   - 无无效 YAML 格式测试

5. **权限问题**
   - 无只读目录测试
   - 无权限不足场景测试

### 改进建议

1. **添加性能测试**
   ```rust
   // 测试大量文件的扫描性能
   #[tokio::test]
   async fn performance_with_many_files() {
       // 创建 1000+ 个文件，验证性能
   }
   ```

2. **添加模糊测试**
   - 使用 `proptest` 或 `quickcheck` 生成随机 frontmatter
   - 验证解析器不会 panic

3. **增强平台覆盖**
   - 添加 Windows 符号链接测试（`std::os::windows::fs::symlink_file`）
   - 添加不同文件系统行为测试

4. **添加集成测试**
   - 测试与 TUI 层的集成
   - 测试真实 `CODEX_HOME` 环境

### 测试代码质量

**优点：**
- 使用 `tempfile` 确保隔离性
- 异步测试使用 `tokio::test`
- 清晰的测试命名和断言
- 平台特定代码使用条件编译

**可改进点：**
- 部分测试可提取公共辅助函数
- 可添加属性测试（property-based testing）
- 可添加基准测试（benchmark）
