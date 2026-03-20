# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 场景关键词：`unicode`、`utf-8`、`fixture e2e`、`line replacement`

## 场景与职责

`019_unicode_simple` 是 `apply_patch` 端到端 fixture 体系中的 Unicode 基线样例，用最小 patch 验证“含非 ASCII 字符（变音字符 + emoji）的文本替换”在真实 CLI 执行路径中可正确生效。

该目录只包含 3 个文件，职责划分非常清晰：

1. `patch.txt` 定义补丁动作：在 `foo.txt` 中将 `naïve café` 替换为 `naïve café ✅`（`codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/patch.txt:1-7`）。
2. `input/foo.txt` 定义初始状态，含 UTF-8 文本 `naïve café`（`.../input/foo.txt:1-3`）。
3. `expected/foo.txt` 定义期望状态，在同一行追加 `✅`（`.../expected/foo.txt:1-3`）。

在 `tests/suite/scenarios.rs` 中，该目录会被当成一个独立场景读取并回放（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-23`），最终通过目录快照深比较校验结果（`:50-58`）。因此该目录承担的是“规范样例 + 回归锚点”的职责，而不是实现逻辑本体。

## 功能点目的

这个场景保护的是“Unicode 文本在标准 update hunk 中的基本可用性”而不是宽松匹配策略。

核心目的：

1. 验证 parser 对 Unicode 行内容不做破坏性处理：`-naïve café` 与 `+naïve café ✅` 能被正常解析为 `old_lines/new_lines`（`codex-rs/apply-patch/src/parser.rs:343-434`）。
2. 验证执行链路按 UTF-8 文本读写：`read_to_string` + `write` 能把 emoji 与重音字符正确落盘（`codex-rs/apply-patch/src/lib.rs:348-380`, `:327-329`）。
3. 验证 fixture runner 的断言粒度是“字节级文件树一致”，避免仅靠 stdout/stderr 误判（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-102`）。

与相邻 Unicode 能力的边界：

1. `019_unicode_simple` 覆盖“补丁和文件都明确写 Unicode 字面量”的直接替换。
2. `seek_sequence` 的 Unicode 归一化宽松匹配（如 EN DASH vs ASCII `-`）属于另一能力，主要由单测 `test_update_line_with_unicode_dash` 覆盖（`codex-rs/apply-patch/src/seek_sequence.rs:67-107`; `codex-rs/apply-patch/src/lib.rs:791-834`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景协议与数据内容

该目录遵循 `fixtures/scenarios` 统一协议（`input/ + patch.txt + expected/`），定义见 `README.md`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。

`patch.txt` 内容：

```patch
*** Begin Patch
*** Update File: foo.txt
@@
 line1
-naïve café
+naïve café ✅
*** End Patch
```

该 patch 有两个关键设计：

1. 使用前置上下文行 ` line1`，确保替换定位唯一。
2. 仅替换一行，避免多因素干扰测试信号。

字节层面（`xxd -g 1`）可见：

1. `ï` 是 `c3 af`，`é` 是 `c3 a9`。
2. `✅` 是 `e2 9c 85`。

说明该样例确实在验证 UTF-8 多字节字符链路，而不是 ASCII 回归。

### 2) 调用链（调用方 -> 被调用方）

场景执行完整链路：

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 复制 `input/` 到 `tempdir`，读取 `patch.txt` 并执行 `apply_patch` 子进程（`:30-48`）。
3. `apply_patch` 可执行入口读取 argv/stdin，要求 PATCH 为 UTF-8 字符串（`codex-rs/apply-patch/src/standalone_executable.rs:16-33`）。
4. `apply_patch()` 调 `parse_patch()` 解析，再 `apply_hunks()` 执行（`codex-rs/apply-patch/src/lib.rs:183-213`）。
5. `derive_new_contents_from_chunks()` 读取旧文件、计算替换、写回新内容（`:348-380`, `:386-474`, `:478-501`）。
6. runner 用 `Entry::File(Vec<u8>)` 快照 expected 与 actual 并 `assert_eq!`（`codex-rs/apply-patch/tests/suite/scenarios.rs:55-58`, `:65-69`）。

### 3) 关键数据结构

1. `Hunk::UpdateFile { path, move_path, chunks }`：描述更新目标和变更块（`codex-rs/apply-patch/src/parser.rs:68-75`）。
2. `UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`：承载逐行替换信息（`:90-104`）。
3. `AffectedPaths { added, modified, deleted }`：执行后用于输出摘要（`codex-rs/apply-patch/src/lib.rs:271-275`, `:537-551`）。
4. 测试侧 `Entry::File(Vec<u8>) | Dir`：保证比较按字节而非仅文本（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-69`）。

### 4) 协议与命令

1. patch 协议来源：`apply_patch_tool_instructions.md` 与 parser 注释中的 Lark 语法（`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`; `codex-rs/apply-patch/src/parser.rs:4-24`）。
2. 该场景复现命令：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
3. 研究流程关联命令：
   - `bash .ops/generate_daily_research_todo.sh`（脚本会重算 pending/done 并写入当日 todo，见 `.ops/generate_daily_research_todo.sh:15-42`）。

## 关键代码路径与文件引用

### 目标目录（本场景）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/patch.txt:1-7`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/input/foo.txt:1-3`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/expected/foo.txt:1-3`

