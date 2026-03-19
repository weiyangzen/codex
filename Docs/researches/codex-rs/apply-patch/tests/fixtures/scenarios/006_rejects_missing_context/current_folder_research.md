# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`006_rejects_missing_context` 是 `apply_patch` 场景集中的负向基线，用于验证“更新块里声明要删除的旧行在目标文件中不存在时，补丁必须失败且不应产生副作用”。

该目录由三部分构成：

1. `patch.txt`：尝试把 `modify.txt` 中的 `missing` 改成 `changed`。
2. `input/modify.txt`：实际内容为 `line1\nline2`，并不包含 `missing`。
3. `expected/modify.txt`：与 `input` 完全一致，表达“失败后文件保持原样”。

它在测试体系里的职责是“文件最终态回归保护”，与 `tests/suite/tool.rs` 的错误文案断言、`core/tests/suite/apply_patch_cli.rs` 的工具链路断言形成分层互补。

## 功能点目的

该场景锁定的是 `Update File` 语义中的核心约束：`old_lines` 必须在目标文件中可定位。

1. 防止误改：当定位失败时，拒绝“近似修改”或“盲写覆盖”。
2. 保证可解释失败：应返回明确诊断 `Failed to find expected lines in ...`。
3. 保证失败无副作用：目标文件在失败后保持不变。
4. 保证跨层一致性：同一错误语义在三层都被覆盖。
5. fixture 层：`scenarios.rs` 比较最终文件树（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。
6. CLI 层：`tool.rs` 断言 stderr 精确文本（`codex-rs/apply-patch/tests/suite/tool.rs:98-108`）。
7. core 层：`apply_patch` 工具链断言 `apply_patch verification failed` + missing lines 诊断（`codex-rs/core/tests/suite/apply_patch_cli.rs:404-429`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景回放流程

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*`，逐目录执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 复制 `input/` 到 `tempdir`（`.../scenarios.rs:33-37`）。
3. 读取场景 `patch.txt`，执行 `apply_patch <patch>`（`.../scenarios.rs:39-48`）。
4. 不断言进程退出码，只比较最终目录快照（`.../scenarios.rs:42-45,50-60`）。
5. 快照结构为 `BTreeMap<PathBuf, Entry>`，`Entry = File(Vec<u8>) | Dir`（`.../scenarios.rs:65-77`）。

### 2) 解析到执行的关键链路

1. 协议解析：`parse_patch()` 识别 `*** Update File` 和 `@@` 块，生成 `Hunk::UpdateFile` 与 `UpdateFileChunk`（`codex-rs/apply-patch/src/parser.rs:106-113,279-333,343-434`）。
2. 本场景 chunk 解析结果本质上是：
   - `change_context = None`
   - `old_lines = ["missing"]`
   - `new_lines = ["changed"]`
3. 执行入口：`apply_patch()` -> `apply_hunks()` -> `apply_hunks_to_files()`（`codex-rs/apply-patch/src/lib.rs:183-213,216-266,279-339`）。
4. `Update File` 路径进入 `derive_new_contents_from_chunks()`，先读取原文件并拆行（`.../lib.rs:348-381`）。
5. `compute_replacements()` 调用 `seek_sequence()` 在原文件中查找 `old_lines`（`.../lib.rs:386-474`）。
6. 因 `modify.txt` 不含 `missing`，查找失败，返回 `ApplyPatchError::ComputeReplacements("Failed to find expected lines in modify.txt:\nmissing")`（`.../lib.rs:463-467`）。
7. `apply_hunks()` 将错误写入 stderr 并返回失败（`.../lib.rs:253-264`），文件不会写回。

### 3) 匹配算法细节（本场景为何仍失败）

`seek_sequence()` 匹配顺序是：

1. 精确匹配；
2. 忽略右侧空白；
3. 忽略两侧空白；
4. Unicode 标点归一化后匹配（`codex-rs/apply-patch/src/seek_sequence.rs:34-107`）。

本场景的 `missing` 与文件中的 `line1/line2` 在以上四轮都无法匹配，因此稳定失败，避免误命中。

### 4) 协议与命令

1. 场景 patch 文本：
   - `*** Begin Patch`
   - `*** Update File: modify.txt`
   - `@@`
   - `-missing`
   - `+changed`
   - `*** End Patch`
2. 协议来源：
   - `codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`
   - `codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-17`
3. 对应命令：
   - `apply_patch "<完整 patch 内容>"`
   - 场景回放命令：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`

## 关键代码路径与文件引用

