# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`011_add_overwrites_existing_file` 是 `apply_patch` fixture 体系里的“Add 操作覆盖已有同名文件”场景。它通过一个最小目录明确回答一个关键语义问题：`*** Add File:` 在目标文件已存在时是报错，还是覆盖。

本目录资产与职责如下：

1. `patch.txt` 定义单一操作 `*** Add File: duplicate.txt`，内容为 `new content`（`codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/patch.txt:1-4`）。
2. `input/duplicate.txt` 提供执行前状态，内容 `old content`（`.../input/duplicate.txt:1`）。
3. `expected/duplicate.txt` 给出执行后状态，内容 `new content`（`.../expected/duplicate.txt:1`）。

该场景是 `001_add_file` 的边界补充：

1. `001` 覆盖“目标不存在时新增成功”。
2. `011` 覆盖“目标已存在时 Add 的冲突处理语义”。

## 功能点目的

该场景的目的不是语法正确性，而是锁定当前实现的文件系统语义，避免未来重构把“覆盖”误改成“拒绝”。

1. 语义锁定：`Add File` 当前实现允许覆盖已有同名常规文件。
2. 回归防线：保护 CLI 层与 core 集成层都沿用一致语义，不因调用链差异产生分叉行为。
3. 用户契约澄清：工具文档写的是“create a new file”，但实际执行为 `std::fs::write` 覆盖写入；该场景用测试事实固定现状。
4. 与 move 语义区分：`010_move_overwrites_existing_destination` 测的是 `Move to` 覆盖；`011` 单独证明 `Add` 也覆盖。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 协议输入与解析结果

场景 patch：

```patch
*** Begin Patch
*** Add File: duplicate.txt
+new content
*** End Patch
```

解析过程由 `parse_patch()` -> `parse_one_hunk()` 完成：

1. 边界标记校验 `*** Begin Patch` / `*** End Patch`（`codex-rs/apply-patch/src/parser.rs:233-243`）。
2. 命中 `*** Add File: ` 分支，收集所有 `+` 行，逐行补 `\n` 形成 `contents`（`codex-rs/apply-patch/src/parser.rs:251-270`）。
3. 输出 `Hunk::AddFile { path, contents }`，其中 `path=duplicate.txt`，`contents="new content\n"`。

### 2) 执行阶段为何会覆盖

覆盖行为来自执行器 `apply_hunks_to_files()` 的 `Hunk::AddFile` 分支：

1. 如有父目录先 `create_dir_all(parent)`（`codex-rs/apply-patch/src/lib.rs:290-295`）。
2. 直接 `std::fs::write(path, contents)`（`codex-rs/apply-patch/src/lib.rs:297-298`）。
3. `std::fs::write` 对已存在常规文件语义是截断并重写，因此旧内容被新内容覆盖。
4. 成功后路径计入 `affected.added`，摘要打印 `A duplicate.txt`（`codex-rs/apply-patch/src/lib.rs:299`, `537-544`）。

这里没有“若文件已存在则报错”的分支，因此 `011` 的 expected 就是实现自然结果。

### 3) fixture 驱动测试如何消费该目录

`tests/suite/scenarios.rs` 的回放流程：

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 把 `input/` 复制到临时目录（`.../scenarios.rs:33-37`）。
3. 读取 `patch.txt` 并执行 `apply_patch <patch>`（`.../scenarios.rs:39-48`）。
4. 比较临时目录与 `expected/` 的全量快照（`BTreeMap<PathBuf, Entry>`，`.../scenarios.rs:50-77`）。

因此本场景最终断言的是“文件树最终态一致”，而非退出码/stderr 文案。

### 4) 代码驱动测试与上游集成如何复核同语义

除了 fixture 回放，仓库还有两层同语义测试：

1. CLI 层：`test_apply_patch_cli_add_overwrites_existing_file()` 先写入 `old content`，再执行 Add patch，断言 stdout 为 `A duplicate.txt` 且文件变为 `new content\n`（`codex-rs/apply-patch/tests/suite/tool.rs:177-191`）。
2. Core 集成层：`apply_patch_cli_add_overwrites_existing_file()` 在 `ApplyPatchModelOutput` 多模式下都断言覆盖成功（`codex-rs/core/tests/suite/apply_patch_cli.rs:340-363`）。

### 5) 调用链（caller/callee）与命令通路

