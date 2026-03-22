# scenarios.rs 研究文档

## 场景与职责

`scenarios.rs` 是 `codex-apply-patch` crate 的综合场景测试模块，采用基于 fixture 目录的测试策略。该模块自动发现并执行 `tests/fixtures/scenarios/` 目录下的所有测试场景，通过对比实际输出与预期输出来验证 patch 应用的正确性。

### 文件位置
- **源文件**: `codex-rs/apply-patch/tests/suite/scenarios.rs`
- **所属 crate**: `codex-apply-patch`
- **测试类型**: 集成测试（基于文件系统的端到端测试）

### 设计哲学
该测试模块采用**数据驱动测试**（Data-Driven Testing）方法：
- 测试用例以目录结构形式组织，易于添加新场景
- 不依赖退出码判断成功/失败，而是比较最终文件系统状态
- 支持复杂多文件操作和边界条件测试

---

## 功能点目的

### 1. 自动化场景发现
通过遍历 `fixtures/scenarios/` 目录自动发现所有测试场景，无需修改代码即可添加新测试。

### 2. 文件系统状态快照比较
使用 `BTreeMap<PathBuf, Entry>` 对目录状态进行完整快照，精确比较预期与实际状态。

### 3. 跨构建系统兼容
特别处理 Buck2 构建系统的符号链接树（symlink trees），确保测试在 Cargo 和 Buck2 下都能通过。

---

## 具体技术实现

### 核心数据结构

#### Entry 枚举
```rust
#[derive(Debug, Clone, PartialEq, Eq)]
enum Entry {
    File(Vec<u8>),  // 文件内容（字节数组，支持二进制）
    Dir,            // 目录标记
}
```

#### AffectedPaths 结构（来自 lib.rs）
```rust
pub struct AffectedPaths {
    pub added: Vec<PathBuf>,
    pub modified: Vec<PathBuf>,
    pub deleted: Vec<PathBuf>,
}
```

### 关键流程

#### 1. 测试发现与执行流程
```
test_apply_patch_scenarios()
    ↓
遍历 fixtures/scenarios/ 目录
    ↓
对每个子目录调用 run_apply_patch_scenario()
    ↓
    1. 创建临时目录 (tempdir())
    2. 复制 input/ 到临时目录
    3. 读取 patch.txt
    4. 执行 apply_patch 二进制
    5. 快照对比 expected/ vs 临时目录
```

#### 2. 目录快照算法
```rust
fn snapshot_dir(root: &Path) -> anyhow::Result<BTreeMap<PathBuf, Entry>> {
    // 使用 BTreeMap 保证遍历顺序确定性
    // 递归遍历目录，处理文件和子目录
    // 关键：使用 fs::metadata() 而非 fs::symlink_metadata()
    // 以跟随 Buck2 的符号链接
}
```

#### 3. 目录复制算法
```rust
fn copy_dir_recursive(src: &Path, dst: &Path) -> anyhow::Result<()> {
    // 同样使用 fs::metadata() 跟随符号链接
    // 自动创建父目录
}
```

### Fixture 目录结构规范

```
fixtures/scenarios/{scenario_name}/
├── input/           # 初始文件状态（可选）
│   └── ...
├── patch.txt        # patch 内容（必需）
└── expected/        # 预期最终状态（必需）
    └── ...
```

### 现有测试场景（22个）

| 编号 | 场景名称 | 测试目的 |
|------|----------|----------|
| 001 | add_file | 基础文件创建 |
| 002 | multiple_operations | 多操作组合（增删改） |
| 003 | multiple_chunks | 单文件多 chunk 更新 |
| 004 | move_to_new_directory | 文件移动到新目录 |
| 005 | rejects_empty_patch | 拒绝空 patch |
| 006 | rejects_missing_context | 拒绝上下文不匹配 |
| 007 | rejects_missing_file_delete | 删除不存在文件失败 |
| 008 | rejects_empty_update_hunk | 拒绝空 update hunk |
| 009 | requires_existing_file_for_update | 更新必须目标存在 |
| 010 | move_overwrites_existing_destination | 移动覆盖目标 |
| 011 | add_overwrites_existing_file | 添加覆盖已存在文件 |
| 012 | delete_directory_fails | 删除目录失败 |
| 013 | rejects_invalid_hunk_header | 拒绝无效 hunk 头 |
| 014 | update_file_appends_trailing_newline | 自动添加末尾换行 |
| 015 | failure_after_partial_success_leaves_changes | 部分失败保留已应用变更 |
| 016 | pure_addition_update_chunk | 纯添加 chunk |
| 017 | whitespace_padded_hunk_header | 容忍 hunk 头空白 |
| 018 | whitespace_padded_patch_markers | 容忍 patch 标记空白 |
| 019 | unicode_simple | Unicode 内容处理 |
| 020 | delete_file_success | 成功删除文件 |
| 020 | whitespace_padded_patch_marker_lines | 行级标记空白容忍 |
| 021 | update_file_deletion_only | 仅删除行更新 |
| 022 | update_file_end_of_file_marker | EOF 标记处理 |

