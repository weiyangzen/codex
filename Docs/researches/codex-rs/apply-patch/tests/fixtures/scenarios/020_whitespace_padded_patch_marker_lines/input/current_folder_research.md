# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/input`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 所属 crate：`codex-apply-patch`
- 目录实体：`file.txt`

## 场景与职责

该目录是场景 `020_whitespace_padded_patch_marker_lines` 的输入态（pre-state）目录，职责非常聚焦：为端到端场景测试提供最小初始文件系统。

本场景由三段式 fixture 组成：

1. `input/file.txt`：初始内容为 `one`（`codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/input/file.txt:1`）。
2. `patch.txt`：定义一次 `Update File` 操作，关键是边界 marker 行带空白（`codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/patch.txt:1-6`）。
3. `expected/file.txt`：期望结果为 `two`（`codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/expected/file.txt:1`）。

该 `input/` 目录本身不承载解析逻辑或执行逻辑，它的责任是确保测试信号只聚焦在“边界 marker 行空白容错是否有效”这一点上。

## 功能点目的

围绕本目录的功能点目的可以拆为 4 个层次：

1. 验证 parser 对边界行空白的容忍性：
`patch.txt` 的第 1 行是 `*** Begin Patch `（尾随空白），第 6 行是 ` *** End Patch`（前导空白），目标是证明这两类 padding 都可接受，而不是报边界错误。

2. 验证容错可落地到真实文件更新，而非仅“解析成功”：
从 `input/file.txt` 的 `one` 到 `expected/file.txt` 的 `two`，确保执行链路完整。

3. 形成 whitespace 容错场景的互补覆盖：
- `017_whitespace_padded_hunk_header`：hunk header 行前导空白。
- `018_whitespace_padded_patch_markers`：Begin 前导空白 + End 尾随空白。
- `020_whitespace_padded_patch_marker_lines`（本场景）：Begin 尾随空白 + End 前导空白。

4. 以最小输入降低误报：
本目录仅 1 个文件、1 行文本，避免 rename、多文件、上下文冲突等因素干扰结论。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*` 并逐目录执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 复制 `input/` 到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`）。
3. 读取场景同级 `patch.txt` 并启动 `apply_patch` 二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
4. CLI 入口 `run_main()` 接收 patch 参数后调用 `crate::apply_patch()`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
5. `apply_patch()` 调 `parse_patch()` 解析，再由 `apply_hunks()` 落盘（`codex-rs/apply-patch/src/lib.rs:183-213`）。
6. `check_start_and_end_lines_strict()` 对首尾行先 `trim()` 再匹配 marker，因此可接受本场景边界行空白（`codex-rs/apply-patch/src/parser.rs:226-244`）。
7. `UpdateFile` hunk 通过 `derive_new_contents_from_chunks()` + `seek_sequence()` 定位并替换内容，写回文件（`codex-rs/apply-patch/src/lib.rs:306-339`, `codex-rs/apply-patch/src/lib.rs:348-370`, `codex-rs/apply-patch/src/seek_sequence.rs:1-65`）。
8. 测试最后用 `snapshot_dir()` 对比临时目录与 `expected/` 的完整文件树快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`, `:71-126`）。

### 2) 关键数据结构

1. `ApplyPatchArgs { patch, hunks, workdir }`：patch 解析结果（`codex-rs/apply-patch/src/lib.rs:85-92`）。
2. `Hunk::UpdateFile { path, move_path, chunks }`：本场景命中的操作类型（`codex-rs/apply-patch/src/parser.rs:58-76`）。
3. `UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`：更新块语义载体（`codex-rs/apply-patch/src/parser.rs:90-104`）。
4. 场景断言快照结构：`BTreeMap<PathBuf, Entry>`，其中 `Entry = File(Vec<u8>) | Dir`（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-77`）。

### 3) 协议与语法

1. fixture 协议：每个场景都必须是 `input/ + patch.txt + expected/`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。
2. tool Lark 语法定义是严格 marker（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-3`）。
3. parser 实现在边界行匹配处是“严格文本 + 行级 trim”，属于宽容实现（`codex-rs/apply-patch/src/parser.rs:23-24`, `:230-235`）。
4. `parse_patch_text()` 开始处对整个 patch 做 `patch.trim().lines()`，会先去掉整体首尾空白（`codex-rs/apply-patch/src/parser.rs:154-156`）。

### 4) 关键命令

1. 场景回归：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 仅复现本场景 patch：
```bash
apply_patch "*** Begin Patch 
*** Update File: file.txt
@@
-one
+two
 *** End Patch"