1. 独立二进制入口：`apply_patch` main 读取 argv/stdin，调用 `crate::apply_patch()`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
2. 验证入口：`maybe_parse_apply_patch_verified()` 将 Add hunk 映射为 `ApplyPatchFileChange::Add`，不读取现有目标文件、也不做冲突检查（`codex-rs/apply-patch/src/invocation.rs:163-169`）。
3. Core handler：`core` 先校验 patch，再走内部 apply 或 runtime 执行（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-240`）。
4. Core runtime：构造 `codex --codex-run-as-apply-patch <patch>` 并在沙箱尝试中执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`, `200-215`）。
5. arg0 分发：当 argv1 为 `--codex-run-as-apply-patch` 时直接调用 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:89-107`）。

### 6) 协议文档与实现存在的语义张力

`apply_patch_tool_instructions.md` 将 `Add File` 描述为“create a new file”（`codex-rs/apply-patch/apply_patch_tool_instructions.md:14`），但实现上是覆盖写入；`011` 实际上承担了“规范以实现为准”的回归锚点角色。

## 关键代码路径与文件引用

### A. 目标目录（被研究对象）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/patch.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/input/duplicate.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/expected/duplicate.txt`

### B. 直接调用方（谁消费这个场景目录）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
2. `codex-rs/apply-patch/tests/all.rs:1-3`
3. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`

### C. 同语义测试（非 fixture，但验证相同功能点）

1. `codex-rs/apply-patch/tests/suite/tool.rs:177-191`
2. `codex-rs/core/tests/suite/apply_patch_cli.rs:340-363`

### D. 被调用方（解析与执行核心）

1. `codex-rs/apply-patch/src/parser.rs:233-270`（patch 边界与 Add hunk 解析）
2. `codex-rs/apply-patch/src/lib.rs:289-300`（Add 文件写入与 added 记录）
3. `codex-rs/apply-patch/src/invocation.rs:132-169`（verified 变更建模）
4. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`（CLI 参数/stdin 入口）

### E. 上游集成/运行时链路

1. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-257`
2. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:200-215`
4. `codex-rs/arg0/src/lib.rs:85-107`

### F. 配置、文档、脚本

1. `codex-rs/apply-patch/Cargo.toml:1-30`（crate/bin、依赖与测试依赖）
2. `codex-rs/apply-patch/BUILD.bazel:1-10`（Bazel 构建与 compile_data）
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`（fixture 协议）
4. `codex-rs/apply-patch/apply_patch_tool_instructions.md:14-16,40-50`（Add 语法与说明）
5. `.ops/generate_daily_research_todo.sh:1-42`（研究 checklist 到每日 todo 的生成脚本）
6. `Docs/researches/blueprint_checklist.md:114`（本次目标勾选项）

## 依赖与外部交互

### 1) crate 与测试依赖

`codex-apply-patch` 在本场景相关链路中的关键依赖：

1. `anyhow` / `thiserror`：错误建模与上下文。
2. `tree-sitter` / `tree-sitter-bash`：shell heredoc 形式 `apply_patch` 解析。
3. `assert_cmd` / `tempfile` / `pretty_assertions` / `codex-utils-cargo-bin`：场景回放与 CLI 断言（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 文件系统交互

1. fixture runner 会复制 `input/`，在 tempdir 执行 patch，再快照对比 `expected/`。
2. Add 执行阶段调用 `std::fs::write`，对同名文件为覆盖写入。
3. 若目标父目录不存在会自动创建。

### 3) 进程交互

1. `tests/suite/scenarios.rs` 每个场景通过子进程执行 `apply_patch`（`.../scenarios.rs:45-48`）。
2. core runtime 通过 `codex --codex-run-as-apply-patch` 自调用执行，复用相同底层 apply 逻辑。

### 4) 文档与构建交互

1. `apply_patch_tool_instructions.md` 被 `include_str!` 使用，且在 Bazel 中通过 `compile_data` 显式打包（`codex-rs/apply-patch/BUILD.bazel:8-10`）。
2. fixture 目录规范由 `scenarios/README.md` 定义，使本场景在跨实现迁移时仍可复用。

## 风险、边界与改进建议

### 风险与边界

1. 语义歧义风险：文档语句“create a new file”容易被理解为“若已存在则失败”，而实现与测试都体现“覆盖”。
2. 非原子覆盖风险：`std::fs::write` 为直接覆盖，异常中断时可能留下截断文件（取决于底层 FS/OS）。
3. 场景断言边界：fixture runner 不检查退出码与 stderr，仅比较最终文件树（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。
4. 类型边界未覆盖：`011` 只覆盖“已存在常规文件”，未覆盖“目标是目录/只读文件/符号链接”下 Add 行为。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 明确补一句：当前实现中 `Add File` 对已存在同名常规文件采用覆盖语义。
2. 新增 fixture：
- `add_target_is_directory_fails`
- `add_overwrites_readonly_file_fails_or_succeeds`（按平台策略明确期望）
- `add_via_symlink_target`
3. 在 `scenarios` 机制引入可选元数据断言（如 `exit_code.txt` / `stderr.txt`），避免仅靠最终态导致错误信息回归漏检。
4. 若未来要改成“严格新增”，需同步调整三层：
- `src/lib.rs` Add 分支冲突检查；
- `tests/suite/tool.rs` 和 `core/tests/suite/apply_patch_cli.rs` 期望；
- 本 fixture `011` 的 expected 与文档说明。
