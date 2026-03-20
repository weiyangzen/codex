# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/input`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 所属 crate：`codex-apply-patch`
- 场景标签：`unicode`、`utf-8`、`fixture`、`e2e`

## 场景与职责

`019_unicode_simple/input` 是 `apply_patch` 场景夹具中的“输入初始态目录”，当前只包含一个文件：

- `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/input/foo.txt`

该目录不负责补丁语法，也不负责执行逻辑；它负责定义 **补丁执行前** 的文件系统状态，并被场景执行器复制到临时目录作为真实执行基底：

1. 场景扫描：`test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 输入复制：`run_apply_patch_scenario()` 将 `input/` 递归复制到 `tempdir`（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-37`）。
3. 在临时目录执行 `patch.txt` 后，将结果与 `expected/` 做快照比对（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-58`）。

在 `019_unicode_simple` 中，`input/foo.txt` 的职责是提供 Unicode 旧行：`naïve café`，作为 update hunk 的匹配目标。

## 功能点目的

该目录服务的核心功能点是：验证 `apply_patch` 在最小真实路径上能够正确处理 UTF-8 文本替换。

围绕本目录的三元关系：

1. 输入（本目录）
- `input/foo.txt` 初始内容：
  - `line1`
  - `naïve café`
  - `line3`

2. 补丁
- `patch.txt` 将 `-naïve café` 替换为 `+naïve café ✅`（`codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/patch.txt:1-7`）。

3. 期望
- `expected/foo.txt` 的第二行应为 `naïve café ✅`（`codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/expected/foo.txt:1-3`）。

该场景关注“显式 Unicode 字面值替换成功”，与 `seek_sequence` 的“ASCII/Unicode 标点宽松归一化匹配”是相邻但不同的覆盖面（后者主要在 `codex-rs/apply-patch/src/seek_sequence.rs:67-107` 和 `codex-rs/apply-patch/src/lib.rs:791-834` 单测覆盖）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

从 `input/` 到断言通过的执行链：

1. fixture 协议加载
- 协议为 `input/ + patch.txt + expected/`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。

2. 子进程执行
- 测试通过 `Command::new(cargo_bin("apply_patch"))` 在临时目录执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。

3. CLI 入口
- `run_main()` 读取 argv 或 stdin，要求 PATCH 为 UTF-8（`codex-rs/apply-patch/src/standalone_executable.rs:11-41`）。

4. 解析 + 应用
- `apply_patch()` 先 `parse_patch()` 后 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
- `parse_update_file_chunk()` 将 `-`/`+` 行解析为 `old_lines/new_lines`（`codex-rs/apply-patch/src/parser.rs:343-434`）。
- `derive_new_contents_from_chunks()` 读取原文、按行计算替换、写回文件（`codex-rs/apply-patch/src/lib.rs:348-380`，`386-474`，`306-329`）。

5. 最终断言
- 使用 `Entry::File(Vec<u8>)` 做字节级目录快照比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-102`）。

### 2) 关键数据结构

1. `Hunk::UpdateFile { path, move_path, chunks }`
- 表达单文件更新语义（`codex-rs/apply-patch/src/parser.rs:68-75`）。

2. `UpdateFileChunk`
- 字段：`change_context`、`old_lines`、`new_lines`、`is_end_of_file`（`codex-rs/apply-patch/src/parser.rs:90-104`）。

3. `AffectedPaths`
- 应用后输出摘要（A/M/D）所需（`codex-rs/apply-patch/src/lib.rs:271-275`，`537-551`）。

4. `Entry::File(Vec<u8>) | Dir`
- 场景快照断言结构，确保 UTF-8 内容按字节一致比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-69`）。

### 3) 协议与约束

1. 文本夹具行尾
- `.gitattributes` 规定 `text eol=lf`，减少换行差异干扰（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`）。

2. 语法规范
- tool 文档语法定义见 `apply_patch_tool_instructions.md`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`）。
- parser 注释内也给出对应 Lark 语法（`codex-rs/apply-patch/src/parser.rs:4-24`）。

3. 当前场景的 UTF-8 字节事实
- `input/foo.txt` 中 `ï`=`c3 af`、`é`=`c3 a9`。
- 期望文件新增 `✅`=`e2 9c 85`。
- 可由 `xxd -g 1` 直接验证（本次已核验）。

### 4) 关键命令

1. 复现场景：
- `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`

2. 仅验证该场景文件内容：
- `cat codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/input/foo.txt`
- `cat codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/patch.txt`
- `cat codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/expected/foo.txt`

3. 研究任务同步：
- `bash .ops/generate_daily_research_todo.sh`（`.ops/generate_daily_research_todo.sh:1-42`）。

## 关键代码路径与文件引用

### A. 目标对象与同场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/input/foo.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/patch.txt:1-7`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/expected/foo.txt:1-3`
4. `Docs/researches/codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/current_folder_research.md`
5. `Docs/researches/codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/expected/current_folder_research.md`

### B. 直接调用方（测试入口与场景运行器）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-3`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:71-126`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`

