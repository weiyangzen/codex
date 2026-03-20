# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 关联场景：`017_whitespace_padded_hunk_header`

## 场景与职责

`expected/` 是该场景的“最终状态判定基准目录”，职责不是执行逻辑，而是为端到端测试提供唯一正确答案（oracle）。

本目录当前仅包含一个文件：

1. `foo.txt`，内容为 `new`（`codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/expected/foo.txt:1`）。

它与同层对象协同关系如下：

1. `input/foo.txt` 给出初始状态 `old`（`codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/input/foo.txt:1`）。
2. `patch.txt` 给出补丁，且 `*** Update File` 头部故意前置空格（`codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/patch.txt:1-6`）。
3. `expected/foo.txt` 给出应达成状态 `new`，用于证明“hunk header 前导空白仍可被正确解析并应用”。

在测试矩阵里，`expected/` 目录是 `scenarios.rs` 对比逻辑直接读取的目标快照来源（`codex-rs/apply-patch/tests/suite/scenarios.rs:51-58`）。

## 功能点目的

本目录所承载的功能目的有三层：

1. 语法宽容性验证目的
- 该场景验证 `*** Update File: ...` 前有空白时，解析器仍应识别为合法 hunk header。
- 对应实现依据：`parse_one_hunk()` 在匹配 header 前执行 `trim()`（`codex-rs/apply-patch/src/parser.rs:248-251,279-333`）。

2. 端到端行为验证目的
- 验证不仅 parser 能通过，还能正确完成文件替换，最终状态从 `old` 变为 `new`。
- `expected/foo.txt` 即该行为的最终断言数据。

3. 回归防护目的
- 若未来解析器改动导致不再容忍前导空白，本场景会在目录快照比对阶段失败。
- 若解析成功但应用逻辑（替换/写回）退化，同样会被 `expected` 对比拦截。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) fixture 协议与目录语义

场景协议由 `tests/fixtures/scenarios/README.md` 定义：每个场景由 `input/`、`patch.txt`、`expected/` 三段组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-17`）。

该目录语义是“期望文件系统树”，不是文本快照字符串；比较逻辑按目录条目和文件字节内容执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-105`）。

### 2) 调用链（调用方 -> 被调用方）

调用方主链：

1. 集成测试入口 `tests/all.rs` 聚合 `suite`（`codex-rs/apply-patch/tests/all.rs:1-3`）。
2. `test_apply_patch_scenarios()` 遍历每个 scenario 目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
3. `run_apply_patch_scenario()` 复制 `input/` 到临时目录，读取 `patch.txt`，执行 `apply_patch` 二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-48`）。
4. 读取 `expected/` 和实际目录快照并 `assert_eq!` 比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。

被调用方主链：

1. `apply_patch` 二进制入口是 `src/main.rs -> codex_apply_patch::main()`（`codex-rs/apply-patch/src/main.rs:1-3`）。
2. `standalone_executable::run_main()` 解析 argv/stdin，调用 `apply_patch()`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
3. `apply_patch()` 先调用 `parse_patch()`，再调用 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
4. `apply_hunks_to_files()` 在 `UpdateFile` 分支应用替换并写回（`codex-rs/apply-patch/src/lib.rs:279-333`）。

### 3) 关键数据结构与本场景对应

1. `Hunk::UpdateFile { path, move_path, chunks }`：本场景 `patch.txt` 会被解析到此结构（`codex-rs/apply-patch/src/parser.rs:60-76,279-333`）。
2. `UpdateFileChunk`：由 `@@`、`-old`、`+new` 形成 `old_lines/new_lines`（`codex-rs/apply-patch/src/parser.rs:343-434`）。
3. `Entry` + `BTreeMap<PathBuf, Entry>`：测试侧目录快照结构，`expected/` 与实际目录都按该结构比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-105`）。

### 4) 关键容错机制（为何该 expected 内容应成立）

1. patch 边界行校验使用 `trim()`，容忍首尾空白（`codex-rs/apply-patch/src/parser.rs:226-243`）。
2. hunk header 匹配前对首行 `trim()`，因此 `"  *** Update File: foo.txt"` 仍能 `strip_prefix("*** Update File: ")` 成功（`codex-rs/apply-patch/src/parser.rs:248-251,279-333`）。
3. chunk 解析读取 `-old/+new`，后续 `compute_replacements()` 找到 old 并替换为 new（`codex-rs/apply-patch/src/parser.rs:385-434`，`codex-rs/apply-patch/src/lib.rs:386-474`）。
4. `derive_new_contents_from_chunks()` 最终写回文件时保证结尾换行（`codex-rs/apply-patch/src/lib.rs:362-377`）。

### 5) 协议/命令层

1. 规范文档声明 `apply_patch` 语法（`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`）。
2. 本场景使用命令形态等价于：

```bash
apply_patch "*** Begin Patch
  *** Update File: foo.txt
@@
-old
+new
*** End Patch"
```

