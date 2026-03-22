# 019_unicode_simple 测试场景研究文档

## 场景与职责

### 文件位置
- **目标文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/patch.txt`
- **输入文件**: `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/input/foo.txt`
- **期望输出**: `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/expected/foo.txt`

### 场景概述

`019_unicode_simple` 是 `apply-patch` 组件的一个集成测试场景，专门用于验证 **Unicode 字符处理** 能力。该场景测试以下核心职责：

1. **多字节 Unicode 字符的正确解析**: 验证 patch 解析器能够正确处理包含非 ASCII 字符（如带变音符号的拉丁字符 `ï`、`é`）的文本内容
2. **Emoji 字符的追加**: 验证系统能够正确处理并写入 Emoji 字符（如 `✅` U+2705）
3. **UTF-8 编码完整性**: 确保文件读写过程中 Unicode 字符不会发生损坏或编码错误

### 测试数据内容

**patch.txt**:
```
*** Begin Patch
*** Update File: foo.txt
@@
 line1
-naïve café
+naïve café ✅
*** End Patch
```

**input/foo.txt** (原始文件):
```
line1
naïve café
line3
```

**expected/foo.txt** (期望输出):
```
line1
naïve café ✅
line3
```

### 在测试套件中的角色

该场景是 `codex-rs/apply-patch/tests/fixtures/scenarios/` 目录下的 23 个测试场景之一（编号 019），属于**正向测试用例**（即期望成功应用 patch）。它补充了其他场景的测试覆盖：

| 场景编号 | 名称 | 测试类型 |
|---------|------|---------|
| 001-004 | 基础操作 | 正向测试 |
| 005-013 | 错误处理 | 负向测试 |
| 014-018 | 边界情况 | 特殊格式 |
| **019** | **unicode_simple** | **Unicode 处理** |
| 020-022 | 其他边界 | 删除/EOF 处理 |

---

## 功能点目的

### 1. Unicode 字符支持验证

该场景的核心目的是验证 `apply-patch` 工具能够正确处理包含 Unicode 字符的文件内容，包括：

- **拉丁字母扩展**: `ï` (U+00EF, 小写拉丁字母 I 带分音符)、`é` (U+00E9, 小写拉丁字母 E 带锐音符)
- **Emoji 符号**: `✅` (U+2705, 白色勾选标记)

### 2. 编码一致性保证

确保在以下操作中 Unicode 字符不会丢失或损坏：
- Patch 文件解析（从 `patch.txt` 读取）
- 源文件读取（从 `input/foo.txt` 读取）
- 内容匹配与替换（`seek_sequence` 模块）
- 目标文件写入（写入到临时目录）

### 3. 与 Unicode 模糊匹配的区分

值得注意的是，本场景测试的是**直接的 Unicode 字符处理**，而非 `seek_sequence.rs` 中实现的 **Unicode 标点符号归一化**功能（该功能用于将排版标点符号归一化为 ASCII 等价物，以支持更宽松的匹配）。这是两个不同层面的 Unicode 支持：

| 功能 | 位置 | 目的 |
|-----|------|-----|
| Unicode 字符直接处理 | 本场景 | 验证多字节字符的正确读写 |
| Unicode 标点归一化 | `seek_sequence.rs:76-94` | 支持 ASCII patch 匹配 Unicode 源文件 |

---

## 具体技术实现

### 关键流程

#### 1. Patch 解析流程

```
patch.txt → parser.rs::parse_patch() → ApplyPatchArgs { hunks: [Hunk::UpdateFile { ... }] }
```

**关键代码路径** (`codex-rs/apply-patch/src/parser.rs:106-113`):
```rust
pub fn parse_patch(patch: &str) -> Result<ApplyPatchArgs, ParseError> {
    let mode = if PARSE_IN_STRICT_MODE {
        ParseMode::Strict
    } else {
        ParseMode::Lenient  // 默认使用宽松模式
    };
    parse_patch_text(patch, mode)
}
```

解析器使用 Rust 原生的 `String` 类型（UTF-8 编码）存储所有文本内容，天然支持 Unicode。

#### 2. 文件更新流程

```
input/foo.txt → lib.rs::derive_new_contents_from_chunks() → 
seek_sequence::seek_sequence() (匹配) → 
apply_replacements() → 写入临时目录
```

**关键代码路径** (`codex-rs/apply-patch/src/lib.rs:348-381`):
```rust
fn derive_new_contents_from_chunks(
    path: &Path,
    chunks: &[UpdateFileChunk],
) -> std::result::Result<AppliedPatch, ApplyPatchError> {
    let original_contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,  // String 类型，UTF-8 编码
        Err(err) => { ... }
    };

    let mut original_lines: Vec<String> = original_contents.split('\n').map(String::from).collect();
    // ... 行处理逻辑
}
```

#### 3. 行匹配算法

**关键代码路径** (`codex-rs/apply-patch/src/seek_sequence.rs:12-110`):

`seek_sequence` 函数实现了多层级匹配策略：

1. **精确匹配**: 字节级完全匹配
2. **尾部空白忽略**: `trim_end()` 比较
3. **全空白忽略**: `trim()` 比较
4. **Unicode 归一化匹配**: 将排版标点符号映射为 ASCII 等价物

```rust
fn normalise(s: &str) -> String {
    s.trim()
        .chars()
        .map(|c| match c {
            // 各种连字符/破折号码点 → ASCII '-'
            '\u{2010}' | '\u{2011}' | '\u{2012}' | '\u{2013}' | '\u{2014}' | '\u{2015}'
            | '\u{2212}' => '-',
            // 花式单引号 → '\''
            '\u{2018}' | '\u{2019}' | '\u{201A}' | '\u{201B}' => '\'',
            // 花式双引号 → '"'
            '\u{201C}' | '\u{201D}' | '\u{201E}' | '\u{201F}' => '"',
            // 不间断空格和其他特殊空格 → 普通空格
            '\u{00A0}' | '\u{2002}' | ... | '\u{3000}' => ' ',
            other => other,
        })
        .collect::<String>()
}
```

在本场景中，由于 patch 和源文件都使用相同的 Unicode 字符（`naïve café`），匹配会在第一层**精确匹配**阶段成功。

### 数据结构

#### Patch 解析结果 (`parser.rs:58-76`)

```rust
#[derive(Debug, PartialEq, Clone)]
pub enum Hunk {
    AddFile {
        path: PathBuf,
        contents: String,  // UTF-8 编码
    },
    DeleteFile {
        path: PathBuf,
    },
    UpdateFile {
        path: PathBuf,
        move_path: Option<PathBuf>,
        chunks: Vec<UpdateFileChunk>,
    },
}

