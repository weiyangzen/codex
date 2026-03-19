# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属模块：`codex-rs/apply-patch`（crate: `codex-apply-patch`）

## 场景与职责

该目录是场景 `006_rejects_missing_context` 的期望终态（expected oracle），用于断言“上下文缺失导致补丁失败时，文件系统必须保持原状”。

目录当前仅含：

1. `modify.txt`，内容为 `line1\nline2\n`（12 字节，LF 结尾）。

它在用例体系中的职责是：

1. 作为 `tests/suite/scenarios.rs` 的最终快照比对基准（该测试不关心退出码，只关心落盘结果）。
2. 与同场景 `input/modify.txt` 保持一致，显式表达“失败无副作用”。
3. 为 `missing context` 负向语义提供文件层面的稳定回归锚点。

## 功能点目的

该目录服务的功能点是 `Update File` 语义里的“旧行必须可定位”约束。

1. 场景补丁尝试把 `-missing` 替换为 `+changed`，但目标文件并不存在 `missing` 行。
2. 引擎应返回错误 `Failed to find expected lines in modify.txt:\nmissing`，并中止写回。
3. `expected/modify.txt` 用于验证失败后仍为原始内容 `line1\nline2\n`。
4. 这与 `tool.rs` 中 stderr 文案断言形成互补：`expected/` 验证状态不变，`tool.rs` 验证诊断信息正确。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景执行主链路

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*` 并逐目录执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11`）。
2. `run_apply_patch_scenario()` 将 `input/` 复制到 `tempdir`，读取 `patch.txt`，执行 `apply_patch <patch>`（`scenarios.rs:30`）。
3. 即使 `apply_patch` 失败，也继续对 `expected/` 与临时目录做快照等值比较（`scenarios.rs:52-58`）。
4. 快照结构是 `BTreeMap<PathBuf, Entry>`，`Entry` 为 `File(Vec<u8>)` 或 `Dir`（`scenarios.rs:65-69`），因此 `modify.txt` 以字节级比较。

### 2) “missing context” 如何在实现中触发

1. 解析层把补丁解析为 `Hunk::UpdateFile`，chunk 中 `old_lines=["missing"]`、`new_lines=["changed"]`（`codex-rs/apply-patch/src/parser.rs:106`, `parser.rs:343`）。
2. 执行层 `apply_patch()` -> `apply_hunks_to_files()` -> `derive_new_contents_from_chunks()`（`codex-rs/apply-patch/src/lib.rs:183`, `lib.rs:279`, `lib.rs:348`）。
3. `compute_replacements()` 调用 `seek_sequence()` 在原文件中查找 `old_lines`（`lib.rs:386`）。
4. 查找失败后抛出 `ComputeReplacements("Failed to find expected lines in ...")`（`lib.rs:464`），`apply_hunks()` 将错误写入 stderr 并返回失败。
5. 因为更新失败发生在写文件前，`modify.txt` 保持输入态不变，这正是本目录需要钉住的行为。

### 3) 匹配算法与边界

`seek_sequence()` 采用多级宽松匹配：精确匹配 -> 忽略尾部空白 -> 忽略两侧空白 -> Unicode 标点归一化匹配（`codex-rs/apply-patch/src/seek_sequence.rs:12`）。

即使存在这些容错，本场景中的 `missing` 仍无法匹配 `line1/line2`，因此应稳定失败，不会误命中。

### 4) 协议与命令接口

1. 语法协议来源：
1. `codex-rs/apply-patch/apply_patch_tool_instructions.md`
2. `codex-rs/core/src/tools/handlers/tool_apply_patch.lark`
2. 场景命令本质等价：

```bash
apply_patch "*** Begin Patch
*** Update File: modify.txt
@@
-missing
+changed
*** End Patch"
```

3. CLI 入口 `run_main()` 读取参数或 stdin，并调用 `codex_apply_patch::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11`）。

## 关键代码路径与文件引用

### 目标对象与直接上下文

1. `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/expected/modify.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/input/modify.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/patch.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes`

