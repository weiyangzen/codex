# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 场景关键词：`Update File`、`*** End of File`、`EOF 锚定匹配`、`fixture e2e`

## 场景与职责

`022_update_file_end_of_file_marker` 是 `apply_patch` 场景集里专门覆盖 `*** End of File` 标记语义的目录级夹具，用于验证：

1. parser 能正确识别 update chunk 末尾的 `*** End of File`，并将其映射到 `UpdateFileChunk.is_end_of_file = true`。
2. 执行器在匹配替换片段时，会走 EOF 优先定位分支，优先从文件尾部尝试匹配，避免错误命中更早的重复片段。
3. 场景级回归（真实子进程调用 `apply_patch`）可稳定得到期望最终文件树。

该目录内文件职责清晰且最小化：

1. `patch.txt`：声明一个 `Update File: tail.txt`，包含上下文行、删除行、新增行，并显式 `*** End of File`（`codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/patch.txt:1`）。
2. `input/tail.txt`：初始状态为两行 `first` / `second`（`codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/input/tail.txt:1`）。
3. `expected/tail.txt`：期望结果为 `first` / `second updated`（`codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/expected/tail.txt:1`）。

在场景矩阵中的职责边界：

1. 与 `016_pure_addition_update_chunk` 不同：`016` 覆盖“纯 `+` 新增”路径，本场景覆盖“替换 + EOF 锚定”路径。
2. 与 `021_update_file_deletion_only` 不同：`021` 覆盖“仅删除”路径，本场景覆盖“删除+新增组合替换且带 EOF marker”。
3. 与 `014_update_file_appends_trailing_newline` 互补：`014` 更关注尾换行补齐，本场景更关注 `is_end_of_file` 匹配策略本身。

## 功能点目的

本场景保护的核心功能目的，是将 `*** End of File` 从“语法标记”落实为“匹配策略约束”：

1. 补丁协议层面：`Hunk := ... [ "*** End of File" NEWLINE ]` 是合法语法组成部分（`codex-rs/apply-patch/apply_patch_tool_instructions.md:49`，`codex-rs/apply-patch/src/parser.rs:21`）。
2. 数据结构层面：`UpdateFileChunk.is_end_of_file` 是显式布尔字段，用于传递 EOF 约束（`codex-rs/apply-patch/src/parser.rs:101`）。
3. 匹配算法层面：`seek_sequence(..., eof = true)` 会将搜索起点偏向文件尾（`codex-rs/apply-patch/src/seek_sequence.rs:29`）。
4. 端到端行为层面：在场景 runner 中，最终文件必须与 `expected/` 完全一致（字节级），从而防止“解析正确但应用偏移”的回归（`codex-rs/apply-patch/tests/suite/scenarios.rs:50`）。

它主要防止两类回归：

1. parser 回归：`*** End of File` 被忽略、误判或错误吞并成下一 hunk。
2. patch 应用回归：当文件中存在重复片段时，未优先尾部定位导致错误替换位置。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景协议与补丁文本解析

fixtures 协议由 `scenarios/README.md` 定义：每个场景由 `input/` + `patch.txt` + `expected/` 构成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:6`）。

本场景补丁为：

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

对应 parser 行为：

1. `parse_patch()` 先检查 begin/end marker，再逐 hunk 解析（`codex-rs/apply-patch/src/parser.rs:106`，`codex-rs/apply-patch/src/parser.rs:154`，`codex-rs/apply-patch/src/parser.rs:171`）。
2. `parse_update_file_chunk()` 识别 `@@` 后的行前缀：
   - `' '` 行进入 `old_lines` 与 `new_lines`；
   - `'-'` 行仅进入 `old_lines`；
   - `'+'` 行仅进入 `new_lines`（`codex-rs/apply-patch/src/parser.rs:405`，`codex-rs/apply-patch/src/parser.rs:409`，`codex-rs/apply-patch/src/parser.rs:412`）。
3. 遇到 `EOF_MARKER`（`*** End of File`）后设置 `chunk.is_end_of_file = true` 并结束当前 chunk（`codex-rs/apply-patch/src/parser.rs:37`，`codex-rs/apply-patch/src/parser.rs:387`，`codex-rs/apply-patch/src/parser.rs:394`）。

> 由此本场景 chunk 语义可还原为：`old_lines = ["first", "second"]`，`new_lines = ["first", "second updated"]`，`is_end_of_file = true`。

### 2) 应用流程（调用方 -> 被调用方）

端到端链路如下：

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*` 目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11`）。
2. `run_apply_patch_scenario()` 复制 `input/` 到临时目录，读取 `patch.txt`，启动 `apply_patch` 子进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:30`，`codex-rs/apply-patch/tests/suite/scenarios.rs:40`，`codex-rs/apply-patch/tests/suite/scenarios.rs:45`）。
3. CLI 入口 `run_main()` 收取 patch 字符串并调用库函数 `apply_patch()`（`codex-rs/apply-patch/src/standalone_executable.rs:11`，`codex-rs/apply-patch/src/standalone_executable.rs:51`）。
4. `apply_patch()` -> `apply_hunks()` -> `apply_hunks_to_files()`，在 `UpdateFile` 分支进入 `derive_new_contents_from_chunks()`（`codex-rs/apply-patch/src/lib.rs:183`，`codex-rs/apply-patch/src/lib.rs:216`，`codex-rs/apply-patch/src/lib.rs:279`，`codex-rs/apply-patch/src/lib.rs:306`）。
5. `compute_replacements()` 调 `seek_sequence(..., chunk.is_end_of_file)` 计算替换片段（`codex-rs/apply-patch/src/lib.rs:386`，`codex-rs/apply-patch/src/lib.rs:439`）。
6. `apply_replacements()` 应用替换并回写文件，最终场景 runner 对比 `expected/` 快照（`codex-rs/apply-patch/src/lib.rs:478`，`codex-rs/apply-patch/tests/suite/scenarios.rs:52`）。