#[derive(Debug, PartialEq, Clone)]
pub struct UpdateFileChunk {
    pub change_context: Option<String>,
    pub old_lines: Vec<String>,  // 包含 Unicode 的行
    pub new_lines: Vec<String>,  // 包含 Unicode 的行
    pub is_end_of_file: bool,
}
```

#### 文件变更类型 (`lib.rs:94-108`)

```rust
pub enum ApplyPatchFileChange {
    Add {
        content: String,  // UTF-8
    },
    Delete {
        content: String,  // UTF-8
    },
    Update {
        unified_diff: String,
        move_path: Option<PathBuf>,
        new_content: String,  // UTF-8
    },
}
```

### 测试执行机制

**测试入口** (`codex-rs/apply-patch/tests/suite/scenarios.rs:11-26`):

```rust
#[test]
fn test_apply_patch_scenarios() -> anyhow::Result<()> {
    let scenarios_dir = repo_root()?
        .join("codex-rs")
        .join("apply-patch")
        .join("tests")
        .join("fixtures")
        .join("scenarios");
    for scenario in fs::read_dir(scenarios_dir)? {
        let scenario = scenario?;
        let path = scenario.path();
        if path.is_dir() {
            run_apply_patch_scenario(&path)?;  // 遍历所有场景目录
        }
    }
    Ok(())
}
```

**场景执行逻辑** (`scenarios.rs:30-63`):

```rust
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;

    // 1. 复制 input 文件到临时目录
    let input_dir = dir.join("input");
    if input_dir.is_dir() {
        copy_dir_recursive(&input_dir, tmp.path())?;
    }

    // 2. 读取 patch.txt
    let patch = fs::read_to_string(dir.join("patch.txt"))?;

    // 3. 执行 apply_patch 命令
    Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;

    // 4. 比较结果与 expected 目录
    let expected_dir = dir.join("expected");
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;

    assert_eq!(actual_snapshot, expected_snapshot, ...);
    Ok(())
}
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 | 与本场景的关联 |
|-----|------|--------------|
| `codex-rs/apply-patch/src/parser.rs` | Patch 格式解析 | 解析包含 Unicode 的 patch 文本 |
| `codex-rs/apply-patch/src/lib.rs` | Patch 应用核心逻辑 | 文件读写、内容替换 |
| `codex-rs/apply-patch/src/seek_sequence.rs` | 行序列匹配 | 定位需要替换的行 |
| `codex-rs/apply-patch/src/standalone_executable.rs` | CLI 入口 | 处理 UTF-8 参数 |