### 目标目录与夹具

1. `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/patch.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/input/modify.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/expected/modify.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`

### 直接调用方（谁消费该场景）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`
3. `codex-rs/apply-patch/tests/all.rs:1-3`

### 被调用方（场景执行时进入的实现）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-266`
3. `codex-rs/apply-patch/src/lib.rs:279-339`
4. `codex-rs/apply-patch/src/lib.rs:348-474`
5. `codex-rs/apply-patch/src/parser.rs:343-434`
6. `codex-rs/apply-patch/src/seek_sequence.rs:12-110`

### 相关测试与上游链路

1. `codex-rs/apply-patch/tests/suite/tool.rs:98-108`（CLI missing-context 精确报错）
2. `codex-rs/core/tests/suite/apply_patch_cli.rs:404-429`（core apply_patch 输出校验）
3. `codex-rs/core/tests/suite/apply_patch_cli.rs:1029-1038`（shell 路径失败诊断）
4. `codex-rs/core/tests/suite/apply_patch_cli.rs:1094-1120`（多 chunk 缺失上下文）
5. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-258`（handler 验证与错误包装）
6. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`（runtime 自调用命令构造）
7. `codex-rs/arg0/src/lib.rs:89-107`（`--codex-run-as-apply-patch` 分发）

### 配置、脚本、文档

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/core/src/tools/spec.rs:2250-2252,2784-2804`
4. `.ops/generate_daily_research_todo.sh:5-7,15-18,37-39`
5. `Docs/researches/blueprint_checklist.md:93`

## 依赖与外部交互

### 1) 依赖

1. 运行与错误封装：`anyhow`、`thiserror`（`codex-rs/apply-patch/Cargo.toml:19-21`）。
2. 匹配/差分：`similar`（`Cargo.toml:20`）。
3. shell 脚本解析（core 验证链路）：`tree-sitter`、`tree-sitter-bash`（`Cargo.toml:22-23`，`src/invocation.rs:5-10`）。
4. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`Cargo.toml:26-30`）。

### 2) 外部交互

1. 文件系统：读取场景文件、复制目录、读取目标文件、失败时不写回。
2. 子进程：场景测试通过 `assert_cmd` 启动 `apply_patch` 可执行文件。
3. 标准流：失败信息经 stderr 透出（`tool.rs` 断言精确文案）。
4. core 工具执行：通过 `codex --codex-run-as-apply-patch "<patch>"` 自调用执行（`core/src/tools/runtimes/apply_patch.rs:90-94`）。

### 3) 配置与文档交互

1. `core` 根据 `apply_patch_tool_type` 选择 freeform 或 function 形态，并注册同一 handler（`core/src/tools/spec.rs:2784-2804`）。
2. freeform 语法由 `tool_apply_patch.lark` 提供，JSON 版本描述复用同协议文本（`core/src/tools/handlers/apply_patch.rs:360-462`）。
3. `apply_patch_tool_instructions.md` 通过 `include_str!` 编译入 crate，Bazel 通过 `compile_data` 保证可访问（`apply-patch/src/lib.rs:26`, `apply-patch/BUILD.bazel:8-10`）。

## 风险、边界与改进建议

### 风险与边界

1. `scenarios.rs` 只比较最终文件树，不校验退出码与 stderr，错误信息回归可能漏检（`tests/suite/scenarios.rs:42-45`）。
2. 该场景是单文件单 chunk；无法覆盖“同一 patch 前序成功后序失败”的跨文件部分成功语义（该语义由 `015_failure_after_partial_success_leaves_changes` 覆盖）。
3. `seek_sequence()` 存在多级宽松匹配（空白/Unicode 归一化），虽提升鲁棒性，但也提高了误匹配风险；本场景只覆盖“完全不匹配”的硬失败。
4. 场景遍历使用 `read_dir` 原生顺序，失败日志的场景顺序在不同环境可能不稳定。

### 改进建议

1. 为 fixture 场景增加可选元数据（如 `result.json`），支持声明 `expected_exit_code` 与 `stderr_contains`，让负向场景同时覆盖“状态+诊断”。
2. 在 `scenarios.rs` 中先按目录名排序再执行，提高 CI 输出可复现性。
3. 增补 missing-context 近邻场景：
   - 仅大小写差异；
   - 仅空白差异（验证 trim 容忍边界）；
   - Unicode 正规化后应匹配/不应匹配的对照组。
4. 在 `scenarios/README.md` 增加“负向场景需要在 `tool.rs` 配套文案断言”的约定，降低维护者误解。
