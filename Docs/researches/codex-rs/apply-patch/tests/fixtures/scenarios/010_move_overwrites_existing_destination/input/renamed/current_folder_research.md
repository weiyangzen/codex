# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 对应场景：`010_move_overwrites_existing_destination`

## 场景与职责

该目录是场景 `010_move_overwrites_existing_destination` 的输入态子树之一，目录结构只有两层：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt:1`，内容为 `existing`

它在场景中的职责不是“被更新源文件”，而是“预置已存在目标文件”。
对应补丁定义为：

- `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt:1-7`
  - `*** Update File: old/name.txt`
  - `*** Move to: renamed/dir/name.txt`

因此本目录承担的验证职责是：当 `Move to` 目标路径已存在同名文件时，`apply_patch` 当前实现应覆盖其内容，而不是报冲突或跳过。

从测试驱动看，`tests/suite/scenarios.rs` 会把整个 `input/` 复制到临时目录后执行补丁，再与 `expected/` 做字节级快照比对（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-60`）。所以 `input/renamed` 的每个字节都直接参与最终断言基线。

## 功能点目的

该目录服务的核心功能点是“移动更新覆盖已存在目标文件”的行为契约。具体目标如下：

1. 证明 `Move to` 分支在目标已存在时是覆盖语义（`existing` -> `new`），不是拒绝语义。
2. 证明覆盖行为只影响命中路径，不影响无关文件（同场景中 `old/other.txt` 仍应保持 `unrelated file`）。
3. 和 `004_move_to_new_directory` 场景形成互补：
   - `004` 验证“目标目录/文件不存在时创建+移动”。
   - `010` 验证“目标文件已存在时覆盖+移动”。

程序化断言也单独覆盖了这一语义：

- `codex-rs/apply-patch/tests/suite/tool.rs:155-174` 的 `test_apply_patch_cli_move_overwrites_existing_destination`
  - 构造 `destination` 预置内容 `existing\n`
  - 断言成功后 `destination` 变为 `new\n`
  - 断言 `original_path` 被删除

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程（从 fixture 到执行）

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:10-25`）。
2. `run_apply_patch_scenario()` 复制 `input/` 到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37,107-124`）。
3. 读取 `patch.txt` 并执行 `apply_patch` 子进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
4. 将临时目录快照与 `expected/` 快照做 `assert_eq!`（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。

### 2) 解析与数据结构

1. `parser` 层把 `*** Move to:` 解析为 `Hunk::UpdateFile { move_path: Option<PathBuf>, ... }`：
   - 语法常量：`MOVE_TO_MARKER`（`codex-rs/apply-patch/src/parser.rs:35-39`）
   - 解析位置：`parse_one_hunk()`（`codex-rs/apply-patch/src/parser.rs:279-330`）
2. `invocation` 层在验证时把相对 `move_path` 解析为基于 `effective_cwd` 的绝对路径，并放入 `ApplyPatchFileChange::Update`（`codex-rs/apply-patch/src/invocation.rs:132-217`）。
3. `scenarios` 快照结构是 `BTreeMap<PathBuf, Entry>`，其中 `Entry = Dir | File(Vec<u8>)`，确保目录结构和文件字节都参与比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-105`）。

### 3) 覆盖语义发生点（核心实现）

`apply_hunks_to_files()` 的 `UpdateFile + move_path` 分支（`codex-rs/apply-patch/src/lib.rs:279-339`）：

1. 先由 `derive_new_contents_from_chunks()` 生成新内容（`codex-rs/apply-patch/src/lib.rs:348-380`）。
2. `create_dir_all(dest.parent())` 确保目标父目录存在（`codex-rs/apply-patch/src/lib.rs:314-320`）。
3. `std::fs::write(dest, new_contents)` 写入目标路径（`codex-rs/apply-patch/src/lib.rs:321-322`）。
4. `std::fs::remove_file(path)` 删除源路径（`codex-rs/apply-patch/src/lib.rs:323-324`）。

这里使用 `std::fs::write`，在目标文件已存在时会直接覆盖，因此本目录 `input/renamed/dir/name.txt` 的预置内容 `existing` 会被替换为 `new`。

### 4) 协议与命令

1. apply-patch 指令文档明确 `Update File` 后可接 `Move to`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:14-20,47-49`）。
2. core 侧工具语法也允许 `update_hunk` 搭配可选 `change_move`（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-17`）。
3. 典型回归命令：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
   - `cargo test -p codex-apply-patch --test all test_apply_patch_cli_move_overwrites_existing_destination`

## 关键代码路径与文件引用

### 目标目录与场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt:1-7`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/name.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt:1`

### 测试与执行链路

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:10-126`
4. `codex-rs/apply-patch/tests/suite/tool.rs:155-174`
5. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
6. `codex-rs/apply-patch/src/lib.rs:279-339`
7. `codex-rs/apply-patch/src/parser.rs:279-330`
8. `codex-rs/apply-patch/src/invocation.rs:132-217`

