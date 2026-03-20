# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/input`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 所属 crate：`codex-apply-patch`
- 目录内实体：`no_newline.txt`

## 场景与职责

`input/` 是场景 `014_update_file_appends_trailing_newline` 的执行前基线目录，职责是为 `patch.txt` 的 `Update File` 操作提供初始文件状态，并和同级 `expected/` 共同构成可回放的三段式契约。

本目录在整体测试中的角色边界：

1. 提供更新前文件：`codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/input/no_newline.txt:1`。
2. 被场景执行器复制到临时目录作为真实工作区：`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`。
3. 不直接参与解析/执行逻辑，只通过“初始内容是否可被 patch 命中”影响执行结果。
4. 最终正确性由 `expected/` 的字节级快照对比判定：`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`。

与同场景其余目录的分工：

1. `input/`：初态。
2. `patch.txt`：操作定义（`Update File`，两行新增）。
3. `expected/`：终态真值（两行文本，末尾换行）。

场景集层面，该目录服务于“更新后收敛到 trailing newline”的回归契约，与 `tool.rs` 的同语义测试共同验证：`codex-rs/apply-patch/tests/suite/tool.rs:223-240`。

## 功能点目的

围绕该 `input/` 目录，核心目的并非覆盖复杂 patch 语法，而是稳定提供一个最小输入，使以下行为可被持续回归：

1. `Update File` 能命中单行旧文本并替换为多行新文本。
2. 更新结果会被实现层标准化为“末尾带 `\n` 的文本文件”。
3. 该行为在 fixture 回放测试与 CLI 集成测试中一致可观测。

对应实现意图的关键代码点：

1. `derive_new_contents_from_chunks` 在输出前强制补尾空行，`join("\n")` 后保证 trailing newline：`codex-rs/apply-patch/src/lib.rs:372-377`。
2. `compute_replacements` 负责把 `old_lines -> new_lines` 映射为 replacement 列表：`codex-rs/apply-patch/src/lib.rs:386-474`。
3. `seek_sequence` 负责匹配旧内容（精确、trim、unicode-normalize 多级策略）：`codex-rs/apply-patch/src/seek_sequence.rs:12-109`。

补充事实：文件名虽为 `no_newline.txt`，但仓库中该输入文件字节末尾实际存在 `0A`（LF），这与场景名存在语义反差；此命名更多强调“行为主题”而非“字节事实”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

场景回放流程（调用方视角）：

1. `test_apply_patch_scenarios()` 扫描 `fixtures/scenarios/*`：`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`。
2. `run_apply_patch_scenario()` 把当前场景 `input/` 递归复制到 `tempdir()`：`codex-rs/apply-patch/tests/suite/scenarios.rs:30-37`。
3. 读取 `patch.txt` 并执行 `apply_patch` 二进制：`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`。
4. 对比 `expected/` 与实际目录快照：`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`。

执行内核流程（被调用方视角）：

1. CLI 入口 `run_main()` 读取 argv 或 stdin：`codex-rs/apply-patch/src/standalone_executable.rs:11-41`。
2. 调用 `apply_patch()`，先 `parse_patch()` 再 `apply_hunks()`：`codex-rs/apply-patch/src/lib.rs:183-213`。
3. `Hunk::UpdateFile` 分支读取原文件、计算替换、写回：`codex-rs/apply-patch/src/lib.rs:306-331`。
4. 输出成功摘要 `Success. Updated the following files`：`codex-rs/apply-patch/src/lib.rs:248-251`。

### 2) 关键数据结构

1. `parser::Hunk::UpdateFile { path, move_path, chunks }`：`codex-rs/apply-patch/src/parser.rs:68-75`。
2. `parser::UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`：`codex-rs/apply-patch/src/parser.rs:90-104`。
3. 场景快照结构：`BTreeMap<PathBuf, Entry>`，其中 `Entry = File(Vec<u8>) | Dir`：`codex-rs/apply-patch/tests/suite/scenarios.rs:65-77`。

### 3) 协议

`apply_patch` 协议来源：

1. fixtures 目录约定：`input/ + patch.txt + expected/`：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`。
2. parser grammar（`update_hunk`、`@@`、`change_line`、可选 `*** End of File`）：`codex-rs/apply-patch/src/parser.rs:6-21`。
3. 工具说明文档（面向调用方）：`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`。

本场景 patch：

```patch
*** Begin Patch
*** Update File: no_newline.txt
@@
-no newline at end
+first line
+second line
*** End Patch
```

来源：`codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/patch.txt:1-7`。

### 4) 命令与脚本

1. 场景测试运行命令入口在 `tests/all.rs` 聚合：`codex-rs/apply-patch/tests/all.rs:1-3`。
2. 研究流程脚本：`.ops/generate_daily_research_todo.sh` 从 `blueprint_checklist.md` 生成当日 todo：`.ops/generate_daily_research_todo.sh:5-41`。
3. 本任务要求更新 checklist 第 127 行，对应目标目录项：`Docs/researches/blueprint_checklist.md:127`。

## 关键代码路径与文件引用

### A. 目标对象

1. `codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/input/no_newline.txt:1`

### B. 直接调用方（谁消费这个 input）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-37`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`
4. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
5. `codex-rs/apply-patch/tests/all.rs:1-3`

### C. 被调用方（输入最终流向的执行链）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:279-339`
4. `codex-rs/apply-patch/src/lib.rs:348-381`
5. `codex-rs/apply-patch/src/lib.rs:386-474`
6. `codex-rs/apply-patch/src/seek_sequence.rs:12-109`
7. `codex-rs/apply-patch/src/parser.rs:106-183`

