# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 场景关键词：`whitespace tolerance`、`hunk header`、`Update File`、`fixture e2e`

## 场景与职责

`017_whitespace_padded_hunk_header` 是 `apply_patch` fixtures 中的“语法宽容”场景，专门验证：
`*** Update File: ...` 这类 hunk header 行在前面带空白时仍应被正确识别并执行。

该目录的职责拆分为：

1. `patch.txt`：构造最小可复现输入，只有一个 `Update File` 操作，并故意在第 2 行写成 `␠␠*** Update File: foo.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/patch.txt:1-6`）。
2. `input/foo.txt`：提供初始文件 `old`（`.../input/foo.txt:1`）。
3. `expected/foo.txt`：提供期望结果 `new`，表达“补丁应成功应用”（`.../expected/foo.txt:1`）。

在同层场景矩阵中，它和以下目录形成互补：

1. `018_whitespace_padded_patch_markers`：验证 patch 边界标记（Begin/End）两端空白容忍。
2. `020_whitespace_padded_patch_marker_lines`：验证 marker 行本身带尾/首空白容忍。
3. 本目录 `017_*`：聚焦“hunk header 行”空白容忍，不混入其他容错因素。

## 功能点目的

该场景保护的核心契约是：

1. `parse_one_hunk()` 对 hunk 首行做 `trim()` 后再匹配 `*** Add/Delete/Update File:` 前缀，因此应接受“带前导/尾随空白的 header”。
2. 该容错必须是“可执行的容错”，即不仅 parser 通过，还要完成真实文件更新（`old -> new`）。
3. 容错只针对 marker/header 的空白，不应误扩展为更激进的语法放宽（例如未知 header、缺失 diff 行仍需拒绝）。

这个场景主要防两类回归：

1. 解析回归：未来如果去掉 `trim()` 或改成更严格匹配，会把本应可接受输入误判为 `InvalidHunkError`。
2. 端到端回归：parser 虽通过，但应用流程（读取/替换/写回）出错，导致最终文件状态不符。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景输入与协议

场景补丁全文：

```patch
*** Begin Patch
  *** Update File: foo.txt
@@
-old
+new
*** End Patch
```

关键点：第 2 行前有两个空格，属于“whitespace padded hunk header”。

协议来源有两层：

1. `fixtures/scenarios/README.md` 规定每个场景由 `input/ + patch.txt + expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-17`）。
2. `apply_patch_tool_instructions.md` 给出官方语法（hunk header 理论上是严格格式）（`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`）。

实现层的 parser 在此基础上做了更宽容处理（见后文）。

### 2) 调用方流程（fixture runner）

`tests/suite/scenarios.rs` 的统一执行流程：

1. 遍历 `tests/fixtures/scenarios/*` 目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 把目标场景的 `input/` 复制到 `tempdir()`（`.../scenarios.rs:33-37,107-126`）。
3. 读取 `patch.txt`，拉起 `apply_patch` 子进程执行（`.../scenarios.rs:39-48`）。
4. 构建 `expected` 与实际输出目录快照（`BTreeMap<PathBuf, Entry>`）并深比较（`.../scenarios.rs:50-58,65-105`）。

注意：该 runner 故意不检查退出码，仅比较最终文件树（`.../scenarios.rs:42-45`）。
因此本场景本质断言是“最终状态等于 expected”，而不是 stderr 文案。

### 3) 被调用方实现（解析 -> 应用）

执行链路：

1. 二进制入口：`src/main.rs` 调 `codex_apply_patch::main()`（`codex-rs/apply-patch/src/main.rs:1-3`）。
2. CLI 主逻辑：`standalone_executable::run_main()` 收 patch 参数（argv 或 stdin），调用 `apply_patch()`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
3. `apply_patch()` 先 `parse_patch()`，成功后 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。

与本场景直接相关的 parser 关键细节：

