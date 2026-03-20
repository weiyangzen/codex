# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/input`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 所属 crate：`codex-apply-patch`
- 目录实体：`file.txt`

## 场景与职责

该目录是场景 `018_whitespace_padded_patch_markers` 的输入基线（pre-state），职责是提供 patch 执行前的最小文件系统状态。

本目录与同级文件组成完整三段式夹具协议：

1. `input/file.txt` 提供初始内容 `one`（`codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/input/file.txt:1`）。
2. `patch.txt` 提供待执行补丁，关键点是 patch 边界标记带空白：
- 第 1 行 ` *** Begin Patch`（前导空格）
- 第 6 行 `*** End Patch `（尾随空格）
对应 `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/patch.txt:1` 与 `:6`。
3. `expected/file.txt` 定义最终状态 `two`（`codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/expected/file.txt:1`）。

因此，`input/` 目录本身不表达语法规则，不承载业务逻辑；它是“容错语法验证”的输入载体，直接被 `tests/suite/scenarios.rs` 的场景执行器消费（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-37`）。

## 功能点目的

围绕该目录的功能目的可归纳为三点：

1. 锁定 parser 的边界容错行为：`*** Begin Patch` / `*** End Patch` 行两端空白应被接受，而不是因字符串严格匹配失败。
2. 验证容错不仅停留在“可解析”，还应完成真实文件更新：`one -> two`。
3. 在 whitespace 系列场景中形成职责分层：
- `017_whitespace_padded_hunk_header` 验证 hunk header 前导空白；
- `018_whitespace_padded_patch_markers`（本场景）验证 patch 边界 marker 空白；
- `020_whitespace_padded_patch_marker_lines` 验证 marker 行其它空白变体。

该目录的存在意义是最小化变量：单文件、单行改动，确保失败时定位到“边界 marker 空白容错”而不是其它逻辑。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

场景从 `input/` 到断言通过的执行路径：

1. `test_apply_patch_scenarios()` 扫描 `fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 把当前场景 `input/` 复制到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-37`）。
3. 读取同级 `patch.txt`，调用 `apply_patch` 二进制执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
4. 入口 `run_main()` 读取参数或 stdin，转调 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
5. `apply_patch()` 先解析 `parse_patch()`，再执行 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
6. 边界校验函数 `check_start_and_end_lines_strict()` 对首尾行 `trim()` 后匹配 marker，因此本场景的前导/尾随空白会被容忍（`codex-rs/apply-patch/src/parser.rs:226-244`）。
7. `Update File` hunk 应用后落盘为 `two\n`（`codex-rs/apply-patch/src/lib.rs:306-339`）。
8. 测试端将临时目录与 `expected/` 做快照深度对比断言（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。

### 2) 关键数据结构

1. `ApplyPatchArgs { patch, hunks, workdir }`：解析输出载体（`codex-rs/apply-patch/src/lib.rs:85-92`）。
2. `Hunk`：`AddFile | DeleteFile | UpdateFile` 三种操作；本场景命中 `UpdateFile`（`codex-rs/apply-patch/src/parser.rs:58-76`）。
3. `UpdateFileChunk`：保存 `change_context/old_lines/new_lines/is_end_of_file`（`codex-rs/apply-patch/src/parser.rs:90-104`）。
4. 场景断言结构 `Entry = File(Vec<u8>) | Dir`，由 `BTreeMap<PathBuf, Entry>` 持有目录快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-77`）。

### 3) 协议与语法

1. fixtures 协议：每个场景目录由 `input/ + patch.txt + expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。
2. tool 规范语法（Lark）：`begin_patch` 与 `end_patch` 定义为严格文本（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-3`）。
3. 文档语法示例同样是严格 marker（`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`）。
4. 运行时实现更宽容：parser 在边界校验处 `trim()`，因此兼容本场景输入（`codex-rs/apply-patch/src/parser.rs:230-235`）。

### 4) 关键命令

1. 场景执行：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 目标文件最小复现：
```bash
apply_patch " *** Begin Patch
*** Update File: file.txt
@@
-one
+two
*** End Patch "
```
3. 研究任务同步脚本：`bash .ops/generate_daily_research_todo.sh`（`.ops/generate_daily_research_todo.sh:1-42`）。

## 关键代码路径与文件引用

### A. 目标对象与同级场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/input/file.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/patch.txt:1-6`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/expected/file.txt:1`

### B. 直接调用方（测试）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:71-126`
5. `codex-rs/apply-patch/tests/suite/cli.rs:11-91`
6. `codex-rs/apply-patch/tests/suite/tool.rs:19-257`

