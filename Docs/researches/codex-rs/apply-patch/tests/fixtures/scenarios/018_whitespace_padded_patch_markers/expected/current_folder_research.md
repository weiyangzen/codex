# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 关联场景：`018_whitespace_padded_patch_markers`

## 场景与职责

该目录是场景 `018_whitespace_padded_patch_markers` 的“最终状态基准”（golden expected state），当前仅包含一个断言文件：

- `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/expected/file.txt:1`，内容为 `two`。

它不参与 patch 解析或执行，而是在场景测试收尾阶段作为“真值快照”参与对比：

1. 测试框架将 `input/` 复制到临时目录。
2. 执行 `apply_patch`。
3. 递归读取 `expected/` 与临时目录，构建目录快照后做深度相等断言。

对应流程见：

- `codex-rs/apply-patch/tests/suite/scenarios.rs:30-60`
- `codex-rs/apply-patch/tests/suite/scenarios.rs:71-105`

因此，本目录的职责是“验证行为结果是否正确”，而不是“驱动行为发生”。

## 功能点目的

本目录服务的核心功能点是：验证补丁边界标记容错（Begin/End marker 前后空白）不仅能通过解析，而且真正改变了文件内容。

场景输入/输出最小链路：

- 输入文件：`.../input/file.txt:1` 为 `one`
- patch：`.../patch.txt:1` 为前导空格的 `*** Begin Patch`，`.../patch.txt:6` 为尾随空格的 `*** End Patch `
- 期望文件：`.../expected/file.txt:1` 为 `two`

该目录保障了两层契约：

1. 解析层契约：边界 marker 两端空白被接受（`trim()` 容忍）。
2. 执行层契约：`Update File` hunk 被正确应用，文件树最终态与 expected 完全一致。

相关代码依据：

- `codex-rs/apply-patch/src/parser.rs:226-244`（首尾 marker 比较前 `trim()`）
- `codex-rs/apply-patch/src/lib.rs:279-339`（hunk 落盘）
- `codex-rs/apply-patch/tests/suite/scenarios.rs:51-58`（最终态断言）

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1. 关键流程

1. 场景发现与调度
- `test_apply_patch_scenarios` 遍历 `fixtures/scenarios/*`，目录即场景：`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`。

2. 输入态准备
- 将场景 `input/` 拷贝到临时目录：`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`。

3. 执行 patch
- 从 `patch.txt` 读取文本并调用 `apply_patch` 可执行：`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`。
- 可执行入口读取参数/stdin 后调用库函数：`codex-rs/apply-patch/src/standalone_executable.rs:11-52`。

4. 解析与应用
- `parse_patch` -> `parse_patch_text`：`codex-rs/apply-patch/src/parser.rs:106-183`。
- 边界校验对首尾行做 `trim()`：`codex-rs/apply-patch/src/parser.rs:230-235`。
- `Update File` hunk 解析：`codex-rs/apply-patch/src/parser.rs:279-333`。
- 内容替换与写回：`codex-rs/apply-patch/src/lib.rs:348-474`、`codex-rs/apply-patch/src/lib.rs:279-339`。

5. expected 对比
- `snapshot_dir` 递归采样，结构 `BTreeMap<PathBuf, Entry>`：`codex-rs/apply-patch/tests/suite/scenarios.rs:65-105`。
- `expected/` 与实际目录执行 `assert_eq!`：`codex-rs/apply-patch/tests/suite/scenarios.rs:55-60`。

### 2. 数据结构

- `Entry`（测试侧目录快照）：`File(Vec<u8>) | Dir`，用于字节级比较目录状态。定义见 `codex-rs/apply-patch/tests/suite/scenarios.rs:65-69`。
- `ApplyPatchArgs`（解析结果）：包含 `patch`、`hunks`、`workdir`，定义见 `codex-rs/apply-patch/src/lib.rs:87-92`。
- `Hunk::UpdateFile` / `UpdateFileChunk`：承载 old/new 行与上下文，定义见 `codex-rs/apply-patch/src/parser.rs:58-104`。

### 3. 协议与命令

- 语法规范来源：
  - `codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-19`
  - `codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`
- 实现差异：规范是严格 marker 文本，但实现对首尾 marker 做了 `trim` 宽容（`parser.rs:230-235`）。

可复现实验命令：

```bash
cargo test -p codex-apply-patch --test all test_apply_patch_scenarios
```

```bash
apply_patch " *** Begin Patch
*** Update File: file.txt
@@
-one
+two
*** End Patch "
```

## 关键代码路径与文件引用

### 目标对象与直接上下文

