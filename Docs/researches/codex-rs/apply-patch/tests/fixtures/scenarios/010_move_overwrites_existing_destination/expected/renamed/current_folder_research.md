# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属模块：`codex-rs/apply-patch` fixtures 场景 `010_move_overwrites_existing_destination`

## 场景与职责

该目录是场景 `010_move_overwrites_existing_destination` 的期望结果子树之一，目录内容只有：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt`（内容：`new`）。

其核心职责不是承载执行逻辑，而是作为 `expected` 快照 oracle 的一部分，精确定义 move 覆盖后的目标路径状态。与同场景的其他对象协作关系如下：

1. `input/old/name.txt` 提供被更新并移动的源文件初值（`from`）。
2. `input/renamed/dir/name.txt` 提供“目标已存在”的前置状态（`existing`）。
3. `patch.txt` 给出 `Update File + Move to` 指令。
4. 本目录中的 `expected/renamed/dir/name.txt` 定义最终应被覆盖后的值（`new`）。
5. `expected/old/other.txt` 定义无关文件应保持不变。

因此，本目录承担的场景责任是：

1. 锁定“目的文件已存在时，`Move to` 分支会覆盖该文件内容”这一实现语义。
2. 与 `expected/old` 共同约束“只改目标，不误改旁路文件”的边界。
3. 为目录驱动回归提供稳定、可移植的跨平台断言输入。

## 功能点目的

本目录对应的功能点目的可以拆分为三个层次：

1. 语义层：验证 `Update File` 在带 `Move to` 时，最终修改结果落到 destination，而不是 source。
2. 冲突层：验证 destination 已存在普通文件时采用覆盖语义（不是报冲突或跳过）。
3. 稳定性层：通过 fixtures 快照约束防止后续实现将覆盖语义悄然改为其他行为。

从测试体系视角，本目录补强了 `004_move_to_new_directory` 的覆盖盲点：

1. `004` 关注“新路径可创建”。
2. `010` 关注“已存在目标如何处理”。

二者共同定义了 `Move to` 成功路径的主干行为。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

目录驱动测试入口位于 `codex-rs/apply-patch/tests/suite/scenarios.rs`：

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`（`11-25` 行）。
2. `run_apply_patch_scenario()` 将 `input/` 复制到临时目录（`33-37`, `107-125` 行）。
3. 读取 `patch.txt`，调用 `apply_patch` 子进程执行（`39-48` 行）。
4. 用 `snapshot_dir(expected)` 与 `snapshot_dir(actual)` 做精确比对（`50-60` 行）。

本目录的数据在第 4 步作为 expected 子树参与断言，一旦 `renamed/dir/name.txt` 内容不是 `new\n`，场景立即失败。

### 2) 协议与语法

本场景 `patch.txt` 内容：

```patch
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-from
+new
*** End Patch
```

协议映射到解析器 (`codex-rs/apply-patch/src/parser.rs`)：

1. 语法支持 `update_hunk` 的可选 `change_move`（`13-21` 行注释）。
2. `MOVE_TO_MARKER` 常量定义为 `*** Move to: `（`36` 行）。
3. `parse_one_hunk()` 将其解析为 `Hunk::UpdateFile { path, move_path: Some(...), chunks }`（`279-330` 行）。

### 3) 执行语义

执行位于 `codex-rs/apply-patch/src/lib.rs::apply_hunks_to_files()`：

1. 对 `Hunk::UpdateFile` 先计算 `new_contents`（`311-313` 行，调用 `derive_new_contents_from_chunks`）。
2. 若存在 `move_path`：
   - 必要时创建目标父目录（`314-320` 行）。
   - `std::fs::write(dest, new_contents)` 写目标（`321-322` 行），已存在目标会被覆盖。
   - `std::fs::remove_file(path)` 删除源文件（`323-324` 行）。
   - 将 destination 记为 `modified`（`325` 行）。

