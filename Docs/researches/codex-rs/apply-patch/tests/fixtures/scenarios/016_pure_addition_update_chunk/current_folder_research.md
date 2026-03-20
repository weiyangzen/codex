# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 场景关键词：`UpdateFile`、`pure addition chunk`、`append semantics`

## 场景与职责

该目录是 `apply_patch` fixtures 中专门验证“`Update File` 里只有 `+` 行（无 `-` 行、无上下文行）”的端到端场景。

目录内三类文件分别承担固定职责：

1. `patch.txt`：定义一个 `*** Update File: input.txt` 的补丁块，chunk 为 `@@` 后连续两行 `+added line`（`codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/patch.txt:1-6`）。
2. `input/input.txt`：初始文件状态 `line1\nline2`（`codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/input/input.txt:1-2`）。
3. `expected/input.txt`：期望输出为原内容后追加两行（`codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/expected/input.txt:1-4`）。

在测试矩阵中，该场景的职责是补齐“update 形式的纯新增”语义：

1. 与 `001_add_file` 区分：这里不是新增文件，而是更新已有文件。
2. 与 `022_update_file_end_of_file_marker` 区分：这里没有 `*** End of File` 标记，验证默认追加路径。
3. 与 `021_update_file_deletion_only` 区分：这里没有删除线，验证 `old_lines` 为空分支。

## 功能点目的

该场景保护的核心契约是：

1. `UpdateFileChunk.old_lines` 为空时，`apply_patch` 应将 `new_lines` 作为插入片段处理，而不是报 “missing context”。
2. 默认插入位置为文件尾部（并由实现补齐末尾换行）。
3. 该行为要在 fixture 级真实进程执行下可观测，而不只是单元测试里的内部函数行为。

更具体地说，它防回归两类问题：

1. 解析层回归：`@@` + `+line` 可能被误判为非法 update hunk。
2. 应用层回归：`old_lines.is_empty()` 分支可能错误计算插入位置，导致内容插到头部/中部或触发 panic。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景协议与补丁语法

本场景补丁：

```patch
*** Begin Patch
*** Update File: input.txt
@@
+added line 1
+added line 2
*** End Patch
```

协议来源：

1. fixture 规范：每个场景由 `input/`、`patch.txt`、`expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-17`）。
2. apply-patch 语法：`Update File` + `Hunk(@@)` + `HunkLine(+/-/ )`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`，`codex-rs/apply-patch/src/parser.rs:6-21`）。

### 2) 调用方流程（fixtures runner）

`tests/suite/scenarios.rs` 对目录执行流程为：

1. 复制 `input/` 到 `tempdir`（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`）。
2. 读取 `patch.txt` 字符串（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-40`）。
3. 启动 `apply_patch` 子进程，`current_dir = tempdir`（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
4. 比较 `tempdir` 与 `expected/` 的目录快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-58`）。

注意：该 runner 故意不校验 exit status，仅以最终文件树为准（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-44`）。

### 3) 解析实现（被调用方上游）

`parser` 侧关键点：

1. `parse_one_hunk` 识别 `*** Update File:` 后循环解析 chunk（`codex-rs/apply-patch/src/parser.rs:279-333`）。
2. `parse_update_file_chunk` 在 `@@` 之后读到 `+` 行时：
   - `old_lines` 不增加
   - `new_lines` 追加对应文本（`codex-rs/apply-patch/src/parser.rs:356-414`）
3. 本场景最终得到 `UpdateFileChunk { change_context: None, old_lines: [], new_lines: ["added line 1", "added line 2"], is_end_of_file: false }`。

同语义 parser 测试可见：

1. `parse_patch` 支持 `@@` + `+line` 的 update chunk（`codex-rs/apply-patch/src/parser.rs:530-551`）。
2. `parse_update_file_chunk` 支持纯新增行并可带 EOF marker（`codex-rs/apply-patch/src/parser.rs:752-760`）。

### 4) 应用实现（核心语义）

`lib.rs` 更新路径关键流程：

1. `apply_patch` -> `apply_hunks` -> `apply_hunks_to_files`（`codex-rs/apply-patch/src/lib.rs:183-213`，`216-333`）。
2. `UpdateFile` 分支调用 `derive_new_contents_from_chunks` 计算新内容（`codex-rs/apply-patch/src/lib.rs:306-313`，`348-381`）。
3. `compute_replacements` 命中 `chunk.old_lines.is_empty()` 分支时，将 replacement 记为插入操作：
   - `old_len = 0`
   - `new_lines = chunk.new_lines.clone()`
   - 插入点默认取文件尾（`codex-rs/apply-patch/src/lib.rs:414-423`）。
4. `apply_replacements` 用“倒序应用 replacements”避免索引漂移（`codex-rs/apply-patch/src/lib.rs:482-499`）。
5. 最后统一补齐尾换行：若最后不是空行，推入空字符串再 `join("\n")`（`codex-rs/apply-patch/src/lib.rs:373-377`）。

这正对应本场景 `expected/input.txt` 的“追加两行并以换行结束”结果。

### 5) 与上层调用链、配置、脚本的关系

虽然 fixture 直接跑 `apply_patch` 二进制，但上层 `core` 也依赖同一 crate 的解析/验证逻辑：

1. `core` handler 先调 `maybe_parse_apply_patch_verified` 做预解析和差异计算（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`，`codex-rs/apply-patch/src/invocation.rs:132-217`）。
2. 通过后再由 runtime 执行 `codex --codex-run-as-apply-patch <patch>`（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`，`codex-rs/arg0/src/lib.rs:89-107`）。
3. `Config.include_apply_patch_tool` 与 `config.apply_patch_tool_type` 决定是否暴露/注册 apply_patch 工具（`codex-rs/core/src/config/mod.rs:528-531`，`codex-rs/core/src/tools/spec.rs:2784-2804`）。

研究流程脚本侧，本任务完成后需要：

1. 更新 checklist（`Docs/researches/blueprint_checklist.md`）。
2. 运行 `.ops/generate_daily_research_todo.sh` 重新生成当日 TODO（`.ops/generate_daily_research_todo.sh:1-42`）。

### 6) 相关命令（研究/验证）

1. 运行场景集合：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 运行 crate 测试：`cargo test -p codex-apply-patch`
3. 刷新研究 todo：`bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 目标目录（研究对象）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/patch.txt:1-6`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/input/input.txt:1-2`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/expected/input.txt:1-4`

### B. 调用方（tests / fixture runner）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-60`
2. `codex-rs/apply-patch/tests/all.rs:1-3`
3. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`

### C. 被调用方（解析/应用）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:279-333`
4. `codex-rs/apply-patch/src/lib.rs:348-423`
5. `codex-rs/apply-patch/src/lib.rs:478-502`
6. `codex-rs/apply-patch/src/parser.rs:279-334`
7. `codex-rs/apply-patch/src/parser.rs:343-434`