---

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `codex_utils_cargo_bin::repo_root` | 定位仓库根目录以解析 fixture 路径 |
| `pretty_assertions::assert_eq` | 提供差异可视化的断言失败信息 |
| `tempfile::tempdir` | 创建隔离的临时测试目录 |
| `std::process::Command` | 执行 apply_patch 二进制 |
| `std::collections::BTreeMap` | 有序的目录快照存储 |

### 被测组件
- **二进制**: `apply_patch`（通过 `codex_utils_cargo_bin::cargo_bin` 定位）
- **核心库**: `codex_apply_patch::apply_patch()`

---

## 关键代码路径与文件引用

### 调用链
```
scenarios.rs
    ↓ (调用)
codex_utils_cargo_bin::cargo_bin("apply_patch")
    ↓ (执行)
apply_patch 二进制
    ↓ (内部调用)
lib::apply_patch() / lib::apply_hunks()
```

### 相关文件
| 文件 | 职责 |
|------|------|
| `src/lib.rs` | Patch 应用核心逻辑 |
| `src/parser.rs` | Patch 格式解析 |
| `src/seek_sequence.rs` | 上下文匹配算法 |
| `tests/fixtures/scenarios/` | 测试数据目录 |
| `tests/fixtures/scenarios/README.md` | Fixture 规范文档 |

---

## 风险、边界与改进建议

### 当前风险与边界

1. **退出码忽略**
   ```rust
   // 故意不断言退出状态
   Command::new(...).arg(patch).current_dir(tmp.path()).output()?;
   ```
   - 即使 patch 应用失败，只要文件状态与 expected/ 匹配即通过
   - 可能掩盖错误处理路径的问题

2. **二进制依赖**
   - 测试依赖预编译的 `apply_patch` 二进制
   - 在 CI 中需要确保二进制先于测试构建

3. **Buck2 符号链接处理**
   ```rust
   // 使用 metadata() 跟随符号链接
   let metadata = fs::metadata(&path)?;
   ```
   - 注释说明这是为了 Buck2 兼容
   - 如果 Buck2 行为变更，测试可能失效

4. **测试隔离性**
   - 所有场景共享同一个二进制执行
   - 如果二进制崩溃，后续场景无法执行

### 改进建议

1. **添加退出码验证选项**
   ```rust
   // 可在 fixture 中添加 exit_code 文件
   fixtures/scenarios/{name}/
   ├── input/
   ├── patch.txt
   ├── expected/
   └── exit_code  # 可选，指定预期退出码
   ```

2. **增强错误诊断**
   ```rust
   // 当前仅比较 snapshot，失败时难以定位差异
   // 建议添加详细差异报告
   if actual_snapshot != expected_snapshot {
       print_diff(&actual_snapshot, &expected_snapshot);
   }
   ```

3. **并行执行优化**
   ```rust
   // 当前串行执行，可使用 rayon 并行化
   use rayon::prelude::*;
   scenarios.par_iter().for_each(|s| run_scenario(s));
   ```

4. **添加性能基准**
   - 记录每个场景的执行时间
   - 检测性能回归

5. **Fixture 验证**
   ```rust
   // 添加测试前验证 fixture 结构完整性
   fn validate_fixture(dir: &Path) -> Result<(), FixtureError> {
       // 确保 patch.txt 存在
       // 确保 expected/ 非空或明确标记为错误场景
   }
   ```

### 与 cli.rs、tool.rs 的关系

| 模块 | 测试策略 | 覆盖范围 |
|------|----------|----------|
| `cli.rs` | 代码内联测试 | CLI 接口基本功能 |
| `scenarios.rs` | 数据驱动测试 | 综合场景、边界条件 |
| `tool.rs` | 代码内联测试 | 高级工具功能（Unix 特有） |

三者形成分层测试金字塔：
- **cli.rs**: 快速反馈的基础功能测试
- **scenarios.rs**: 全面的场景覆盖（当前 22 个场景）
- **tool.rs**: 平台特定的深度功能测试