3. 测试里实际使用 `Command::new(cargo_bin("apply_patch"))` 调二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。

## 关键代码路径与文件引用

### A. 目标目录与同场景输入

1. `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/expected/foo.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/input/foo.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/patch.txt`

### B. fixture 测试执行链路

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:65-126`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`

### C. 解析与应用实现链路

1. `codex-rs/apply-patch/src/main.rs:1-3`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/lib.rs:183-213`
4. `codex-rs/apply-patch/src/lib.rs:279-339`
5. `codex-rs/apply-patch/src/lib.rs:348-474`
6. `codex-rs/apply-patch/src/parser.rs:226-243`
7. `codex-rs/apply-patch/src/parser.rs:248-341`
8. `codex-rs/apply-patch/src/parser.rs:343-434`
9. `codex-rs/apply-patch/src/seek_sequence.rs:1-110`

### D. 配置、工具接入与上游调用方

1. `codex-rs/core/src/config/mod.rs:528-531`（`include_apply_patch_tool`）
2. `codex-rs/core/src/tools/spec.rs:321-380`（tool type 决策）
3. `codex-rs/core/src/tools/spec.rs:2784-2804`（注册 apply_patch 工具）
4. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-257`（再次验证 + 分发执行）
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`（构建 `codex --codex-run-as-apply-patch` 命令）
6. `codex-rs/arg0/src/lib.rs:85-107`（arg0/argv1 分发到 `codex_apply_patch`）

### E. 构建与研究流程脚本

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-10`
3. `.ops/generate_daily_research_todo.sh:1-42`
4. `Docs/researches/blueprint_checklist.md:134`

## 依赖与外部交互

### 1) crate 与测试依赖

`codex-apply-patch` 的关键依赖包括：

1. `anyhow`、`thiserror`：错误建模与上下文。
2. `similar`：unified diff 生成。
3. `tree-sitter`、`tree-sitter-bash`：shell/heredoc 解析（供 invocation 路径使用）。
4. `assert_cmd`、`tempfile`、`codex-utils-cargo-bin`、`pretty_assertions`：集成测试执行与断言。

依赖声明见 `codex-rs/apply-patch/Cargo.toml:18-30`。

### 2) 文件系统与进程交互

1. 场景测试通过子进程运行真实 `apply_patch`，不是 mock（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
2. 比较前会把 `input/` 复制到 `tempdir`，比较时遍历目录并读取每个文件字节（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37,71-105,107-126`）。
3. `apply_patch` 本体执行真实 `read/write/remove_file` I/O（`codex-rs/apply-patch/src/lib.rs:289-333,352-359`）。

### 3) 与上层工具系统交互

1. core handler 会对 patch 再做 `maybe_parse_apply_patch_verified`，把变更结构化后进入审批与执行流程（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-257`）。
2. runtime 用最小环境 `env: HashMap::new()` 执行自调用，减少环境泄露（`codex-rs/core/src/tools/runtimes/apply_patch.rs:96-100`）。
3. `arg0` 支持通过 `apply_patch` 名称或 `--codex-run-as-apply-patch` 参数路由（`codex-rs/arg0/src/lib.rs:85-107`）。

### 4) 文档与脚本交互

1. 语法规范文档是 `apply_patch_tool_instructions.md`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`）。
2. 研究进度由 `blueprint_checklist.md` 标记，`generate_daily_research_todo.sh` 每次按正则重算 pending（`.ops/generate_daily_research_todo.sh:15-39`）。

## 风险、边界与改进建议

### 风险

1. 规范文档是严格文法描述，但实现允许 marker/header 空白容忍；若读者只看文档可能误判行为边界。
2. `scenarios.rs` 仅以最终目录状态断言，不断言退出码与 stderr，某些诊断回归可能漏检（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-45`）。
3. 本目录作为 oracle 若被误改，会直接改变测试真值，需通过 code review 严控。

### 边界

1. 本 `expected/` 目录只覆盖“Update File header 前导空白”一类容错，不覆盖 Add/Delete header 的同类空白变体。
2. 不覆盖 tab 前缀、中间多空格（例如 `***  Update File:`）等更激进格式。
3. 不覆盖路径安全边界（绝对路径、`..`、符号链接）与审批策略，这些在 core 层处理。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 增补“实现层当前容忍 marker/header 首尾空白”的兼容说明，降低规范与实现认知偏差。
2. 为 `scenarios` 框架增加可选断言字段（如 `expected_exit_code`/`stderr_contains`），在保持目录快照优势的同时补足诊断质量。
3. 为 `017_*` 增加 `Add File`、`Delete File` 的 whitespace-padded header 兄弟场景，使 header 容忍覆盖更完整。
4. 在 `expected/` 相关研究文档中固定记录 `input -> patch -> expected` 三元组，便于后续批量审计 fixture 真值变更。
