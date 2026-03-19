# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`008_rejects_empty_update_hunk` 是 `apply_patch` fixture 场景中的负向语义用例，目标是验证：当补丁只声明 `*** Update File` 头但没有任何变更 chunk（`@@` 或 `+/-/ ` 行）时，解析阶段必须拒绝该补丁，且文件系统状态保持不变。

本场景夹具由三部分组成：

1. `patch.txt` 只包含：`*** Begin Patch`、`*** Update File: foo.txt`、`*** End Patch`（`codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/patch.txt:1-3`）。
2. `input/foo.txt` 预置稳定内容 `stable`（`.../input/foo.txt:1`）。
3. `expected/foo.txt` 与 input 一致，用于表达失败后无副作用（`.../expected/foo.txt:1`）。

它在测试体系中的职责分层如下：

1. 场景回放层：由 `tests/suite/scenarios.rs` 递归跑所有场景并比对最终目录快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`）。
2. 错误文案层：由 `tests/suite/tool.rs` 精确断言 stderr（`codex-rs/apply-patch/tests/suite/tool.rs:127-135`）。
3. 解析器单元层：`parser.rs` 内置测试直接断言 `InvalidHunkError`（`codex-rs/apply-patch/src/parser.rs:469-480`）。

## 功能点目的

该场景的核心目的不是“更新成功”，而是“无效 update 语法必须被早拒绝”。这对应三个工程目标：

1. 语法完整性：`Update File` 至少要有一个 chunk，空 update 不能进入执行层（`codex-rs/apply-patch/src/parser.rs:318-323`）。
2. 失败可诊断：报错必须定位到 hunk 行号与原因，便于模型/调用方修补 patch（`codex-rs/apply-patch/src/lib.rs:195-203`）。
3. 失败无副作用：在 parse 阶段失败时，`apply_hunks` 不会被调用，文件不会被改写（`codex-rs/apply-patch/src/lib.rs:188-210`）。

与邻近场景形成的覆盖矩阵：

1. `005_rejects_empty_patch`：补丁内 0 个 hunk。 
2. `008_rejects_empty_update_hunk`：有 hunk header，但 update hunk 内容为空。 
3. `009_requires_existing_file_for_update`：update chunk 合法，但目标文件不存在。 

三者分别锁定“结构为空”“update 语义为空”“执行对象不存在”三个不同失败边界。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 执行流程（从 fixture 到失败返回）

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios` 目录，按目录调用 `run_apply_patch_scenario`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 把 `input/` 复制到临时目录，读取 `patch.txt`，执行 `apply_patch <patch>`（`.../scenarios.rs:33-48`）。
3. 该测试不校验 exit code，仅比较最终目录快照（`.../scenarios.rs:42-45,50-60`）。
4. 解析失败后无写盘，临时目录仍为 `foo.txt=stable`，与 `expected` 一致。

### 2) 解析/报错关键链路

1. CLI 主入口：`src/main.rs` 转发到 `codex_apply_patch::main()`（`codex-rs/apply-patch/src/main.rs:1-2`）。
2. `run_main()` 读取 argv 或 stdin，然后调用 `crate::apply_patch`；出错退出码为 1（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
3. `apply_patch()` 先 `parse_patch()`，若 `InvalidHunkError` 则输出 `Invalid patch hunk on line ...`（`codex-rs/apply-patch/src/lib.rs:183-207`）。
4. `parse_one_hunk()` 进入 `*** Update File` 分支后解析 chunk；当 `chunks.is_empty()` 直接返回：
   `Update file hunk for path 'foo.txt' is empty`（`codex-rs/apply-patch/src/parser.rs:279-323`）。
5. 因为失败发生在 parse 阶段，`apply_hunks`/`apply_hunks_to_files` 不会执行（`codex-rs/apply-patch/src/lib.rs:210`）。

### 3) 数据结构与协议约束

