# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是场景 `011_add_overwrites_existing_file` 的最终态基准（`expected oracle`），职责是定义补丁执行后的文件系统真值，而不承担任何执行逻辑。

目录内当前唯一文件：

1. `duplicate.txt`：内容为 `new content`，表示在输入态已有同名文件时，执行 `*** Add File: duplicate.txt` 后结果应为覆盖后的新内容。

与同场景其他资产的职责分工：

1. `input/duplicate.txt`：初始态（`old content`）。
2. `patch.txt`：操作定义（`Add File` + `+new content`）。
3. `expected/duplicate.txt`：终态断言。

该目录因此专门回答一个语义问题：`Add File` 在“文件已存在”时，当前实现采用“覆盖写入”而非“冲突报错”。

## 功能点目的

本目录对应的功能点是“Add 覆盖已有文件”，核心目的如下：

1. 锁定行为语义：防止后续重构把当前覆盖行为改成拒绝覆盖。
2. 作为回归锚点：与 `tests/suite/tool.rs` 里的同名语义测试相互校验，避免仅靠单一测试形态。
3. 约束最终文件树：`scenarios` 测试比较的是目录快照，`expected/` 直接决定断言真值。
4. 与相邻场景区分：`001_add_file` 关注“新增”；`011_add_overwrites_existing_file` 关注“新增指令命中已存在路径时的冲突策略”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 协议输入到 Hunk 的转换

`patch.txt` 内容：

```patch
*** Begin Patch
*** Add File: duplicate.txt
+new content
*** End Patch
```

`parser.rs` 中 `parse_one_hunk()` 识别 `*** Add File: ` 头后，逐行消费前缀为 `+` 的行并拼接为 `contents`，最终产生：

- `Hunk::AddFile { path: "duplicate.txt", contents: "new content\n" }`

关键点是：解析阶段不检查“目标路径是否已存在”，因此是否覆盖完全由执行阶段决定。

### 2) 执行阶段为何会覆盖

`lib.rs::apply_hunks_to_files()` 在 `Hunk::AddFile` 分支中执行：

1. 如有父目录则 `create_dir_all(parent)`。
2. 调用 `std::fs::write(path, contents)` 写入目标文件。
3. 将路径记录到 `AffectedPaths.added`，摘要输出 `A duplicate.txt`。

`std::fs::write` 对已存在常规文件会截断重写，所以输入态 `old content` 被覆盖为 `new content\n`。`expected/duplicate.txt` 即该实现语义的直接投影。

### 3) 场景夹具测试如何消费 `expected/`

`tests/suite/scenarios.rs` 的执行流程：

1. 遍历 `tests/fixtures/scenarios/*`。
2. 复制 `input/` 到 tempdir。
3. 读取 `patch.txt`，子进程执行 `apply_patch <patch>`。
4. 将 tempdir 与 `expected/` 分别快照为 `BTreeMap<PathBuf, Entry>`，逐项 `assert_eq!`。

这里的 `Entry`：

1. `Entry::Dir`
2. `Entry::File(Vec<u8>)`

因此 `expected/` 不只是文本预期，而是“最终目录树 + 字节内容”的完整断言源。

### 4) 命令/运行路径

常见验证命令：

1. `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. `cargo test -p codex-apply-patch --test all test_apply_patch_cli_add_overwrites_existing_file`

运行链路：

1. `apply_patch` 二进制入口 `src/main.rs` -> `standalone_executable::run_main()`
2. `run_main()` 调 `codex_apply_patch::apply_patch()`
3. `apply_patch()` 先解析再调用 `apply_hunks()`
4. `apply_hunks_to_files()` 实施文件写入

## 关键代码路径与文件引用

### A. 研究对象与场景资产

1. `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/expected/duplicate.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/input/duplicate.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/patch.txt`

### B. 直接调用方（谁读取 `expected/`）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs`（目录驱动执行 + 快照比对）
2. `codex-rs/apply-patch/tests/suite/mod.rs`
3. `codex-rs/apply-patch/tests/all.rs`