```
3. 日常研究清单重建：`bash .ops/generate_daily_research_todo.sh`（`.ops/generate_daily_research_todo.sh:1-42`）。

## 关键代码路径与文件引用

### A. 目标目录与同级场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/input/file.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/patch.txt:1-6`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/expected/file.txt:1`

### B. 直接调用方（测试）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-3`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:71-126`

### C. 被调用方（解析与执行）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:279-339`
4. `codex-rs/apply-patch/src/parser.rs:154-183`
5. `codex-rs/apply-patch/src/parser.rs:226-244`
6. `codex-rs/apply-patch/src/parser.rs:248-333`
7. `codex-rs/apply-patch/src/seek_sequence.rs:1-110`

### D. 上游配置/调度路径

1. apply_patch 工具注册依赖 `config.apply_patch_tool_type`（`codex-rs/core/src/tools/spec.rs:2784-2804`）。
2. handler 先 `maybe_parse_apply_patch_verified` 后执行审批/落盘（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-257`）。
3. runtime 组装 `codex --codex-run-as-apply-patch <patch>` 自调用命令（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`）。
4. `arg0` 分发 `apply_patch` alias 与 `--codex-run-as-apply-patch` 参数（`codex-rs/arg0/src/lib.rs:85-107`）。
5. core README 对该跨 crate 约定有明确说明（`codex-rs/core/README.md:94`）。

### E. 文档与脚本

1. 场景规范文档：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
2. 工具说明文档：`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`
3. todo 生成脚本：`.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

### 1) 代码依赖

1. `codex-apply-patch` 主依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 场景测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。
3. Bazel 侧 `compile_data` 包含 `apply_patch_tool_instructions.md`，确保构建时可访问（`codex-rs/apply-patch/BUILD.bazel:1-11`）。

### 2) 外部交互

1. 文件系统交互：复制 `input/`、执行 patch 写盘、读取 `expected/` 快照比对（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`, `:50-53`）。
2. 子进程交互：测试通过 `Command::new(cargo_bin("apply_patch"))` 执行二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. 标准输出/错误：`apply_patch` 成功输出 summary，失败输出诊断（`codex-rs/apply-patch/src/lib.rs:191-206`, `:247-265`）。
4. 上游运行时交互：`ApplyPatchRuntime` 在沙箱尝试中通过 `execute_env` 实际执行命令（`codex-rs/core/src/tools/runtimes/apply_patch.rs:200-215`）。

### 3) 与配置的关系

1. 若 `config.apply_patch_tool_type` 未启用，apply_patch 工具不会注册（`codex-rs/core/src/tools/spec.rs:2784-2804`）。
2. 启用后可选 Freeform/Function 两种协议入口，但最终都归一到 patch 文本解析（`codex-rs/core/src/tools/handlers/apply_patch.rs:157-174`, `:358-380`）。

## 风险、边界与改进建议

### 风险

1. 规范与实现语义差异：Lark 语法描述为严格 marker，实际 parser 在边界上做了 `trim()` 容错，阅读文档者容易误判可接受输入范围（`tool_apply_patch.lark:1-3` vs `parser.rs:230-235`）。
2. 场景执行器不校验进程退出码，只校验最终文件树；若未来出现“错误码变化但文件状态碰巧一致”，可能延迟暴露（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。
3. 目录命名存在双 `020_*`（`020_delete_file_success` 与 `020_whitespace_padded_patch_marker_lines`），对人工排查和统计脚本可读性有干扰。

### 边界

1. 本目录仅覆盖单文件内容替换，不覆盖 rename/delete/add 复合操作。
2. 不覆盖 heredoc 解析、shell 包裹命令提取等调用形式（这些由 `invocation.rs` 相关路径与其它测试覆盖）。
3. 不覆盖空白字符类型矩阵（如 tab、NBSP、混合空白），当前用例只覆盖普通空格。

### 改进建议

1. 将 marker 空白容错场景参数化：按 Begin/End 的 leading/trailing、空格/tab 组合生成矩阵，减少手工增补。
2. 在 `tests/suite/scenarios.rs` 为场景增加可选元数据（如 `expect_exit_code`），保持快照断言的同时补强行为信号。
3. 在 `apply_patch_tool_instructions.md` 增加“实现层容错行为”说明，降低“语法文档严格、实现宽容”带来的使用偏差。
4. 为 whitespace 系列场景补充简短索引文档，明确 `017/018/020_whitespace...` 的互补关系，降低维护重复。