1. 协议边界：`*** Begin Patch` + 至少一个 hunk + `*** End Patch`；update hunk 的 grammar 是 `change_move? change?`，实现上进一步要求必须产出至少一个 `UpdateFileChunk`（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-19`，`codex-rs/apply-patch/src/parser.rs:318-323`）。
2. 解析结果结构：`ApplyPatchArgs { patch, hunks, workdir }`；hunk 为 `Hunk::{AddFile,DeleteFile,UpdateFile}`（`codex-rs/apply-patch/src/lib.rs:83-88`，`codex-rs/apply-patch/src/parser.rs:61-76`）。
3. 本场景中 `UpdateFile` 本应携带 `chunks: Vec<UpdateFileChunk>`，但该向量为空时被拒绝，不会进入执行逻辑。

### 4) 关键命令与验证方式

1. 直接复现命令：
   `apply_patch "*** Begin Patch\n*** Update File: foo.txt\n*** End Patch"`
2. 对应 CLI 断言：
   `Invalid patch hunk on line 2: Update file hunk for path 'foo.txt' is empty`（`codex-rs/apply-patch/tests/suite/tool.rs:130-135`）。
3. 场景回放命令：
   `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`

## 关键代码路径与文件引用

### 1) 目标目录与夹具文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/patch.txt:1-3`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/input/foo.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/expected/foo.txt:1`

### 2) 直接调用方（场景消费方）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/tool.rs:127-135`

### 3) 被调用方（解析与执行实现）

1. `codex-rs/apply-patch/src/main.rs:1-2`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/lib.rs:183-213`
4. `codex-rs/apply-patch/src/parser.rs:248-341`
5. `codex-rs/apply-patch/src/parser.rs:469-480`

### 4) 上下文配置、文档、脚本与上游链路

1. 场景规范文档：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
2. 行尾规范：`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
3. 工具协议文档：`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50,65-75`
4. Lark 语法：`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-19`
5. crate 与可执行定义：`codex-rs/apply-patch/Cargo.toml:1-30`
6. Bazel compile_data 配置：`codex-rs/apply-patch/BUILD.bazel:1-11`
7. `just` 常用命令入口：`justfile:1-47`
8. core apply_patch handler 预检与错误包装：`codex-rs/core/src/tools/handlers/apply_patch.rs:170-245`
9. core runtime 自调用命令：`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`
10. 研究 todo 生成脚本：`.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

### 1) 代码依赖

1. 运行依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 外部交互

1. 文件系统：fixture runner 复制 `input`、读取 `patch.txt`、快照比对 `expected`（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-53,71-126`）。
2. 子进程：通过 `cargo_bin("apply_patch")` 拉起 `apply_patch` 可执行文件（`.../scenarios.rs:45-48`）。
3. 标准流：parse 失败时写 stderr，不写 stdout（`codex-rs/apply-patch/src/lib.rs:191-203`）。

### 3) 与 core/tool 协议的交互

1. core `ApplyPatchHandler` 会先 `maybe_parse_apply_patch_verified`，失败时统一包装为 `apply_patch verification failed: ...`（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-245`）。
2. 验证通过后由 runtime 组装 `codex --codex-run-as-apply-patch <patch>` 执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:89-94`）。
3. 当前 core 集成测试里未看到“empty update hunk”专门用例（`codex-rs/core/tests/suite/apply_patch_cli.rs:505-554` 仅覆盖 empty patch、delete directory 等），属于可补强点。

## 风险、边界与改进建议

### 风险与边界

1. `scenarios.rs` 只断言最终目录状态，不断言 stderr/exit code；若错误文本退化但无副作用，场景回放不会报警（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-45`）。
2. 该场景仅覆盖“完全无 chunk”的 update，未覆盖“只有 `*** Move to` 但无 chunk”的变体（实现同样会触发 `chunks.is_empty()`，但缺少 fixture 显式锁定）。
3. core 层目前无该错误的端到端专门测试，跨层错误文案一致性依赖 `apply-patch` crate 自身测试。
4. 场景遍历未排序（`read_dir`），异常日志顺序可能随文件系统变化。

### 改进建议

1. 在 `tests/suite/scenarios.rs` 增加可选元数据断言（如 `expect_exit_code`、`expect_stderr_contains`），让负向场景既测“状态”也测“诊断”。
2. 新增 `Update File + Move to` 但缺失 chunk 的 fixture，用于锁定 rename 语义下的空 hunk 拒绝行为。
3. 在 `core/tests/suite/apply_patch_cli.rs` 新增 empty update hunk 集成测试，验证 `apply_patch verification failed` 包装层输出。
4. 场景执行前按目录名排序，提高 CI 与本地排障可复现性。