### 调用方/被调用方（上层集成）

1. 调用方（工具入口）
   - `codex-rs/core/src/tools/handlers/apply_patch.rs:146-258`：解析 patch、验证、组装 runtime 请求
2. 权限与安全
   - `codex-rs/core/src/tools/handlers/apply_patch.rs:46-124`：提取源/目标路径用于写权限申请
   - `codex-rs/core/src/safety.rs:159-175`：`Update` 同时校验源路径和 `move_path` 可写性
3. 执行 runtime
   - `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101,200-215`：构造 `codex --codex-run-as-apply-patch <patch>` 并在 sandbox attempt 下执行
4. arg0 分发
   - `codex-rs/arg0/src/lib.rs:89-107`：识别 `CODEX_CORE_APPLY_PATCH_ARG1` 并调用 `codex_apply_patch::apply_patch`

### 配置、文档、脚本

1. crate 配置：`codex-rs/apply-patch/Cargo.toml:1-30`
2. Bazel 编译数据：`codex-rs/apply-patch/BUILD.bazel:1-11`
3. fixtures 约定文档：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
4. 行尾规范：`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
5. 工具文档：`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50,65-75`
6. 研究流程脚本：`.ops/generate_daily_research_todo.sh:4-42`

## 依赖与外部交互

### 1) 依赖（编译/测试）

来自 `codex-rs/apply-patch/Cargo.toml:18-30`：

1. `anyhow`、`thiserror`：错误传播与结构化错误。
2. `similar`：生成 unified diff（verified 流程用）。
3. `tree-sitter`、`tree-sitter-bash`：解析 shell/heredoc 形式的 apply_patch 调用。
4. `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`：集成测试与可执行定位。

### 2) 外部交互

1. 文件系统交互
   - 读取源文件、写目标文件、删除源文件、复制 fixture、目录快照比较。
2. 进程交互
   - `tests/suite/scenarios.rs` 通过 `Command::new(cargo_bin("apply_patch"))` 启动子进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. 标准流交互
   - 成功摘要输出 `Success. Updated the following files:` + `M <path>`（`codex-rs/apply-patch/src/lib.rs:537-551`）。

### 3) 协议/权限交互

1. `ApplyPatchHandler` 会把 update 的源路径和 move 目标路径都纳入权限集合（`codex-rs/core/src/tools/handlers/apply_patch.rs:46-63`）。
2. safety 检查要求这两类路径都可写，否则拒绝（`codex-rs/core/src/safety.rs:166-175`）。
3. runtime 执行时传最小环境并走 sandbox/审批流程（`codex-rs/core/src/tools/runtimes/apply_patch.rs:96-101,122-197`）。

## 风险、边界与改进建议

### 风险

1. 非原子移动风险：当前逻辑是“写目标再删源”，若 `remove_file(path)` 失败，可能留下“源和目标同时存在”的中间态（`codex-rs/apply-patch/src/lib.rs:321-324`）。
2. 文档语义缺口：工具文档说明了可 `Move to`，但没有显式写出“目标已存在时覆盖”策略，易导致调用方预期分歧（`codex-rs/apply-patch/apply_patch_tool_instructions.md:14-20`）。
3. 场景框架观测维度有限：`scenarios` 用最终文件系统状态断言，不校验 exit status/stderr，错误消息层回归可能被遗漏（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。

### 边界

1. 本目录只验证“目标为已存在文件”的覆盖路径，不覆盖“目标是目录”或“权限不足”异常。
2. 本目录不涉及 shell heredoc/`cd` 解析边界；该部分由 `invocation.rs` 单测覆盖（`codex-rs/apply-patch/src/invocation.rs:767-812`）。
3. 本目录也不覆盖跨设备 rename 等平台差异语义（当前实现非 `rename`，而是写+删）。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 增补一句明确契约：`Move to` 命中已存在目标文件时按覆盖处理。
2. 为 fixture 框架引入可选元数据断言（例如 `exit_code.txt`、`stderr_contains.txt`），让“状态+输出”双维度可回归。
3. 新增负向场景：`move_destination_is_directory`、`move_source_remove_failure`，把当前边界行为固定成可审查测试。
4. 如需更强一致性，可评估“临时文件 + 原子替换”方案，以降低写入成功但删除失败的半成功窗口。