### D. 上下文依赖（core/tool/runtime/dispatch）

1. 工具注册：`codex-rs/core/src/tools/spec.rs:2784-2804`
2. handler 再校验并编排执行：`codex-rs/core/src/tools/handlers/apply_patch.rs:170-239`
3. runtime 构造 `codex --codex-run-as-apply-patch` 命令：`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`
4. `arg0` 分发到 `codex_apply_patch::apply_patch`：`codex-rs/arg0/src/lib.rs:89-107`
5. 平台文档说明该虚拟 CLI 约定：`codex-rs/core/README.md:94`

### E. 对照测试与文档

1. 同语义 CLI 测试：`codex-rs/apply-patch/tests/suite/tool.rs:223-240`
2. core 集成同语义测试：`codex-rs/core/tests/suite/apply_patch_cli.rs:199-218`
3. exec 侧自调用验证：`codex-rs/exec/tests/suite/apply_patch.rs:20-46`
4. fixture 规范文档：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
5. `apply_patch` 工具说明：`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`

## 依赖与外部交互

### 1) 依赖

`codex-apply-patch` 运行时依赖：

1. `anyhow`、`thiserror`（错误建模）：`codex-rs/apply-patch/Cargo.toml:18-23`。
2. `similar`（diff 相关逻辑）：`codex-rs/apply-patch/Cargo.toml:18-23`。
3. `tree-sitter`、`tree-sitter-bash`（shell/heredoc 解析路径）：`codex-rs/apply-patch/Cargo.toml:22-23`。

测试依赖：

1. `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`：`codex-rs/apply-patch/Cargo.toml:25-30`。

### 2) 文件系统与进程交互

1. 场景测试会复制目录、运行子进程、读取二进制快照：`codex-rs/apply-patch/tests/suite/scenarios.rs:33-53`。
2. 执行器会真实读写目标文件（非内存模拟）：`codex-rs/apply-patch/src/lib.rs:297-329`。
3. `core` 运行时会把 patch 作为参数传给当前 `codex` 可执行文件并在指定 `cwd` 执行：`codex-rs/core/src/tools/runtimes/apply_patch.rs:87-95`。

### 3) 配置与构建交互

1. crate/bin 声明：`codex-rs/apply-patch/Cargo.toml:1-13`。
2. Bazel `compile_data` 引入 `apply_patch_tool_instructions.md`：`codex-rs/apply-patch/BUILD.bazel:3-10`。
3. fixtures 行尾策略 `** text eol=lf`：`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`。

### 4) 文档与脚本交互

1. 本研究任务由 `Docs/researches/blueprint_checklist.md` 管理。
2. todo 通过 `.ops/generate_daily_research_todo.sh` 自动重建。

## 风险、边界与改进建议

### 风险

1. 文件命名与字节事实不一致：`no_newline.txt` 实际以 LF 结尾，可能误导维护者对场景覆盖范围的理解。
2. `scenarios.rs` 明确“不校验退出码”，仅看最终文件树，可能漏掉错误信息退化：`codex-rs/apply-patch/tests/suite/scenarios.rs:42-45`。
3. 当前实现统一补尾换行；若未来要支持“保留无末尾换行”文本，场景期望会与实现目标冲突。

### 边界

1. 本目录只覆盖单文件文本更新，不覆盖二进制、权限位、时间戳、所有者等元数据。
2. 不覆盖 `*** End of File` 分支（由 `022_update_file_end_of_file_marker` 承担）。
3. 不覆盖“多文件部分成功后失败”的事务边界（由 `015_failure_after_partial_success_leaves_changes` 承担）。

### 改进建议

1. 在本场景目录增加短注释（README 或文档段落），明确“行为主题是输出补尾换行，而非输入字节严格无换行”。
2. 为 fixtures 框架扩展可选断言元数据（如 `expected_exit_code`、`stderr_contains`），补齐目前只比文件树的盲区。
3. 若要严格验证“输入文件无末尾换行”，新增不受文本归一化影响的字节级 fixture（例如 `-text` 或显式二进制断言路径）。
4. 在 `apply_patch_tool_instructions.md` 增加“更新输出默认 newline-terminated”说明，减少调用方认知偏差。