### 直接调用方（测试组织与 fixture 执行）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-3`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-126`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`

### 被调用方（apply_patch 实现）

1. `codex-rs/apply-patch/src/main.rs:1-3`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/lib.rs:183-339`
4. `codex-rs/apply-patch/src/lib.rs:348-474`
5. `codex-rs/apply-patch/src/parser.rs:106-244`
6. `codex-rs/apply-patch/src/parser.rs:343-434`
7. `codex-rs/apply-patch/src/seek_sequence.rs:12-110`
8. `codex-rs/apply-patch/src/invocation.rs:103-217`

### 上游工具接入与配置上下文

1. `codex-rs/core/src/tools/handlers/apply_patch.rs:146-258`（处理 function/custom 两种 payload，并调用 `maybe_parse_apply_patch_verified`）。
2. `codex-rs/core/src/apply_patch.rs:36-77`（安全策略决策：自动批准/询问/拒绝）。
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`（构造 `codex --codex-run-as-apply-patch <patch>` 执行命令，最小环境）。
4. `codex-rs/core/src/tools/spec.rs:2784-2804`（是否注册 apply_patch tool 及其类型）。
5. `codex-rs/core/src/config/mod.rs:528-531`（`include_apply_patch_tool` 配置说明）。
6. `codex-rs/arg0/src/lib.rs:82-107`（`apply_patch` 别名与 `CODEX_CORE_APPLY_PATCH_ARG1` 分发）。

### 构建与文档

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`
4. `.ops/generate_daily_research_todo.sh:1-42`
5. `Docs/researches/blueprint_checklist.md:139`

## 依赖与外部交互

### 代码依赖

`codex-apply-patch` 相关依赖：

1. `anyhow` / `thiserror`：错误传播与上下文。
2. `tree-sitter` / `tree-sitter-bash`：解析 shell/heredoc 型 apply_patch 调用（`invocation.rs`）。
3. `similar`：生成 unified diff（`lib.rs:527-531`）。
4. 测试依赖 `assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 文件系统与进程交互

1. fixture runner 复制输入目录并启动子进程执行 `apply_patch`（`tests/suite/scenarios.rs:33-48`）。
2. 引擎通过 `read_to_string` 读取原文并回写新内容（`lib.rs:352-359`, `:327-329`）。
3. 最终比较使用字节快照，既比较内容也比较目录结构（`tests/suite/scenarios.rs:71-105`）。

### 与上层系统交互

1. core handler 会先解析验证 patch，再进入安全评估与审批流程（`core/src/tools/handlers/apply_patch.rs:170-239`）。
2. runtime 将 patch 作为参数自调用当前 `codex` 可执行文件，走统一 sandbox 执行通道（`core/src/tools/runtimes/apply_patch.rs:69-101`, `:200-215`）。
3. arg0 机制确保 `apply_patch` 既可作为别名命令运行，也可通过隐藏参数进入同一执行实现（`arg0/src/lib.rs:85-107`, `:214-228`）。

## 风险、边界与改进建议

### 风险

1. 本场景仅覆盖“显式 Unicode 替换成功”，无法证明 parser/匹配层在所有 Unicode 规范化组合下都稳定。
2. `scenarios.rs` 不断言 exit status 与 stderr（`tests/suite/scenarios.rs:42-45`），若输出语义回归但最终文件偶然一致，可能漏检。
3. `apply_patch` 参数要求 UTF-8（`standalone_executable.rs:17-21`），对非 UTF-8 输入会直接失败；当前场景不覆盖该错误分支。

### 边界

1. 不覆盖跨文件、跨目录 Unicode 路径名。
2. 不覆盖 Unicode 正规化差异（NFC/NFD）导致的潜在匹配问题。
3. 不覆盖“补丁是 ASCII，源码是 Unicode 标点”的宽松匹配（该能力由 `seek_sequence` 和对应单测覆盖）。

### 改进建议

1. 在 fixtures 增加 `unicode_normalization` 场景：同形异码（NFC/NFD）行替换，明确当前是否支持。
2. 增加 `unicode_ascii_mismatch_fixture`：复用 `seek_sequence` 归一化能力做端到端验证，而非仅单元测试。
3. 在 `scenarios` 协议中引入可选断言元数据（如 `expect_exit`），补齐“最终态一致但退出码异常”的盲区。
4. 若未来增强 CLI 输入能力，可考虑新增二进制读取模式以支持非 UTF-8 文本；若不计划支持，建议在文档中显式声明 UTF-8 前提。
