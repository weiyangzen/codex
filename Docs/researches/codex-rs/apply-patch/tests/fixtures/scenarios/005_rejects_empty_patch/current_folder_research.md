# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`005_rejects_empty_patch` 是 `apply_patch` 场景集里“空补丁应被拒绝”的负向基线。该目录通过最小夹具定义了一个明确契约：

1. `patch.txt` 只有边界标记（`*** Begin Patch` / `*** End Patch`），没有任何 hunk。
2. `input/foo.txt` 与 `expected/foo.txt` 都是 `stable`，表示失败后文件系统应保持不变。
3. 该场景在 `tests/suite/scenarios.rs` 的目录回放框架内执行，职责是验证“无操作 patch 不产生副作用”。

这个场景与 `tests/suite/tool.rs::test_apply_patch_cli_rejects_empty_patch` 形成互补：

1. fixture 场景强调最终文件树不变（状态正确性）。
2. CLI 单测强调退出状态与 stderr 文案（行为可观测性）。

## 功能点目的

该场景锁定的是“解析允许空 hunk 集合，但执行层必须拒绝”的分层语义。

1. 解析层：`parse_patch()` 会把该 patch 解析为 `hunks = []`（即语法合法）。
2. 执行层：`apply_hunks_to_files()` 对空数组直接 `bail!("No files were modified.")`，阻止“成功但什么都没做”的假阳性。
3. CLI 层：`standalone_executable::run_main()` 调用 `apply_patch()`，遇错返回退出码 `1`，并通过 stderr 输出错误。
4. 场景层：虽然 `scenarios.rs` 不断言退出码，但会比较 `input` 与执行后目录快照，确保没有任何写盘副作用。

这使得 `apply_patch` 的“失败=无副作用”契约在数据驱动场景中有持续回归保护。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景回放流程（fixture runner）

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*` 并调用 `run_apply_patch_scenario()`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-23`）。
2. `run_apply_patch_scenario()` 先复制 `input/` 到 `tempdir`（`:33-37`）。
3. 读取 `patch.txt` 后直接执行 `apply_patch <patch>`（`:39-48`）。
4. 对 `expected/` 与临时目录分别做快照，快照结构为 `BTreeMap<PathBuf, Entry>`（`:65-77`），`Entry` 为 `File(Vec<u8>) | Dir`（`:65-69`）。
5. 使用 `assert_eq!` 比较快照；若一致，场景通过（`:55-60`）。

关键点：该 runner 明确“不检查退出码，仅比较最终状态”（`:42-44` 注释）。因此这个场景主要证明失败不产生副作用。

### 2) 空补丁的解析与执行分层

