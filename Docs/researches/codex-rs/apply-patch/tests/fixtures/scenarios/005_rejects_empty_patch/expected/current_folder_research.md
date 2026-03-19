# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属模块：`codex-rs/apply-patch`（crate: `codex-apply-patch`）

## 场景与职责

该目录是场景 `005_rejects_empty_patch` 的“期望终态目录（expected oracle）”。

1. 目录当前仅含一个文件：`expected/foo.txt`，内容为 `stable\n`。
2. 在场景测试里，它不参与 patch 执行，仅作为最终文件系统比对基准。
3. 它表达的业务语义是：当 patch 只有 `*** Begin Patch` / `*** End Patch`、没有任何 hunk 时，`apply_patch` 必须失败且不改动文件系统。

与同场景 `input/foo.txt` 的内容一致（均为 `stable\n`）并非冗余，而是负向用例的关键断言设计：失败路径应保持幂等、无副作用。

## 功能点目的

`expected/` 在该场景中的目的不是“描述操作结果”，而是“钉住失败后的不变性契约”。

1. 对 `apply_patch` 独立 CLI：空 patch 会在执行层报错 `No files were modified.`，因此终态应与输入态完全一致（`codex-rs/apply-patch/src/lib.rs:279-282`）。
2. 对场景回放测试：`tests/suite/scenarios.rs` 故意不校验退出码，仅校验目录快照，`expected/` 就成为唯一真值源（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-58`）。
3. 对跨 crate 行为一致性：core 工具链会更早拒绝空 patch（`patch rejected: empty patch`），但同样要求“不落盘变更”，该目录间接保障这一底线语义（`codex-rs/core/src/safety.rs:36-39`，`codex-rs/core/tests/suite/apply_patch_cli.rs:511-527`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景执行主流程

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*` 目录并逐个执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 复制 `input/` 到临时目录，读取 `patch.txt`，执行 `apply_patch <patch>`（`scenarios.rs:30-48`）。
3. 无论命令成功失败，都会对 `expected/` 与临时目录做快照并 `assert_eq!`（`scenarios.rs:50-60`）。
4. 快照结构是 `BTreeMap<PathBuf, Entry>`，其中 `Entry = File(Vec<u8>) | Dir`（`scenarios.rs:65-77`）。

因此 `expected/foo.txt` 的字节级内容（含结尾换行）直接参与等值比较，不是“文本近似比较”。

### 2) 空 patch 的解析/执行分层

1. parser 对 `*** Begin Patch ... *** End Patch` 可解析为 `hunks = []`（`codex-rs/apply-patch/src/parser.rs:154-182`, `483-490`）。
2. 真正拒绝发生在执行层：`apply_hunks_to_files()` 对空 hunk 列表直接 `bail!("No files were modified.")`（`codex-rs/apply-patch/src/lib.rs:279-282`）。
3. CLI 入口 `run_main()` 捕获错误并返回退出码 `1`（`codex-rs/apply-patch/src/standalone_executable.rs:49-58`）。
4. `tool.rs` 单测补充了 stderr 精确断言（`codex-rs/apply-patch/tests/suite/tool.rs:85-93`）。

`expected/` 的职责就是固定“失败后文件树不变”，与 stderr/exit code 断言形成互补覆盖。

### 3) 协议与命令语义

1. 协议文档写明 patch 包络与文件操作语法，规范语义是应包含文件操作段（`codex-rs/apply-patch/apply_patch_tool_instructions.md:6-50`）。
2. 场景 `005` 的 `patch.txt` 仅有边界行，是“语法边界合法、语义无操作”的极小输入。
3. 回放执行命令等价于：

```bash
apply_patch "*** Begin Patch
*** End Patch"
```

4. `expected/foo.txt` 作为结果真值，要求执行后临时目录中 `foo.txt` 仍保持 `stable\n`。

## 关键代码路径与文件引用

### A. 目标目录与同场景夹具

1. `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/expected/foo.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/input/foo.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/patch.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`

### B. 直接调用方（消费 `expected/`）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`（遍历场景）
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`（复制输入、执行命令、快照比较）
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:71-126`（目录快照与复制实现）

### C. 被调用方（执行引擎）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:216-265`
4. `codex-rs/apply-patch/src/lib.rs:279-339`
5. `codex-rs/apply-patch/src/parser.rs:154-182`
6. `codex-rs/apply-patch/src/parser.rs:483-490`

### D. 上游调用链（跨 crate）

1. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-179`
2. `codex-rs/core/src/apply_patch.rs:36-76`
3. `codex-rs/core/src/safety.rs:28-40`
4. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`
5. `codex-rs/arg0/src/lib.rs:85-107`

### E. 配置、测试、脚本、文档

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/tests/suite/tool.rs:85-93`
4. `codex-rs/core/tests/suite/apply_patch_cli.rs:511-527`
5. `.ops/generate_daily_research_todo.sh:1-42`
6. `Docs/researches/blueprint_checklist.md:91`

## 依赖与外部交互

### 1) 依赖

1. 运行时依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。
3. 场景 runner 通过 `codex_utils_cargo_bin::repo_root()` 和 `cargo_bin("apply_patch")` 在 Cargo/Bazel 下定位资源和可执行文件（`codex-rs/apply-patch/tests/suite/scenarios.rs:1,12,45`）。

### 2) 外部交互

1. 文件系统：读取 `expected/foo.txt` 并与临时目录同路径文件做字节级比较。
2. 子进程：每个场景都会拉起一次 `apply_patch` 进程。
3. 标准流：本场景失败信息主要走 stderr；但 `scenarios.rs` 不读取 stderr，而是只看终态。
4. 构建系统：Bazel 通过 `compile_data` 暴露 `apply_patch_tool_instructions.md` 给 `include_str!`（`BUILD.bazel:8-10`）。

## 风险、边界与改进建议

### 风险与边界

1. `expected/` 与 `input/` 内容相同，能检测“被改动”，但不能检测“错误文案/退出码退化”；这依赖 `tool.rs` 补测。
2. 场景 runner 不断言 exit status，若未来出现“报错文案变化但仍无副作用”，本目录对应场景不会失败。
3. 当前目录仅覆盖单文件、单层路径；未覆盖空 patch 对嵌套目录/多文件输入的“不变性”。
4. 跨层语义存在差异：`codex-apply-patch` 报 `No files were modified.`，而 core 侧会前置拒绝为 `patch rejected: empty patch`；维护时需避免误判为冲突。

### 改进建议

1. 在 `scenarios` 框架增加可选元数据（如 `expected_exit_code`、`stderr_contains`），让 `expected/` 目录型用例也能校验失败语义。
2. 为空 patch 增加“多文件输入目录”变体，强化“失败无副作用”覆盖面。
3. 在 `scenarios.rs` 遍历前按目录名排序，提高 CI 回归定位稳定性。
4. 在 `tests/fixtures/scenarios/README.md` 明确建议：负向场景应同时具备“终态断言 + stderr/exit code 断言”。
