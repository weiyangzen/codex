# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`004_move_to_new_directory` 是 `apply_patch` fixture 场景中“更新并迁移文件到新目录”的基线用例。它验证的不是单纯 `rename`，而是一次 `Update File` 操作同时包含：

1. 内容变更：`old content -> new content`。
2. 路径迁移：`old/name.txt -> renamed/dir/name.txt`。
3. 目录自动创建：目标目录 `renamed/dir` 初始不存在，但执行后必须存在。
4. 非目标文件不受影响：`old/other.txt` 在输入与期望中内容一致。

该目录自身由三类文件构成并分别承担规范职责：

1. `patch.txt`：声明协议级输入（`*** Update File` + `*** Move to` + hunk）。
2. `input/`：声明运行前文件系统初始状态。
3. `expected/`：声明运行后最终文件树状态。

它在测试体系中的定位是“数据驱动的语义契约样例”，由目录回放器统一执行，而不是单独写死在 Rust 测试代码里。

## 功能点目的

该场景用于锁定 `apply_patch` 的以下关键行为：

1. `*** Move to:` 对 `Update File` 有效，且与文本替换共同生效，而不是先 move 再独立编辑。
2. 迁移目标父目录缺失时，执行器会自动 `create_dir_all`，无需调用方预建目录。
3. 源文件在成功写入目标后被删除，最终只保留新路径文件。
4. 目录内其他无关文件保持不变，确保操作作用域准确。

和相邻场景的关系：

1. `004_move_to_new_directory` 覆盖“目标目录不存在”的创建路径。
2. `010_move_overwrites_existing_destination` 覆盖“目标已存在文件”的覆盖路径。
3. 两者共享 `*** Move to` 协议，但边界条件不同，共同构成 move 行为最小覆盖面。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 端到端执行流程

1. `tests/suite/scenarios.rs` 的 `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`，发现 `004_move_to_new_directory` 后调用 `run_apply_patch_scenario()`。
2. `run_apply_patch_scenario()` 将 `input/` 复制到临时目录。
3. 读取 `patch.txt` 文本后启动 `apply_patch` 二进制：
   `apply_patch "<完整 patch 文本>"`。
4. 执行完后对比 `expected/` 与临时目录快照（`BTreeMap<PathBuf, Entry>`）。
5. 若任意目录结构或文件字节内容不同，则该场景失败。

### 2) 协议与解析

本场景 patch 内容：

```patch
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-old content
+new content
*** End Patch
```

解析层行为（`src/parser.rs`）：

1. 命中 `Hunk::UpdateFile { path, move_path, chunks }`。
2. 识别可选 `*** Move to: ...` 行并填充 `move_path: Some(PathBuf)`。
3. 将 `@@` 后的 `-`/`+` 行转为一个 `UpdateFileChunk`。

### 3) 执行器内部数据结构与写盘逻辑

核心结构：

1. `Hunk::UpdateFile { path, move_path, chunks }`：表达“更新+可选迁移”。
2. `AppliedPatch { original_contents, new_contents }`：表达文本替换前后结果。
3. `AffectedPaths { added, modified, deleted }`：汇总输出用途。

关键逻辑（`src/lib.rs`）：

1. `derive_new_contents_from_chunks(path, chunks)` 先从源路径读旧文件并计算 `new_contents`。
2. 若 `move_path` 存在：
   - `create_dir_all(dest.parent())`（父目录缺失时自动创建）。
   - `write(dest, new_contents)`。
   - `remove_file(path)` 删除源文件。
   - 记录 `modified.push(dest)`。
3. 若 `move_path` 不存在，则原地 `write(path, new_contents)`。

这说明 `Move to` 在实现上是“写新路径 + 删除旧路径”的组合，而不是 OS 级 `rename` 调用，因此天然允许覆盖已有目标文件（由写入语义决定）。

### 4) 上下游调用链（调用方/被调用方）

调用方：

1. `tests/all.rs -> tests/suite/mod.rs -> tests/suite/scenarios.rs`（fixture 回放入口）。
2. `core` 工具层可通过 `codex_apply_patch::maybe_parse_apply_patch_verified()` 在执行前做 patch 结构验证与变更提取（`core/src/tools/handlers/apply_patch.rs`）。

被调用方：

