# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是场景 `011_add_overwrites_existing_file` 的“输入态基线（pre-state oracle）”。

目录内容非常小，但职责明确且不可替代：

1. `input/duplicate.txt` 定义补丁执行前文件系统状态，当前内容为 `old content`（`codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/input/duplicate.txt:1`）。
2. 在场景回放流程中，`tests/suite/scenarios.rs` 会先把 `input/` 完整复制到临时目录，再执行补丁（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-48`）。
3. 该输入态与 `patch.txt`、`expected/` 共同锁定语义问题：`*** Add File: duplicate.txt` 命中已存在同名文件时是否覆盖。

因此，`input/` 并非“样例数据”，而是行为契约的一部分：如果这里没有预置 `duplicate.txt`，该场景就会退化成普通新增文件场景，无法验证覆盖语义。

## 功能点目的

本目录对应功能点是“Add 操作覆盖已存在文件”的前置条件构造，目的如下：

1. 语义定位：确保测试对象处于“目标路径已存在常规文件”的初始状态。
2. 回归防护：防止未来实现将 Add 行为改成“仅新建、不允许覆盖”而不被发现。
3. 分层一致性：与 CLI 层和 core 集成层同语义用例共同保证行为一致。
4. 可移植 fixture 设计：符合 `scenarios/README.md` 约定的 `input/ + patch.txt + expected/` 三段结构，便于跨实现复用（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景输入如何进入执行链

1. 场景总入口 `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*` 目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 把当前场景的 `input/` 递归复制到 tempdir（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-37,107-123`）。
3. 读取 `patch.txt` 并在 tempdir 中执行 `apply_patch <patch>` 子进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
4. 最终用 `BTreeMap<PathBuf, Entry>` 快照比对 tempdir 与 `expected/`（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-77`）。

数据结构要点：

1. `Entry::File(Vec<u8>)` 和 `Entry::Dir` 以字节级比较最终状态，不仅比较文本（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-69`）。
2. 本输入目录目前只有一个文件，因此最终比对的关键键是 `duplicate.txt`。

### 2) 协议到执行：为何会发生覆盖

场景 patch 为：

```patch
*** Begin Patch
*** Add File: duplicate.txt
+new content
*** End Patch
```

解析与执行关键点：

1. `parser::parse_one_hunk()` 命中 `*** Add File:` 后把所有 `+` 行拼成 `contents`，得到 `Hunk::AddFile`（`codex-rs/apply-patch/src/parser.rs:251-270`）。
2. `apply_hunks_to_files()` 在 `Hunk::AddFile` 分支中直接 `std::fs::write(path, contents)`（`codex-rs/apply-patch/src/lib.rs:289-299`）。
3. 对“已存在常规文件”，`std::fs::write` 语义是截断并重写，因此 `old content` 被覆盖为 `new content`。
4. 操作摘要仍记为 `A <path>`，因为内部分类是 `added.push(path)`（`codex-rs/apply-patch/src/lib.rs:299,334-338`）。

### 3) 与 verified/integration 链路的关系

1. `maybe_parse_apply_patch_verified()` 对 `AddFile` 仅记录 `ApplyPatchFileChange::Add { content }`，不检查目标是否已存在（`codex-rs/apply-patch/src/invocation.rs:163-169`）。
2. core handler 复用 verified 结果做权限评估并执行 apply_patch，保证该语义在工具链中一致（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-258`）。
3. runtime 会构造 `codex --codex-run-as-apply-patch <patch>` 执行路径（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`），`arg0` 再分发到 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:89-107`）。

### 4) 同功能点测试矩阵

除 fixture 场景外，仓库还有两层同语义验证：

1. CLI 测试：`test_apply_patch_cli_add_overwrites_existing_file`，先写入 `old content`，执行 Add patch，断言文件变为 `new content\n`（`codex-rs/apply-patch/tests/suite/tool.rs:177-191`）。
2. core 集成测试：`apply_patch_cli_add_overwrites_existing_file` 在多种模型输出形态下复核覆盖行为（`codex-rs/core/tests/suite/apply_patch_cli.rs:340-363`）。

### 5) 相关命令与协议语法

1. 场景回放命令：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 单点 CLI 语义命令：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_add_overwrites_existing_file`
3. freeform 语法由 `tool_apply_patch.lark` 提供，`add_hunk` 规则允许 `+` 行作为新文件内容（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:5-11`）。
4. 工具文档中 `Add File` 描述为“create a new file”（`codex-rs/apply-patch/apply_patch_tool_instructions.md:14`），但本场景证明当前实现语义是“可覆盖”。

## 关键代码路径与文件引用

### A. 研究对象与同场景资产

1. `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/input/duplicate.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/patch.txt:1-4`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/011_add_overwrites_existing_file/expected/duplicate.txt:1`