### C. 被调用方（解析/执行）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-266`
3. `codex-rs/apply-patch/src/lib.rs:279-339`
4. `codex-rs/apply-patch/src/parser.rs:154-183`
5. `codex-rs/apply-patch/src/parser.rs:226-244`
6. `codex-rs/apply-patch/src/parser.rs:248-340`
7. `codex-rs/apply-patch/src/seek_sequence.rs:12-110`

### D. 配置与注册路径（上游调用链）

1. tool 注册与类型选择：`codex-rs/core/src/tools/spec.rs:2784-2804`
2. handler 二次验证与调度：`codex-rs/core/src/tools/handlers/apply_patch.rs:146-258`
3. runtime 构建自调用命令：`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`
4. CLI/arg0 分发与内部参数契约：`codex-rs/arg0/src/lib.rs:85-107`
5. core 文档里的平台约定：`codex-rs/core/README.md:92-94`

### E. 构建、脚本、文档

1. crate 与依赖：`codex-rs/apply-patch/Cargo.toml:1-30`
2. Bazel 编译数据：`codex-rs/apply-patch/BUILD.bazel:1-11`
3. apply_patch 说明文档：`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`
4. fixtures 协议文档：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
5. todo 生成脚本：`.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

### 1) 依赖

与本目录场景直接相关的 crate 依赖：

1. `anyhow`、`thiserror`：错误上下文与类型（`codex-rs/apply-patch/Cargo.toml:19-23`）。
2. `similar`：生成 unified diff 的文本比较能力（`codex-rs/apply-patch/Cargo.toml:20`，`codex-rs/apply-patch/src/lib.rs:527-529`）。
3. `tree-sitter`、`tree-sitter-bash`：解析 shell/heredoc 形式的 apply_patch 调用（`codex-rs/apply-patch/Cargo.toml:22-23`，`codex-rs/apply-patch/src/invocation.rs:102-217`）。
4. 测试依赖 `assert_cmd/tempfile/pretty_assertions/codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 外部交互

1. 文件系统：复制 `input/`、写入更新后的文件、读取 `expected/` 进行快照对比（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37,50-53,79-126`）。
2. 子进程：测试通过 `Command::new(cargo_bin("apply_patch"))` 启动二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. 标准流：`apply_patch` 成功输出 summary，失败输出诊断（`codex-rs/apply-patch/src/lib.rs:191-206,535-552`）。

### 3) 与上层系统交互

1. `core` handler 对模型输入先 `maybe_parse_apply_patch_verified` 再决定审批与执行路径（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-257`）。
2. `ApplyPatchRuntime` 将 patch 变为 `codex --codex-run-as-apply-patch <patch>`，在沙箱策略下执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:89-100,207-214`）。
3. `arg0` 在 `argv0=apply_patch/applypatch` 或 `argv1=--codex-run-as-apply-patch` 时分发到同一实现（`codex-rs/arg0/src/lib.rs:85-107`）。

## 风险、边界与改进建议

### 风险

1. 规范与实现差异风险：Lark/说明文档表面是严格 marker，parser 实现对边界 marker 使用 `trim()`，存在认知偏差（`tool_apply_patch.lark:1-3` vs `parser.rs:230-235`）。
2. 场景测试信号风险：`scenarios.rs` 不校验 exit status，仅比较最终目录；诊断信息回归可能被掩盖（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。
3. 场景重叠风险：`018` 与 `020_whitespace_padded_patch_marker_lines` 都覆盖 marker 空白容错，长期可能出现重复维护成本。

### 边界

1. 本目录只验证单文件单行更新，不覆盖多文件原子性或重命名行为。
2. 不验证权限审批、沙箱拒绝、跨目录写入策略等安全语义（这些属于 core/runtime 层）。
3. 不覆盖 marker 拼写错误、大小写错误、混合噪声字符等非法输入变体。

### 改进建议

1. 为 whitespace 容错建立参数化矩阵（space/tab/mixed，Begin/End/header 分维度），减少 017/018/020 的手工重复。
2. 在 `tests/suite/scenarios.rs` 引入可选元数据断言（如 `exit_code`、`stderr_contains`），保持快照优势同时增强诊断覆盖。
3. 在 `apply_patch_tool_instructions.md` 增加“实现兼容行为”说明（至少说明边界 marker 的空白容错），降低规范与实现差异带来的误用风险。
4. 修订 `parse_one_hunk` 注释中“case mismatches”表述，当前实现仅做 `trim()`，并未做大小写归一（`codex-rs/apply-patch/src/parser.rs:249-251`）。
