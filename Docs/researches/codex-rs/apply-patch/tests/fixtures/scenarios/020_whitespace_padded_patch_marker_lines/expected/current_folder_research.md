# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 关联场景：`020_whitespace_padded_patch_marker_lines`

## 场景与职责

该目录是场景 `020_whitespace_padded_patch_marker_lines` 的期望结果目录（oracle），用于定义 apply_patch 执行后的“最终文件系统状态”。

当前目录只包含一个断言文件：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/expected/file.txt:1`，内容为 `two`。

它本身不参与补丁解析、权限决策或写盘逻辑；其职责是被场景测试框架读取并与临时执行目录逐项对比，作为端到端通过标准。

在测试链路中的具体位置：

1. `run_apply_patch_scenario()` 先复制 `input/` 到临时目录，再执行 `apply_patch` 二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-48`）。
2. 执行后读取 `expected/` 与实际目录为快照并 `assert_eq!`（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。
3. 因而 `expected/` 目录是该场景最终语义的唯一真值源。

## 功能点目的

该目录服务的功能点不是“如何解析 marker”，而是“容错解析是否真正落地为正确结果”。

对应业务意图：

1. 场景 patch 在边界 marker 行加入空白：
   - `*** Begin Patch `（末尾空格，`patch.txt:1`）
   - ` *** End Patch`（开头空格，`patch.txt:6`）
2. parser 应该仍能接受该补丁（边界检查前对首尾行 `trim()`）。
3. Update hunk 应成功把 `input/file.txt` 的 `one` 改为 `two`。
4. 最终由 `expected/file.txt` 对该结果做字节级确认。

这个 expected 目录因此承担两层回归保护：

1. 防止 parser 边界容错退化导致补丁未被应用。
2. 防止 parser 虽通过、但执行层（chunk 定位/替换/写回）出现退化。

与相邻场景的关系：

1. `018_whitespace_padded_patch_markers` 关注首行前导空白 + 末行尾随空白。
2. 本场景 `020_whitespace_padded_patch_marker_lines` 覆盖互补变体：首行尾随空白 + 末行前导空白。
3. `017_whitespace_padded_hunk_header` 则关注 `*** Update File:` 头行前导空白，不是 Begin/End 边界行。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) fixture 协议与目录语义

`tests/fixtures/scenarios/README.md` 定义了场景结构：每个 case 由 `input/ + patch.txt + expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。

本场景中：

1. `input/file.txt` 初始值 `one`（`.../input/file.txt:1`）。
2. `patch.txt` 为单文件 `Update File`，含 whitespace-padded Begin/End marker（`.../patch.txt:1-6`）。
3. `expected/file.txt` 期望值 `two`（`.../expected/file.txt:1`）。

### 2) 调用方关键流程（tests/suite/scenarios.rs）

1. `test_apply_patch_scenarios()` 枚举 `fixtures/scenarios` 下所有目录并逐个运行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()`：
   - 拷贝输入目录到 `tempdir`（`33-37`）。
   - 读取 `patch.txt`（`39-40`）。
   - 运行 `apply_patch` 子进程（`45-48`）。
3. `snapshot_dir()` 递归采样目录，数据结构是 `BTreeMap<PathBuf, Entry>`，`Entry` 为 `File(Vec<u8>) | Dir`（`65-105`）。
4. 使用 `pretty_assertions::assert_eq!` 比较 `actual_snapshot` 与 `expected_snapshot`（`55-58`）。

该设计意味着 expected 目录是“最终态协议”的核心组成。

### 3) 被调用方关键流程（apply_patch 可执行与库）

1. 二进制入口：`src/main.rs` -> `codex_apply_patch::main()`（`codex-rs/apply-patch/src/main.rs:1-3`）。
2. `standalone_executable::run_main()` 从 argv/stdin 取 patch 并调用 `crate::apply_patch()`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
3. `apply_patch()` 调 `parse_patch()`，解析成功后执行 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
4. `apply_hunks_to_files()` 在 `Hunk::UpdateFile` 分支中：
   - `derive_new_contents_from_chunks()` 产出新内容。
   - `std::fs::write(path, new_contents)` 写回文件（`codex-rs/apply-patch/src/lib.rs:307-330`）。

### 4) 本场景最相关的 parser 容错机制

1. `parse_patch_text()` 首先 `patch.trim().lines()`（`codex-rs/apply-patch/src/parser.rs:154-156`）。
2. `check_start_and_end_lines_strict()` 再对首尾行 `line.trim()` 后比对 marker（`codex-rs/apply-patch/src/parser.rs:226-235`）。
3. 因此 `*** Begin Patch ` 和 ` *** End Patch` 都被接受。
4. `parse_one_hunk()` 对 hunk header 也先 `trim()`（`codex-rs/apply-patch/src/parser.rs:248-251`），保证 header 行前后空白具兼容性。
5. parser 单测已覆盖此类行为：`concat!("*** Begin Patch", " ", ..., " ", "*** End Patch")` 解析成功（`codex-rs/apply-patch/src/parser.rs:451-468`）。

