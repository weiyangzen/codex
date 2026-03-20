# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 场景关键词：`partial success`、`non-transactional apply`、`failure leaves prior changes`

## 场景与职责

该目录是 `apply_patch` fixtures 中用于锁定“补丁中途失败时，前序已生效改动不回滚”的专门场景。

目录内容很小但语义明确：

1. `patch.txt` 先执行 `Add File created.txt`，再执行 `Update File missing.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/patch.txt:1-8`）。
2. 目录没有 `input/`，意味着场景初始态为空工作目录（由 `scenarios` runner 的“仅在 input 存在时复制”逻辑决定，`codex-rs/apply-patch/tests/suite/scenarios.rs:34-37`）。
3. `expected/created.txt` 只保留第一步新增文件，表达“整体命令失败，但前序改动保留”（`codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/expected/created.txt:1`）。

它在测试矩阵中的职责是补齐事务边界语义：

1. `001/002/003` 等场景覆盖成功路径。
2. `005/006/007/009/012/013` 等覆盖失败路径。
3. `015` 单独覆盖“失败 + 已有副作用”这一高风险组合，避免调用方误以为 `apply_patch` 是原子事务。

另有代码驱动对照测试 `test_apply_patch_cli_failure_after_partial_success_leaves_changes`，显式断言命令失败且 `created.txt` 仍存在（`codex-rs/apply-patch/tests/suite/tool.rs:243-255`）。

## 功能点目的

该场景要保护的契约不是“失败即零改动”，而是“按 hunk 顺序执行，失败时停止，但不回滚前序成功落盘”。

具体目的：

1. 固化 CLI 实际行为，防止未来误改成 silent rollback 或 silently continue。
2. 告诉上层调用方：`apply_patch` 的错误返回仅表示“未全部成功”，不代表文件系统无变化。
3. 让 fixture 层与单测层形成互补：
- fixture 层：只看最终文件树，强调落盘结果（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-60`）。
- tool 层：看退出状态与 stderr 文案（`codex-rs/apply-patch/tests/suite/tool.rs:247-253`）。

同时，本场景也暴露了一个上下文差异：

1. 裸 `apply_patch` CLI：先执行再失败，可能留下部分改动。
2. `codex-rs/core` 里的 `apply_patch` 工具链：先 `maybe_parse_apply_patch_verified` 预检全部变更，再决定是否执行；像本场景这种 `missing.txt` 更新在预检阶段就会失败，通常不会落下前序新增（`codex-rs/apply-patch/src/invocation.rs:132-205`，`codex-rs/core/src/tools/handlers/apply_patch.rs:170-178`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 协议与补丁内容

场景补丁：

```patch
*** Begin Patch
*** Add File: created.txt
+hello
*** Update File: missing.txt
@@
-old
+new
*** End Patch
```

语法来自 apply-patch 协议：`Begin/End` 包裹、多 file op 串行、`Update` 使用 `@@` chunk（`codex-rs/apply-patch/apply_patch_tool_instructions.md:6-50`，`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`）。

parser 解析后对应 `Hunk` 序列：

1. `Hunk::AddFile { path, contents }`
2. `Hunk::UpdateFile { path, chunks, .. }`

见 `Hunk` 数据结构与 `parse_one_hunk` 分支（`codex-rs/apply-patch/src/parser.rs:58-76`，`codex-rs/apply-patch/src/parser.rs:248-333`）。

### 2) fixture 执行流程（调用方）

`test_apply_patch_scenarios` 流程：

1. 遍历 `tests/fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 若有 `input/` 才复制；本场景无 `input/`，因此 tempdir 初始为空（`codex-rs/apply-patch/tests/suite/scenarios.rs:34-37`）。
3. 启动 `apply_patch <patch>` 子进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
4. 关键点：故意不检查 exit status，仅比较最终目录快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-44`，`50-60`）。

这正好让 `015` 能表达“失败但保留 created.txt”。

### 3) CLI 执行内核（被调用方）

入口链：

1. `standalone_executable::run_main` 读参数并调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
2. `apply_patch` 先 parse，再 `apply_hunks`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
3. `apply_hunks` 调用 `apply_hunks_to_files` 串行落盘（`codex-rs/apply-patch/src/lib.rs:247-249`，`279-333`）。

`015` 的关键行为来自 `apply_hunks_to_files` 的 for-loop 顺序语义（`codex-rs/apply-patch/src/lib.rs:287-333`）：

1. 第一个 `AddFile` 直接 `std::fs::write(path, contents)`，文件已落盘（`codex-rs/apply-patch/src/lib.rs:289-299`）。
2. 第二个 `UpdateFile` 调 `derive_new_contents_from_chunks`，内部先 `read_to_string(missing.txt)`；该文件不存在时返回 `ApplyPatchError::IoError`（`codex-rs/apply-patch/src/lib.rs:311-313`，`348-359`）。
3. 错误回传后 `apply_hunks` 输出 stderr 并返回失败，不触发任何回滚（`codex-rs/apply-patch/src/lib.rs:253-264`）。

因此最终状态是：进程失败 + `created.txt` 仍在。

### 4) 关键数据结构

1. `Hunk`：表达 add/delete/update 三类文件操作（`codex-rs/apply-patch/src/parser.rs:58-76`）。
2. `UpdateFileChunk`：表达 update 的上下文与 old/new 行（`codex-rs/apply-patch/src/parser.rs:90-104`）。
3. `AffectedPaths`：成功完成时用于 summary 输出；本场景失败，因此不会走成功 summary（`codex-rs/apply-patch/src/lib.rs:271-275`，`248-252`）。
4. fixture 快照 `Entry::{File, Dir}`：以字节级比较最终文件树（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-77`）。

### 5) 与 core 集成路径的差异（配置/调用链上下文）

