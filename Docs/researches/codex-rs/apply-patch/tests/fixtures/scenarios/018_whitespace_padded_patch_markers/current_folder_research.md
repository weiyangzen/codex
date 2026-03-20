# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 场景关键词：`whitespace tolerance`、`patch boundary markers`、`Begin/End Patch`、`fixture e2e`

## 场景与职责

`018_whitespace_padded_patch_markers` 是 `apply_patch` fixtures 中的“补丁边界容错”场景，专门验证：
补丁首尾标记 `*** Begin Patch` 与 `*** End Patch` 即使存在前导或尾随空白，仍可被解析并成功执行。

该目录由三个最小组件组成：

1. `patch.txt`：构造带空白补丁边界的最小 patch。
   - 第 1 行是 `␠*** Begin Patch`（前导空格）。
   - 最后一行是 `*** End Patch␠`（尾随空格）。
2. `input/file.txt`：初始内容为 `one`。
3. `expected/file.txt`：期望内容为 `two`，验证 patch 被真正应用而非仅“解析通过”。

因此该目录不是业务逻辑代码，而是 parser 容错语义的端到端回归保护样例。

## 功能点目的

该场景保护的核心契约是“边界标记空白容忍”：

1. Parser 在检查补丁开始/结束标记时应允许 marker 行两端空白。
2. 容忍行为必须可执行，最终文件状态必须和 `expected/` 完全一致。
3. 容忍范围要有边界：只放宽 marker 两端空白，不放宽为任意错误 marker。

它主要防止两类回归：

1. 解析回归：如果未来把边界检查改为不 `trim()` 的严格字符串匹配，本场景会从“成功修改文件”退化为 `InvalidPatchError`。
2. 端到端回归：即便 parser 接受输入，后续 hunk 应用链路若异常，最终目录快照仍会不一致并触发失败。

与邻近场景的职责分工：

1. `017_whitespace_padded_hunk_header`：验证 hunk header（如 `*** Update File:`）前导空白容忍。
2. `018_whitespace_padded_patch_markers`（本目录）：验证 Begin/End patch 边界 marker 的两端空白容忍。
3. `020_whitespace_padded_patch_marker_lines`：验证 marker 行级别的另一组空白变体（如 `*** Begin Patch ` 与 ` *** End Patch`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景协议与输入

该目录遵循 `fixtures/scenarios` 统一协议（`input/ + patch.txt + expected/`）：

1. `patch.txt`（本场景实际载荷）：

```patch
 *** Begin Patch
*** Update File: file.txt
@@
-one
+two
*** End Patch 
```

2. `input/file.txt`：`one`
3. `expected/file.txt`：`two`

这是一段最小 `Update File` patch，只改变一行内容，确保测试信号集中在“边界 marker 的空白处理”。

### 2) 调用方流程（fixture runner）

场景由 `tests/suite/scenarios.rs` 统一驱动：

1. 遍历 `codex-rs/apply-patch/tests/fixtures/scenarios/*`。
2. 把场景 `input/` 复制到临时目录（`tempdir`）。
3. 读取 `patch.txt`，启动 `apply_patch` 子进程执行。
4. 将实际目录与 `expected/` 构造成 `BTreeMap<PathBuf, Entry>` 快照并做深度相等断言。

关键点：runner 故意不检查退出码，只比较最终文件树状态。这使场景更聚焦“语义最终态”。

### 3) 被调用方实现（解析 -> 执行）

执行链路：

1. `apply_patch` 可执行入口：`codex-rs/apply-patch/src/main.rs`。
2. `standalone_executable::run_main()` 读取 patch 参数（argv 或 stdin）并调用 `apply_patch()`。
3. `apply_patch()` 先 `parse_patch()`，后 `apply_hunks()`。
4. `apply_hunks_to_files()` 根据 `Hunk` 类型进行文件增删改。

与本场景直接相关的 parser 关键逻辑：

1. `parse_patch_text()` 先按行分割并调用边界检查。
2. `check_start_and_end_lines_strict()` 中，首行和尾行都先 `trim()`，再与 `*** Begin Patch` / `*** End Patch` 比对。
3. 因此 `" *** Begin Patch"` 与 `"*** End Patch "` 都会被接受。

本场景通过后，`Update File` hunk 继续由 `parse_one_hunk()` / `parse_update_file_chunk()` 解析，最后进入文本替换并写回文件。

### 4) 核心数据结构

1. `ApplyPatchArgs`：保存原始 patch 文本与解析后的 `hunks`。
2. `Hunk::UpdateFile`：携带目标路径、可选 `move_path`、以及多个 `UpdateFileChunk`。
3. `UpdateFileChunk`：包含 `old_lines/new_lines/change_context/is_end_of_file`，用于精确定位并替换。
4. `Entry`（测试侧）：`File(Vec<u8>) | Dir`，用于目录快照字节级比对。

