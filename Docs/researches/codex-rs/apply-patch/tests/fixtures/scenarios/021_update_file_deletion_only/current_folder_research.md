# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 场景关键词：`Update File`、`deletion-only chunk`、`上下文保留删除`、`fixture e2e`

## 场景与职责

`021_update_file_deletion_only` 是 `apply_patch` 场景集中的一个“更新文件但仅删除、不新增替换行”的正向用例。它验证 `Update File` hunk 在只有 `-` 删除线时，能够基于上下文精确删掉目标行，并保持其他行不变。

该目录三类文件职责如下：

1. `patch.txt` 定义单个 `Update File` 操作，保留 `line1`、删除 `line2`、保留 `line3`（`codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/patch.txt:1`）。
2. `input/lines.txt` 提供原始文件状态（3 行）（`codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/input/lines.txt:1`）。
3. `expected/lines.txt` 定义执行后最终状态（剩余 `line1`、`line3`）（`codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/expected/lines.txt:1`）。

它在场景矩阵中的定位：

1. 与 `020_delete_file_success` 不同：`020` 测的是 `Delete File` 整文件删除；`021` 测的是 `Update File` 内部行级删除。
2. 与 `016_pure_addition_update_chunk` 对称：`016` 只新增，`021` 只删除，二者共同约束 `Update File` 的单侧变更语义。
3. 与 `022_update_file_end_of_file_marker` 区分：`021` 不依赖 `*** End of File`，关注中间行删除匹配。

## 功能点目的

该场景保护的关键行为契约是：

1. parser 必须把 `-line2` 识别为 `UpdateFileChunk.old_lines`，而不要求必须存在 `+` 行（`codex-rs/apply-patch/src/parser.rs:409`、`codex-rs/apply-patch/src/parser.rs:413`）。
2. 执行器应把该 chunk 视为“替换为更短内容”（`new_lines` 少于 `old_lines`），最终实现行删除（`codex-rs/apply-patch/src/lib.rs:459`-`codex-rs/apply-patch/src/lib.rs:467`）。
3. 上下文行 ` line1` / ` line3` 参与定位和保留，避免误删同名行或错误位置（`codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/patch.txt:4`、`:6`）。
4. 最终文件仍保持标准换行结尾（实现层总会补齐末尾换行，`codex-rs/apply-patch/src/lib.rs:373`-`codex-rs/apply-patch/src/lib.rs:376`）。

该场景主要防止两类回归：

1. 解析回归：只删不增的 update chunk 被错误判定为空或非法。
2. 应用回归：`compute_replacements` 或 `apply_replacements` 在“只删”场景下产生错位、漏删或多删。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景协议与补丁结构

该目录遵循 `scenarios` 统一 fixture 协议：每个 case 由 `input/`、`patch.txt`、`expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`-`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:7`）。

本场景补丁原文：

```patch
*** Begin Patch
*** Update File: lines.txt
@@
 line1
-line2
 line3
*** End Patch
```

技术要点：

1. `@@` 使用空上下文头，随后由具体行前缀表达上下文/删除。
2. 两条空格前缀行（` line1`、` line3`）会同时进入 `old_lines/new_lines`，用于定位且保留。
3. `-line2` 只进入 `old_lines`，表示删除该行。

### 2) 调用链（调用方 -> 被调用方）