### 3) EOF 匹配策略细节

`seek_sequence` 的 `eof` 参数是该场景最核心技术点：

1. 当 `eof == true` 且 `lines.len() >= pattern.len()` 时，`search_start = lines.len() - pattern.len()`，即优先从“能容纳完整 pattern 的最末端位置”开始扫描（`codex-rs/apply-patch/src/seek_sequence.rs:29`）。
2. 匹配级别分 4 层：精确匹配 -> 右裁剪空白 -> 双侧裁剪空白 -> Unicode 标点归一化匹配（`codex-rs/apply-patch/src/seek_sequence.rs:35`，`codex-rs/apply-patch/src/seek_sequence.rs:41`，`codex-rs/apply-patch/src/seek_sequence.rs:54`，`codex-rs/apply-patch/src/seek_sequence.rs:67`）。
3. 对于本场景的 2 行文件，尾部起点与开头相同（索引 0），但该 fixture 仍然验证了 `EOF marker` 端到端传递与启用，不会在未来重构时被静默移除。

### 4) 协议与文档一致性

1. 工具文档 grammar 明确定义 `*** End of File` 是可选 hunk 尾标记（`codex-rs/apply-patch/apply_patch_tool_instructions.md:49`）。
2. parser 顶部注释中的 Lark grammar 与工具文档保持一致（`codex-rs/apply-patch/src/parser.rs:4`，`codex-rs/apply-patch/src/parser.rs:21`）。
3. parser 单元测试显式覆盖 `*** End of File` 合法/非法分支（`codex-rs/apply-patch/src/parser.rs:711`，`codex-rs/apply-patch/src/parser.rs:752`）。
4. lib/invocation 单元测试覆盖 `insert_at_eof` 语义，验证 unified diff 与新内容（`codex-rs/apply-patch/src/lib.rs:949`，`codex-rs/apply-patch/src/invocation.rs:687`）。

### 5) 相关命令（研究与回归验证）

1. 跑场景全集：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 跑 crate 全测试：`cargo test -p codex-apply-patch`
3. 生成研究待办：`bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 目标目录（研究对象）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/patch.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/input/tail.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/022_update_file_end_of_file_marker/expected/tail.txt:1`

### B. 直接调用方（场景执行框架）

1. `codex-rs/apply-patch/tests/all.rs:1`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:6`

### C. 被调用方（解析与应用核心）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11`
2. `codex-rs/apply-patch/src/lib.rs:183`
3. `codex-rs/apply-patch/src/lib.rs:279`
4. `codex-rs/apply-patch/src/lib.rs:348`
5. `codex-rs/apply-patch/src/lib.rs:386`
6. `codex-rs/apply-patch/src/lib.rs:439`
7. `codex-rs/apply-patch/src/parser.rs:343`
8. `codex-rs/apply-patch/src/seek_sequence.rs:12`

### D. 配置与上层工具链依赖（上下文）

1. `codex-rs/core/src/config/mod.rs:528`（是否启用 apply_patch 工具）
2. `codex-rs/core/src/tools/spec.rs:2784`（注册 freeform/function apply_patch spec）
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:170`（handler 中二次验证 patch）
4. `codex-rs/core/src/tools/handlers/apply_patch.rs:262`（从 shell/unified_exec 拦截 apply_patch）
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69`（构建 `codex --codex-run-as-apply-patch` 执行命令）
6. `codex-rs/arg0/src/lib.rs:90`（arg0 分发到 apply_patch 执行分支）