### 5) 协议与命令

1. 协议来源：`apply_patch_tool_instructions.md` 给出规范语法（严格 marker 文本）。
2. 实际行为：`parser.rs` 对 patch 边界 marker 实现了 `trim()` 宽容。
3. 复现命令示例：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
   - `apply_patch " *** Begin Patch\n*** Update File: file.txt\n@@\n-one\n+two\n*** End Patch "`

## 关键代码路径与文件引用

### A. 研究对象（目标目录）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/patch.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/input/file.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/expected/file.txt`

### B. 直接调用方（测试组织与执行）

1. `codex-rs/apply-patch/tests/all.rs`
2. `codex-rs/apply-patch/tests/suite/mod.rs`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`

### C. 被调用方（解析与执行主链）

1. `codex-rs/apply-patch/src/main.rs`
2. `codex-rs/apply-patch/src/standalone_executable.rs`
3. `codex-rs/apply-patch/src/lib.rs`
4. `codex-rs/apply-patch/src/parser.rs`
5. `codex-rs/apply-patch/src/seek_sequence.rs`

### D. 上游接入与配置上下文（调用/注册/调度）

1. `codex-rs/core/src/tools/handlers/apply_patch.rs`
2. `codex-rs/core/src/tools/runtimes/apply_patch.rs`
3. `codex-rs/core/src/tools/spec.rs`
4. `codex-rs/core/src/config/mod.rs`
5. `codex-rs/arg0/src/lib.rs`

### E. 构建与规范文件

1. `codex-rs/apply-patch/Cargo.toml`
2. `codex-rs/apply-patch/BUILD.bazel`
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md`
4. `.ops/generate_daily_research_todo.sh`
5. `Docs/researches/blueprint_checklist.md`

## 依赖与外部交互

### 1) 依赖关系

`codex-apply-patch` 与本场景相关依赖包括：

1. `anyhow` / `thiserror`：错误建模与传播。
2. `similar`：生成 diff 相关输出。
3. `tree-sitter` / `tree-sitter-bash`：解析某些 shell heredoc 形态的 `apply_patch` 调用（主要在 `invocation.rs`）。
4. `assert_cmd` / `tempfile` / `pretty_assertions` / `codex-utils-cargo-bin`：测试命令执行与断言。

### 2) 文件系统与进程交互

1. 场景 runner 会复制 `input/` 到临时目录。
2. 通过子进程执行 `apply_patch` 二进制。
3. 运行后读取整个目录树，按字节比对 `expected` 与实际产物。

### 3) 与上层系统的交互

1. 在 core 工具层，`apply_patch` 由 `ApplyPatchHandler` 再解析校验，计算变更与权限。
2. runtime 构造 `codex --codex-run-as-apply-patch <patch>` 执行命令，并用最小环境运行。
3. `arg0` 支持通过 `apply_patch` 别名或内部参数 `--codex-run-as-apply-patch` 分发到同一执行逻辑。
4. 工具是否暴露、以 freeform 还是 function 形式注册，受 `ToolsConfig` 与 feature/config（如 `include_apply_patch_tool`、`apply_patch_tool_type`）控制。

## 风险、边界与改进建议

### 风险

1. 规范文档与实现存在“严格语法 vs 宽容实现”差距：文档看似严格 marker 文本，代码对边界 marker 做了 `trim()`。
2. `scenarios.rs` 只看最终文件树，不检查退出码与 stderr，某些诊断层回归可能被掩盖。
3. 边界容忍扩大时若缺乏细粒度测试，未来可能误接受本应拒绝的 malformed patch。

### 边界

1. 本场景只覆盖 Begin/End marker 两端空白，不覆盖 marker 拼写错误、大小写错误等。
2. 不覆盖 `Add File`/`Delete File` header 的同类空白变体（由其他场景/单测间接覆盖）。
3. 不涉及权限拒绝、只读文件、路径穿越等运行时安全边界。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 补一段“实现兼容行为”说明（marker/header 两端空白容忍），降低规范理解偏差。
2. 在 `tests/suite/scenarios.rs` 增加可选元数据断言（`exit_code` / `stderr_contains`），保留最终态断言同时增强诊断覆盖。
3. 为“空白容忍”增加更系统的矩阵测试（前导空格、尾随空格、tab、混合空白），并显式区分“应接受”和“应拒绝”。
4. 若未来计划收紧语法，建议通过 feature 或版本开关渐进收敛，避免直接破坏既有行为。
