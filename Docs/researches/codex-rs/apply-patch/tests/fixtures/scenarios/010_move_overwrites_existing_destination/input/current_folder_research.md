# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 对应场景：`010_move_overwrites_existing_destination`

## 场景与职责

该目录是场景 `010_move_overwrites_existing_destination` 的**输入态夹具**，用于描述 `apply_patch` 执行前的工作目录状态。目录树如下（来自 `find` 结果）：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/name.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/other.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt`

其中每个文件承担不同职责：

1. `input/old/name.txt`：补丁更新与移动的源文件，初始内容 `from`（`.../input/old/name.txt:1`）。
2. `input/renamed/dir/name.txt`：已存在的目标文件，初始内容 `existing`（`.../input/renamed/dir/name.txt:1`），用于验证 `Move to` 的覆盖行为。
3. `input/old/other.txt`：无关旁路文件，内容 `unrelated file`（`.../input/old/other.txt:1`），用于验证变更范围不会误伤同目录其他文件。

该目录并不直接执行逻辑，而是由场景回放框架消费：

1. `run_apply_patch_scenario()` 复制 `input/` 到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-37`）。
2. 在该临时目录执行同级 `patch.txt`（`.../scenarios.rs:39-48`）。
3. 将执行后目录与 `expected/` 做完整快照对比（`.../scenarios.rs:50-60`）。

## 功能点目的

`input/` 目录服务的是“**移动更新覆盖已有目标文件**”这个行为点，目的不是验证 parser 语法，而是固定执行语义：

1. `*** Update File: old/name.txt` + `*** Move to: renamed/dir/name.txt` 在目标已存在时仍应成功。
2. 目标文件应被新内容覆盖（`existing -> new`），而不是拒绝冲突。
3. 源文件应被删除（`old/name.txt` 在 `expected/` 中不存在）。
4. 无关文件应保持不变（`old/other.txt` 在 `expected/old/other.txt` 中保持一致）。

同场景 patch 定义如下（`codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt:1-7`）：

```patch
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-from
+new
*** End Patch
```

与邻近场景的职责边界：

1. `004_move_to_new_directory` 偏向验证“移动到新目录”。
2. `010_move_overwrites_existing_destination` 明确验证“目标已存在时的覆盖”。
3. `011_add_overwrites_existing_file` 则覆盖 Add 操作的覆盖语义，不是 Move。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) fixture 回放流程（input 目录如何被消费）

1. 测试入口 `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 命中本场景后，`copy_dir_recursive(input, tmp)` 递归复制输入目录（`.../scenarios.rs:33-37,107-124`）。
3. 读取 patch 文本并运行 `apply_patch` 子进程（`.../scenarios.rs:39-48`）。
4. 生成 `BTreeMap<PathBuf, Entry>` 快照对比，其中 `Entry` 是 `Dir | File(Vec<u8>)`（`.../scenarios.rs:65-105`）。

注意：框架刻意不检查 exit status，而是只检查最终文件系统状态（`.../scenarios.rs:42-45`）。

### 2) patch 协议与解析实现

协议层定义支持 `Update File` 可选 `Move to`：

1. Lark 语法：`update_hunk: ... change_move? change?`（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:8-17`）。
2. 工具说明文档：`MoveTo := "*** Move to: " newPath NEWLINE`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:47-49`）。

解析层将其映射到结构体：

1. `Hunk::UpdateFile { path, move_path, chunks }`（`codex-rs/apply-patch/src/parser.rs:68-75`）。
2. `parse_one_hunk()` 识别 `MOVE_TO_MARKER` 并填入 `move_path`（`.../parser.rs:279-333`）。

### 3) 执行层覆盖行为（本场景的核心）

执行路径：`standalone_executable::run_main()` -> `apply_patch()` -> `apply_hunks_to_files()`。

1. `run_main()` 接收单个 patch 参数（或 stdin）并调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
2. `apply_patch()` 解析 patch 后进入 `apply_hunks`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
3. `apply_hunks_to_files()` 在 `Hunk::UpdateFile + Some(move_path)` 分支执行：
   - `derive_new_contents_from_chunks(path, chunks)` 计算新内容（`.../lib.rs:311-313,348-360`）。
   - `create_dir_all(dest.parent())`（`.../lib.rs:314-320`）。
   - `std::fs::write(dest, new_contents)`（`.../lib.rs:321-322`），因此已有目标文件会被覆盖。
   - `std::fs::remove_file(path)` 删除源文件（`.../lib.rs:323-324`）。
4. 成功摘要输出 `M <dest>`（`.../lib.rs:247-251`，`tests/suite/tool.rs:169`）。

这正是本 `input/` 目录要验证的语义：源存在、目标已存在、执行后目标内容更新且源被删。

### 4) 上下游调用与安全约束

上游不是直接盲跑 patch，而是先 verified：

1. `ApplyPatchHandler` 调用 `maybe_parse_apply_patch_verified()` 重新解析并提取变更（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`）。
2. 对 `Update` 变更，`move_path` 会被解析为有效 cwd 下绝对路径写入 `ApplyPatchFileChange::Update`（`codex-rs/apply-patch/src/invocation.rs:184-203`）。
3. Handler 还会把源路径和 move 目标都纳入写权限路径集合（`codex-rs/core/src/tools/handlers/apply_patch.rs:46-64`）。
4. `assess_patch_safety()` 对 update 同时检查源与目的路径是否可写（`codex-rs/core/src/safety.rs:159-175`）。
5. 真执行阶段由 runtime 组装 `codex --codex-run-as-apply-patch <patch>`，并在最小环境运行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`）。
6. `arg0` 负责把 `--codex-run-as-apply-patch` 分发到 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:89-107`）。