### C. 被调用方（解析与执行）

1. `codex-rs/apply-patch/src/main.rs:1-3`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/lib.rs:183-213`
4. `codex-rs/apply-patch/src/lib.rs:279-339`
5. `codex-rs/apply-patch/src/lib.rs:348-474`
6. `codex-rs/apply-patch/src/parser.rs:106-183`
7. `codex-rs/apply-patch/src/parser.rs:343-434`
8. `codex-rs/apply-patch/src/seek_sequence.rs:12-110`
9. `codex-rs/apply-patch/src/invocation.rs:103-217`

### D. 配置、接入与上游调用链（项目级上下文依赖）

1. tool handler 二次验证入口：`codex-rs/core/src/tools/handlers/apply_patch.rs:170-258`
2. shell/exec 拦截路径：`codex-rs/core/src/tools/handlers/apply_patch.rs:262-355`
3. freeform/function tool 描述注册源：`codex-rs/core/src/tools/handlers/apply_patch.rs:360-430`
4. runtime 自调用命令构建：`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`
5. runtime 执行与审批复用：`codex-rs/core/src/tools/runtimes/apply_patch.rs:122-215`
6. 功能开关到 tool 类型推导：`codex-rs/core/src/tools/spec.rs:321-380`
7. `apply_patch` handler 注册：`codex-rs/core/src/tools/spec.rs:2784-2804`
8. arg0 分发 `apply_patch`/内部 flag：`codex-rs/arg0/src/lib.rs:85-107`

### E. 构建、依赖、脚本、文档

1. crate 定义与依赖：`codex-rs/apply-patch/Cargo.toml:1-30`
2. Bazel `compile_data`：`codex-rs/apply-patch/BUILD.bazel:1-11`
3. apply_patch 文档：`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`
4. 每日 TODO 生成脚本：`.ops/generate_daily_research_todo.sh:1-42`
5. checklist 对应行：`Docs/researches/blueprint_checklist.md:141`

## 依赖与外部交互

### 1) 代码依赖

`codex-apply-patch` 相关关键依赖：

1. `anyhow`、`thiserror`：错误类型与上下文（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. `similar`：生成 unified diff（`codex-rs/apply-patch/src/lib.rs:527-532`）。
3. `tree-sitter`、`tree-sitter-bash`：解析 shell/heredoc 形式的 `apply_patch` 调用（`codex-rs/apply-patch/src/invocation.rs:219-260`）。
4. `assert_cmd`、`tempfile`、`codex-utils-cargo-bin`、`pretty_assertions`：场景测试基础设施（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 外部交互

1. 文件系统交互
- 读取 `input/`、复制至临时目录、应用变更、再对比 `expected/`（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-53`）。

2. 进程交互
- 测试启动 `apply_patch` 子进程执行 patch（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
- core runtime 中通过 `codex --codex-run-as-apply-patch` 自调用执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:89-93`）。

3. 编码交互
- CLI 参数必须 UTF-8（`codex-rs/apply-patch/src/standalone_executable.rs:16-22`）。
- 本目录即 UTF-8 真实输入样本，覆盖非 ASCII 字符（`ï`、`é`）。

## 风险、边界与改进建议

### 风险

1. 覆盖面风险
- 本目录仅单文件单行替换，无法覆盖多文件、多目录、重命名联动语义。

2. 判定维度风险
- `scenarios.rs` 不校验子进程退出码/stderr，只校验最终文件树（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）；过程异常可能被最终态掩盖。

3. 输入编码风险
- `apply_patch` 仅接受 UTF-8 PATCH；若上游产生非 UTF-8 内容会直接失败，此场景不覆盖该分支。

### 边界

1. 不覆盖 Unicode 规范化差异（NFC/NFD）导致的匹配偏差。
2. 不覆盖 Unicode 文件路径（当前只覆盖 Unicode 文件内容）。
3. 不覆盖 ASCII patch 对 Unicode 标点的模糊匹配端到端场景（当前主要是单元测试覆盖）。

### 改进建议

1. 增加 `unicode_normalization` fixture
- 同形异码（NFC/NFD）文本替换，明确当前行为边界。

2. 增加 `unicode_filename` fixture
- 包含 Unicode 路径名（例如 `测试/naïve✅.txt`）的 add/update/delete。

3. 扩展场景断言元数据
- 在 fixture 协议中支持可选 `expected_exit_code` / `stderr_contains`，补齐“过程正确性”断言盲区。

4. 增加端到端模糊匹配 fixture
- 将 `seek_sequence` 的 Unicode 标点归一化能力从单测提升到 fixture 回归层。
