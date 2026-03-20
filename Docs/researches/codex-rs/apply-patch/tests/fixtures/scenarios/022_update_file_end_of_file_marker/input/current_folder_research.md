# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/input`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 所属 crate：`codex-apply-patch`
- 目录实体：`tail.txt`

## 场景与职责

该目录是场景 `022_update_file_end_of_file_marker` 的输入态目录，职责是为 `*** End of File` 更新语义提供最小可验证的真实文件基线。

本目录仅包含：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/input/tail.txt:1`

`tail.txt` 初始内容为两行：`first`、`second`。同级 `patch.txt` 定义对 `tail.txt` 的 `Update File` 操作，并在 chunk 末尾携带 `*** End of File`；同级 `expected/tail.txt` 定义期望结果为 `first`、`second updated`。

该输入目录在场景矩阵中的职责边界：

1. 与 `021_update_file_deletion_only/input` 区分：`021` 强调 only-delete，本目录服务于 replace + EOF marker。
2. 与 `016_pure_addition_update_chunk/input` 区分：`016` 强调 only-add，本目录强调尾部锚定下的替换。
3. 与 `014_update_file_appends_trailing_newline` 互补：`014` 主测尾换行补齐，本目录主测 EOF 标记贯穿解析与匹配流程。

## 功能点目的

围绕本 `input/` 目录，目标是验证：当补丁声明 `*** End of File` 时，`apply_patch` 会把这条语义转成“应在文件尾部区域匹配并替换”的约束，而不是普通全文件任意位置匹配。

具体保护点：

1. 解析层：`*** End of File` 被识别为合法 EOF 行，并映射到 `UpdateFileChunk.is_end_of_file = true`（`codex-rs/apply-patch/src/parser.rs:37`, `codex-rs/apply-patch/src/parser.rs:387`）。
2. 匹配层：`compute_replacements()` 将 `chunk.is_end_of_file` 透传给 `seek_sequence(..., eof)`（`codex-rs/apply-patch/src/lib.rs:439`）。
3. 搜索层：`seek_sequence` 在 `eof=true` 时优先从 `lines.len() - pattern.len()` 处开始（`codex-rs/apply-patch/src/seek_sequence.rs:29`）。
4. e2e 层：场景 runner 比较 `input -> 执行后目录快照` 与 `expected` 的字节级一致性（`codex-rs/apply-patch/tests/suite/scenarios.rs:51`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) fixture 协议与场景资产

场景采用统一结构 `input/ + patch.txt + expected/`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:6`）：

1. 输入态：`.../input/tail.txt`。
2. 操作定义：`.../patch.txt`。
3. 期望态：`.../expected/tail.txt`。

`patch.txt` 的关键协议行：

1. `*** Update File: tail.txt`
2. `@@`
3. ` first`
4. `-second`
5. `+second updated`
6. `*** End of File`

其中第 6 行对应 grammar：`eof_line: "*** End of File" LF`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:49`, `codex-rs/core/src/tools/handlers/tool_apply_patch.lark:17`）。

### 2) 调用链（调用方 -> 被调用方）

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11`）。
2. `run_apply_patch_scenario()` 复制本 `input/` 到临时目录根，并读取同级 `patch.txt`（`codex-rs/apply-patch/tests/suite/scenarios.rs:34`, `codex-rs/apply-patch/tests/suite/scenarios.rs:40`）。
3. 测试以子进程运行 `apply_patch` 二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45`）。
4. CLI 入口 `run_main()` 转调 `codex_apply_patch::apply_patch()`（`codex-rs/apply-patch/src/standalone_executable.rs:11`, `codex-rs/apply-patch/src/standalone_executable.rs:51`）。
5. `apply_patch()` 完成解析后进入 `apply_hunks_to_files()`（`codex-rs/apply-patch/src/lib.rs:183`, `codex-rs/apply-patch/src/lib.rs:279`）。
6. `UpdateFile` 分支执行 `derive_new_contents_from_chunks()` -> `compute_replacements()` -> `apply_replacements()`（`codex-rs/apply-patch/src/lib.rs:311`, `codex-rs/apply-patch/src/lib.rs:370`, `codex-rs/apply-patch/src/lib.rs:478`）。
7. runner 通过 `snapshot_dir()` 比较执行结果与 `expected`（`codex-rs/apply-patch/tests/suite/scenarios.rs:52`, `codex-rs/apply-patch/tests/suite/scenarios.rs:71`）。

### 3) 数据结构与 EOF 语义落点

1. `Hunk::UpdateFile { chunks }` 承载更新操作（`codex-rs/apply-patch/src/parser.rs:68`）。
2. `UpdateFileChunk` 包含 `old_lines/new_lines/is_end_of_file`（`codex-rs/apply-patch/src/parser.rs:91`）。
3. 本场景 chunk 解析后语义等价于：
   - `old_lines = ["first", "second"]`
   - `new_lines = ["first", "second updated"]`
   - `is_end_of_file = true`
4. `seek_sequence` 在 `eof=true` 下先尝试“尾部起点”并按四级容错匹配（精确、rstrip、trim、Unicode 归一化）（`codex-rs/apply-patch/src/seek_sequence.rs:35`, `codex-rs/apply-patch/src/seek_sequence.rs:67`）。

### 4) 配置与产品运行链（非 fixture 直接执行，但属上游依赖）

1. `Config.include_apply_patch_tool` 决定是否纳入该工具（`codex-rs/core/src/config/mod.rs:528`）。
2. `tools/spec` 根据 `apply_patch_tool_type` 注册 freeform/function 形态（`codex-rs/core/src/tools/spec.rs:2784`）。
3. `ApplyPatchHandler` 对输入再次做 `maybe_parse_apply_patch_verified()`（`codex-rs/core/src/tools/handlers/apply_patch.rs:174`）。
4. `ApplyPatchRuntime` 以 `codex --codex-run-as-apply-patch <patch>` 执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:91`）。
5. `arg0` 分发层消费 `CODEX_CORE_APPLY_PATCH_ARG1` 并调用同一库函数实现（`codex-rs/arg0/src/lib.rs:90`, `codex-rs/arg0/src/lib.rs:96`）。

