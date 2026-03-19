# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是场景 `009_requires_existing_file_for_update` 的输入快照目录，当前仅包含一个文件：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/input/foo.txt:1`（内容为 `stable`）。

它在测试体系中的职责不是“提供被更新目标”，而是“提供无关稳定文件作为副作用探针”：

1. 同级 `patch.txt` 明确尝试更新不存在文件 `missing.txt`（`.../009_requires_existing_file_for_update/patch.txt:1-6`）。
2. `input/foo.txt` 作为初始状态基线，验证失败路径不会误改目录中其他文件。
3. `expected/foo.txt` 与 `input/foo.txt` 完全一致（`.../009_requires_existing_file_for_update/expected/foo.txt:1`），用于表达“失败后文件系统保持不变”。

该职责与邻近场景分工互补：

1. `008_rejects_empty_update_hunk`：解析阶段失败（空 update hunk）。
2. `009_requires_existing_file_for_update`：执行阶段失败（目标文件不存在）。
3. `015_failure_after_partial_success_leaves_changes`：多操作中部分成功后再失败。

## 功能点目的

该 `input/` 目录服务的功能点是“Update 必须作用在已存在文件上”的行为契约验证，目的有三层：

1. 前置条件明确：`*** Update File:` 不是隐式创建；不存在目标时必须失败。
2. 失败语义可诊断：错误应定位到 `Failed to read file to update missing.txt ...`。
3. 副作用边界清晰：失败后不应影响工作目录里无关文件（本目录用 `foo.txt` 验证此点）。

它避免两类真实风险：

1. 路径拼写错误被“静默创建新文件”掩盖，导致上层误判补丁成功。
2. 失败时错误地改写/删除其他文件，造成难以回溯的污染。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景回放流程（谁消费该 input 目录）

`tests/suite/scenarios.rs` 会遍历 `fixtures/scenarios` 中每个场景目录并执行：

1. `run_apply_patch_scenario()` 将本目录 `input/` 递归复制到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-37,107-124`）。
2. 读取同级 `patch.txt` 并在临时目录执行 `apply_patch` 二进制（`.../scenarios.rs:39-48`）。
3. 不断言退出码，仅将“临时目录快照”与 `expected/` 快照做字节级比较（`.../scenarios.rs:42-60,65-105`）。

因此该目录的验证方式是“最终状态一致性”，而不是 stderr 文案一致性。

### 2) 失败链路（为何 `foo.txt` 应保持不变）

执行入口链路：

1. `src/main.rs` 调到 `codex_apply_patch::main()`（`codex-rs/apply-patch/src/main.rs:1-2`）。
2. `run_main()` 解析参数后调用 `crate::apply_patch()`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
3. `apply_patch()` 先 `parse_patch()`，语法通过后进入 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
4. `apply_hunks_to_files()` 处理 `Hunk::UpdateFile` 时调用 `derive_new_contents_from_chunks(path, chunks)`（`.../lib.rs:306-313`）。
5. `derive_new_contents_from_chunks()` 第一件事是 `read_to_string(path)`；若文件不存在，返回 `IoError`，context 为 `Failed to read file to update {path}`（`.../lib.rs:352-359`）。
6. 错误被写入 stderr 并终止（`.../lib.rs:253-265`）。

本场景中 `path=missing.txt`，因此失败发生在读取目标文件阶段；`foo.txt` 没有命中任何写操作路径，预期保持 `stable\n`。

### 3) 关键数据结构与协议边界

1. `Hunk::UpdateFile { path, move_path, chunks }` 由 parser 产出（`codex-rs/apply-patch/src/parser.rs:68-75`）。
2. parser 注释明确“不检查补丁能否应用到文件系统”，即存在性校验不在语法层（`codex-rs/apply-patch/src/parser.rs:1-3`）。
3. core 侧 Lark 语法定义 `update_hunk: ... change_move? change?`，同样不含“文件必须存在”语义（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:8`）。
4. 因此“目标文件是否存在”由执行层 I/O 校验承担，恰好由本场景覆盖。

### 4) 与上层工具链的交互