### D. 相关测试与文档

1. `codex-rs/apply-patch/src/lib.rs:764-789`（`test_pure_addition_chunk_followed_by_removal`）
2. `codex-rs/apply-patch/src/lib.rs:949-981`（`test_unified_diff_insert_at_eof`）
3. `codex-rs/apply-patch/src/parser.rs:530-551`（纯新增 update chunk 解析）
4. `codex-rs/apply-patch/src/parser.rs:752-760`（`+line` + EOF marker）
5. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
6. `codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`

### E. 上下文依赖（core/arg0/config/脚本）

1. `codex-rs/apply-patch/src/invocation.rs:132-217`
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-257`
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-215`
4. `codex-rs/core/src/config/mod.rs:528-531`
5. `codex-rs/core/src/tools/spec.rs:2784-2804`
6. `codex-rs/arg0/src/lib.rs:85-107`
7. `.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

### 1) crate 依赖

`codex-apply-patch` 在该场景涉及的关键依赖：

1. 解析/错误处理：`thiserror`、`anyhow`
2. unified diff 生成：`similar`
3. shell heredoc 解析：`tree-sitter`、`tree-sitter-bash`
4. 测试执行：`assert_cmd`、`tempfile`、`codex-utils-cargo-bin`、`pretty_assertions`
（见 `codex-rs/apply-patch/Cargo.toml:18-30`）

### 2) 文件系统与进程交互

1. fixture runner 会在临时目录复制输入并执行子进程。
2. `apply_patch` 执行时直接进行 `read_to_string` / `write` 等真实 I/O。
3. 目录快照比较基于字节内容与目录项，避免只比较文本语义。

### 3) 与外部模块交互

1. 与 `arg0`：通过 `CODEX_CORE_APPLY_PATCH_ARG1` 支持内部自调用执行。
2. 与 `core`：通过 `maybe_parse_apply_patch_verified` 产出结构化变更给审批/沙箱流程。
3. 与测试基建：`repo_root()` + `cargo_bin("apply_patch")` 保障 Cargo/Bazel 路径可解析。

### 4) 与文档/脚本交互

1. 补丁格式契约由 `apply_patch_tool_instructions.md` 和 parser grammar 双重定义。
2. 研究任务完成态通过 `blueprint_checklist.md` 与每日 todo 生成脚本串联维护。

## 风险、边界与改进建议

### 风险

1. 纯新增 chunk 语义当前是“默认追加到文件尾”，若调用者期望“在 context 处插入”会出现认知偏差。
2. `compute_replacements` 在 `old_lines.is_empty()` 分支忽略 `line_index` 与 `change_context`，即使提供上下文也不会改变插入点（`codex-rs/apply-patch/src/lib.rs:414-423`）。
3. fixture runner 不校验退出码和 stderr，失败通路信息退化不会被该类场景及时发现（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。

### 边界

1. 本场景只覆盖“单文件、单 chunk、纯追加”。
2. 不覆盖 CRLF、只读文件、符号链接、超大文件等 I/O 边界。
3. 不覆盖多纯新增 chunk 与混合 chunk 的插入顺序复杂情况（虽然 `lib.rs` 有相关单测覆盖一部分）。

### 改进建议

1. 在协议文档中明确“`old_lines` 为空时默认尾部插入”的行为，避免与直觉 diff 语义混淆。
2. 如希望支持“带 context 的插入点控制”，可在 `old_lines.is_empty()` 分支优先采用 `line_index`（或 context 匹配结果）计算 `insertion_idx`。
3. 为 fixture 框架增加可选元数据断言（`exit_code` / `stderr_contains`），让状态断言与错误通道并行覆盖。
4. 可新增一个场景验证“pure-add chunk + 显式 `@@ context`”的定位行为，避免未来修改时语义漂移。
