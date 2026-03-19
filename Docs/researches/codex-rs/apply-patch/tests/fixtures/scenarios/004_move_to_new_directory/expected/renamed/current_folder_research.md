# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 当前目录结构：`dir/name.txt`

## 场景与职责

该目录是场景 `004_move_to_new_directory` 的“迁移目标路径真值目录（destination oracle）”。

它的职责不是描述补丁如何执行，而是定义执行完成后目标路径必须出现的目录树和文件内容：

1. 必须存在新目录层级 `renamed/dir/`。
2. 必须存在迁移后的文件 `renamed/dir/name.txt`。
3. `name.txt` 内容必须是 hunk 应用后的 `new content`，而非源文件原始内容。

在整个场景契约里，`expected/renamed` 与 `expected/old` 分工明确：

1. `expected/renamed` 证明“目标路径已创建并写入正确内容”。
2. `expected/old` 证明“无关文件保留且未受误伤”。

两者同时满足，才构成 `Move to` 的完整验收。

## 功能点目的

围绕本目录，场景 004 主要锁定以下功能目的：

1. 验证 `*** Move to:` 在 `*** Update File:` 内生效，并把结果写到新路径而不是原路径。
2. 验证目标父目录在初始不存在时能自动创建（`renamed/dir` 由执行器创建）。
3. 验证“移动 + 内容更新”是一个组合语义：目标文件既改路径又改内容。
4. 验证目录快照断言会严格要求目标目录结构存在，避免仅靠文件内容误判为通过。
5. 与 `010_move_overwrites_existing_destination` 形成互补：004 覆盖“新目录创建路径”，010 覆盖“已存在目标文件覆盖路径”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. `tests/suite/scenarios.rs::test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`，发现 `004_move_to_new_directory`。
2. `run_apply_patch_scenario()` 把 `input/` 拷贝到临时目录，初始仅有 `old/name.txt`、`old/other.txt`。
3. 读取 `patch.txt` 后，以子进程方式执行 `apply_patch <patch>`。
4. `apply_patch` 内部执行链：
   - `parse_patch()` 把文本解析为 `Hunk::UpdateFile { path, move_path, chunks }`；
   - `apply_hunks_to_files()` 命中 `move_path` 分支；
   - `create_dir_all(dest.parent())` 创建 `renamed/dir`；
   - `write(dest, new_contents)` 写入 `renamed/dir/name.txt`；
   - `remove_file(path)` 删除 `old/name.txt`。
5. 场景测试将 `expected/` 与临时目录做字节级目录快照比对，`expected/renamed/dir/name.txt` 是必须命中的关键断言点。

### 2) 关键数据结构

1. `parser::Hunk::UpdateFile { path, move_path, chunks }`
2. `parser::UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`
3. `lib::AppliedPatch { original_contents, new_contents }`
4. `tests/suite/scenarios.rs::Entry::{Dir, File(Vec<u8>)}`
5. `BTreeMap<PathBuf, Entry>`（用于稳定、可重复的目录快照比较）

### 3) 协议与命令

场景协议（`patch.txt`）：

```patch
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-old content
+new content
*** End Patch
```

与目录 `expected/renamed` 直接相关的命令链：

1. `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. `cargo test -p codex-apply-patch --test all test_apply_patch_cli_moves_file_to_new_directory`
3. `bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 目标目录与场景工件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed/dir/name.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/patch.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/name.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/old/other.txt`

### B. 调用方（谁消费这个目录）

1. `codex-rs/apply-patch/tests/all.rs`
2. `codex-rs/apply-patch/tests/suite/mod.rs`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs`
4. `codex-rs/apply-patch/tests/suite/tool.rs`（语义平行验证：`test_apply_patch_cli_moves_file_to_new_directory`）

### C. 被调用方（如何产出该目录期望）

1. `codex-rs/apply-patch/src/standalone_executable.rs`
2. `codex-rs/apply-patch/src/lib.rs`（`apply_patch` / `apply_hunks_to_files` / `derive_new_contents_from_chunks`）
3. `codex-rs/apply-patch/src/parser.rs`（`MOVE_TO_MARKER`、`move_path` 解析）
4. `codex-rs/apply-patch/src/seek_sequence.rs`（更新块定位）

### D. 配置、脚本、文档与跨 crate 上下文依赖

1. `codex-rs/apply-patch/Cargo.toml`（crate 与 binary 声明）
2. `codex-rs/apply-patch/BUILD.bazel`（compile_data：`apply_patch_tool_instructions.md`）
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`（场景三件套规范）
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes`（统一 LF）
5. `codex-rs/apply-patch/apply_patch_tool_instructions.md`（补丁协议说明）
6. `codex-rs/core/src/tools/handlers/apply_patch.rs`（`maybe_parse_apply_patch_verified` 校验入口）
7. `codex-rs/core/src/tools/runtimes/apply_patch.rs`（`codex --codex-run-as-apply-patch` 执行路径）
8. `codex-rs/core/src/tools/spec.rs`（`apply_patch` 工具注册，受 `apply_patch_tool_type` 控制）
9. `codex-rs/core/src/config/mod.rs`（`include_apply_patch_tool` 特性衍生配置）
10. `codex-rs/arg0/src/lib.rs`（`apply_patch`/`applypatch` arg0 分发）
11. `.ops/generate_daily_research_todo.sh`（每日研究 TODO 生成）
12. `Docs/researches/blueprint_checklist.md`（研究进度基准）

## 依赖与外部交互

### 1) 依赖

`codex-apply-patch` 该路径相关核心依赖：

1. `anyhow`、`thiserror`：错误建模与上下文信息。
2. `similar`：生成 unified diff（供 verified/上游消费）。
3. `tree-sitter`、`tree-sitter-bash`：shell heredoc 形式调用解析。
4. `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`：测试执行与断言。

### 2) 外部交互

1. 文件系统交互：读 `old/name.txt`，建 `renamed/dir`，写 `renamed/dir/name.txt`，删 `old/name.txt`。
2. 进程交互：测试通过 `Command::new(cargo_bin("apply_patch"))` 启动二进制。
3. 标准流交互：成功输出 `Success. Updated the following files:`，失败输出错误描述。
4. 跨 crate 交互：`core` 层先做 patch 结构校验与审批，再由 runtime 调用内部 apply_patch 通道落盘。

## 风险、边界与改进建议

### 1) 风险与边界

1. `Move to` 实现是“写目标 + 删源”，不是单次原子 rename；中途失败可能留下部分变更。
2. 场景 fixture 主要比较最终文件树，不直接断言退出码和 stderr，行为回归需依赖 `tool.rs/cli.rs`。
3. 本目录仅覆盖“目标目录可创建且写入成功”正向路径，不覆盖权限不足、只读目录、路径冲突。
4. 该目录只验证目标落点，不单独验证目标已存在文件的覆盖语义（该语义由场景 010 覆盖）。

### 2) 改进建议

1. 增加场景：`move_to_new_directory_permission_denied`，明确失败后源/目标状态期望。
2. 为目录驱动场景扩展元数据断言（如 `expected_exit_code`、`stderr_contains`），补足“只看最终态”的盲区。
3. 在 `apply_patch_tool_instructions.md` 明确 `Move to` 的覆盖与非原子特性，减少调用方误用。
4. 增加“多 chunk + Move to + 新目录创建”组合场景，强化 `expected/renamed` 的复杂路径覆盖。
