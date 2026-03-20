# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/expected`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 所属模块：`codex-rs/apply-patch`（crate：`codex-apply-patch`）
- 目录内文件：`input.txt`

## 场景与职责

该目录是场景 `016_pure_addition_update_chunk` 的期望输出快照目录（`expected/`），用于定义“对已有文件执行 `Update File`，且 chunk 仅包含新增行（`+`）时，新增内容应追加到文件末尾”的行为基线。

从场景三件套可看到完整语义：

1. 初始文件：`input/input.txt` 只有两行 `line1`、`line2`（`codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/input/input.txt:1-2`）。
2. 补丁：`patch.txt` 是 `*** Update File: input.txt` + `@@` + 两行 `+added line`（`codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/patch.txt:1-6`）。
3. 期望结果：`expected/input.txt` 为原两行后追加两行（`codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/expected/input.txt:1-4`）。

在测试体系里，该目录承担“最终文件系统状态真值（oracle）”职责：

1. `tests/suite/scenarios.rs` 会遍历 fixtures，复制 `input/` 到临时目录，执行 `apply_patch`，再将临时目录与 `expected/` 做字节级快照对比（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-60`）。
2. 因为 runner 以最终状态为准、不强制检查 exit status（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`），所以 `expected/` 的文件内容直接决定场景通过与否。

## 功能点目的

该 `expected/` 目录锁定的是一个细粒度但高风险的行为分支：`UpdateFileChunk.old_lines.is_empty()`（纯新增 chunk）时的插入策略。

主要目的：

1. 防止 parser/执行链把“纯新增 update chunk”误判为非法 hunk。
2. 防止执行层在无删除行时错误定位插入位置（例如误插入到文件头、中间，或行为依赖上下文偶然性）。
3. 保证末尾换行策略稳定：最终内容以 `\n` 结尾。

与相邻场景的边界分工：

1. 相对 `001_add_file`：该场景不是创建新文件，而是更新已有文件。
2. 相对 `021_update_file_deletion_only`：该场景只验证新增，不验证纯删除。
3. 相对 `022_update_file_end_of_file_marker`：该场景不依赖 `*** End of File` 标记，验证默认追加路径。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景协议与文件组织

fixtures 协议在 `scenarios/README.md` 定义：每个场景由 `input/`、`patch.txt`、`expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-17`）。

本目录是该协议中的 `expected/` 端，当前只有一个目标文件 `input.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/expected/input.txt:1-4`）。

### 2) 调用方流程（tests/suite/scenarios.rs）

