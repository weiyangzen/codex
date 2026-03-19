# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/expected` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是场景 `009_requires_existing_file_for_update` 的“期望状态快照（oracle）”目录，当前仅包含：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/expected/foo.txt:1`

其职责不是实现逻辑，而是固定断言语义：当 patch 尝试 `*** Update File: missing.txt` 且目标不存在时，执行必须失败，最终文件系统状态应与输入一致。

对应场景输入如下：

1. `patch.txt` 指向不存在文件（`.../patch.txt:1-6`）。
2. `input/foo.txt` 是稳定基线（`.../input/foo.txt:1`）。
3. `expected/foo.txt` 与 input 一致（`.../expected/foo.txt:1`）。

该目录在测试体系中的角色：

1. 为 `tests/suite/scenarios.rs` 的目录快照对比提供“最终状态标准答案”（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。
2. 将“失败无副作用”显式化：即便补丁执行失败，已有文件 `foo.txt` 不应变化。
3. 作为跨平台 fixture 协议的一部分，与场景 README 定义保持一致（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-17`）。

## 功能点目的

该目录绑定的功能目标是“约束 Update 行为必须基于已存在文件”，具体目的包括：

1. 前置条件校验：`Update File` 不是“隐式创建”，必须先能读取目标文件。
2. 失败路径可观测：当目标缺失时，应得到可诊断 I/O 错误文本（`Failed to read file to update ...`）。
3. 状态安全：失败后不应污染无关文件。

在覆盖矩阵里，此目录与相邻场景形成互补：

1. 相对 `008_rejects_empty_update_hunk`：`009` 语法合法、执行失败；`008` 是解析阶段失败。
2. 相对 `015_failure_after_partial_success_leaves_changes`：`009` 关注“首个 Update 即失败且无写入”；`015` 关注“前序成功后失败的部分提交”。
3. 相对 `tool.rs` 错误文案断言：本目录只验证“最终状态”，不验证 stderr 文本。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景回放执行链路

`test_apply_patch_scenarios` 会枚举所有 fixture 场景目录并运行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。

针对每个场景：

1. 复制 `input/` 到临时目录（`.../scenarios.rs:33-37,107-124`）。
2. 读取 `patch.txt`（`.../scenarios.rs:39-40`）。
3. 子进程执行 `apply_patch <patch>`（`.../scenarios.rs:45-48`）。
4. 把临时目录与 `expected/` 都快照为 `BTreeMap<PathBuf, Entry>` 并 `assert_eq!`（`.../scenarios.rs:50-60,65-105`）。

`Entry` 数据结构：

1. `Entry::File(Vec<u8>)`
2. `Entry::Dir`

因此比较是“字节级目录树一致性”而非仅文本近似。

### 2) Update 缺失文件失败机制

运行时入口：`standalone_executable::run_main -> crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`，`codex-rs/apply-patch/src/lib.rs:183-213`）。

关键失败点在 `derive_new_contents_from_chunks`：

1. `apply_hunks_to_files` 遇到 `Hunk::UpdateFile` 时调用 `derive_new_contents_from_chunks(path, chunks)`（`codex-rs/apply-patch/src/lib.rs:306-313`）。
2. 函数第一步 `std::fs::read_to_string(path)` 读取原始文件（`.../lib.rs:352`）。
3. 读取失败时构造 `ApplyPatchError::IoError`，context 为 `Failed to read file to update {path}`（`.../lib.rs:355-358`）。
4. `apply_hunks` 把错误写入 stderr 并返回失败（`.../lib.rs:253-265`）。

该路径解释了为何本场景 `expected/foo.txt` 与 `input/foo.txt` 相同：更新目标在读取阶段即失败，未进入写入分支。

### 3) 解析与协议边界

协议层（Lark）仅定义结构，不承担文件存在性：

1. `update_hunk: "*** Update File: " filename LF change_move? change?`（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:8`）。

解析器负责语法完整性（例如 update hunk 不可为空）：

1. `parse_one_hunk` 在 `chunks.is_empty()` 时报 `InvalidHunkError`（`codex-rs/apply-patch/src/parser.rs:318-323`）。

因此“目标文件必须存在”是执行层 I/O 约束，不是语法层约束。

### 4) 上层工具链的 verified 调用与拦截

在 core handler 里，会先进行 verified parse：

