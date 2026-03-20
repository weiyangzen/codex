# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 关联场景：`022_update_file_end_of_file_marker`

## 场景与职责

该目录是场景 `022_update_file_end_of_file_marker` 的 expected 断言端，当前仅包含 1 个文件：

- `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/expected/tail.txt:1`

它在场景体系中的职责不是“执行补丁”，而是“定义执行后的真值状态（oracle）”，供 `tests/suite/scenarios.rs` 的目录快照比较使用。调用侧会把 `input/` 复制到临时目录、执行 `apply_patch`，再把临时目录与 `expected/` 做字节级比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-58`）。

该目录承载的核心场景语义：

1. `patch.txt` 使用 `*** End of File` 标记（`codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/patch.txt:7`）。
2. 输入 `tail.txt` 为两行 `first/second`（`.../input/tail.txt:1-2`）。
3. 期望输出 `tail.txt` 为 `first/second updated`（`.../expected/tail.txt:1-2`）。

因此，该目录职责是验证“EOF 锚定 update chunk”在端到端执行后得到准确最终文件内容，而不是仅验证解析器是否接受语法。

## 功能点目的

该 expected 目录对应的功能点目的，是把 `*** End of File` 从“语法允许”提升为“行为正确”：

1. 协议层允许 `Hunk` 末尾可带 `*** End of File`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:49`）。
2. parser 将该标记映射到 `UpdateFileChunk.is_end_of_file = true`（`codex-rs/apply-patch/src/parser.rs:37`, `:101-103`, `:387-395`）。
3. 执行层用 `chunk.is_end_of_file` 驱动匹配策略，调用 `seek_sequence(..., eof=true)`（`codex-rs/apply-patch/src/lib.rs:437-440`）。
4. `seek_sequence` 在 `eof=true` 时优先从文件尾起始位置匹配（`codex-rs/apply-patch/src/seek_sequence.rs:29-33`）。
5. 最终输出由本目录的 `tail.txt` 作为唯一判定标准，防止“解析正确、落盘错误”的回归。

简言之：这个 expected 目录是 EOF 锚定语义的最终行为契约。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景协议与 fixture 结构

`scenarios/README.md` 定义每个场景都由 `input/ + patch.txt + expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`）。

本场景补丁内容如下（`.../022_update_file_end_of_file_marker/patch.txt:1-8`）：

```patch
*** Begin Patch
*** Update File: tail.txt
@@
 first
-second
+second updated
*** End of File
*** End Patch
```

其中第 7 行是关键 EOF 标记。`expected/` 的 `tail.txt` 则定义最终应为：

```text
first
second updated
```

（`.../expected/tail.txt:1-2`）

### 2) 执行流程（调用方 -> 被调用方）

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-23`）。
2. `run_apply_patch_scenario()`：复制 `input/`、读取 `patch.txt`、执行 `apply_patch` 子进程（`:33-48`）。
3. CLI 入口 `run_main()` 接收 patch 参数并调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-52`）。
4. `apply_patch()` 解析 hunk 后进入 `apply_hunks_to_files()`（`codex-rs/apply-patch/src/lib.rs:183-210`, `:268-339`）。
5. `UpdateFile` 分支在 `derive_new_contents_from_chunks()`/`compute_replacements()` 中根据 chunk 计算替换，再写回文件（`codex-rs/apply-patch/src/lib.rs:348-380`, `:386-474`）。
6. 场景框架把临时目录快照与 `expected/` 快照做 `assert_eq!`，该目录即最终判定基线（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-58`, `:71-103`）。

注意：该 runner 明确“不检查 exit status，只看最终文件状态”（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-44`），因此 expected 目录在该测试模型里权重极高。

### 3) 数据结构与 EOF 语义落地

关键数据结构：`UpdateFileChunk`（`codex-rs/apply-patch/src/parser.rs:90-104`）。

- `old_lines/new_lines`：旧片段与新片段。
- `is_end_of_file`：是否要求旧片段在文件尾匹配。

`parse_update_file_chunk()` 遇到 `*** End of File` 时将 `is_end_of_file = true` 并结束当前 chunk（`codex-rs/apply-patch/src/parser.rs:387-396`）。

执行时 `compute_replacements()` 将该布尔值透传给匹配器：

- `seek_sequence(original_lines, pattern, line_index, chunk.is_end_of_file)`（`codex-rs/apply-patch/src/lib.rs:437-440`）。
- 当 `eof=true`，`seek_sequence` 的 `search_start = lines.len() - pattern.len()`，先从尾部可匹配起点尝试（`codex-rs/apply-patch/src/seek_sequence.rs:29-33`）。

因此，EOF 标记不仅改变解析结果，还改变替换定位策略。

### 4) 相关协议/文档/命令

- 协议文档：`Hunk := ... [ "*** End of File" NEWLINE ]`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`）。
- parser 语法注释与文档保持一致（`codex-rs/apply-patch/src/parser.rs:4-21`）。
- 推荐回归命令：
  - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
  - `cargo test -p codex-apply-patch`
  - `bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 研究对象与直接场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/expected/tail.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/input/tail.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/patch.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`

### B. 调用方（场景执行与断言）

1. `codex-rs/apply-patch/tests/all.rs:1`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-3`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-23`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-48`
5. `codex-rs/apply-patch/tests/suite/scenarios.rs:50-58`

