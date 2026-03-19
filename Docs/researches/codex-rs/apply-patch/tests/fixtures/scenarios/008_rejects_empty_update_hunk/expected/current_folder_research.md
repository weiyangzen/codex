# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/expected` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是场景 `008_rejects_empty_update_hunk` 的“期望结果快照目录（oracle）”，当前只包含一个文件：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/expected/foo.txt`

它不承载执行逻辑，而是承载断言语义：当 patch 只有 `*** Update File: foo.txt` 且没有任何 update chunk 时，`apply_patch` 必须在解析阶段失败，因此最终文件系统状态应与输入完全一致。`expected/foo.txt` 的值 `stable` 正是这个“不发生写入副作用”的判据。

在测试职责分层里，`expected/` 的角色是：

1. 作为 `tests/suite/scenarios.rs` 的状态比较基准，和临时执行目录逐字节对比（`snapshot_dir`）。
2. 与 `input/foo.txt` 构成“前后相同”的负向场景断言，证明失败点发生在落盘前。
3. 为跨语言/跨平台复用提供静态样例，和 `scenarios/README.md` 的 fixture 协议保持一致。

## 功能点目的

`expected/` 目录对应的功能目标不是“产生新内容”，而是验证错误路径的三个约束：

1. 语法完整性约束：`Update File` hunk 不能为空，空 hunk 必须报错。
2. 失败前置约束：错误应在解析阶段抛出，不能进入 `apply_hunks_to_files`。
3. 无副作用约束：失败后文件内容不改变，因此 `expected/foo.txt` 与 `input/foo.txt` 保持一致。

该目录在覆盖矩阵中的价值：

1. 区分 `005_rejects_empty_patch`（整个 patch 空）与本场景（有 hunk header 但 update 内容空）。
2. 区分 `009_requires_existing_file_for_update`（语法有效但目标不存在，失败在 I/O 阶段）与本场景（语法层失败）。
3. 为 `tool.rs` 中精确 stderr 断言提供文件状态侧互补验证。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 从 `expected/` 参与断言的完整流程

1. `tests/suite/scenarios.rs::test_apply_patch_scenarios` 遍历 `fixtures/scenarios/*` 并调用 `run_apply_patch_scenario`。
2. `run_apply_patch_scenario` 将 `input/` 复制到 `tempdir`，读取 `patch.txt`，执行 `apply_patch <patch>`。
3. 测试随后读取 `expected/`（本目录）和 `tempdir` 两边目录树，转换为 `BTreeMap<PathBuf, Entry>` 快照。
4. 通过 `assert_eq!` 比较快照；本场景里只有 `foo.txt`，内容必须与 `expected/foo.txt` 完全一致。

### 2) 使 `expected/foo.txt` 成立的解析链路

1. `src/standalone_executable.rs::run_main` 将参数传给 `crate::apply_patch`。
2. `src/lib.rs::apply_patch` 首先执行 `parse_patch`，若失败直接写 stderr 并返回。
3. `src/parser.rs::parse_one_hunk` 在 `*** Update File` 分支中累计 `chunks`；遇到下一个 `***` marker 且 `chunks.is_empty()` 时返回 `InvalidHunkError`。
4. 因为 parse 失败，`apply_hunks` 与 `apply_hunks_to_files` 不会被调用，磁盘文件保持初始值；这就是 `expected/foo.txt=stable` 的技术来源。

### 3) 协议与数据结构

1. 协议源：`tool_apply_patch.lark` 与 `apply_patch_tool_instructions.md`，要求 patch 位于 `*** Begin Patch` / `*** End Patch` 包裹中。
2. hunk 数据结构：`parser::Hunk::UpdateFile { path, move_path, chunks }`；本场景触发的是“`chunks` 为空非法”。
3. 场景快照数据结构：`Entry::File(Vec<u8>) | Entry::Dir`，用字节级比较避免编码歧义。

### 4) 关键命令（复现与验证）