### 调用方（消费 expected 的测试）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:52`
4. `codex-rs/apply-patch/tests/all.rs:3`

### 被调用方（补丁解析与执行）

1. `codex-rs/apply-patch/src/parser.rs:106`
2. `codex-rs/apply-patch/src/parser.rs:343`
3. `codex-rs/apply-patch/src/lib.rs:183`
4. `codex-rs/apply-patch/src/lib.rs:279`
5. `codex-rs/apply-patch/src/lib.rs:348`
6. `codex-rs/apply-patch/src/lib.rs:386`
7. `codex-rs/apply-patch/src/lib.rs:464`
8. `codex-rs/apply-patch/src/seek_sequence.rs:12`
9. `codex-rs/apply-patch/src/standalone_executable.rs:11`

### 上游工具链、配置与并行实现链路

1. `codex-rs/core/src/tools/handlers/apply_patch.rs:174`（工具入口验证）
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:243`（`apply_patch verification failed`）
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:360`（freeform tool 定义）
4. `codex-rs/core/src/tools/handlers/apply_patch.rs:373`（function tool 定义）
5. `codex-rs/core/src/tools/spec.rs:263`（`apply_patch_tool_type` 配置项）
6. `codex-rs/core/src/tools/spec.rs:2784`（按配置注册 apply_patch）
7. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69`（构建 `--codex-run-as-apply-patch` 命令）
8. `codex-rs/arg0/src/lib.rs:85`（`apply_patch`/`applypatch` arg0 分发）
9. `codex-rs/arg0/src/lib.rs:90`（secret argv1 分发）

### 测试、脚本、文档

1. `codex-rs/apply-patch/tests/suite/tool.rs:98`（missing context CLI 失败断言）
2. `codex-rs/core/tests/suite/apply_patch_cli.rs:404`（core 链路 missing context 断言）
3. `codex-rs/core/tests/suite/apply_patch_cli.rs:1094`（second chunk context 缺失）
4. `codex-rs/apply-patch/Cargo.toml`
5. `codex-rs/apply-patch/BUILD.bazel`
6. `.ops/generate_daily_research_todo.sh`
7. `Docs/researches/blueprint_checklist.md`

## 依赖与外部交互

### 依赖

1. 运行时依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`。
3. 构建依赖：Bazel 通过 `compile_data` 暴露 `apply_patch_tool_instructions.md`（`codex-rs/apply-patch/BUILD.bazel`）。

### 外部交互

1. 文件系统：场景测试读取 `expected/modify.txt` 并做字节快照对比。
2. 子进程：`scenarios.rs` 每个场景都会启动一次 `apply_patch` 可执行文件。
3. 标准流：失败信息输出到 stderr；本 expected 目录本身不消费 stderr，而是间接由 `tool.rs` 覆盖。
4. 运行时分发：core runtime 通过 `codex --codex-run-as-apply-patch` 执行补丁，再由 arg0 分发到 `codex_apply_patch::apply_patch`。

## 风险、边界与改进建议

### 风险与边界

1. `scenarios.rs` 不断言退出码/stderr，若错误文案退化但文件未变，此目录相关场景仍会通过。
2. 当前 expected 仅覆盖单文件、不涉及目录层级与多文件事务边界。
3. `seek_sequence` 的宽松匹配策略提高可用性，但在某些近似文本场景可能有误匹配风险；本场景只覆盖“完全找不到上下文”。
4. `read_dir` 的遍历顺序未显式排序，场景执行顺序可能随平台波动，影响问题定位体验。

### 改进建议

1. 为 fixture 场景增加可选元数据（如 `expected_exit_code`、`stderr_contains`），让负向用例同时校验副作用与诊断质量。
2. 增加“多文件输入 + missing context”变体，验证失败下是否存在部分成功写入的边界行为。
3. 在 `tests/fixtures/scenarios/README.md` 明确负向场景应搭配 CLI 文案断言，避免只验证终态。
4. 在 `test_apply_patch_scenarios` 中按目录名排序后执行，提高 CI 复现与排障稳定性。
