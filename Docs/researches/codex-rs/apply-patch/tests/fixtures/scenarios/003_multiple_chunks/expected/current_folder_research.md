# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属模块：`codex-rs/apply-patch`（crate: `codex-apply-patch`）

## 场景与职责

该目录是场景 `003_multiple_chunks` 的“结果真值目录”，当前只包含一个断言文件：

- `codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/expected/multi.txt:1`

在 `apply-patch` 的 fixture 规范中，每个场景都由 `input/ + patch.txt + expected/` 组成，`expected/` 不参与执行逻辑，只作为最终文件系统快照对比基准（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。

本目录在该场景里表达的职责是：定义“单个 `Update File` 中包含两个 `@@` chunk 后，`multi.txt` 的最终稳定内容”，用于验证多段替换的组合结果，而非仅验证某一段替换是否成功。

## 功能点目的

围绕 `expected/` 目录，`003_multiple_chunks` 的验证目标分为三层：

1. 场景语义层：`patch.txt` 在同一 `Update File: multi.txt` 内声明两个 chunk，分别把 `line2 -> changed2`、`line4 -> changed4`（`codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/patch.txt:1-9`）。
2. 引擎行为层：执行器必须把两段变更都应用到同一个文件并保持行序正确，最终产出 `line1/changed2/line3/changed4`（`codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/expected/multi.txt:1-4`）。
3. 回归防护层：作为目录快照断言基线，防止未来在 chunk 定位、替换顺序、尾换行处理上出现回归。

与该目录同语义的代码侧测试还有：

- `codex-rs/apply-patch/tests/suite/tool.rs:45-61`（CLI 断言 + 文件内容）
- `codex-rs/apply-patch/src/lib.rs:674-710`（库级单元测试）

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 将 `input/` 复制到临时目录，读取 `patch.txt`，执行 `apply_patch <patch>`（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-48`）。
3. 测试随后把 `expected/` 与临时目录都做快照并比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。
4. 因此本目录文件内容会被 `snapshot_dir()` 读取为字节向量，参与 `BTreeMap<PathBuf, Entry>` 等值断言（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-102`）。

### 2) 关键数据结构与算法

1. parser 将 `Update File` 解析为 `Hunk::UpdateFile { chunks: Vec<UpdateFileChunk>, ... }`（`codex-rs/apply-patch/src/parser.rs:279-333`）。
2. 每个 `@@` 段被解析成 `UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`（`codex-rs/apply-patch/src/parser.rs:90-104`, `343-434`）。
3. `compute_replacements()` 逐 chunk 搜索 `old_lines` 并构建替换计划，维护 `line_index` 防止后续 chunk 回退匹配（`codex-rs/apply-patch/src/lib.rs:386-473`）。
4. `apply_replacements()` 倒序应用替换，避免前面的替换影响后面的索引（`codex-rs/apply-patch/src/lib.rs:478-501`）。
5. `derive_new_contents_from_chunks()` 统一保证输出尾部换行，这直接影响 `expected/multi.txt` 的末尾 `\n`（`codex-rs/apply-patch/src/lib.rs:348-380`）。

### 3) 协议与命令

1. 补丁协议：`*** Begin Patch` ... `*** End Patch`（`codex-rs/apply-patch/src/parser.rs:31-32`）。
2. 更新操作协议：`*** Update File: <path>` + 多个 `@@` 段（`codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/patch.txt:1-9`）。
3. 每段内行前缀约定：`-` 删除，`+` 新增，` ` 上下文（`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`）。
4. CLI 执行方式：参数传入或 stdin 传入，最终调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。

## 关键代码路径与文件引用

### A. 目标目录本体

1. `codex-rs/apply-patch/tests/fixtures/scenarios/003_multiple_chunks/expected/multi.txt:1`

### B. 直接调用方（消费 expected 的测试代码）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`（场景遍历）
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`（场景执行）
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:71-126`（目录快照与递归复制）

### C. 被调用方（场景执行触发的实现）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`（CLI 参数/stdin 入口）
2. `codex-rs/apply-patch/src/lib.rs:183-213`（`apply_patch` 主入口）
3. `codex-rs/apply-patch/src/lib.rs:279-339`（hunk 落盘执行）
4. `codex-rs/apply-patch/src/lib.rs:386-501`（多 chunk 替换计划 + 应用）
5. `codex-rs/apply-patch/src/parser.rs:248-333`（`Update File` 与 chunk 解析）
6. `codex-rs/apply-patch/src/seek_sequence.rs:12-110`（序列定位策略）

### D. 上下游产品链路（跨 crate）

1. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-258`（工具层重解析并校验）
2. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`（构造 `codex --codex-run-as-apply-patch`）
3. `codex-rs/arg0/src/lib.rs:85-107`（arg0 分发到 `codex_apply_patch::main/apply_patch`）

### E. 配置、构建、脚本、文档

1. `codex-rs/apply-patch/Cargo.toml:1-30`（crate/bin 与依赖）
2. `codex-rs/apply-patch/BUILD.bazel:1-11`（Bazel compile_data）
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`（补丁协议说明）
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`（fixture 行尾 LF 约束）
5. `Docs/researches/blueprint_checklist.md:81`（本次研究条目）
6. `.ops/generate_daily_research_todo.sh:1-42`（todo 生成脚本）

## 依赖与外部交互

### 1) 依赖

1. 运行时依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。
3. 测试通过 `codex_utils_cargo_bin::cargo_bin("apply_patch")` 与 `repo_root()` 保证 Cargo/Bazel 下路径可解析（`codex-rs/apply-patch/tests/suite/scenarios.rs:1,12,45`）。

### 2) 外部交互

1. 文件系统读写：
- 读取场景 `patch.txt` 与 `expected/`；
- 在临时目录写入/更新 `multi.txt`；
- 用 `metadata()` 跟随 symlink 兼容 Buck2 物化行为（`codex-rs/apply-patch/tests/suite/scenarios.rs:92-95,113-115`）。
2. 子进程交互：场景测试为每个场景启动一次 `apply_patch` 进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. 标准输出/错误：成功打印 `Success...` 与 `A/M/D`，失败打印解析或匹配错误（`codex-rs/apply-patch/src/lib.rs:191-205`, `247-265`, `537-551`）。

## 风险、边界与改进建议

### 风险与边界

1. 本目录仅覆盖“单文件双 chunk 的正向路径”，不覆盖重复文本歧义、跨文件依赖、复杂上下文锚点等情形。
2. `scenarios.rs` 明确“不校验退出码”，只比较最终文件树；若输出协议回归但最终文件正确，可能漏检（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。
3. 场景遍历基于 `fs::read_dir` 自然顺序，失败顺序在不同文件系统下可能不稳定（`codex-rs/apply-patch/tests/suite/scenarios.rs:18`）。
4. 执行引擎不是事务性回滚模型；若前序 hunk 成功、后序 hunk 失败，会留下部分修改（由 `015_failure_after_partial_success_leaves_changes` 体现，`codex-rs/apply-patch/tests/suite/tool.rs:245-257`）。

### 改进建议

1. 为 `003_multiple_chunks` 增补“重复旧行”变体，验证 `line_index` 前移策略不会误匹配前文。
2. 扩展一个“context + 无 context 混合 chunk”变体，覆盖 `change_context` 与 `seek_sequence` 协同分支。
3. 为场景框架增设可选元数据断言（如 `expectedExit`、`expectedStderrContains`），补齐仅终态对比的盲区。
4. 在场景遍历前按目录名排序，提升跨平台回归定位稳定性。