### 关键函数调用链

```
测试执行:
  tests/suite/scenarios.rs::test_apply_patch_scenarios()
    └── run_apply_patch_scenario(&path)
          └── Command::new("apply_patch").arg(patch).output()

apply_patch 二进制:
  src/main.rs::main()
    └── src/standalone_executable.rs::run_main()
          └── src/lib.rs::apply_patch(&patch_arg, ...)
                └── src/parser.rs::parse_patch(patch)
                      └── parse_patch_text(patch, mode)
                └── apply_hunks(&hunks, ...)
                      └── apply_hunks_to_files(hunks)
                            └── derive_new_contents_from_chunks(path, chunks)
                                  └── seek_sequence::seek_sequence(...)  // 匹配行
                                  └── apply_replacements(...)            // 应用替换
```

### 相关测试代码

**Unicode 标点归一化测试** (`lib.rs:797-834`):

```rust
#[test]
fn test_update_line_with_unicode_dash() {
    // 原始行包含 EN DASH (\u{2013}) 和 NON-BREAKING HYPHEN (\u{2011})
    let original = "import asyncio  # local import \u{2013} avoids top\u{2011}level dep\n";
    
    // Patch 使用普通 ASCII 连字符
    let patch = wrap_patch(&format!(r#"...-import asyncio  # local import - avoids top-level dep...+import asyncio  # HELLO"#));
    
    // 验证模糊匹配成功
    apply_patch(&patch, &mut stdout, &mut stderr).unwrap();
}
```

该测试与本场景形成互补：
- `test_update_line_with_unicode_dash`: 测试 **ASCII patch → Unicode 文件** 的模糊匹配
- `019_unicode_simple`: 测试 **Unicode patch → Unicode 文件** 的精确处理

---

## 依赖与外部交互

### 外部依赖

| Crate | 用途 | 版本来源 |
|-------|------|---------|
| `anyhow` | 错误处理 | workspace |
| `similar` | 统一差异计算 | workspace |
| `thiserror` | 错误类型定义 | workspace |
| `tree-sitter` | Bash 脚本解析（用于 heredoc 提取） | workspace |
| `tree-sitter-bash` | Bash 语法支持 | workspace |

### 系统依赖

- **文件系统**: 使用标准库 `std::fs` 进行文件操作，依赖操作系统的 UTF-8 文件路径支持
- **编码**: 完全依赖 Rust `String` 类型的 UTF-8 编码，不处理其他编码（如 GBK、Latin-1）

### 与上游组件的交互

`apply-patch` 作为底层工具，被以下组件调用：

1. **codex-cli**: 通过 `apply_patch` shell 命令调用
2. **codex-core**: 通过 `invocation.rs` 中的 `maybe_parse_apply_patch_verified()` 函数库调用
3. **测试框架**: 通过 `cargo test` 执行集成测试

### 调用协议

**命令行接口** (`standalone_executable.rs:11-47`):