### C. 被调用方（解析与执行）

1. `codex-rs/apply-patch/src/parser.rs`（`ADD_FILE_MARKER`、`parse_one_hunk`）
2. `codex-rs/apply-patch/src/lib.rs`（`apply_patch`、`apply_hunks_to_files`、`print_summary`）
3. `codex-rs/apply-patch/src/standalone_executable.rs`（CLI 参数/STDIN 入口）
4. `codex-rs/apply-patch/src/main.rs`（二进制 main）

### D. 并行语义测试（同功能点）

1. `codex-rs/apply-patch/tests/suite/tool.rs`（`test_apply_patch_cli_add_overwrites_existing_file`）
2. `codex-rs/core/tests/suite/apply_patch_cli.rs`（`apply_patch_cli_add_overwrites_existing_file`，覆盖多模型输出路径）

### E. 配置、脚本、文档

1. `codex-rs/apply-patch/Cargo.toml`（crate/bin 与依赖）
2. `codex-rs/apply-patch/BUILD.bazel`（Bazel 构建入口与 `compile_data`）
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`（fixtures 协议）
4. `codex-rs/apply-patch/apply_patch_tool_instructions.md`（工具语法与调用说明）
5. `Docs/researches/blueprint_checklist.md`（研究清单）
6. `.ops/generate_daily_research_todo.sh`（每日 todo 生成脚本）

## 依赖与外部交互

### 1) 依赖关系

`codex-apply-patch` 在该场景相关链路使用：

1. `anyhow` / `thiserror`：错误传递与上下文。
2. `tree-sitter` / `tree-sitter-bash`：shell/heredoc 调用解析（`invocation.rs`）。
3. `assert_cmd` / `tempfile` / `pretty_assertions` / `codex-utils-cargo-bin`：测试执行、进程调用、断言与仓库路径定位。

### 2) 外部交互面

1. 文件系统：读取输入文件、覆盖写入目标文件、目录创建、快照递归读取。
2. 子进程：`scenarios.rs` 与 `tool.rs` 都通过 `cargo_bin("apply_patch")` 启动可执行文件。
3. 标准流：成功摘要输出到 stdout，错误输出到 stderr。

### 3) 配置语义（与上游集成）

虽然本场景是 fixture 目录，不直接持有运行配置，但在真实工具链中会经过：

1. `core/src/tools/handlers/apply_patch.rs`：对 patch 做 verified 解析并计算权限。
2. `core/src/tools/runtimes/apply_patch.rs`：构造 `codex --codex-run-as-apply-patch <patch>` 命令，带 sandbox/approval 配置执行。
3. `arg0/src/lib.rs`：识别 `--codex-run-as-apply-patch` 并分发到 `codex_apply_patch::apply_patch`。

这说明该语义不只存在于独立 CLI，也被 core 工具执行链复用。

## 风险、边界与改进建议

### 风险与边界

1. 文档与实现表述偏差：指令文案常写“create a new file”，但实现对已有文件是覆盖，容易产生认知差异。
2. 覆盖非原子风险：当前是直接 `fs::write`，极端中断可能留下部分写入状态。
3. 场景断言范围：`scenarios.rs` 只比较最终文件树，不直接断言退出码/stderr 文本。
4. 类型边界未覆盖：本场景仅验证“目标为已存在常规文件”；未覆盖目录、只读权限、符号链接等目标类型。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 明确写出当前 `Add File` 的覆盖语义，降低歧义。
2. 增加针对 `Add` 的边界 fixture：
   - 目标是目录时的失败语义；
   - 目标只读时的行为；
   - 符号链接目标写入行为。
3. 为 `scenarios` 机制增加可选行为断言元数据（如 `exit_code.txt` / `stderr.txt`），补齐“最终态之外”的验证维度。