1. `src/standalone_executable.rs::run_main()`：处理 argv/stdin 后进入 `crate::apply_patch()`。
2. `src/lib.rs::apply_patch()`：调用 `parse_patch()` 并执行 `apply_hunks()`。
3. `src/lib.rs::apply_hunks_to_files()`：真正文件系统操作（写入、删源、建目录）。
4. `src/parser.rs`：`Move to` 与 hunk 解析。

跨 crate 执行通道：

1. `arg0` 通过 `CODEX_CORE_APPLY_PATCH_ARG1` 可分发到 `codex_apply_patch::apply_patch`。
2. `core` runtime 通过当前可执行文件自调用并传入 `--codex-run-as-apply-patch`，实现统一运行时管道。

### 5) 关键命令

1. 场景回放（目录驱动）：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. CLI 等价验证（代码驱动）：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_moves_file_to_new_directory`
3. 研究流程命令（本任务要求）：`bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 场景本体

1. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/patch.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/name.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/other.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed/dir/name.txt`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/old/other.txt`

### B. 直接调用方（消费 fixture）

1. `codex-rs/apply-patch/tests/all.rs`
2. `codex-rs/apply-patch/tests/suite/mod.rs`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs`

### C. 同语义对照测试

1. `codex-rs/apply-patch/tests/suite/tool.rs`（`test_apply_patch_cli_moves_file_to_new_directory`）
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/*`

### D. 被调用实现

1. `codex-rs/apply-patch/src/standalone_executable.rs`
2. `codex-rs/apply-patch/src/lib.rs`
3. `codex-rs/apply-patch/src/parser.rs`
4. `codex-rs/apply-patch/src/seek_sequence.rs`
5. `codex-rs/apply-patch/apply_patch_tool_instructions.md`

### E. 上下文依赖（跨 crate）

1. `codex-rs/core/src/tools/handlers/apply_patch.rs`
2. `codex-rs/core/src/tools/runtimes/apply_patch.rs`
3. `codex-rs/arg0/src/lib.rs`
4. `codex-rs/apply-patch/Cargo.toml`
5. `codex-rs/apply-patch/BUILD.bazel`

## 依赖与外部交互

### 1) 依赖

`codex-apply-patch` 关键依赖：

1. `anyhow` / `thiserror`：错误建模与上下文包装。
2. `similar`：生成 unified diff（用于变更校验与上游展示）。
3. `tree-sitter` / `tree-sitter-bash`：`invocation` 中 bash heredoc 解析。
4. 测试依赖 `assert_cmd` / `tempfile` / `pretty_assertions` / `codex-utils-cargo-bin`。

### 2) 外部交互面

1. 文件系统：读取/写入/删除文件，创建新目录。
2. 子进程：fixture 测试启动 `apply_patch` 可执行文件。
3. 标准流：成功输出 `Success. Updated...`，失败输出具体错误文本。
4. 路径解析：在 `core` 集成路径中，`move_path` 会按 `effective_cwd` 解析为绝对路径后参与审批和执行。

### 3) 文档与脚本交互

1. 场景规范文档：`tests/fixtures/scenarios/README.md`。
2. 协议说明：`apply_patch_tool_instructions.md`。
3. 研究流水线脚本：`.ops/generate_daily_research_todo.sh` 基于 checklist 生成当日待办快照。

## 风险、边界与改进建议

### 风险与边界

1. 非原子性：实现按顺序写入和删除，若中途失败可能留下部分已应用结果（仓库内已有 `015_failure_after_partial_success_leaves_changes` 佐证这一行为）。
2. move 采用“写目标+删源”语义而非 `rename`，在跨设备场景可工作，但也意味着目标已存在时默认覆盖，调用方需知晓该策略。
3. 场景 004 仅覆盖目标目录缺失路径，未覆盖权限受限目录、只读文件、并发写入等 I/O 边界。
4. fixture 回放只比较最终文件树，不校验 stdout/stderr 与退出码；输出协议回归需依赖 `tool.rs/cli.rs` 补充覆盖。

### 改进建议

1. 在场景层补充 `move_to_readonly_directory_fails` 与 `move_source_missing_after_partial_write`，提高异常路径覆盖。
2. 给 `scenarios.rs` 增加可选元数据断言能力（例如 `expected_exit_code`、`stderr_contains`），保持数据驱动同时补足行为可观测性。
3. 在 `apply_patch_tool_instructions.md` 明确 `Move to` 覆盖目标文件的语义，减少调用方误判。
4. 对 `004` 增加一个 sibling fixture：同样迁移到新目录，但包含多 chunk 更新，验证“多块替换+目录创建+迁移”组合路径。