关键执行步骤：

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*` 并逐个调用 `run_apply_patch_scenario`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 将 `input/` 复制到 `tempdir`（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`）。
3. 读取 `patch.txt`，启动 `apply_patch` 二进制执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
4. `snapshot_dir()` + `snapshot_dir_recursive()` 把目录转成 `BTreeMap<PathBuf, Entry>`，其中 `Entry::File(Vec<u8>)` 进行字节级比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-105`）。
5. 最终断言 `actual_snapshot == expected_snapshot`（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。

这意味着：`expected/input.txt` 的每个字节（包含换行）都属于稳定契约。

### 3) 被调用方流程（apply_patch 可执行入口）

`apply_patch` 入口在 `standalone_executable.rs`：

1. 接收 argv 或 stdin 的 patch 文本（`codex-rs/apply-patch/src/standalone_executable.rs:11-41`）。
2. 调用 `crate::apply_patch(&patch_arg, &mut stdout, &mut stderr)`（`codex-rs/apply-patch/src/standalone_executable.rs:49-57`）。

对应 crate 声明：

1. 二进制名 `apply_patch`（`codex-rs/apply-patch/Cargo.toml:11-13`）。
2. Bazel 目标 `apply-patch` 导出工具说明文档作为 `compile_data`（`codex-rs/apply-patch/BUILD.bazel:1-11`）。

### 4) 解析层（parser）如何表示“纯新增 update chunk”

在 `parse_update_file_chunk()`：

1. `@@` 被解析为 `change_context: None`（`codex-rs/apply-patch/src/parser.rs:356-357`）。
2. 以 `+` 开头的行只进入 `new_lines`（`codex-rs/apply-patch/src/parser.rs:409-411`）。
3. 因没有 `-` 行，`old_lines` 保持空向量。

因此该场景会形成 `UpdateFileChunk { old_lines: vec![], new_lines: vec!["added line 1", "added line 2"], ... }`。

解析侧已有相关回归测试：

1. `@@` + `+line` 后接新 hunk 的用例（`codex-rs/apply-patch/src/parser.rs:528-558`）。
2. `parse_update_file_chunk(&["@@", "+line", "*** End of File"], ...)` 结果验证（`codex-rs/apply-patch/src/parser.rs:752-761`）。

### 5) 应用层（lib.rs）如何得到 `expected/input.txt`

关键在 `compute_replacements()`：

1. 当 `chunk.old_lines.is_empty()`，走纯新增分支（`codex-rs/apply-patch/src/lib.rs:414`）。
2. 插入位置 `insertion_idx` 默认取文件尾（若末尾有空行则在其前一位，否则在 `len()`）（`codex-rs/apply-patch/src/lib.rs:417-421`）。
3. 记录 replacement 为 `(insertion_idx, 0, chunk.new_lines.clone())`（`codex-rs/apply-patch/src/lib.rs:422`）。

随后：

1. `apply_replacements()` 以倒序应用 replacement，避免索引漂移（`codex-rs/apply-patch/src/lib.rs:482-499`）。
2. `derive_new_contents_from_chunks()` 在最终行集末尾补齐空行，再 `join("\n")`，保证文件以换行结束（`codex-rs/apply-patch/src/lib.rs:373-377`）。

该逻辑直接对应本目录目标文件：

- `line1\nline2\n` 变为 `line1\nline2\nadded line 1\nadded line 2\n`。

应用层相关回归测试：

1. `test_pure_addition_chunk_followed_by_removal` 覆盖“纯新增 chunk + 后续替换 chunk”顺序行为（`codex-rs/apply-patch/src/lib.rs:765-789`）。
2. `test_unified_diff_insert_at_eof` 覆盖 EOF 插入的 diff 与内容结果（`codex-rs/apply-patch/src/lib.rs:950-981`）。

### 6) 上游集成链路（core/arg0/config）

虽然本场景是 `codex-apply-patch` fixtures，但其语义被上游直接消费：

1. `core` 的 apply_patch handler 会先调用 `maybe_parse_apply_patch_verified` 预检并计算变更（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`，`codex-rs/apply-patch/src/invocation.rs:132-217`）。
2. 若需真实执行，runtime 构造 `codex <CODEX_CORE_APPLY_PATCH_ARG1> <patch>` 命令（`codex-rs/core/src/tools/runtimes/apply_patch.rs:88-99`）。
3. `arg0` 通过 `CODEX_CORE_APPLY_PATCH_ARG1` 分发到 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:89-107`）。
4. 工具注册受 `config.apply_patch_tool_type` 与 handler 注册控制（`codex-rs/core/src/tools/spec.rs:2784-2804`），并受配置项 `include_apply_patch_tool` 影响（`codex-rs/core/src/config/mod.rs:528-531`）。

### 7) 研究任务相关命令/脚本

本次任务关联脚本：

1. `bash .ops/generate_daily_research_todo.sh`：从 `Docs/researches/blueprint_checklist.md` 统计并生成当日 todo（`.ops/generate_daily_research_todo.sh:1-42`）。
2. checklist 当前目标行是第 131 行（`Docs/researches/blueprint_checklist.md:131`）。

建议验证命令：

1. `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. `cargo test -p codex-apply-patch`

## 关键代码路径与文件引用

### A. 目标对象与同场景输入

1. `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/expected/input.txt:1-4`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/input/input.txt:1-2`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/patch.txt:1-6`

