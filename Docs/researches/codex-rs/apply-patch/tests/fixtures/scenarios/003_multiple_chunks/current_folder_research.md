# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`003_multiple_chunks` 是 `apply_patch` 场景集中用于验证“单个 `Update File` hunk 内包含多个 chunk”语义的最小样例。它验证的是同一文件在一次 patch 中跨位置多次替换，而不是多文件或多操作混合。

目录职责拆分：

1. `patch.txt` 定义协议输入：一个 `Update File: multi.txt`，包含两个 `@@` chunk，分别替换 `line2` 与 `line4`（`codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/patch.txt:1-9`）。
2. `input/multi.txt` 定义初始状态（`.../input/multi.txt:1-4`）。
3. `expected/multi.txt` 定义期望终态（`.../expected/multi.txt:1-4`）。

该目录在整体测试链路中的定位：

1. 由目录回放器 `test_apply_patch_scenarios()` 自动发现并执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-23`）。
2. 验证标准是“最终文件树快照一致”，而非命令输出文本（`.../scenarios.rs:42-60`）。
3. 与 `tests/suite/tool.rs` 中同语义用例互补：`tool.rs` 额外断言 stdout，fixture 场景强调数据化可移植规范（`codex-rs/apply-patch/tests/suite/tool.rs:45-61`，`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:2-7`）。

## 功能点目的

`003_multiple_chunks` 直接服务于以下目标：

1. 验证 parser 能将同一 `Update File` 块解析为多个 `UpdateFileChunk`，并按顺序保留（`codex-rs/apply-patch/src/parser.rs:279-333`，`343-434`）。
2. 验证执行器对多 chunk 的替换计划能顺序定位、统一应用，不会因为前一个替换导致后一个 chunk 定位偏移（`codex-rs/apply-patch/src/lib.rs:386-474`，`478-501`）。
3. 验证一次 `Update File` 即使含多个 chunk，最终汇总仍应只记一条 `M <path>`（由单 hunk 触发一次 modified push，`codex-rs/apply-patch/src/lib.rs:306-330`，`537-551`）。
4. 固化与单元测试一致的行为基线，防止未来重构回归：
- `test_multiple_update_chunks_apply_to_single_file`（`codex-rs/apply-patch/src/lib.rs:674-710`）
- `test_apply_patch_cli_applies_multiple_chunks`（`codex-rs/apply-patch/tests/suite/tool.rs:45-61`）

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景回放关键流程

1. 集成测试入口 `tests/all.rs -> suite/mod.rs -> scenarios.rs`（`codex-rs/apply-patch/tests/all.rs:1-3`，`codex-rs/apply-patch/tests/suite/mod.rs:1-4`）。
2. `run_apply_patch_scenario()` 将 `input/` 复制到 `tempdir`，读取 `patch.txt`，执行 `apply_patch <patch>`（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-48`）。
3. 使用 `snapshot_dir()` 构建 `BTreeMap<PathBuf, Entry>`，对比 `expected` 与实际目录（`.../scenarios.rs:50-77`）。
4. 快照层按字节比较文件内容（`Entry::File(Vec<u8>)`），并跟随 symlink 兼容 Buck2（`.../scenarios.rs:65-69`，`92-101`）。

### 2) 数据结构与算法落点

1. Patch 解析产物
- `Hunk::UpdateFile { path, move_path, chunks }`（`codex-rs/apply-patch/src/parser.rs:68-75`）。
- `UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`（`.../parser.rs:91-104`）。

2. 场景 `003` 的 chunk 语义
- chunk1：`-line2 +changed2`
- chunk2：`-line4 +changed4`
- 均无显式上下文行（`@@` 空 header），不设置 `change_context`（`patch.txt:3-8`，`parser.rs:356-370`）。

3. 替换定位与应用算法
- `derive_new_contents_from_chunks()` 先把原文件切成行向量并去除末尾空切片（`codex-rs/apply-patch/src/lib.rs:348-368`）。
- `compute_replacements()` 逐 chunk 从 `line_index` 开始查找 `old_lines`，命中后更新 `line_index` 到替换段后方（`.../lib.rs:391-462`）。
- `apply_replacements()` 按倒序应用替换，避免前序替换改变后序索引（`.../lib.rs:482-501`）。

以本场景为例，逻辑上会得到：

1. `line2` 匹配索引 1，记录替换 `(1, 1, ["changed2"])`。
2. `line_index` 前移到 2 后继续搜索，`line4` 匹配索引 3，记录 `(3, 1, ["changed4"])`。
3. 倒序替换后得到 `line1/changed2/line3/changed4`，与 `expected` 对齐。

### 3) 协议与命令

1. patch 外层协议：`*** Begin Patch` / `*** End Patch`（`patch.txt:1,9`）。
2. 文件操作协议：`*** Update File: <path>`（`patch.txt:2`）。
3. 多 chunk 协议：重复 `@@` 分段，每段由 `-`/`+`/` ` 行组成（`patch.txt:3-8`，`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`）。
4. 测试内执行命令：`apply_patch "<完整patch文本>"`（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
5. CLI 入口支持参数或 stdin 两种输入（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。

