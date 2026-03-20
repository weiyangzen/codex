# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属模块：`codex-rs/apply-patch` 场景夹具（fixtures）
- 对应测试入口：`codex-rs/apply-patch/tests/suite/scenarios.rs`

## 场景与职责

该目录是场景 `010_move_overwrites_existing_destination` 的 **最终状态基准（expected oracle）**，不执行逻辑，只定义“apply_patch 执行后文件系统应当变成什么样”。

当前目录结构与职责：

1. `expected/renamed/dir/name.txt`
   - 目标文件，内容为 `new`。
   - 表示 `*** Update File: old/name.txt` + `*** Move to: renamed/dir/name.txt` 执行后，目标路径内容被更新且覆盖旧目标文件内容。
2. `expected/old/other.txt`
   - 无关文件，内容保持 `unrelated file`。
   - 用于约束补丁仅影响命中路径，不误伤旁路文件。

该目录与同场景 `input/`、`patch.txt` 共同组成三件套契约：

1. 输入态由 `input/` 给出。
2. 变更指令由 `patch.txt` 给出。
3. 输出态由 `expected/` 给出。

## 功能点目的

这个 `expected/` 目录主要验证 `Move to` 的覆盖分支行为，目的包括：

1. 验证移动更新时的 **目标覆盖语义**：目的路径原本存在文件（`existing`），最终应被覆盖为 `new`。
2. 验证移动后源文件应消失：由于 `expected/` 不包含 `old/name.txt`，快照比对会强制检查“源文件已删除”。
3. 验证副作用边界：`old/other.txt` 仍存在且内容不变。
4. 为目录驱动 E2E 提供稳定回归锚点，防止后续实现将“覆盖”悄然改成“拒绝冲突”或其他行为。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景执行关键流程

1. `tests/suite/scenarios.rs::test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`。
2. 命中 `010_move_overwrites_existing_destination` 时，`run_apply_patch_scenario()`：
   - 复制 `input/` 到临时目录。
   - 读取 `patch.txt`。
   - 启动 `apply_patch` 子进程执行补丁。
3. 执行后用 `snapshot_dir(expected_dir)` 与 `snapshot_dir(tmp.path())` 做全量比对。
4. 两侧都映射为 `BTreeMap<PathBuf, Entry>`，其中 `Entry` 为：
   - `Entry::Dir`
   - `Entry::File(Vec<u8>)`

结论：`expected/` 的目录项和文件字节内容直接参与断言，任何偏差都会导致场景失败。

### 2) 协议与解析到执行的映射

`patch.txt` 关键内容：

```patch
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-from
+new
*** End Patch
```

语法映射：

1. `parser.rs` 把该段解析为 `Hunk::UpdateFile { path, move_path: Some(...), chunks }`。
2. `lib.rs::apply_hunks_to_files()` 在 `move_path` 分支执行：
   - 计算 `new_contents`
   - `write(dest, new_contents)`（已存在目标文件会被覆盖）
   - `remove_file(path)` 删除源文件
3. 因此 `expected/renamed/dir/name.txt=new` 且不存在 `old/name.txt` 是实现结果的直接投影。

### 3) 数据结构与断言影响

1. `snapshot_dir_recursive()` 使用 `fs::metadata()`（跟随符号链接）统一 Cargo/Buck2 行为。
2. 断言按字节比较 `Vec<u8>`，不是宽松文本比较。
3. 使用 `BTreeMap` 保证稳定顺序，避免遍历顺序噪音。

这意味着：

1. 内容末尾换行差异会失败。
2. 多余目录或缺失目录也会失败。
3. `expected/` 必须精确表达最终文件树。

### 4) 复现与验证命令

1. 运行 fixtures 场景回归：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 运行同语义 CLI 单测：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_cli_move_overwrites_existing_destination`
3. 刷新研究任务清单：
   - `bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 本目录与场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/old/other.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/name.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt`

### B. 直接调用方（测试）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs`（目录驱动执行与 expected 快照比对）
2. `codex-rs/apply-patch/tests/suite/tool.rs`（`test_apply_patch_cli_move_overwrites_existing_destination`）
3. `codex-rs/apply-patch/tests/suite/mod.rs`
4. `codex-rs/apply-patch/tests/all.rs`

### C. 被调用实现（解析/执行）

1. `codex-rs/apply-patch/src/parser.rs`（`MOVE_TO_MARKER`、`UpdateFile.move_path` 解析）
2. `codex-rs/apply-patch/src/lib.rs`（`apply_patch`、`apply_hunks_to_files`、`derive_new_contents_from_chunks`）
3. `codex-rs/apply-patch/src/standalone_executable.rs`（CLI 参数/STDIN 入口）

### D. 上下游集成与配置

1. `codex-rs/core/src/tools/handlers/apply_patch.rs`（模型工具调用拦截与 verified 解析）
2. `codex-rs/core/src/tools/runtimes/apply_patch.rs`（构造 `--codex-run-as-apply-patch` 执行请求）
3. `codex-rs/arg0/src/lib.rs`（`apply_patch`/`applypatch` argv0 分发）
4. `codex-rs/apply-patch/Cargo.toml`（crate 与依赖定义）
5. `codex-rs/apply-patch/BUILD.bazel`（Bazel crate 与 compile_data）
6. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`（fixtures 规范）
7. `codex-rs/apply-patch/apply_patch_tool_instructions.md`（apply_patch 文法与调用约束）

### E. 脚本与任务清单

1. `Docs/researches/blueprint_checklist.md`
2. `.ops/generate_daily_research_todo.sh`
3. `Docs/researches/todos_20260320.md`

## 依赖与外部交互

### 1) crate 依赖

`codex-apply-patch` 关键依赖及其在本场景的作用：

1. `anyhow`、`thiserror`：错误封装与上下文。
2. `similar`：生成 unified diff（用于 verified 路径，不直接决定 expected，但属于同功能链）。
3. `tree-sitter`、`tree-sitter-bash`：解析 shell/heredoc 形式 apply_patch 调用。
4. 测试依赖 `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`。

### 2) 外部交互面

1. 文件系统：读源文件、写目标文件、删源文件、递归建目录。
2. 进程：测试通过子进程启动 `apply_patch` 二进制。
3. 标准流：成功摘要写 stdout，错误写 stderr。

### 3) 与构建系统交互

1. Bazel 通过 `BUILD.bazel` 把 `apply_patch_tool_instructions.md` 作为 `compile_data`。
2. fixtures 在测试运行时由 `repo_root()` + 相对路径定位，不依赖网络或外部服务。

## 风险、边界与改进建议

### 风险与边界

1. 非原子 move 实现：当前为“写目标 + 删源”，删除失败会留下部分完成状态。
2. 覆盖语义是实现事实：目的文件存在时默认覆盖，若调用方预期冲突报错会产生认知偏差。
3. fixtures 断言最终态优先：`scenarios.rs` 不直接断言退出码/stderr，行为信息主要靠 `tool.rs` 补齐。
4. 本目录仅覆盖成功路径：未覆盖权限不足、目标为目录、并发竞争、跨设备异常等边界。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 明确写出 `Move to` 覆盖已存在目标文件的当前语义。
2. 为 fixtures 增加可选行为断言文件（例如 `exit_code.txt`、`stderr.txt`），提升目录驱动测试的信息密度。
3. 新增失败边界场景：
   - `move_destination_is_directory_fails`
   - `move_destination_readonly_fails`
   - `move_overwrite_then_remove_source_fails_partial_state`
4. 若后续需要可配置冲突策略，可引入“覆盖/拒绝”显式模式并为二者建立独立 fixture。