1. `maybe_parse_apply_patch_verified(&command, &cwd)`（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`）。
2. 对 Update hunk，verified 路径会调用 `unified_diff_from_chunks`，同样会触发源文件读取（`codex-rs/apply-patch/src/invocation.rs:184-194`）。
3. 失败返回 `CorrectnessError`，再包装成 `apply_patch verification failed: ...`（`codex-rs/core/src/tools/handlers/apply_patch.rs:241-244`）。

若通过校验并进入 runtime，会以 `codex --codex-run-as-apply-patch <patch>` 自调用（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`），由 arg0 分发到 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:89-107`）。

### 5) 关键命令与验证

1. 场景批量回放：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 错误文本定向验证：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_requires_existing_file_for_update`
3. 对应 stderr 断言位于 `tool.rs`（`codex-rs/apply-patch/tests/suite/tool.rs:140-149`）。

## 关键代码路径与文件引用

### 1) 目标目录与场景资产

1. `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/expected/foo.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/input/foo.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/patch.txt:1-6`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-17`

### 2) 直接调用方（测试）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/tool.rs:140-149`

### 3) 被调用方（执行/解析）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:279-339`
4. `codex-rs/apply-patch/src/lib.rs:348-359`
5. `codex-rs/apply-patch/src/parser.rs:279-333`
6. `codex-rs/apply-patch/src/invocation.rs:132-217`

### 4) 配置、协议、构建与脚本

1. 协议说明：`codex-rs/apply-patch/apply_patch_tool_instructions.md:14-50`
2. Lark 语法：`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-19`
3. crate 定义：`codex-rs/apply-patch/Cargo.toml:1-30`
4. Bazel compile_data：`codex-rs/apply-patch/BUILD.bazel:3-10`
5. 上层 handler：`codex-rs/core/src/tools/handlers/apply_patch.rs:170-245`
6. 上层 runtime：`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-215`
7. arg0 分发：`codex-rs/arg0/src/lib.rs:82-107`
8. 每日 TODO 生成脚本：`.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

### 1) 代码依赖

`codex-apply-patch` 的关键依赖：

1. 运行依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 外部交互面

1. 文件系统：复制 `input`、读取 `patch`、写/删目标文件、快照 `expected` 与临时目录。
2. 子进程：测试通过 `cargo_bin("apply_patch")` 启动可执行。
3. 标准流：错误路径写 stderr（本场景关键反馈面）。
4. 平台差异：stderr 中 `os error` 文案与 errno 编号受 OS 影响，`tool.rs` 用 `#[cfg(not(target_os = "windows"))]` 控制该测试模块加载（`codex-rs/apply-patch/tests/suite/mod.rs:3`）。

### 3) 与上层系统交互

1. core handler 在执行前做 verified parse，可提前把缺失文件错误反馈给模型。
2. runtime 采用最小环境变量执行，避免环境泄漏影响 patch 应用行为（`codex-rs/core/src/tools/runtimes/apply_patch.rs:96-99`）。
3. arg0 支持 `apply_patch` 别名与 `--codex-run-as-apply-patch` 隐式入口，保持调用协议一致。

## 风险、边界与改进建议

### 风险

1. `scenarios.rs` 不断言退出码和 stderr，仅比较最终文件树；可能漏掉“报错文案回归”或“错误码异常”问题。
2. 本场景只覆盖“单一 Update 缺失源文件”；未覆盖 move/update 组合下的缺失路径优先级。
3. 错误文案包含平台相关 I/O 文本，跨平台稳定性依赖条件编译与运行环境一致性。

### 边界

1. 该目录只表达“状态不变性”，不表达“错误信息正确性”。
2. 该目录不涉及权限审批、sandbox 执行细节本身，只间接依赖上层调用链。
3. 该目录也不验证 patch 解析容错（如 heredoc/空白兼容），这些由其他测试覆盖。

### 改进建议

1. 为 fixture 场景格式补充可选元数据（如 `expected_stderr_contains.txt`、`expected_exit_code.txt`），让负向场景同时验证状态与诊断。
2. 增补 `Update File + Move to` 且源文件缺失场景，明确复合操作的失败语义。
3. 在 core 端增加一条端到端断言，验证 `apply_patch verification failed: Failed to read file to update ...` 的稳定对外消息。
4. 在 `scenarios/README.md` 增加“负向场景中 expected 可等于 input，用于表达无副作用”的说明，降低维护者理解成本。