1. `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/expected/file.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/input/file.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/patch.txt:1-6`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`

### 调用方（测试驱动）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-60`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:71-126`

### 被调用方（解析与执行）

1. `codex-rs/apply-patch/src/main.rs:1-3`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-59`
3. `codex-rs/apply-patch/src/parser.rs:154-183`
4. `codex-rs/apply-patch/src/parser.rs:226-244`
5. `codex-rs/apply-patch/src/parser.rs:279-333`
6. `codex-rs/apply-patch/src/lib.rs:183-213`
7. `codex-rs/apply-patch/src/lib.rs:279-339`
8. `codex-rs/apply-patch/src/lib.rs:348-474`

### 上游工具接入与配置路径

1. `codex-rs/core/src/tools/spec.rs:370-380`（选择 apply_patch tool type）
2. `codex-rs/core/src/tools/spec.rs:2784-2804`（注册 `apply_patch` handler）
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:146-258`（handler 解析/校验/调度）
4. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`（构造 `codex --codex-run-as-apply-patch` 命令）
5. `codex-rs/core/src/apply_patch.rs:36-77`（安全检查与委派策略）
6. `codex-rs/arg0/src/lib.rs:85-107`（arg0 / 内部参数分派到 apply_patch）

### 构建与元数据

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:3-10`

### 研究流程脚本与记录

1. `Docs/researches/blueprint_checklist.md:137`
2. `.ops/generate_daily_research_todo.sh:5-39`

## 依赖与外部交互

### 1. 依赖

`codex-apply-patch` 关键依赖（与该场景链路直接相关）：

- `anyhow`、`thiserror`：错误上下文和错误类型。
- `similar`：生成 unified diff。
- `tree-sitter`、`tree-sitter-bash`：识别 shell heredoc 形态 `apply_patch` 调用（`invocation.rs`）。
- 测试依赖 `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`。

来源：`codex-rs/apply-patch/Cargo.toml:18-30`。

### 2. 外部交互面

- 文件系统：
  - 测试期会复制 input、写临时目录、读取 expected 目录（`scenarios.rs:33-37`, `51-53`, `84-103`）。
  - 执行期会写目标文件（`lib.rs:297`, `327`）。
- 进程：
  - 场景测试通过 `Command::new(cargo_bin("apply_patch"))` 启动子进程（`scenarios.rs:45-48`）。
  - 工具运行时在 core 中使用 `codex --codex-run-as-apply-patch` 再执行（`apply_patch runtime:90-93`）。

### 3. 配置交互

- feature 开关 `ApplyPatchFreeform` 控制是否默认启用 freeform apply_patch 工具：
  - `codex-rs/core/src/features.rs:98-100`
  - `codex-rs/core/src/features.rs:639-643`
- 旧配置兼容键仍会映射到该 feature：
  - `codex-rs/core/src/features/legacy.rs:25-31`
  - `codex-rs/core/src/features/legacy.rs:72-84`
- 模型元数据可直接指定 `apply_patch_tool_type`：`codex-rs/protocol/src/openai_models.rs:244-266`。

## 风险、边界与改进建议

### 风险

1. 规范与实现偏差风险
- 规范文本强调精确 `*** Begin Patch`/`*** End Patch`，实现却允许首尾空白。若后续文档或模型提示未同步，可能产生预期偏差。

2. 结果判定粒度风险
- 场景 runner 不校验 exit code/stderr，仅以最终文件树为准。某些“输出异常但最终态凑巧一致”的问题可能被掩盖。

3. 夹具信号强度风险
- `expected/` 当前只有单文件单行，能够验证核心行为，但无法暴露更多并发或多文件副作用问题。

### 边界

1. 本目录只描述“最终应为 `two`”，不覆盖 parser 错误路径。
2. 不覆盖 marker 拼写错误、大小写错误、非空白噪声等非法输入。
3. 不覆盖权限拒绝、sandbox 差异、只读文件系统等运行时环境因素。

### 改进建议

1. 在 `scenarios` 框架中扩展可选断言元数据（如 `expected_exit_code`、`stderr_contains`），保留最终态断言同时提升诊断能力。
2. 在 `apply_patch_tool_instructions.md` 或 handler 描述中补充“实现兼容行为”说明（至少注明 marker 行两端空白被接受），减少规范误解。
3. 将 whitespace 容错场景做参数化矩阵（leading/trailing/tab/mixed，含 expected accept/reject），降低回归盲区。
4. 为 `expected/` 目录引入多文件版本的容错场景，确保容错解析不会破坏多文件应用顺序与汇总输出。