### B. 直接调用方（测试框架）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-60`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:65-126`
3. `codex-rs/apply-patch/tests/all.rs:1-3`
4. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`

### C. 被调用方（解析与应用）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/parser.rs:343-430`
3. `codex-rs/apply-patch/src/lib.rs:386-423`
4. `codex-rs/apply-patch/src/lib.rs:482-499`
5. `codex-rs/apply-patch/src/lib.rs:370-377`

### D. 上游集成与配置

1. `codex-rs/apply-patch/src/invocation.rs:132-217`
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-257`
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:88-101`
4. `codex-rs/arg0/src/lib.rs:89-107`
5. `codex-rs/core/src/tools/spec.rs:2784-2804`
6. `codex-rs/core/src/config/mod.rs:528-531`

### E. 文档、构建与脚本

1. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-17`
2. `codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`
3. `codex-rs/apply-patch/Cargo.toml:1-30`
4. `codex-rs/apply-patch/BUILD.bazel:1-11`
5. `.ops/generate_daily_research_todo.sh:1-42`
6. `Docs/researches/blueprint_checklist.md:131`

## 依赖与外部交互

### 1) 依赖

`codex-apply-patch` 核心依赖：

1. `anyhow` / `thiserror`：错误封装和上下文传播（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. `similar`：unified diff 生成（`codex-rs/apply-patch/Cargo.toml:20`）。
3. `tree-sitter` / `tree-sitter-bash`：shell heredoc 形式解析（`codex-rs/apply-patch/Cargo.toml:22-23`）。

测试依赖：`assert_cmd`、`tempfile`、`codex-utils-cargo-bin`、`pretty_assertions`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 文件系统交互

1. fixtures runner 在临时目录进行真实复制/写入/读取，非 mock（`codex-rs/apply-patch/tests/suite/scenarios.rs:31-48`）。
2. 目录比对采用 `Vec<u8>` 字节快照，不仅比较文本语义（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-105`）。
3. `expected/input.txt` 作为稳定快照，任何换行或内容差异都会导致断言失败。

### 3) 进程与运行时交互

1. 测试通过 `cargo_bin("apply_patch")` 启动独立进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:45`）。
2. core 运行链通过 `arg0` 派发标志二次进入同一 apply_patch 核心逻辑（`codex-rs/core/src/tools/runtimes/apply_patch.rs:90-93`，`codex-rs/arg0/src/lib.rs:90-99`）。

### 4) 与研究流程脚本交互

1. checklist 用于记录研究完成态（本目标在第 131 行）。
2. `generate_daily_research_todo.sh` 根据 checklist 重新生成每日待办，反映最新 pending 列表（`.ops/generate_daily_research_todo.sh:15-39`）。

## 风险、边界与改进建议

### 风险

1. 语义认知风险：纯新增 chunk 当前默认“尾部插入”，若调用者期望“按 context 定位插入”会产生偏差。
2. 覆盖风险：本目录只表达成功路径的最终快照，不覆盖 stderr/exit code 通道回归。
3. 行尾风险：若未来换行策略被修改（例如不强制补尾换行），该场景会直接失败，可能与外部预期不一致。

### 边界

1. 仅覆盖单文件、单 update hunk、纯新增两行。
2. 不覆盖 CRLF、超大文件、权限错误、符号链接、并发改写等 I/O 边界。
3. 不覆盖“带 `change_context` 且 `old_lines` 为空”的插入定位语义。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 增补“`old_lines` 为空时默认 EOF 追加”的显式约定，减少调用方误解。
2. 在 fixtures 中新增“`@@ context` + 纯新增”的场景，明确 context 与 pure-add 分支的交互行为。
3. 为 `scenarios` runner 增加可选元数据断言（如 `exit_code` / `stderr_contains`），与状态快照形成双轨覆盖。
4. 若产品层需要“按上下文插入而非默认尾插”，可在 `compute_replacements` 的 pure-add 分支引入可配置策略（例如优先使用 `line_index`）。