1. 单场景复现：
`apply_patch "*** Begin Patch\n*** Update File: foo.txt\n*** End Patch"`
2. 场景测试：
`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
3. 定向错误文案测试：
`cargo test -p codex-apply-patch --test all test_apply_patch_cli_rejects_empty_update_hunk`

## 关键代码路径与文件引用

### 1) 目标目录与场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/expected/foo.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/input/foo.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/patch.txt`

### 2) 直接调用方（测试侧）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs`（读取 `expected/` 并做目录快照对比）
2. `codex-rs/apply-patch/tests/suite/tool.rs`（同语义下断言 stderr：空 update hunk 报错）
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`（fixture 协议定义）

### 3) 被调用方（实现侧）

1. `codex-rs/apply-patch/src/parser.rs`（`chunks.is_empty()` 拒绝空 update hunk）
2. `codex-rs/apply-patch/src/lib.rs`（parse 失败时提前返回，不进入写盘）
3. `codex-rs/apply-patch/src/standalone_executable.rs`（CLI 参数/退出码链路）
4. `codex-rs/apply-patch/src/main.rs`（二进制入口转发）

### 4) 上下文配置、脚本、文档与上游调用

1. `codex-rs/apply-patch/Cargo.toml`（`codex-apply-patch` crate/bin 定义与依赖）
2. `codex-rs/apply-patch/BUILD.bazel`（`apply_patch_tool_instructions.md` 作为 `compile_data`）
3. `codex-rs/core/src/tools/handlers/tool_apply_patch.lark`（freeform grammar）
4. `codex-rs/core/src/tools/handlers/apply_patch.rs`（上游 `maybe_parse_apply_patch_verified` 校验入口）
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs`（校验后通过 `--codex-run-as-apply-patch` 执行）
6. `codex-rs/arg0/src/lib.rs`（`argv1 == --codex-run-as-apply-patch` 分发到 `codex_apply_patch::apply_patch`）
7. `.ops/generate_daily_research_todo.sh`（研究任务完成后刷新 todo 的脚本）

## 依赖与外部交互

### 1) 依赖关系

1. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（负责启动可执行、构造临时目录、快照断言、定位仓库和二进制）。
2. 运行依赖：`anyhow`、`thiserror`、`tree-sitter`、`tree-sitter-bash`、`similar`（用于错误建模、shell/heredoc 解析、diff 生成）。

### 2) 外部交互

1. 文件系统：读取本目录 `expected/foo.txt` 参与快照比较。
2. 子进程：测试通过 `cargo_bin("apply_patch")` 启动 CLI。
3. 标准流：空 update hunk 失败时写 stderr，scenarios 测试本身不依赖 stderr 文案。

### 3) 与上游系统的交互点

1. 在 core 工具链中，`apply_patch` 输入先做 verified parse，再计算权限与审批。
2. 本场景的错误会被包装为 `apply_patch verification failed: ...` 反馈给模型侧。
3. 因为该目录仅保存最终状态快照，所以它验证的是“结果不变性”，不是“错误文案稳定性”。

## 风险、边界与改进建议

### 风险与边界

1. `expected/` 只能证明“最终文件状态正确”，不能单独证明 stderr/exit code 是否回归。
2. 当前目录只有 `foo.txt`，覆盖粒度是单文件不变；未覆盖多文件同时存在时的副作用隔离。
3. `scenarios.rs` 使用目录快照比对但不强制排序执行，失败日志顺序可能随平台变化。
4. 空 update hunk 的变体（例如仅 `*** Move to` 无 chunk）不在本目录覆盖范围内。

### 改进建议

1. 为场景格式增加可选元数据（如 `expect_stderr_contains`），与 `expected/` 形成“状态 + 诊断”双重断言。
2. 增加 sibling 场景：`Update File + Move to` 且无 chunk，进一步确认 rename 场景下同样拒绝。
3. 在 core 层补一条端到端测试，验证包装错误 `apply_patch verification failed` 与该场景语义一致。
4. 在 `scenarios/README.md` 增补“`expected/` 对负向场景表达的是无副作用基线”说明，降低误读成本。