### 5) 相关命令（本地复现/验证）

1. 场景回放：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 同语义代码测试：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_move_overwrites_existing_destination`
3. TODO 更新脚本：`bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### 1) 目标目录与同场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/name.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/other.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt:1-7`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt:1`
6. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/old/other.txt:1`

### 2) 直接调用方（测试入口）

1. `codex-rs/apply-patch/tests/all.rs`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/tool.rs:155-175`

### 3) 被调用方（解析/执行）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:279-339`
4. `codex-rs/apply-patch/src/lib.rs:348-360`
5. `codex-rs/apply-patch/src/parser.rs:31-39`
6. `codex-rs/apply-patch/src/parser.rs:68-75`
7. `codex-rs/apply-patch/src/parser.rs:279-333`
8. `codex-rs/apply-patch/src/invocation.rs:132-217`

### 4) 配置、脚本与文档

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
4. `codex-rs/apply-patch/apply_patch_tool_instructions.md:14-50`
5. `codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-19`
6. `codex-rs/core/src/tools/handlers/apply_patch.rs:44-64`
7. `codex-rs/core/src/safety.rs:125-180`
8. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`
9. `codex-rs/arg0/src/lib.rs:82-107`
10. `.ops/generate_daily_research_todo.sh:1-42`
11. `Docs/researches/blueprint_checklist.md:100-113`

## 依赖与外部交互

### 1) 代码依赖

`codex-apply-patch` 的关键依赖：

1. `anyhow`、`thiserror`：错误聚合与上下文（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. `similar`：构建 unified diff（verified 场景中的 update 变更描述）。
3. `tree-sitter`、`tree-sitter-bash`：解析 shell/heredoc 调用形式。
4. 测试依赖 `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`.../Cargo.toml:25-30`）。

### 2) 外部交互

1. 文件系统交互：复制 `input/`、读取 patch、写目标、删源、快照比对。
2. 进程交互：测试通过 `cargo_bin("apply_patch")` 启动二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. 标准流交互：成功写 stdout，失败写 stderr（`codex-rs/apply-patch/src/lib.rs:247-255`）。

### 3) 与上层系统交互

1. handler 先 verified，再审批/执行，避免未解析 patch 直接落地（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-179`）。
2. 安全策略同时覆盖 source 与 move 目标路径（`codex-rs/core/src/safety.rs:166-175`）。
3. runtime 使用最小环境执行，降低环境泄漏与非确定性（`codex-rs/core/src/tools/runtimes/apply_patch.rs:96-99`）。

## 风险、边界与改进建议

### 风险

1. 移动实现是“写目标 + 删源”两步，非原子；若删源失败可能出现双文件并存。
2. 本场景框架只比较最终文件树，不检查 exit code/stderr，诊断信息回归需依赖其他测试。
3. `Move to` 覆盖已存在目标是实现事实，不是可配置策略；调用方若期望冲突报错可能产生语义偏差。

### 边界

1. 该目录仅表示输入态，不承载 parser 或 runtime 业务代码。
2. 仅覆盖成功覆盖路径，未覆盖权限错误、目标为目录、并发/竞态等 I/O 边界。
3. 不覆盖“缺失源文件”的失败路径，该语义由 `009_requires_existing_file_for_update` 与 `tool.rs` 对应断言覆盖（`codex-rs/apply-patch/tests/suite/tool.rs:140-149`）。

### 改进建议

1. 在场景框架中增加可选断言文件（如 `exit_code.txt`、`stderr_contains.txt`），补齐负向行为验证维度。
2. 新增 move 失败类场景：`move_destination_is_directory_fails`、`move_source_remove_fails_partial_state`。
3. 在 `apply_patch_tool_instructions.md` 显式写明“目标已存在时当前实现会覆盖”，降低工具使用方误解。
4. 若未来需要更强一致性，可评估“临时文件 + 原子替换”策略并用独立场景固定行为。