这解释了为何本目录必须存在 `renamed/dir/name.txt = new`，且 expected 中不再出现 `old/name.txt`。

### 4) 快照数据结构

`scenarios.rs` 用 `BTreeMap<PathBuf, Entry>` 表示快照：

1. `Entry::Dir`。
2. `Entry::File(Vec<u8>)`。

实现细节（`65-105` 行）意味着断言是“结构 + 字节级内容”双重严格比较，不是模糊文本比较。

### 5) 相关命令

1. 运行场景回归：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 运行同语义程序化测试：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_cli_move_overwrites_existing_destination`
3. 刷新研究待办：
   - `bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 目标目录与场景数据

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/name.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/old/other.txt`

### B. 调用方（消费 fixture 的测试）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
2. `codex-rs/apply-patch/tests/suite/tool.rs:155-175`
3. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
4. `codex-rs/apply-patch/tests/all.rs:1-3`

### C. 被调用方（解析与执行）

1. `codex-rs/apply-patch/src/parser.rs:13-21,36,279-330`
2. `codex-rs/apply-patch/src/lib.rs:183-213,279-339`
3. `codex-rs/apply-patch/src/lib.rs:311-325`（move 覆盖关键分支）
4. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`

### D. 上游集成/配置/文档/脚本

1. `codex-rs/apply-patch/src/invocation.rs:132-217`（verified 解析，含 move_path 绝对化）
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-258`
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102,200-215`
4. `codex-rs/arg0/src/lib.rs:85-107`
5. `codex-rs/apply-patch/Cargo.toml:1-30`
6. `codex-rs/apply-patch/BUILD.bazel:3-10`
7. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`
8. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
9. `codex-rs/apply-patch/apply_patch_tool_instructions.md:14-19,40-50`
10. `.ops/generate_daily_research_todo.sh:4-39`

## 依赖与外部交互

### 1) 依赖

`codex-apply-patch` 关键依赖（`Cargo.toml:18-30`）：

1. `anyhow` / `thiserror`：错误封装与传播。
2. `similar`：生成 unified diff（verified 路径使用）。
3. `tree-sitter` / `tree-sitter-bash`：shell heredoc 调用解析。
4. 测试依赖 `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`。

### 2) 外部交互

本目录本身是静态测试数据，但其生效依赖以下外部交互：

1. 文件系统：读取 input、写 destination、删除 source、读取 expected/actual 快照。
2. 进程：测试中通过子进程调用 `apply_patch` 二进制。
3. 标准流：`apply_patch` 输出成功摘要到 stdout，错误信息到 stderr。

### 3) 构建与运行链路交互

1. `BUILD.bazel` 通过 `compile_data` 带入 `apply_patch_tool_instructions.md`。
2. `core` handler/runtime 对 patch 先验证后执行，执行命令为 `codex --codex-run-as-apply-patch <patch>`。
3. `arg0` 负责把 `apply_patch` 或隐藏参数分发到 `codex_apply_patch::apply_patch`。

## 风险、边界与改进建议

### 风险与边界

1. move 不是原子 `rename`，而是“写目标 + 删源”；若删源失败会出现部分完成状态。
2. destination 覆盖语义是当前实现事实，但文档层对“覆盖 vs 拒绝”策略说明仍可更显式。
3. 场景测试更关注最终文件树，不直接断言退出码/stderr，错误语义需依赖 `tool.rs` 用例补充。
4. 本目录只覆盖成功路径，尚未覆盖以下边界：目标为目录、只读权限、并发冲突、跨设备异常。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 明确写出 destination 存在时的覆盖语义。
2. 为 fixtures 增加可选行为断言元数据（如 `exit_code.txt`、`stderr.txt`），提升可观测性。
3. 新增失败边界场景：
   - `move_destination_is_directory_fails`
   - `move_destination_readonly_fails`
   - `move_partial_failure_after_dest_write`
4. 若未来需要更强一致性，可评估临时文件 + 原子替换方案，并将冲突策略显式配置化。