### B. 直接调用方（消费 `input/`）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:107-123`
3. `codex-rs/apply-patch/tests/all.rs:1-3`
4. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`

### C. 被调用方（解析/执行核心）

1. `codex-rs/apply-patch/src/parser.rs:248-270`
2. `codex-rs/apply-patch/src/lib.rs:279-339`
3. `codex-rs/apply-patch/src/invocation.rs:132-217`
4. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`

### D. 上游工具链与运行时

1. `codex-rs/core/src/tools/handlers/apply_patch.rs:46-125`
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-258`
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`
4. `codex-rs/core/src/tools/runtimes/apply_patch.rs:122-215`
5. `codex-rs/arg0/src/lib.rs:89-107`

### E. 配置、测试、脚本、文档

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
5. `codex-rs/apply-patch/apply_patch_tool_instructions.md:10-16,40-50,65-69`
6. `.ops/generate_daily_research_todo.sh:1-42`
7. `Docs/researches/blueprint_checklist.md:116`

## 依赖与外部交互

### 1) 依赖

从 `codex-rs/apply-patch/Cargo.toml:18-30` 可见，本功能点链路关键依赖为：

1. `anyhow`、`thiserror`：错误建模与上下文。
2. `tree-sitter`、`tree-sitter-bash`：shell/heredoc 形式 apply_patch 解析。
3. `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`：场景回放与 CLI 断言。

### 2) 外部交互

1. 文件系统交互：复制 `input/`、读取 `patch.txt`、执行覆盖写、快照比对。
2. 子进程交互：测试通过 `cargo_bin("apply_patch")` 启动二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. 标准流交互：`apply_patch` 成功输出 summary 到 stdout，失败输出 stderr（`codex-rs/apply-patch/src/standalone_executable.rs:49-58`）。
4. core 审批与沙箱交互：handler 计算写权限范围，runtime 在 sandbox attempt 中执行（`codex-rs/core/src/tools/handlers/apply_patch.rs:95-125`, `codex-rs/core/src/tools/runtimes/apply_patch.rs:200-215`）。

### 3) 构建与协议交互

1. `apply_patch_tool_instructions.md` 通过 `include_str!` 被编译进 crate，Bazel 通过 `compile_data` 保证可访问（`codex-rs/apply-patch/BUILD.bazel:8-10`）。
2. freeform 语法在 core 侧由 Lark grammar 暴露，协议和实现共享同一 Add 语法形状（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-19`）。

## 风险、边界与改进建议

### 风险

1. 文档语义偏差风险：规范文案强调“create a new file”，但当前实现是覆盖，调用方容易误解（`codex-rs/apply-patch/apply_patch_tool_instructions.md:14` vs `codex-rs/apply-patch/src/lib.rs:297-299`）。
2. 非原子覆盖风险：`std::fs::write` 直接重写目标文件，异常中断时可能出现部分写入。
3. 场景框架可观测性风险：`scenarios.rs` 仅比较最终文件状态，不断言退出码/stderr 细节（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。

### 边界

1. 本目录仅覆盖“目标为已存在常规文件”的 Add 行为。
2. 未覆盖目标为目录、符号链接、权限受限文件的 Add 行为。
3. 仅验证单文件同名覆盖，不涉及多 hunk、跨目录批量 Add 的冲突策略。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 与 core JSON tool 描述中明确写出：当前 `Add File` 命中已存在常规文件时按覆盖处理。
2. 补充 fixture：
   - `add_target_is_directory_fails`
   - `add_target_is_symlink`
   - `add_overwrite_permission_denied`
3. 为 `scenarios` 框架加入可选 `exit_code`/`stderr` 断言文件，提升错误路径回归能力。
4. 若未来计划改为“严格新增”，需要同步更新 `src/lib.rs`、`tests/suite/tool.rs`、`core/tests/suite/apply_patch_cli.rs` 及本场景输入输出语义文档，避免分层不一致。