```rust
pub fn run_main() -> i32 {
    // 期望一个参数（patch 内容）或从 stdin 读取
    let mut args = std::env::args_os();
    let _argv0 = args.next();

    let patch_arg = match args.next() {
        Some(arg) => match arg.into_string() {
            Ok(s) => s,  // 必须有效的 UTF-8
            Err(_) => {
                eprintln!("Error: apply_patch requires a UTF-8 PATCH argument.");
                return 1;
            }
        },
        None => {
            // 从 stdin 读取
            let mut buf = String::new();
            std::io::stdin().read_to_string(&mut buf)?
            ...
        }
    };
    ...
}
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 编码假设风险

**风险**: 系统假设所有输入文件均为 UTF-8 编码。如果源文件使用其他编码（如 GBK、Shift-JIS），会导致：
- `std::fs::read_to_string()` 返回 `InvalidData` 错误
- Patch 应用失败

**缓解措施**: 
- 当前无自动编码检测
- 错误信息会提示 I/O 错误，但不会明确说明是编码问题

#### 2. 行尾符处理

**风险**: 当前实现使用 `'\n'` 作为行分隔符 (`lib.rs:362`)，在 Windows 平台（CRLF 行尾）可能导致：
- 行内容包含尾部 `\r`
- 匹配失败（如果 patch 使用 LF 而文件使用 CRLF）

**相关代码** (`lib.rs:362`):
```rust
let mut original_lines: Vec<String> = original_contents.split('\n').map(String::from).collect();
```

### 边界情况

| 边界情况 | 当前行为 | 建议 |
|---------|---------|------|
| 文件包含无效 UTF-8 序列 | 返回 I/O 错误 | 可考虑添加编码转换选项 |
| Emoji 位于行尾 | 正常处理 | 已覆盖（本场景） |
| 组合字符（如 `e` + `́` vs `é`） | 字节级比较，可能不匹配 | 可考虑 NFC/NFD 归一化 |
| 零宽字符（如零宽空格 U+200B） | 正常处理，但不可见 | 文档说明 |
| 从右到左文本（如阿拉伯语、希伯来语） | 未明确测试 | 添加测试场景 |

### 改进建议

#### 1. 编码检测与转换

```rust
// 建议添加编码检测
fn read_file_with_encoding_detection(path: &Path) -> Result<String, ...> {
    let bytes = std::fs::read(path)?;
    
    // 尝试 UTF-8
    if let Ok(s) = String::from_utf8(bytes.clone()) {
        return Ok(s);
    }
    
    // 尝试其他编码（如 GBK）
    // ...
}
```

#### 2. 行尾符规范化

```rust
// 建议：读取时统一将 CRLF 转换为 LF
let contents = std::fs::read_to_string(path)?
    .replace("\r\n", "\n");  // 规范化行尾符
```

#### 3. Unicode 归一化（NFC/NFD）

对于组合字符场景，建议在匹配前进行 Unicode 归一化：

```rust
use unicode_normalization::UnicodeNormalization;

fn normalize_for_comparison(s: &str) -> String {
    s.nfc().collect()  // 或 nfd()
}
```

例如：`"café"` (U+0065 U+0301) 和 `"café"` (U+00E9) 在归一化后应视为相等。

#### 4. 增强测试覆盖

建议添加以下测试场景：

| 场景 | 描述 |
|-----|------|
| `023_unicode_cjk` | 中日韩统一表意文字（如 `你好世界`） |
| `024_unicode_rtl` | 从右到左文本（如 `مرحبا`） |
| `025_unicode_combining` | 组合字符序列 |
| `026_unicode_mixed_encoding` | 混合编码文件的处理 |

#### 5. 文档改进

在 `apply_patch_tool_instructions.md` 中明确说明：
- 所有文件必须使用 UTF-8 编码
- 行尾符使用 Unix 风格（LF）
- Emoji 和特殊 Unicode 字符完全支持

### 性能考量

当前 `seek_sequence` 的 Unicode 归一化匹配是**惰性执行**的（仅在前面三层匹配失败后执行），这在性能上是合理的。但对于大型文件（>10MB），逐字符归一化可能成为瓶颈。

**优化建议**:
```rust
// 当前：逐行归一化
if normalise(&lines[i + p_idx]) != normalise(pat) { ... }

// 优化：缓存归一化结果
let normalized_lines: Vec<String> = lines.iter().map(normalise).collect();
```

---

## 总结

`019_unicode_simple` 场景是 `apply-patch` 组件 Unicode 支持的基础测试用例，验证了系统能够正确处理包含多字节 Unicode 字符（拉丁字母扩展、Emoji）的文件内容。该场景与 `seek_sequence.rs` 中的 Unicode 标点归一化功能共同构成了完整的 Unicode 支持体系。

关键要点：
1. **编码**: 完全基于 UTF-8，依赖 Rust `String` 类型
2. **匹配**: 支持精确匹配和模糊匹配（Unicode 标点归一化）
3. **测试**: 通过集成测试框架自动执行，验证端到端功能
4. **风险**: 非 UTF-8 编码文件将导致错误，需用户确保编码一致性