1. `check_start_and_end_lines_strict()` 对首尾行 `trim()` 后再校验 `*** Begin Patch / *** End Patch`（`codex-rs/apply-patch/src/parser.rs:226-243`）。
2. `parse_one_hunk()` 对 hunk 首行做 `trim()`：`let first_line = lines[0].trim();`（`codex-rs/apply-patch/src/parser.rs:248-251`）。
3. 随后用 `strip_prefix("*** Update File: ")` 匹配，所以 `"  *** Update File: foo.txt"` 也能识别为 `UpdateFile`（`codex-rs/apply-patch/src/parser.rs:279-333`）。
4. chunk 解析由 `parse_update_file_chunk()` 完成，`@@` 后的 `-old/+new` 生成 `old_lines/new_lines`（`codex-rs/apply-patch/src/parser.rs:343-434`）。

应用阶段关键数据结构与流程：

1. hunk 解析为 `Hunk::UpdateFile { path, move_path, chunks }`（`codex-rs/apply-patch/src/parser.rs:60-76,325-331`）。
2. `apply_hunks_to_files()` 在 `UpdateFile` 分支调用 `derive_new_contents_from_chunks()`（`codex-rs/apply-patch/src/lib.rs:279-333,348-381`）。
3. `compute_replacements()` 基于 `chunk.old_lines` 定位替换片段，`seek_sequence()` 负责匹配（含空白宽松匹配）并生成 replacement（`codex-rs/apply-patch/src/lib.rs:386-474`，`codex-rs/apply-patch/src/seek_sequence.rs:1-110`）。
4. `apply_replacements()` 逆序应用替换并写回文件（`codex-rs/apply-patch/src/lib.rs:478-502`）。

### 4) 同语义测试与文档证据

除了 fixture，本语义在单测也有旁证：

1. parser 单测包含“header 前有空白仍能识别”的输入（`codex-rs/apply-patch/src/parser.rs:470-479`）。
2. parser 单测也覆盖 patch marker 两端空白容忍（`codex-rs/apply-patch/src/parser.rs:451-468`）。
3. tool 测试覆盖非法 header 报错，界定了容错边界（`codex-rs/apply-patch/tests/suite/tool.rs:210-218`）。

### 5) 上下文配置与上层调用链

虽然本场景在 `codex-apply-patch` crate 内执行，但其语义会直接影响 core 工具链：

1. `ApplyPatchHandler` 在执行前会调用 `maybe_parse_apply_patch_verified()` 重解析并做安全/审批前置（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-179`，`codex-rs/apply-patch/src/invocation.rs:132-217`）。
2. runtime 最终执行 `codex --codex-run-as-apply-patch <patch>`，而非直接 shell 解释 patch（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`）。
3. `arg0` 通过 `CODEX_CORE_APPLY_PATCH_ARG1` 路由到 `codex_apply_patch::apply_patch()`（`codex-rs/arg0/src/lib.rs:90-107`）。
4. 工具是否暴露受配置/特性控制：`include_apply_patch_tool` 与 `apply_patch_tool_type`（`codex-rs/core/src/config/mod.rs:528-531`，`codex-rs/core/src/tools/spec.rs:321-380,2784-2804`）。

### 6) 相关命令（研究/复现）

1. 全量场景回放：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 仅验证非法 header 边界：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_rejects_invalid_hunk_header`
3. 手工复现本场景：
   `apply_patch "*** Begin Patch\n  *** Update File: foo.txt\n@@\n-old\n+new\n*** End Patch"`

## 关键代码路径与文件引用

### A. 目标目录（研究对象）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/patch.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/input/foo.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/expected/foo.txt`

### B. 直接调用方（场景执行器）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`

### C. 被调用方（解析与执行主链）

1. `codex-rs/apply-patch/src/main.rs:1-3`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/lib.rs:183-213`
4. `codex-rs/apply-patch/src/lib.rs:279-339`
5. `codex-rs/apply-patch/src/lib.rs:348-474`
6. `codex-rs/apply-patch/src/parser.rs:226-243`
7. `codex-rs/apply-patch/src/parser.rs:248-341`
8. `codex-rs/apply-patch/src/parser.rs:343-434`
9. `codex-rs/apply-patch/src/seek_sequence.rs:1-110`

### D. 同语义/边界测试

1. `codex-rs/apply-patch/src/parser.rs:451-479`
2. `codex-rs/apply-patch/tests/suite/tool.rs:210-218`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/patch.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/patch.txt`