`codex-rs/core` 对 `apply_patch` 的调用并非直接“盲执行 patch”，而是先做 verified 解析：

1. handler 收到 patch 后调用 `maybe_parse_apply_patch_verified`（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`）。
2. verified 会为每个 hunk 预计算变更；对 `UpdateFile` 会调用 `unified_diff_from_chunks`，间接读取目标文件，缺失即报错（`codex-rs/apply-patch/src/invocation.rs:184-194`）。
3. handler 在 `CorrectnessError` 分支直接报 `apply_patch verification failed`，不进入 runtime 执行（`codex-rs/core/src/tools/handlers/apply_patch.rs:241-244`）。
4. 只有 verified 成功才可能由 runtime 以 `codex --codex-run-as-apply-patch <patch>` 真正执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`，`codex-rs/arg0/src/lib.rs:89-107`）。

相关配置入口：`Config.include_apply_patch_tool` 决定是否暴露该工具（`codex-rs/core/src/config/mod.rs:528-531`），并在工具注册时依据 `apply_patch_tool_type` 绑定 handler（`codex-rs/core/src/tools/spec.rs:2784-2804`）。

### 6) 关键命令（本场景相关）

1. 场景批量执行：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 单测对照执行：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_failure_after_partial_success_leaves_changes -- --exact`
3. 研究流程脚本：`bash .ops/generate_daily_research_todo.sh`（`.ops/generate_daily_research_todo.sh:1-42`）

## 关键代码路径与文件引用

### A. 目标目录（研究对象）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/patch.txt:1-8`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/expected/created.txt:1`

### B. 直接调用方（测试入口）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-60`
2. `codex-rs/apply-patch/tests/suite/tool.rs:243-255`
3. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
4. `codex-rs/apply-patch/tests/all.rs:1-3`

### C. 被调用方（apply_patch 实现）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:247-333`
4. `codex-rs/apply-patch/src/lib.rs:348-359`
5. `codex-rs/apply-patch/src/parser.rs:58-76`
6. `codex-rs/apply-patch/src/parser.rs:248-333`

### D. 上下文依赖（core/arg0/config）

1. `codex-rs/apply-patch/src/invocation.rs:132-217`
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-244`
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`
4. `codex-rs/core/src/apply_patch.rs:36-77`
5. `codex-rs/arg0/src/lib.rs:85-107`
6. `codex-rs/core/src/config/mod.rs:528-531`
7. `codex-rs/core/src/tools/spec.rs:2784-2804`

### E. 协议/文档/构建/脚本

1. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`
2. `codex-rs/apply-patch/apply_patch_tool_instructions.md:6-50`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
4. `codex-rs/apply-patch/Cargo.toml:1-30`
5. `codex-rs/apply-patch/BUILD.bazel:1-11`
6. `.ops/generate_daily_research_todo.sh:1-42`
7. `Docs/researches/blueprint_checklist.md:128`

## 依赖与外部交互

### 1) crate 依赖

`codex-apply-patch` 依赖：

1. 运行时：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试时：`assert_cmd`、`codex-utils-cargo-bin`、`pretty_assertions`、`tempfile`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 文件系统/进程交互

1. fixture runner 在临时目录执行真实文件读写和进程调用（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-53`）。
2. `apply_patch` 在执行期直接进行 `write/remove/read`，失败由 OS I/O 返回（`codex-rs/apply-patch/src/lib.rs:289-329`，`348-359`）。
3. 该场景依赖“无 input 初始态”；`expected` 只保留新增文件用于断言副作用。

### 3) 与 core 生态交互

1. handler/runtime/arg0 形成完整执行链，允许审批、事件上报、沙箱执行（`codex-rs/core/src/tools/handlers/apply_patch.rs:185-237`，`codex-rs/core/src/tools/runtimes/apply_patch.rs:122-215`，`codex-rs/arg0/src/lib.rs:89-107`）。
2. 但本场景语义在 core 常被 pre-verify 截断（`invocation.rs` 的预计算），因此“部分成功”主要是裸 CLI 语义，而非所有上层路径都可复现。

### 4) 研究流程脚本交互

1. 本任务完成后需要勾选 checklist 并重建当日 todo。
2. todo 由脚本按 checklist 正则实时重写（`.ops/generate_daily_research_todo.sh:15-39`）。

## 风险、边界与改进建议

### 风险

1. 非事务性风险：补丁失败不代表无副作用；上层若以“失败即安全”处理可能产生数据偏差。
2. fixture runner 风险：当前不检查退出码/stderr，某些错误通道回归可能被漏掉（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。
3. 语义分叉风险：core 预检路径与裸 CLI 路径在“何时失败、是否部分落盘”上存在差异，易导致调用方认知不一致。

### 边界

1. 本场景仅覆盖 `Add` 成功 + `Update missing` 失败；不覆盖 `Delete` 或 `Move` 的部分成功组合。
2. 不覆盖跨平台错误文案差异（如 Windows I/O 报错文本）。
3. 不覆盖并发修改或文件权限竞争。

### 改进建议

1. 在 `scenarios` 框架增加可选断言元数据（例如 `exit_code.txt`、`stderr_contains.txt`），让本场景既验证最终态，也验证失败通道。
2. 在 `apply_patch_tool_instructions.md` 或 crate 文档明确写出“当前实现为顺序应用、非事务回滚”。
3. 若产品需要原子语义，可考虑新增模式：
- 先在内存预演全部 hunk（含文件存在性与可写性检查）；
- 全部通过后再统一落盘；
- 或提供 `--atomic` 选项供调用方选择。
4. 为 core 增加一条显式测试，说明其 pre-verify 行为与裸 CLI 差异是“有意设计”还是“待统一行为”，避免后续误回归。