1. core handler 会先调用 `maybe_parse_apply_patch_verified()` 做预校验（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`）。
2. 对 Update 操作，verified 阶段构建 diff 时也会读取源文件，失败返回 `CorrectnessError`（`codex-rs/apply-patch/src/invocation.rs:184-194`）。
3. handler 将其转成 `apply_patch verification failed: ...` 返回模型（`codex-rs/core/src/tools/handlers/apply_patch.rs:241-245`）。
4. 若通过验证并需要执行，则 runtime 通过 `codex --codex-run-as-apply-patch <patch>` 自调用（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`，`codex-rs/arg0/src/lib.rs:89-107`）。

### 5) 关键命令（定位与复现）

1. 场景回放：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 语义同源的 stderr 断言：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_requires_existing_file_for_update`
3. 第二条对应断言在 `tool.rs`：`Failed to read file to update missing.txt: No such file or directory (os error 2)`（`codex-rs/apply-patch/tests/suite/tool.rs:140-149`）。

## 关键代码路径与文件引用

### 目标对象与同场景资产

1. `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/input/foo.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/patch.txt:1-6`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/expected/foo.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`

### 调用方（消费 input 的测试）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/tool.rs:140-149`

### 被调用方（解析/执行路径）

1. `codex-rs/apply-patch/src/main.rs:1-2`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/lib.rs:183-213`
4. `codex-rs/apply-patch/src/lib.rs:279-339`
5. `codex-rs/apply-patch/src/lib.rs:348-359`
6. `codex-rs/apply-patch/src/parser.rs:1-3`
7. `codex-rs/apply-patch/src/parser.rs:60-85`
8. `codex-rs/apply-patch/src/invocation.rs:132-217`

### 配置、脚本与文档依赖

1. crate 配置：`codex-rs/apply-patch/Cargo.toml:1-30`
2. Bazel 打包数据：`codex-rs/apply-patch/BUILD.bazel:1-10`
3. 工具协议文档：`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`
4. grammar 文件：`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-19`
5. 日常任务脚本：`.ops/generate_daily_research_todo.sh:1-42`
6. 任务模板来源：`.ops/research_guard.sh:195-229`

## 依赖与外部交互

### 1) 依赖关系

`codex-apply-patch` 关键依赖：

1. 运行依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 外部交互面

1. 文件系统：复制 `input/`、读取 `patch.txt`、应用 patch、快照比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-60`）。
2. 子进程：场景测试使用 `cargo_bin("apply_patch")` 启动真实 CLI（`.../scenarios.rs:45-48`）。
3. 标准流：失败信息写 stderr，成功汇总写 stdout（`codex-rs/apply-patch/src/lib.rs:249-256`）。
4. 平台差异：`tool.rs` 错误文案依赖 Unix I/O 文本，模块在 Windows 上禁用（`codex-rs/apply-patch/tests/suite/mod.rs:3`）。

### 3) 与上层系统交互

1. 在 `core` 流程里，缺失文件错误可能在“verified 阶段”就被拦截，不一定进入 runtime 真执行（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-245`）。
2. runtime 真执行时使用最小环境变量集，降低环境干扰（`codex-rs/core/src/tools/runtimes/apply_patch.rs:96-99`）。

## 风险、边界与改进建议

### 风险

1. `scenarios.rs` 不校验退出码/stderr，仅对比最终目录；诊断文案退化可能漏检（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-45`）。
2. 本 `input/` 目录只覆盖“更新目标不存在”这一类 I/O 前置条件，未覆盖权限拒绝、符号链接异常、目录同名等路径类型错误。
3. 场景是单文件最小集，无法揭示大目录下误匹配更新时的潜在 collateral damage。

### 边界

1. 该目录本身不包含业务逻辑，只是 fixture 输入；语义由同级 `patch.txt` 与 runner 共同决定。
2. 该目录不验证 parse 容错（如 heredoc 宽松解析），对应行为在 `parser.rs` 与 `invocation.rs` 的单元测试中覆盖。
3. 该目录也不验证 approval/sandbox 策略，只间接参与 core 侧 apply_patch 行为链。

### 改进建议

1. 给场景框架增加 `stderr_contains`/`exit_code` 可选断言文件，补齐负向场景的诊断验证维度。
2. 新增与本目录配套的 `input/` 变体（例如包含多个无关文件与子目录），提升“失败无副作用”覆盖强度。
3. 增加“目标路径存在但不可读”的 fixture（权限位或受限 runfiles），补全 Update 前置条件矩阵。
4. 在 `scenarios/README.md` 明确说明：某些负向场景 `expected` 可以与 `input` 完全一致，用于表达无副作用语义。
