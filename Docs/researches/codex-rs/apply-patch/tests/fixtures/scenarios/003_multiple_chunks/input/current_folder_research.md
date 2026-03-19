# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/input` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`input/` 是场景 `003_multiple_chunks` 的“执行前文件系统基线目录”。该目录当前只包含一个文件：

- `codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/input/multi.txt:1-4`

内容为：

1. `line1`
2. `line2`
3. `line3`
4. `line4`

在该场景中，`input/` 的核心职责不是表达业务逻辑，而是提供可重复、可对照的初态，使同级 `patch.txt` 中一个 `Update File` 下的两个 chunk 能够被稳定命中并完成替换。该职责与同级目录形成固定契约：

1. `input/` 提供初态。
2. `patch.txt` 提供单次补丁操作（`codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/patch.txt:1-9`）。
3. `expected/` 提供终态真值（`codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/expected/multi.txt:1-4`）。

该三段式约定由场景说明文档明确（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`）。

## 功能点目的

围绕 `003_multiple_chunks/input`，功能目的有三层：

1. 验证“同一文件、同一 Update File hunk、多个 chunk”的正确应用。
- `patch.txt` 在 `multi.txt` 上声明两个 `@@`：
  - `line2 -> changed2`
  - `line4 -> changed4`
- 该目录中的 `multi.txt` 提供这两处原始命中点。

2. 验证 chunk 顺序处理时的定位推进逻辑。
- 执行器会逐 chunk 计算 replacement，并通过内部游标避免后续 chunk 回到前文误命中。
- 本目录构造了一个最小但清晰的线性序列样本，便于验证该行为。

3. 作为回归样本，约束 parser+executor 联合行为。
- 场景测试（目录快照对比）覆盖“最终状态”。
- 工具测试（`tool.rs`）覆盖“CLI 输出+最终内容”。
- 库单测覆盖“多 chunk 的 replacement 逻辑细节”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 测试入口 `test_apply_patch_scenarios()` 扫描 `tests/fixtures/scenarios` 下每个目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11`）。
2. 对 `003_multiple_chunks` 调用 `run_apply_patch_scenario()`（`codex-rs/apply-patch/tests/suite/scenarios.rs:30`）。
3. 测试先把 `input/` 递归复制到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:107`）。
4. 读取 `patch.txt`，启动 `apply_patch` 可执行文件执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-60`）。
5. 对比临时目录与 `expected/` 的快照（`BTreeMap<PathBuf, Entry>`）是否完全一致，完成断言。

### 2) 数据结构与算法落点

1. 解析数据结构：
- `Hunk::UpdateFile { path, move_path, chunks }`（`codex-rs/apply-patch/src/parser.rs:248`）。
- `UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`（`codex-rs/apply-patch/src/parser.rs:343`）。

2. 执行数据结构：
- `AffectedPaths { added, modified, deleted }` 汇总变更（`codex-rs/apply-patch/src/lib.rs:279-339`）。
- replacement 列表：`Vec<(start_index, old_len, new_lines)>`（`codex-rs/apply-patch/src/lib.rs:386`）。

3. 多 chunk 关键算法：
- `compute_replacements()` 逐块定位并累计替换计划（`codex-rs/apply-patch/src/lib.rs:386`）。
- `seek_sequence()` 提供精确/trim/unicode-normalize 逐级匹配能力（`codex-rs/apply-patch/src/seek_sequence.rs:12`）。
- `apply_replacements()` 倒序应用替换，避免索引位移污染后续替换（`codex-rs/apply-patch/src/lib.rs:478`）。

结合本目录样本，等价流程为：

1. 从 `multi.txt` 命中 `line2`，计划替换为 `changed2`。
2. 再命中 `line4`，计划替换为 `changed4`。
3. 倒序应用后得到 `expected/multi.txt`。

### 3) 协议与命令

1. Patch 协议边界：
- `*** Begin Patch` / `*** End Patch`（`codex-rs/apply-patch/src/parser.rs:31`, `codex-rs/apply-patch/src/parser.rs:106`）。

2. Update 协议：
- `*** Update File: multi.txt`
- 两个 `@@` chunk
- 每行以 `-`/`+`/空格前缀描述删改上下文（`codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/patch.txt:1-9`；协议说明见 `codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`）。

3. 命令执行路径：
- 二进制入口：`codex-rs/apply-patch/src/main.rs:1`。
- 实际 CLI 分发：`run_main()` 读参数或 stdin，再调用 `apply_patch()`（`codex-rs/apply-patch/src/standalone_executable.rs:11`）。
- 库入口：`apply_patch()` -> `apply_hunks()` -> 文件系统变更（`codex-rs/apply-patch/src/lib.rs:183`, `codex-rs/apply-patch/src/lib.rs:216`）。