### E. 协议、测试与脚本文档

1. `codex-rs/apply-patch/apply_patch_tool_instructions.md:40`
2. `codex-rs/apply-patch/src/parser.rs:711`
3. `codex-rs/apply-patch/src/lib.rs:949`
4. `codex-rs/apply-patch/src/invocation.rs:687`
5. `.ops/generate_daily_research_todo.sh:5`
6. `Docs/researches/blueprint_checklist.md:151`

## 依赖与外部交互

### 1) crate 依赖

`codex-apply-patch` 在该场景涉及的关键依赖（`codex-rs/apply-patch/Cargo.toml:18`）：

1. `anyhow` / `thiserror`：错误建模与上下文。
2. `similar`：`unified_diff_from_chunks` 生成统一 diff。
3. `tree-sitter` / `tree-sitter-bash`：解析 shell heredoc 形式的 apply_patch 调用。
4. `assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`：integration tests 执行基础设施。

### 2) 文件系统与进程交互

1. 场景 runner 通过 `Command::new(cargo_bin("apply_patch"))` 启动真实二进制，非 mock（`codex-rs/apply-patch/tests/suite/scenarios.rs:45`）。
2. patch 应用路径使用真实文件读写（`read_to_string` / `write` / `remove_file`），因此该场景是有效的 I/O 语义回归检查（`codex-rs/apply-patch/src/lib.rs:352`，`codex-rs/apply-patch/src/lib.rs:327`）。
3. runner 对比的是目录快照（含目录项与文件字节），不是仅比较 stdout（`codex-rs/apply-patch/tests/suite/scenarios.rs:71`）。

### 3) 与 core / runtime 的外部交互

1. 在产品路径中，`apply_patch` 不只作为二进制存在，还会被 `core` handler 预解析并做审批判断（`codex-rs/core/src/tools/handlers/apply_patch.rs:174`）。
2. 通过 `ApplyPatchRuntime` 转换为 `CommandSpec` 后执行，命令参数使用 `CODEX_CORE_APPLY_PATCH_ARG1`（`codex-rs/core/src/tools/runtimes/apply_patch.rs:91`）。
3. `arg0` 入口识别该隐藏参数后直接调用 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:90`，`codex-rs/arg0/src/lib.rs:96`）。

### 4) 构建与文档交互

1. `BUILD.bazel` 将 `apply_patch_tool_instructions.md` 作为 `compile_data` 打入目标，保障运行期可读取（`codex-rs/apply-patch/BUILD.bazel:8`）。
2. 研究流程通过 `Docs/researches/blueprint_checklist.md` + `.ops/generate_daily_research_todo.sh` 串联维护（`.ops/generate_daily_research_todo.sh:15`）。

## 风险、边界与改进建议

### 风险

1. 当前 fixture 输入很短（2 行），无法暴露“文件中重复片段时 EOF 锚定是否优于中间匹配”的真实分歧风险。
2. `scenarios` runner 不断言 exit code/stderr（只看最终文件树），某些“写入成功但错误通道异常”问题可能被漏检（`codex-rs/apply-patch/tests/suite/scenarios.rs:42`）。
3. EOF 语义同时依赖 parser 与 matcher 两层，若未来只改其中一层可能产生“语法接受但行为退化”的隐蔽回归。

### 边界

1. 本场景仅覆盖单文件、单 chunk、单次替换。
2. 不覆盖多 chunk 混合（EOF chunk + 非 EOF chunk）同文件顺序问题。
3. 不覆盖 CRLF 与编码异常、权限异常、符号链接等 I/O 边界。
4. 不覆盖 `Move to` 与 EOF marker 组合路径。

### 改进建议

1. 新增一个“重复尾段文本”的 EOF 场景，例如文件中前后两段都含 `first/second`，只有末尾段应被替换，以更直接验证 `eof=true` 的价值。
2. 为 `tests/suite/scenarios.rs` 增加可选元数据断言（如 `exit_code.txt`、`stderr.txt`），保留最终态断言同时补充行为信号。
3. 增加“`*** End of File` + `*** Move to`”组合场景，验证 `UpdateFile` 重命名时 EOF 约束在新旧路径分支上都成立。
4. 在 `scenarios/README.md` 增补“EOF marker 语义说明与典型误用”小节，降低新增场景时的语义歧义。