1. `parse_patch_text()` 只要求边界合法，随后循环解析内部 hunks；当中间区为空时返回 `hunks = []`（`codex-rs/apply-patch/src/parser.rs:154-182`）。
2. `check_start_and_end_lines_strict()` 仅检查首尾标记，不要求至少一个 hunk（`parser.rs:226-243`）。
3. `apply_patch()` 先调用 `parse_patch()`，成功后进入 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-211`）。
4. `apply_hunks_to_files()` 发现空数组时立即报错：`No files were modified.`（`lib.rs:279-282`）。
5. `apply_hunks()` 捕获该错误并写入 stderr，然后返回错误（`lib.rs:248-264`）。

因此，空补丁是“语法可解析、语义不可执行”的设计，不是纯 parser error。

### 3) CLI 与上层 runtime 的错误传播

1. 独立二进制入口 `run_main()` 调用 `crate::apply_patch(&patch_arg, ...)`，错误返回 exit code `1`（`codex-rs/apply-patch/src/standalone_executable.rs:49-58`）。
2. CLI 定点测试断言该行为：`failure()` 且 stderr 精确为 `No files were modified.\n`（`codex-rs/apply-patch/tests/suite/tool.rs:85-93`）。
3. 在 core 工具链中，handler 会先 `maybe_parse_apply_patch_verified()` 计算变更，再交给 runtime 执行（`codex-rs/core/src/tools/handlers/apply_patch.rs:173-179`）。
4. runtime 通过 `codex --codex-run-as-apply-patch <patch>` 的自调用路径执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:88-94`），该 flag 在 `arg0` 中被分派到 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:89-107`）。

### 4) 协议与命令

1. 协议边界：`*** Begin Patch` / `*** End Patch`。
2. 文档规范写明完整 patch 应包含文件操作段（`codex-rs/apply-patch/apply_patch_tool_instructions.md:6-16,40-50`）。
3. 本场景命令等价于：

```bash
apply_patch "*** Begin Patch
*** End Patch"
```

4. 预期结果：stderr = `No files were modified.`，退出码失败，文件系统不变。

## 关键代码路径与文件引用

### 场景与夹具

1. `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/patch.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/input/foo.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/expected/foo.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`

### 场景执行与断言

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-23`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:65-77`
4. `codex-rs/apply-patch/tests/suite/tool.rs:85-93`

### 解析与执行实现

1. `codex-rs/apply-patch/src/parser.rs:154-182`
2. `codex-rs/apply-patch/src/parser.rs:226-243`
3. `codex-rs/apply-patch/src/lib.rs:183-211`
4. `codex-rs/apply-patch/src/lib.rs:279-282`
5. `codex-rs/apply-patch/src/lib.rs:248-264`
6. `codex-rs/apply-patch/src/standalone_executable.rs:49-58`

### 上下文调用链（跨 crate）

1. `codex-rs/core/src/tools/handlers/apply_patch.rs:173-179`
2. `codex-rs/core/src/tools/runtimes/apply_patch.rs:88-94`
3. `codex-rs/arg0/src/lib.rs:85-107`
4. `codex-rs/apply-patch/Cargo.toml`
5. `codex-rs/apply-patch/BUILD.bazel`

### 研究流程脚本与清单

1. `.ops/generate_daily_research_todo.sh:4-7`
2. `.ops/generate_daily_research_todo.sh:15-18`
3. `.ops/generate_daily_research_todo.sh:37-39`
4. `Docs/researches/blueprint_checklist.md:90`

## 依赖与外部交互

### 依赖

`codex-apply-patch` 与本场景关联最直接的依赖如下：

1. `anyhow` / `thiserror`：错误封装与上下文构建（空补丁拒绝路径依赖 `anyhow::bail!`）。
2. `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`：集成测试进程启动、隔离目录与断言支持（见 `Cargo.toml` dev-dependencies）。
3. `tree-sitter` / `tree-sitter-bash`：虽非本场景核心，但决定 shell/heredoc 形式 `apply_patch` 的识别与验证入口（`invocation.rs`）。

### 外部交互

1. 文件系统：读取 `patch.txt`、复制 `input/`、运行后对目录做二进制快照比对。
2. 子进程：`scenarios.rs` 与 `tool.rs` 均实际拉起 `apply_patch` 可执行文件。
3. 标准流：错误通过 stderr 传递（空补丁时为固定文案）。
4. 运行时分发：在 core 中通过 `--codex-run-as-apply-patch` 将执行统一路由到同一实现。

### 配置与构建

1. `Cargo.toml`：定义 crate 名 `codex-apply-patch` 与二进制 `apply_patch`。
2. `BUILD.bazel`：`compile_data` 包含 `apply_patch_tool_instructions.md`，保证编译时 `include_str!` 可访问。
3. 本场景无独立环境变量开关；行为由 patch 内容与执行路径决定。

## 风险、边界与改进建议

### 风险与边界

1. fixture runner 不断言退出码/stderr，只断言最终状态；若未来错误文案或错误类型回归，`005` 本身不会报错。
2. 当前 `005` 仅覆盖“严格空补丁”一种形态，未覆盖“仅空白行”“仅注释/未知 marker”等近邻输入。
3. 空补丁在 parser 层被接受、执行层拒绝是有意分层；若后续有人将“至少一个 hunk”前移到 parser，需要同步评估 core 审批链（`maybe_parse_apply_patch_verified`）的影响。
4. `scenarios.rs` 按 `read_dir` 顺序遍历目录，未显式排序；虽不影响单测正确性，但会影响失败日志稳定性。

### 改进建议

1. 在 `scenarios` 机制中引入可选元数据（例如 `result.json`）以声明 `expected_exit_code` 与 `stderr_contains`，让 `005` 类负向场景不仅检验“无副作用”，还检验“失败语义”。
2. 增加近邻负向场景：
   - 仅空白行包裹的补丁。
   - 只有非法 hunk header 的补丁（与 `013` 可形成更细粒度区分）。
3. 在 `tests/suite/scenarios.rs` 中对目录名排序后执行，提升 CI 输出可读性与排障一致性。
4. 在 `tests/fixtures/scenarios/README.md` 补充“负向场景推荐同时在 `tool.rs` 断言 stderr/exit code”的约定，避免仅状态断言导致的行为回归漏检。