### C. 被调用方（解析、匹配、写回）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-52`
2. `codex-rs/apply-patch/src/parser.rs:31-39`
3. `codex-rs/apply-patch/src/parser.rs:90-104`
4. `codex-rs/apply-patch/src/parser.rs:343-434`
5. `codex-rs/apply-patch/src/lib.rs:348-380`
6. `codex-rs/apply-patch/src/lib.rs:386-474`
7. `codex-rs/apply-patch/src/seek_sequence.rs:12-33`
8. `codex-rs/apply-patch/src/seek_sequence.rs:34-109`

### D. 配置、注册、运行时与分发链路（上游上下文依赖）

1. `codex-rs/core/src/config/mod.rs:528-531`（是否启用 apply_patch）
2. `codex-rs/core/src/tools/spec.rs:2784-2804`（注册 apply_patch 工具与 handler）
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-178`（verified parse）
4. `codex-rs/core/src/tools/handlers/apply_patch.rs:197-210`（构造 ApplyPatchRequest）
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`（构建 `codex --codex-run-as-apply-patch`）
6. `codex-rs/core/src/tools/runtimes/apply_patch.rs:188-197`（审批要求绑定）
7. `codex-rs/arg0/src/lib.rs:85-90`（alias 分发）
8. `codex-rs/arg0/src/lib.rs:90-107`（隐藏参数触发 apply_patch 执行）

### E. 测试、构建、脚本、文档

1. `codex-rs/apply-patch/src/parser.rs:685-763`（EOF 解析单元测试）
2. `codex-rs/apply-patch/src/lib.rs:949-981`（`test_unified_diff_insert_at_eof`）
3. `codex-rs/core/tests/suite/apply_patch_cli.rs:1071-1085`（core 端 EOF anchor 用例）
4. `codex-rs/apply-patch/Cargo.toml:1-30`
5. `codex-rs/apply-patch/BUILD.bazel:3-10`
6. `codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`
7. `.ops/generate_daily_research_todo.sh:4-7`
8. `.ops/generate_daily_research_todo.sh:15-18`
9. `Docs/researches/blueprint_checklist.md:152`

## 依赖与外部交互

### 1) crate 依赖

`codex-apply-patch` 依赖（`codex-rs/apply-patch/Cargo.toml:18-30`）：

1. `anyhow`/`thiserror`：错误上下文建模。
2. `similar`：统一 diff 生成。
3. `tree-sitter`/`tree-sitter-bash`：shell/heredoc 形式命令提取与解析。
4. `assert_cmd`/`tempfile`/`codex-utils-cargo-bin`/`pretty_assertions`：集成测试基础设施。

### 2) 进程与文件系统交互

1. 场景测试通过真实子进程执行 `apply_patch`，不是 mock（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
2. patch 执行涉及真实读写磁盘：`read_to_string`、`write`、`remove_file`（`codex-rs/apply-patch/src/lib.rs:352-359`, `:327-333`）。
3. `scenarios/.gitattributes` 固定 `eol=lf`，减少跨平台换行差异（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`）。

### 3) 与 core 的外部交互

该 expected 目录虽位于 `apply-patch` 测试夹具，但其验证语义直接对应 core 链路：

1. 工具可由配置启用（`codex-rs/core/src/config/mod.rs:528-531`）。
2. spec 层注册 freeform/function apply_patch 与 handler（`codex-rs/core/src/tools/spec.rs:2784-2804`）。
3. handler 先 `maybe_parse_apply_patch_verified` 再决定执行/审批（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-178`）。
4. runtime 构造 `CODEX_CORE_APPLY_PATCH_ARG1 + patch` 命令执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:90-93`）。
5. `arg0` 接收该隐藏参数并落到 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:90-107`）。

### 4) 文档与脚本交互

1. apply_patch 语法由工具文档声明（`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`）。
2. 研究流程通过 checklist + daily todo 脚本维护（`.ops/generate_daily_research_todo.sh:5`, `:15-18`, `:41-42`）。

## 风险、边界与改进建议

### 风险

1. 本 expected 目录只覆盖 2 行文本的简单 EOF 替换，不能充分暴露“重复片段歧义 + EOF 锚定”的复杂定位风险。
2. 场景 runner 不检查 exit status/stderr（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-44`），若出现“错误输出但最终态偶然一致”可能漏报。
3. EOF 语义横跨 parser 与 matcher 两层；任一层重构都可能引入隐蔽退化。

### 边界

1. 当前场景只覆盖单文件、单 chunk、非 rename 路径。
2. 不覆盖 `*** Move to` + `*** End of File` 组合。
3. 不覆盖 CRLF、权限失败、符号链接、路径越界等 I/O 与安全边界。
4. `expected` 目录本身不承载过程断言（如 stderr/exit code），仅承载最终文件态断言。

### 改进建议

1. 新增“重复尾段文本”的 EOF 场景：让同一 `old_lines` 在文件中出现两次，仅尾部应被替换，以直接验证 `eof=true` 的判定价值。
2. 给 `scenarios` 增加可选元数据断言（例如 `stderr.txt` / `exit_code.txt`），保持最终态断言同时补足行为可观测性。
3. 增加 `Move to + End of File` 组合场景，验证更新与重命名并存时的 EOF 语义。
4. 在 `scenarios/README.md` 增加 EOF marker 的语义说明和常见误用示例，降低维护成本。