### E. 上下游依赖（配置、handler、runtime、调度）

1. `codex-rs/apply-patch/src/invocation.rs:103-217`
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-257`
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-215`
4. `codex-rs/arg0/src/lib.rs:85-107`
5. `codex-rs/core/src/config/mod.rs:528-531`
6. `codex-rs/core/src/tools/spec.rs:321-380`
7. `codex-rs/core/src/tools/spec.rs:2784-2804`
8. `codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`
9. `codex-rs/apply-patch/Cargo.toml:1-30`
10. `codex-rs/apply-patch/BUILD.bazel:1-10`
11. `.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

### 1) crate 依赖

`codex-apply-patch` 与本场景相关的主要依赖（`codex-rs/apply-patch/Cargo.toml:18-30`）：

1. `thiserror` / `anyhow`：错误建模与上下文传播。
2. `similar`：生成 unified diff（用于 verified 路径与上游审批展示）。
3. `tree-sitter` / `tree-sitter-bash`：解析 shell heredoc 形式的 `apply_patch` 调用（`invocation.rs`）。
4. `assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`：集成测试执行与快照比较。

### 2) 文件系统与进程交互

1. fixture runner 会复制输入目录、启动 `apply_patch` 子进程、然后读取目录树做字节级比较。
2. `apply_patch` 真实执行 `read_to_string`/`write`/`remove_file` 等 I/O，不是纯内存 mock。
3. `scenarios.rs` 在 Buck2 下用 `fs::metadata()` 跟随 symlink，减少跨构建系统差异（`codex-rs/apply-patch/tests/suite/scenarios.rs:92-95,113-115`）。

### 3) 与上层系统的交互

1. 对 core 而言，`codex-apply-patch` 提供的是“解析+验证+变更结构化表示”能力，供审批与执行解耦。
2. runtime 通过最小环境执行内部命令（`env: HashMap::new()`），降低环境泄露与不确定性（`codex-rs/core/src/tools/runtimes/apply_patch.rs:96-100`）。
3. `arg0` 提供别名与内部参数分发，使 `apply_patch` 既可独立调用也可由 `codex` 自调用。

### 4) 文档与脚本交互

1. 语法文档（`apply_patch_tool_instructions.md`）定义“规范形式”。
2. parser 代码定义“实际兼容行为”（例如 header/patch marker 空白容忍）。
3. 研究工作流脚本 `.ops/generate_daily_research_todo.sh` 基于 `Docs/researches/blueprint_checklist.md` 生成当日待办。

## 风险、边界与改进建议

### 风险

1. 文档语法与实现语义存在“严格 vs 宽容”差距：文档看起来是严格 header 格式，而实现接受 header 前后空白。
2. `parse_one_hunk()` 注释写到“tolerant of case mismatches”，但当前实现只做 `trim()`，并没有大小写容忍；注释与行为不一致有误导风险（`codex-rs/apply-patch/src/parser.rs:249-251`）。
3. `scenarios.rs` 不检查退出码/stderr，导致“错误信息退化但最终状态碰巧一致”这类问题可能漏检。

### 边界

1. 本场景只覆盖 `Update File` header 前导空白，不覆盖 `Add File`/`Delete File` 的同类输入。
2. 不覆盖 tab、混合空白、header 中间多空格（如 `***  Update File:`）等变体。
3. 不覆盖路径层边界（绝对路径、`..`、符号链接写入权限等）；这些属于其他安全/运行时路径。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 增补“实现当前允许 marker/header 两端空白”的兼容说明，减少规范误解。
2. 在 parser 单测中增加 `Add/Delete` header 的 whitespace 容忍用例，避免只由 fixture 间接覆盖。
3. 将 `scenarios` 框架扩展为可选断言 `exit_code`/`stderr_contains`，补足状态断言之外的诊断质量。
4. 修正 `parse_one_hunk()` 注释，避免“支持大小写不敏感”的错误暗示，保持文档与代码一致。