## 关键代码路径与文件引用

### A. 目标目录（本体）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/patch.txt:1-9`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/input/multi.txt:1-4`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/expected/multi.txt:1-4`

### B. 直接调用方（消费该场景目录）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-23`（扫描目录）
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`（单场景执行）
3. `codex-rs/apply-patch/tests/all.rs:1-3`（integration test 聚合入口）

### C. 被调用方（场景执行触发的实现）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`（CLI 入参/退出码）
2. `codex-rs/apply-patch/src/lib.rs:183-213`（`apply_patch` 入口）
3. `codex-rs/apply-patch/src/lib.rs:279-339`（hunk 执行与写盘）
4. `codex-rs/apply-patch/src/lib.rs:386-474`（多 chunk replacement 计算）
5. `codex-rs/apply-patch/src/parser.rs:279-333`（`Update File` hunk 解析）
6. `codex-rs/apply-patch/src/parser.rs:343-434`（单 chunk 解析）
7. `codex-rs/apply-patch/src/seek_sequence.rs:12-110`（序列匹配策略）

### D. 并行/上游关联路径（上下文依赖）

1. `codex-rs/apply-patch/tests/suite/tool.rs:45-61`（同语义 CLI 断言）
2. `codex-rs/apply-patch/src/lib.rs:674-710`（同语义单元测试）
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-258`（core 工具层复用 `maybe_parse_apply_patch_verified`）
4. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`（runtime 组装 `--codex-run-as-apply-patch`）
5. `codex-rs/arg0/src/lib.rs:85-107`（arg0 分发到 `codex_apply_patch::apply_patch`）

### E. 配置、构建、文档、脚本

1. `codex-rs/apply-patch/Cargo.toml:1-30`（crate/bin 与依赖）
2. `codex-rs/apply-patch/BUILD.bazel:1-11`（Bazel 打包 `apply_patch_tool_instructions.md`）
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`（协议文档）
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`（fixture 结构约定）
5. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`（LF 约束）
6. `.ops/generate_daily_research_todo.sh:1-42`（todo 生成脚本）

## 依赖与外部交互

### 1) 依赖

1. 运行时依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`.../Cargo.toml:25-30`）。
3. `codex-utils-cargo-bin::repo_root` 与 `cargo_bin` 解决 Cargo/Bazel 下路径定位（`codex-rs/utils/cargo-bin/src/lib.rs:168-202`）。

### 2) 外部交互面

1. 文件系统：读取 `patch.txt`、复制 `input/`、写回目标文件、读取 `expected/` 对比（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-53`，`codex-rs/apply-patch/src/lib.rs:297-329`）。
2. 子进程：每个场景都会调用一次 `apply_patch` 可执行文件（`.../scenarios.rs:45-48`）。
3. 标准输出/错误输出：成功时输出 `A/M/D` 汇总，失败时输出解析或匹配错误文本（`codex-rs/apply-patch/src/lib.rs:191-205`，`247-265`，`537-551`）。

### 3) 与上游系统的交互

1. 在 `core` 层，`apply_patch` 先走“解析验证 + 审批”，再由 runtime 真正执行（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-239`，`codex-rs/core/src/tools/runtimes/apply_patch.rs:188-215`）。
2. 通过 `CODEX_CORE_APPLY_PATCH_ARG1` 实现同一二进制内的 apply_patch 子路径调用（`codex-rs/core/src/tools/runtimes/apply_patch.rs:91-93`，`codex-rs/arg0/src/lib.rs:90-107`）。

## 风险、边界与改进建议

### 风险与边界

1. 场景过于“理想化”：仅覆盖无上下文、无重复行歧义的双替换；未覆盖 repeated lines 下 chunk 锚定冲突。
2. `scenarios.rs` 不断言 exit status/stdout/stderr，只看最终目录快照；若输出协议回归但文件状态正确，可能漏报（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。
3. 遍历场景使用 `fs::read_dir` 原序，失败输出顺序在不同文件系统上可能不稳定（`.../scenarios.rs:18`）。
4. 本场景不验证事务语义；实际实现按 hunk 顺序落盘，后续失败不会回滚前序成功更改（`codex-rs/apply-patch/src/lib.rs:287-333`，对应场景 `015_failure_after_partial_success_leaves_changes`）。

### 改进建议

1. 为 `003_multiple_chunks` 增加“重复旧行歧义”变体：例如两个 chunk 都要替换同一文本值，验证 `line_index` 递进策略不会命中前文段。
2. 增加“chunk 含 context + chunk 无 context 混合”变体，覆盖 `change_context` 与 `seek_sequence` 联动分支（`codex-rs/apply-patch/src/lib.rs:397-412`）。
3. 在 `tests/suite/scenarios.rs` 增加可选元数据断言（如 `expect_exit`、`expect_stderr_contains`），补齐当前仅最终态断言的盲区。
4. 将场景遍历结果按目录名排序后执行，提升 CI 稳定性和定位一致性。