### 5) 相关命令

1. 场景回归：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. crate 全测：`cargo test -p codex-apply-patch`
3. 研究待办刷新：`bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 目标目录与同级场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/input/tail.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/patch.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/expected/tail.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:6`

### B. 直接调用方（测试框架）

1. `codex-rs/apply-patch/tests/all.rs:1`
2. `codex-rs/apply-patch/tests/suite/mod.rs:2`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:30`
5. `codex-rs/apply-patch/tests/suite/scenarios.rs:45`

### C. 被调用方（apply-patch 核心）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11`
2. `codex-rs/apply-patch/src/lib.rs:183`
3. `codex-rs/apply-patch/src/lib.rs:279`
4. `codex-rs/apply-patch/src/lib.rs:386`
5. `codex-rs/apply-patch/src/lib.rs:439`
6. `codex-rs/apply-patch/src/parser.rs:343`
7. `codex-rs/apply-patch/src/seek_sequence.rs:12`

### D. 上游配置/协议/执行链

1. `codex-rs/core/src/config/mod.rs:528`
2. `codex-rs/core/src/tools/spec.rs:2784`
3. `codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1`
4. `codex-rs/core/src/tools/handlers/apply_patch.rs:170`
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69`
6. `codex-rs/arg0/src/lib.rs:90`

### E. 研究流程脚本与清单

1. `.ops/generate_daily_research_todo.sh:5`
2. `.ops/generate_research_blueprint_checklist.sh:5`
3. `Docs/researches/blueprint_checklist.md:153`

## 依赖与外部交互

### 1) crate 与测试依赖

`codex-apply-patch` 关键依赖（`codex-rs/apply-patch/Cargo.toml:18`）：

1. `anyhow` / `thiserror`：错误与上下文。
2. `similar`：生成 unified diff。
3. `tree-sitter` / `tree-sitter-bash`：shell/heredoc 解析。
4. `assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`：集成测试执行与断言。

### 2) 文件系统与进程交互

1. `copy_dir_recursive()` 把该目录文件复制到临时测试目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:107`）。
2. `apply_patch` 进程在临时目录内运行，直接执行真实文件 I/O（`codex-rs/apply-patch/tests/suite/scenarios.rs:47`）。
3. `apply_hunks_to_files()` 对目标文件做覆盖写回（`codex-rs/apply-patch/src/lib.rs:327`）。

### 3) 与 core/审批/沙箱交互

1. handler 层会先验证 patch，再根据安全评估决定是否委托 exec（`codex-rs/core/src/tools/handlers/apply_patch.rs:174`, `codex-rs/core/src/apply_patch.rs:41`）。
2. runtime 执行命令时走最小环境，权限策略通过 orchestrator 下发（`codex-rs/core/src/tools/runtimes/apply_patch.rs:96`）。
3. `apply_patch` 既可独立二进制调用，也可通过 `arg0` 内部参数调用，底层复用同一实现。

### 4) 文档/脚本交互

1. 协议文档 `apply_patch_tool_instructions.md` 与 `tool_apply_patch.lark` 一致定义 EOF 行。
2. 研究任务由 `blueprint_checklist.md` 驱动，`generate_daily_research_todo.sh` 负责生成当日 todo 快照。

## 风险、边界与改进建议

### 风险

1. 当前 `input/tail.txt` 仅两行，不足以暴露“重复片段导致错误命中”的复杂 EOF 定位风险。
2. `scenarios` runner 只比较最终目录状态，不显式断言 exit code/stderr，过程信号覆盖有限（`codex-rs/apply-patch/tests/suite/scenarios.rs:42`）。
3. EOF 语义跨 parser 与 matcher 两层，任一层重构都可能产生“语法仍通过但定位退化”的隐性回归。

### 边界

1. 本目录只服务单文件场景，不覆盖多文件事务行为。
2. 不覆盖 `Move to` + EOF marker 组合。
3. 不覆盖 CRLF、权限失败、符号链接等 I/O 边界。
4. 不覆盖上层 UI 文案与事件输出，仅覆盖文件系统最终态。

### 改进建议

1. 新增一个“文件前后都出现 `first/second`，只应替换尾部块”的 EOF 场景，直接验证尾部优先策略价值。
2. 为 `scenarios` 机制增加可选 `exit_code/stderr` 断言文件，补强行为层信号。
3. 增加 `Update File + Move to + End of File` 场景，覆盖重命名路径下 EOF 语义。
4. 在 `tests/fixtures/scenarios/README.md` 增加 EOF marker 专节，减少未来新增场景时的语义分歧。