端到端执行链路：

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*` 目录并执行每个场景（`codex-rs/apply-patch/tests/suite/scenarios.rs:11`-`codex-rs/apply-patch/tests/suite/scenarios.rs:23`）。
2. `run_apply_patch_scenario()` 把 `input/` 复制到临时目录，读取 `patch.txt`，以子进程调用 `apply_patch`（`codex-rs/apply-patch/tests/suite/scenarios.rs:30`-`codex-rs/apply-patch/tests/suite/scenarios.rs:48`）。
3. `apply_patch` 可执行入口解析 argv/stdin 后调用库函数 `apply_patch()`（`codex-rs/apply-patch/src/standalone_executable.rs:11`-`codex-rs/apply-patch/src/standalone_executable.rs:57`）。
4. `apply_patch()` 解析 patch（`parse_patch`）并进入 `apply_hunks_to_files()`（`codex-rs/apply-patch/src/lib.rs:183`-`codex-rs/apply-patch/src/lib.rs:213`，`codex-rs/apply-patch/src/lib.rs:280`）。
5. `UpdateFile` 分支调用 `derive_new_contents_from_chunks()`，计算新内容后回写（`codex-rs/apply-patch/src/lib.rs:306`-`codex-rs/apply-patch/src/lib.rs:329`）。
6. 场景 runner 对比实际目录快照与 `expected/`，以最终态为准（`codex-rs/apply-patch/tests/suite/scenarios.rs:50`-`codex-rs/apply-patch/tests/suite/scenarios.rs:58`）。

### 3) 关键数据结构与删除语义落点

1. `Hunk::UpdateFile { path, move_path, chunks }`：承载本场景唯一 hunk（`codex-rs/apply-patch/src/parser.rs:326`-`codex-rs/apply-patch/src/parser.rs:330`）。
2. `UpdateFileChunk`：
   - 上下文行进入 `old_lines` 与 `new_lines`；
   - 删除行仅进入 `old_lines`（`codex-rs/apply-patch/src/parser.rs:405`-`codex-rs/apply-patch/src/parser.rs:414`）。
3. `compute_replacements()`：匹配 `old_lines` 后生成 `(start_index, old_len, new_lines)` replacement；本场景是 `old_len > new_lines.len()` 的“收缩替换”（`codex-rs/apply-patch/src/lib.rs:386`-`codex-rs/apply-patch/src/lib.rs:473`）。
4. `apply_replacements()`：先删除旧片段再插入新片段，从而完成行删除（`codex-rs/apply-patch/src/lib.rs:478`-`codex-rs/apply-patch/src/lib.rs:499`）。
5. `AffectedPaths.modified` 与摘要 `M <path>`：删除行属于“修改文件”，不是“删除文件”（`codex-rs/apply-patch/src/lib.rs:285`、`codex-rs/apply-patch/src/lib.rs:327`、`codex-rs/apply-patch/src/lib.rs:545`-`codex-rs/apply-patch/src/lib.rs:546`）。

### 4) 协议、命令与构建/运行上下文

1. 协议文档将 `UpdateFile`/`HunkLine` 定义为 `(" " | "-" | "+")` 行语义，本场景即是标准子集（`codex-rs/apply-patch/apply_patch_tool_instructions.md:47`-`codex-rs/apply-patch/apply_patch_tool_instructions.md:50`）。
2. `codex-apply-patch` crate 暴露 `apply_patch` 二进制与库 API（`codex-rs/apply-patch/Cargo.toml:2`、`codex-rs/apply-patch/Cargo.toml:12`）。
3. Bazel target `apply-patch` 把工具说明文档作为 `compile_data` 打包（`codex-rs/apply-patch/BUILD.bazel:5`-`codex-rs/apply-patch/BUILD.bazel:10`）。
4. 场景回归常用命令：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
   - `cargo test -p codex-apply-patch`

### 5) 与上层 `core` 的联动实现（上下文依赖）

虽然本场景测试直接运行 `apply_patch` 二进制，但生产路径在 `core` 中会先验证再执行：

1. handler 在处理 tool payload 时调用 `maybe_parse_apply_patch_verified()` 产出结构化改动（`codex-rs/core/src/tools/handlers/apply_patch.rs:170`-`codex-rs/core/src/tools/handlers/apply_patch.rs:175`）。
2. `maybe_parse_apply_patch_verified()` 会把 `UpdateFile` 转换为 `ApplyPatchFileChange::Update`（含 unified diff/new content），供审批与事件展示（`codex-rs/apply-patch/src/invocation.rs:132`-`codex-rs/apply-patch/src/invocation.rs:211`）。
3. runtime 最终通过 `codex --codex-run-as-apply-patch <patch>` 执行真实写盘（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69`-`codex-rs/core/src/tools/runtimes/apply_patch.rs:93`）。
4. `arg0` 分发层接收该 arg1 并调用同一 `codex_apply_patch::apply_patch()` 实现（`codex-rs/arg0/src/lib.rs:89`-`codex-rs/arg0/src/lib.rs:99`）。

## 关键代码路径与文件引用

### A. 目标目录（研究对象）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/patch.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/input/lines.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/expected/lines.txt:1`

### B. 直接调用方（场景测试与 fixture 框架）

1. `codex-rs/apply-patch/tests/all.rs:1`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`

### C. 被调用方（解析/执行核心）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11`
2. `codex-rs/apply-patch/src/lib.rs:183`
3. `codex-rs/apply-patch/src/lib.rs:306`
4. `codex-rs/apply-patch/src/lib.rs:348`
5. `codex-rs/apply-patch/src/lib.rs:386`
6. `codex-rs/apply-patch/src/lib.rs:478`
7. `codex-rs/apply-patch/src/parser.rs:279`
8. `codex-rs/apply-patch/src/parser.rs:343`

### D. 配置、工具注册与运行时通路