### 5) 协议与命令

1. 工具说明文档中给出的语法是严格文法（`Begin := "*** Begin Patch"`，`End := "*** End Patch"`），见 `codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`。
2. 运行时实现在 parser 层做了 marker 空白容错（见上节）。
3. 可复现命令：

```bash
cargo test -p codex-apply-patch --test all test_apply_patch_scenarios
```

## 关键代码路径与文件引用

### A. 目标对象与同场景输入

1. `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/expected/file.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/input/file.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/patch.txt:1-6`

### B. 场景测试执行器（直接调用方）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:65-126`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`

### C. 解析与执行主链（被调用方）

1. `codex-rs/apply-patch/src/main.rs:1-3`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/lib.rs:183-213`
4. `codex-rs/apply-patch/src/lib.rs:279-339`
5. `codex-rs/apply-patch/src/lib.rs:348-474`
6. `codex-rs/apply-patch/src/parser.rs:154-183`
7. `codex-rs/apply-patch/src/parser.rs:226-244`
8. `codex-rs/apply-patch/src/parser.rs:248-341`
9. `codex-rs/apply-patch/src/seek_sequence.rs:1-110`

### D. 上游接入路径（调用方的调用方）

1. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-257`（工具调用时再次验证 patch 并进入审批/执行）。
2. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`（构造 `codex --codex-run-as-apply-patch <patch>`）。
3. `codex-rs/arg0/src/lib.rs:85-107`（`apply_patch`/`applypatch` 或内部 argv1 分发到 `codex_apply_patch`）。
4. `codex-rs/core/src/tools/spec.rs:2784-2804`（按配置注册 apply_patch tool spec）。
5. `codex-rs/core/src/config/mod.rs:528-531`（`include_apply_patch_tool` 配置项）。

### E. 构建与研究流程文件

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-10`
3. `Docs/researches/blueprint_checklist.md:146`
4. `.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

### 1) 依赖

`codex-apply-patch` 与本场景直接相关依赖（`codex-rs/apply-patch/Cargo.toml:18-30`）：

1. `anyhow`、`thiserror`：错误封装和传播。
2. `similar`：`unified_diff` 生成（Update 路径会使用）。
3. `tree-sitter`、`tree-sitter-bash`：heredoc/脚本形态 apply_patch 识别（`invocation.rs`）。
4. `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`：测试执行和目录快照断言。

### 2) 外部交互面

1. 文件系统交互：
   - 读取 `patch.txt`。
   - 复制 `input/` 到临时目录。
   - 将执行后目录与 `expected/` 做字节级比较。
2. 进程交互：
   - `scenarios.rs` 通过 `Command::new(cargo_bin("apply_patch"))` 启动子进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. 上层工具交互：
   - core handler 拦截/校验后再调 runtime，runtime 通过 arg0 内部参数触发 apply_patch 执行链。

### 3) 协议/配置交互

1. patch 文本协议由 `apply_patch_tool_instructions.md` 和 lark grammar 定义。
2. `include_apply_patch_tool` / `apply_patch_tool_type` 决定模型侧工具暴露形态（freeform/function）。
3. `expected/` 目录属于 test fixture 协议的一部分，不依赖运行时动态配置。

## 风险、边界与改进建议

### 风险

1. 规范与实现可能出现认知偏差：规范写法偏严格，parser 对 marker 行做 `trim` 容错；若未来改动一侧未同步，会产生“文档说法和真实行为不一致”。
2. 场景 runner 仅做最终态断言，不显式断言 exit code/stderr；对某些诊断层回归可见性有限。
3. expected 目录是真值文件，一旦误改会直接改变测试语义，需要严格 code review。

### 边界

1. 本目录仅覆盖“边界 marker 行空白容错 + 成功更新最终态”，不覆盖非法 marker 拼写或大小写错误。
2. 仅覆盖单文件、单 chunk 的最小更新，不覆盖多文件/多 chunk 或 move/delete 混合操作。
3. 不覆盖权限审批、sandbox 失败、只读文件系统等环境边界。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 增补“实现层容错行为（marker 两端空白）”说明，降低规范-实现偏差风险。
2. 在 `tests/suite/scenarios.rs` 引入可选元数据断言（如 `expected_exit_code`、`stderr_contains`），保留最终态对比的同时增强诊断能力。
3. 补充 whitespace 容错矩阵场景（空格/tab/混合、Begin/End/header 分别覆盖），提高回归检测粒度。
4. 为 expected 文档增加固定模板字段（input 摘要、patch 摘要、expected 摘要），便于后续批量审计 fixture 真值变更。
