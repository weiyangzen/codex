# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 场景关键词：`whitespace tolerance`、`patch marker lines`、`Begin/End Patch`、`fixture e2e`

## 场景与职责

`020_whitespace_padded_patch_marker_lines` 是 `apply_patch` 场景集中用于验证“补丁边界标记行可带前后空白”的端到端 fixture。

该目录是最小可复现结构（`input/ + patch.txt + expected/`）：

1. `patch.txt`：
   - 首行是 `*** Begin Patch `（尾随空格，`patch.txt:1`）。
   - 末行是 ` *** End Patch`（前导空格，`patch.txt:6`）。
   - 中间是一个最小 `Update File` hunk，把 `one` 改为 `two`（`patch.txt:2-5`）。
2. `input/file.txt`：初始内容 `one`（`input/file.txt:1`）。
3. `expected/file.txt`：期望内容 `two`（`expected/file.txt:1`）。

职责上，它不测试复杂 patch 语义，而是专门防守 parser 的边界容错行为是否仍能贯通到真实文件写入结果。

## 功能点目的

该场景保护的功能契约如下：

1. 补丁边界行允许 marker 两端空白（而非严格逐字匹配整行）。
2. 解析通过后，`Update File` 仍应按正常链路生效，最终文件树与 `expected/` 完全一致。
3. 容错范围有限：仅是 marker 行两端空白容错，不等于接受拼写错误 marker。

它主要覆盖两类回归：

1. 若未来将边界检查改成不 `trim()` 的硬匹配，本场景会失败（无法到达 `expected` 最终态）。
2. 若 parser 通过但执行链路（chunk 应用/写盘）回归，目录快照对比仍会失败，避免“只测解析不测效果”。

与邻近场景分工：

1. `018_whitespace_padded_patch_markers` 也覆盖边界 marker 空白容错，但变体是“首行前导空白 + 末行尾随空白”。
2. 本场景 `020_whitespace_padded_patch_marker_lines` 覆盖互补变体“首行尾随空白 + 末行前导空白”，形成对称覆盖。
3. `017_whitespace_padded_hunk_header` 则关注 hunk header（如 `*** Update File:`）前导空白，不是边界 marker 本身。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景协议与输入组织

`scenarios/README.md` 定义了统一 fixture 协议：每个 case 目录由 `input/`、`patch.txt`、`expected/` 三部分组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`）。

本场景 patch 原文如下：

```patch
*** Begin Patch 
*** Update File: file.txt
@@
-one
+two
 *** End Patch