1. `codex-rs/core/src/config/mod.rs:528`
2. `codex-rs/core/src/tools/spec.rs:2784`
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:174`
4. `codex-rs/apply-patch/src/invocation.rs:132`
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69`
6. `codex-rs/arg0/src/lib.rs:90`

### E. 协议文档与构建文件

1. `codex-rs/apply-patch/apply_patch_tool_instructions.md:40`
2. `codex-rs/apply-patch/Cargo.toml:1`
3. `codex-rs/apply-patch/BUILD.bazel:5`

### F. 研究流程脚本与清单

1. `Docs/researches/blueprint_checklist.md:148`
2. `.ops/generate_daily_research_todo.sh:5`

## 依赖与外部交互

### 1) crate 依赖（本场景涉及的关键能力）

`codex-apply-patch` 依赖中与此场景相关的部分（`codex-rs/apply-patch/Cargo.toml:18`-`codex-rs/apply-patch/Cargo.toml:30`）：

1. `anyhow` / `thiserror`：解析与应用阶段的错误包装与上下文。
2. `similar`：上层验证时生成 unified diff（`maybe_parse_apply_patch_verified` 路径会用到）。
3. `tree-sitter` / `tree-sitter-bash`：支持 shell/heredoc 的 apply_patch 识别与抽取。
4. `assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`：集成测试基础设施。

### 2) 文件系统与进程交互

1. 场景测试通过子进程执行真实 `apply_patch`，不是 mock（`codex-rs/apply-patch/tests/suite/scenarios.rs:45`-`codex-rs/apply-patch/tests/suite/scenarios.rs:48`）。
2. 更新逻辑读文件、算 replacement、重写文件（`codex-rs/apply-patch/src/lib.rs:352`、`codex-rs/apply-patch/src/lib.rs:370`、`codex-rs/apply-patch/src/lib.rs:327`）。
3. runner 使用目录快照（文件字节 + 目录项）比较最终态，跨实现可移植（`codex-rs/apply-patch/tests/suite/scenarios.rs:65`-`codex-rs/apply-patch/tests/suite/scenarios.rs:102`）。

### 3) 与 `core`/审批/沙箱的外部交互

1. `core` 会先做 patch 结构化验证，再进入审批/执行编排，不直接盲跑 shell（`codex-rs/core/src/tools/handlers/apply_patch.rs:174`-`codex-rs/core/src/tools/handlers/apply_patch.rs:237`）。
2. runtime 支持 guardian 或用户审批路径，决定是否直接执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:129`-`codex-rs/core/src/tools/runtimes/apply_patch.rs:175`）。
3. 真正执行命令在受控 `CommandSpec` 与 sandbox 环境中完成（`codex-rs/core/src/tools/runtimes/apply_patch.rs:88`-`codex-rs/core/src/tools/runtimes/apply_patch.rs:214`）。

### 4) 脚本与文档交互

1. 研究任务完成状态由 `blueprint_checklist.md` 管理。
2. `.ops/generate_daily_research_todo.sh` 从 checklist 抽取未完成项生成当日 TODO（`.ops/generate_daily_research_todo.sh:15`-`.ops/generate_daily_research_todo.sh:39`）。

## 风险、边界与改进建议

### 风险

1. `scenarios` runner 不断言进程退出码或 stderr，仅按最终文件树断言；如果出现“状态正确但错误通道异常”不会被直接捕获（`codex-rs/apply-patch/tests/suite/scenarios.rs:42`-`codex-rs/apply-patch/tests/suite/scenarios.rs:48`）。
2. 该场景仅覆盖单文件、单删除行，无法发现多处重复文本下的潜在定位歧义问题。
3. 目录编号存在双 `020_*`（`020_delete_file_success` 与 `020_whitespace_padded_patch_marker_lines`），不影响执行但增加人工检索混淆成本。

### 边界

1. 不覆盖失败路径（缺失文件、目录删除、权限不足），这些由其他场景承担。
2. 不覆盖 `*** End of File`、多 chunk 交错、移动文件等组合语义。
3. 不覆盖 core 的权限策略差异，仅验证 `apply_patch` 工具行为与最终态。

### 改进建议

1. 为 `scenarios` 框架增加可选 `exit_code` 与 `stderr_contains` 断言文件，保持最终态断言同时提升可观测性。
2. 增加一个“同一文件多删除块（含重复文本）”fixture，强化 `seek_sequence + replacement` 定位稳定性验证。
3. 给场景目录名增加唯一序号规范（避免重复编号），降低维护成本与文档交叉引用歧义。
4. 在 `scenarios/README.md` 增加“Update File 单侧变更矩阵（仅加/仅删/仅上下文）”说明，便于后续补齐覆盖缺口。