## 关键代码路径与文件引用

### A. 目标目录本体

1. `codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/input/multi.txt:1-4`

### B. 直接调用方（谁消费了这个 input 目录）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:79`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:107`
5. `codex-rs/apply-patch/tests/all.rs:1-3`

### C. 被调用方（该场景触发到的实现）

1. `codex-rs/apply-patch/src/parser.rs:106`
2. `codex-rs/apply-patch/src/parser.rs:248`
3. `codex-rs/apply-patch/src/parser.rs:343`
4. `codex-rs/apply-patch/src/lib.rs:183`
5. `codex-rs/apply-patch/src/lib.rs:216`
6. `codex-rs/apply-patch/src/lib.rs:279`
7. `codex-rs/apply-patch/src/lib.rs:348`
8. `codex-rs/apply-patch/src/lib.rs:386`
9. `codex-rs/apply-patch/src/lib.rs:478`
10. `codex-rs/apply-patch/src/lib.rs:537`
11. `codex-rs/apply-patch/src/seek_sequence.rs:12`

### D. 并行校验/上下文依赖

1. `codex-rs/apply-patch/tests/suite/tool.rs:7`
2. `codex-rs/apply-patch/tests/suite/tool.rs:45`
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:42`
4. `codex-rs/core/src/tools/handlers/apply_patch.rs:174`
5. `codex-rs/core/src/tools/handlers/apply_patch.rs:262`
6. `codex-rs/core/src/tools/spec.rs:2784`
7. `codex-rs/core/src/tools/runtimes/apply_patch.rs:36`
8. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69`
9. `codex-rs/core/src/tools/runtimes/apply_patch.rs:91`
10. `codex-rs/core/src/tools/runtimes/apply_patch.rs:200`

### E. 配置、测试、脚本、文档

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
6. `.ops/generate_daily_research_todo.sh:1-42`
7. `Docs/researches/blueprint_checklist.md:82`

## 依赖与外部交互

### 1) crate 与测试依赖

1. 运行时依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`assert_matches`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。
3. Bazel 构建显式导入 `apply_patch_tool_instructions.md`（`codex-rs/apply-patch/BUILD.bazel:3-10`）。

### 2) 外部交互面

1. 文件系统：
- 测试阶段复制 `input/` 到临时目录；
- 执行阶段对 `multi.txt` 读取、改写；
- 验证阶段对 `expected/` 与临时目录做字节级快照比对。

2. 子进程：
- 场景回放通过 `Command::new(cargo_bin("apply_patch"))` 启动真实 CLI。

3. I/O 输出：
- 成功输出 `Success. Updated the following files:` 与 `M multi.txt`；
- 错误输出由 parser/执行器给出具体失败原因。

### 3) 与上游系统交互

1. 在 `core` 中，`apply_patch` 工具注册受 `apply_patch_tool_type` 控制（`codex-rs/core/src/tools/spec.rs:2784-2803`）。
2. handler 中会再次执行 `maybe_parse_apply_patch_verified()` 做安全与正确性校验（`codex-rs/core/src/tools/handlers/apply_patch.rs:174-258`）。
3. runtime 通过 `--codex-run-as-apply-patch` 自调用执行真实 patch（`codex-rs/core/src/tools/runtimes/apply_patch.rs:91`）。

## 风险、边界与改进建议

### 风险与边界

1. 本目录样本过于最小化：仅覆盖“单文件两处替换且文本唯一”的成功路径，不覆盖重复文本歧义。
2. 场景测试 `scenarios.rs` 只比最终文件树，不断言退出码与 stderr，可能漏掉“行为协议回归但终态一致”的问题。
3. `apply_patch` 当前是顺序落盘而非事务回滚模型；多操作 patch 在中途失败时可能保留部分已写入结果（本场景不涉及，但属于该目录语义上游边界）。
4. `input/` 只含 LF 文本样本，未覆盖 CRLF、二进制文件、权限位差异等平台边界。

### 改进建议

1. 在 `003_multiple_chunks` 旁新增变体：`multi.txt` 中出现重复 `line2`/`line4`，验证 chunk 定位游标不会误命中前文。
2. 增加“chunk1 成功、chunk2 失败”的同构场景，显式验证部分应用行为并写入 `expected/`。
3. 为 `scenarios` 测试框架扩展可选元数据（例如 `expectExitCode`、`expectStderrContains`），补强仅终态断言的盲区。
4. 为 `input/` 系列场景补充换行风格覆盖（LF/CRLF）并与 `.gitattributes` 约束联动验证。