```

这是一个最小更新补丁，故意把测试信号集中在边界 marker 空白容忍上。

### 2) 调用方流程（测试执行框架）

集成测试入口：

1. `tests/all.rs` 聚合 `tests/suite/*`（`codex-rs/apply-patch/tests/all.rs:1-3`）。
2. `tests/suite/mod.rs` 启用 `scenarios` 模块（`codex-rs/apply-patch/tests/suite/mod.rs:1-4`）。
3. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*`，对每个目录执行 `run_apply_patch_scenario()`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
4. `run_apply_patch_scenario()` 复制 `input/` 到临时目录、读取 `patch.txt`、调用 `apply_patch` 二进制，再对比 `expected` 与实际目录快照（`.../scenarios.rs:30-60`）。

关键实现细节：

1. runner 故意不对进程退出码做断言，而是只对“最终文件树”做强一致比较（`.../scenarios.rs:42-44`）。
2. 快照结构使用 `BTreeMap<PathBuf, Entry>`，`Entry` 区分 `File(Vec<u8>)` 和 `Dir`（`.../scenarios.rs:65-105`）。

### 3) 被调用方流程（解析 -> 执行）

执行链如下：

1. `apply_patch` CLI 从 argv 或 stdin 取 PATCH 文本，调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
2. `apply_patch()` 先 `parse_patch()`，解析成功后进入 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
3. `apply_hunks_to_files()` 在 `Hunk::UpdateFile` 分支调用 `derive_new_contents_from_chunks()` 后写回目标文件（`codex-rs/apply-patch/src/lib.rs:279-333`）。

与本场景最相关的 parser 关键点：

1. `parse_patch_text()` 对整段 patch `trim()` 后按行切分，再做边界检查（`codex-rs/apply-patch/src/parser.rs:154-177`）。
2. `check_start_and_end_lines_strict()` 中对首尾行再做 `trim()`，然后与 `*** Begin Patch` / `*** End Patch` 比较（`codex-rs/apply-patch/src/parser.rs:226-244`）。
3. 因此 `*** Begin Patch ` 与 ` *** End Patch` 都能通过边界检查。

### 4) 关键数据结构

1. `ApplyPatchArgs { patch, hunks, workdir }`：解析后的补丁模型（`codex-rs/apply-patch/src/lib.rs:85-92`）。
2. `Hunk::UpdateFile { path, move_path, chunks }`：文件更新语义（`codex-rs/apply-patch/src/parser.rs:68-75`）。
3. `UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`：逐段替换单元（`codex-rs/apply-patch/src/parser.rs:91-104`）。
4. `AffectedPaths { added, modified, deleted }`：执行结果摘要（`codex-rs/apply-patch/src/lib.rs:271-275`）。

### 5) 协议、语法与命令

1. 工具文档声明严格语法边界：`Begin := "*** Begin Patch"`、`End := "*** End Patch"`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:41-44`）。
2. freeform grammar（core 侧）同样是严格文法（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-4`）。
3. 实际 `codex-apply-patch` parser 出于兼容性做了 marker 行两端空白容错（`parser.rs:23-24` + `parser.rs:230-235`）。
4. 本场景回归命令：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`

## 关键代码路径与文件引用

### A. 研究对象（目标目录）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/patch.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/input/file.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/expected/file.txt:1`

### B. 直接调用方（场景测试）

1. `codex-rs/apply-patch/tests/all.rs:1`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`

### C. 被调用方（解析与执行主链）

1. `codex-rs/apply-patch/src/main.rs:1`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11`
3. `codex-rs/apply-patch/src/lib.rs:183`
4. `codex-rs/apply-patch/src/lib.rs:279`
5. `codex-rs/apply-patch/src/parser.rs:154`
6. `codex-rs/apply-patch/src/parser.rs:226`
7. `codex-rs/apply-patch/src/parser.rs:343`

### D. 上游集成与配置（调用方的调用方）

1. `codex-rs/core/src/tools/handlers/unified_exec.rs:237`（`exec_command` 路径中的 apply_patch 拦截）。
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:174`（`maybe_parse_apply_patch_verified` 校验）。
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69`（构造 `codex --codex-run-as-apply-patch <patch>` 命令）。
4. `codex-rs/arg0/src/lib.rs:85-107`（`apply_patch`/内部 arg1 分发执行）。
5. `codex-rs/core/src/config/mod.rs:528-531`（`include_apply_patch_tool` 开关）。
6. `codex-rs/core/src/tools/spec.rs:2784-2804`（按 `apply_patch_tool_type` 注册 freeform/function 工具）。

### E. 构建、脚本与研究流程文件

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-10`
3. `.ops/generate_daily_research_todo.sh:1-42`
4. `Docs/researches/blueprint_checklist.md:145`

## 依赖与外部交互

### 1) crate 依赖

`codex-apply-patch` 与本场景相关依赖（`Cargo.toml:18-30`）：

1. `anyhow` / `thiserror`：错误建模与传播。
2. `similar`：统一 diff 生成（本场景是 update，会走更新链路）。
3. `tree-sitter` / `tree-sitter-bash`：shell/heredoc 形态 `apply_patch` 解析（`invocation.rs`）。
4. `assert_cmd` / `tempfile` / `pretty_assertions` / `codex-utils-cargo-bin`：测试执行与断言。

### 2) 外部交互面

1. 文件系统：读 `input`/`patch`、写临时目录文件、与 `expected` 做字节级快照比对。
2. 进程：`scenarios.rs` 启动 `apply_patch` 子进程执行（`scenarios.rs:45-48`）。
3. 路径分发：`arg0` 允许以 `apply_patch` 别名或内部参数两种入口调用同一逻辑（`arg0/src/lib.rs:85-107`）。

### 3) 配置与协议交互

1. 工具是否对模型暴露由 `include_apply_patch_tool` 与 `apply_patch_tool_type` 决定（`config/mod.rs:528-531`，`tools/spec.rs:2784-2804`）。
2. 协议层文法严格、实现层 parser 宽容，二者存在“文档/grammar 与 runtime 行为”的兼容差异。
3. 场景目录通过 `.gitattributes` 固定 `eol=lf`，降低跨平台换行差异干扰（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`）。

## 风险、边界与改进建议

### 风险

1. 文档与实现差异：说明和 lark 语法是严格 marker；parser 实现对 marker 行做 `trim()` 宽容，认知上容易造成“以为严格，实际宽松”。
2. `scenarios` runner 仅断言最终态，不断言 exit code/stderr；诊断层面回归可能被弱化。
3. 本场景只覆盖一种 update 形态，若未来在 chunk 解析上回归，可能需要更细分 case 才能快速定位。

### 边界

1. 本场景只覆盖补丁边界 marker 行空白，不覆盖 marker 拼写错误、大小写错误。
2. 不覆盖 heredoc 包裹、`cd && apply_patch`、或 `applypatch` 别名解析（这些在 `invocation.rs` 路径）。
3. 不覆盖权限与审批路径（core runtime/guardian），仅覆盖 fixture 层黑盒执行结果。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 增补“实现兼容行为”说明，明确 marker 行两端空白会被接受，减少使用方误判。
2. 给 `scenarios` 框架增加可选 `exit_code`/`stderr` 断言文件，保留最终态断言同时增强可观测性。
3. 增加 whitespace 容错矩阵用例（空格、tab、混合空白、仅单侧空白、空白+错误拼写）并明确 accept/reject 预期。
4. 在 `scenarios/README.md` 增加“空白容错相关场景映射（017/018/020）”，降低维护者定位成本。
