# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`002_multiple_operations` 是 `apply_patch` 场景集中第一个“复合操作”样例：单个 patch 同时包含 `Add`、`Delete`、`Update` 三类 hunk，并要求一次执行后文件树达到目标状态。

目录内容与职责分工如下：

1. `input/` 定义执行前状态：
   - `input/delete.txt` 含待删除内容（`codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/delete.txt:1`）。
   - `input/modify.txt` 含待更新内容（`codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/modify.txt:1-2`）。
2. `patch.txt` 定义一次性复合变更：新增 `nested/new.txt`、删除 `delete.txt`、修改 `modify.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/patch.txt:1-9`）。
3. `expected/` 定义执行后快照：
   - `expected/modify.txt` 期望 `line2 -> changed`（`.../expected/modify.txt:1-2`）。
   - `expected/nested/new.txt` 期望新增文件内容为 `created`（`.../expected/nested/new.txt:1`）。

该场景在整个 fixture 系统中的职责不是“覆盖复杂 parser 语法边界”，而是验证一个核心行为契约：

1. 多操作顺序执行时，新增/删除/修改可在一次 patch 中并存。
2. 结果判断以最终文件树为准，而非只看进程输出。
3. 该契约与 `tests/suite/tool.rs` 的命令行断言版（含 stdout 校验）保持一致语义（`codex-rs/apply-patch/tests/suite/tool.rs:20-41`）。

## 功能点目的

### 1) 本目录直接验证的功能目的

1. `Add File`：验证执行器能为 `nested/new.txt` 自动创建父目录并写入内容（`patch.txt:2-3`，实现位于 `codex-rs/apply-patch/src/lib.rs:289-300`）。
2. `Delete File`：验证 `delete.txt` 被移除（`patch.txt:4`，实现位于 `lib.rs:301-305`）。
3. `Update File`：验证 `modify.txt` 的行替换生效（`patch.txt:5-8`，实现位于 `lib.rs:306-331` 与 `lib.rs:386-474`）。
4. `Scenario Harness`：验证场景机制会将临时目录最终快照与 `expected/` 做字节级对比（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-58,71-105`）。

### 2) 在测试金字塔中的定位

1. `fixtures/scenarios/002_*`：端到端“状态一致性”验证，关注最终文件树（`scenarios.rs:42-58`）。
2. `tests/suite/tool.rs::test_apply_patch_cli_applies_multiple_operations`：同语义的 CLI 行为验证，额外校验 stdout 为 `A/M/D` 顺序（`tool.rs:20-33`）。
3. `src/lib.rs` 单元层：分拆验证 Add/Delete/Update 细节与错误路径（`codex-rs/apply-patch/src/lib.rs:568-611,613-783`）。

三层一起把“复合 patch”从协议、CLI、内部函数三条路径压实。

### 3) 设计动机

场景 README 明确每个场景采用 `input/ + patch.txt + expected/` 三段式，目标是可迁移到其它语言/平台（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:2,5-17`）。`002_multiple_operations` 正是该可迁移规范中的最小复合事务样例。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程（调用链）

1. 测试入口聚合：`tests/all.rs` 加载 `tests/suite/mod.rs`，其中启用 `scenarios` 模块（`codex-rs/apply-patch/tests/all.rs:1-3`, `codex-rs/apply-patch/tests/suite/mod.rs:1-3`）。
2. 场景遍历：`test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`，目录即测试用例（`scenarios.rs:11-24`）。
3. 场景执行：`run_apply_patch_scenario()`
   - 把 `input/` 复制到临时目录（`scenarios.rs:33-37,107-125`）。
   - 读取 `patch.txt`（`scenarios.rs:39-40`）。
   - 在临时目录执行 `apply_patch <patch>`（`scenarios.rs:45-48`）。
4. 结果断言：`snapshot_dir()` 构造 `BTreeMap<PathBuf, Entry>`，对比 `expected/` 与实际目录（`scenarios.rs:50-58,65-77`）。

### 2) 关键数据结构

1. `parser::Hunk` 三类变更：`AddFile/DeleteFile/UpdateFile`（`codex-rs/apply-patch/src/parser.rs:58-76`）。
2. `UpdateFileChunk`：承载 `change_context`、`old_lines`、`new_lines`、`is_end_of_file`（`parser.rs:90-104`）。
3. 执行统计：`AffectedPaths { added, modified, deleted }` 作为 stdout 汇总来源（`codex-rs/apply-patch/src/lib.rs:271-275,537-551`）。
4. 场景快照：`Entry::File(Vec<u8>) | Entry::Dir`，实现对目录和文件内容的精确比较（`scenarios.rs:65-69`）。

### 3) 协议解析与执行细节

1. 协议边界：必须以 `*** Begin Patch` 开始，以 `*** End Patch` 结束（`parser.rs:31-33,185-243`；示例 `patch.txt:1,9`）。
2. 多 hunk 顺序：`parse_patch_text()` 顺序解析并保留 hunk 列表顺序（`parser.rs:166-176`）。
3. Add hunk：读取连续 `+` 行拼接成新文件内容（自动补 `\n`）（`parser.rs:251-270`）。
4. Delete hunk：仅记录目标路径（`parser.rs:271-278`），执行阶段 `remove_file`（`lib.rs:301-305`）。
5. Update hunk：
   - `@@` 开始 chunk（`parser.rs:343-371`）。
   - `compute_replacements()` 定位旧行并构建替换计划（`lib.rs:386-474`）。
   - `apply_replacements()` 倒序应用替换避免索引漂移（`lib.rs:478-501`）。
6. 新增目录处理：Add/Move 场景都会 `create_dir_all(parent)`（`lib.rs:290-296,314-320`）。

### 4) 运行命令与进程协议

1. 独立 CLI：`apply_patch` bin 入口在 `src/main.rs -> standalone_executable::main`（`codex-rs/apply-patch/src/main.rs:1-3`, `standalone_executable.rs:4-11`）。
2. 输入协议：支持 `argv[1]` 或 stdin 读取 patch 文本（`standalone_executable.rs:16-41`）。
3. 执行器入口：`apply_patch()` 先 parse，再 `apply_hunks()`（`lib.rs:183-213`）。
4. 成功输出：`Success. Updated the following files:` + `A/M/D` 行（`lib.rs:541-550`；`tool.rs:30-33` 给出多操作期望输出）。

### 5) 与生产链路（core）连接点

虽然当前目录是 crate 内 fixture，但语义复用到核心工具链：

1. `core` handler 通过 `maybe_parse_apply_patch_verified` 预解析并校验（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-176`）。
2. 通过 runtime 构造 `codex --codex-run-as-apply-patch <patch>` 执行命令（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-95`）。
3. `arg0` 收到该 flag 后调用 `codex_apply_patch::apply_patch` 真正落盘（`codex-rs/arg0/src/lib.rs:89-107`）。

## 关键代码路径与文件引用

### A. 目标目录本体

1. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/patch.txt:1-9`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/delete.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/modify.txt:1-2`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/modify.txt:1-2`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/nested/new.txt:1`

### B. 直接调用方（消费本目录）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`（扫描场景目录）。
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`（单场景执行与断言）。
3. `codex-rs/apply-patch/tests/all.rs:1-3`（integration test 聚合入口）。

### C. 同语义行为测试（并行验证）

1. `codex-rs/apply-patch/tests/suite/tool.rs:20-41`（复合操作 CLI 测试，含 stdout 断言）。
2. `codex-rs/apply-patch/tests/suite/cli.rs:11-90`（argv/stdin 两条路径基础行为）。

### D. 被调用实现（解析/执行）

1. `codex-rs/apply-patch/src/parser.rs:106-183`（parse 主流程）。
2. `codex-rs/apply-patch/src/parser.rs:248-340`（hunk 头解析）。
3. `codex-rs/apply-patch/src/lib.rs:183-266`（apply_patch + 错误输出协议）。
4. `codex-rs/apply-patch/src/lib.rs:279-339`（按 hunk 执行文件变更）。
5. `codex-rs/apply-patch/src/lib.rs:386-501`（Update replacement 计算与应用）。

### E. 配置/文档/脚本上下文

1. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`（场景规范）。
2. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`（统一 LF）。
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`（协议文档与语法）。
4. `codex-rs/apply-patch/Cargo.toml:1-30`（crate/bin、依赖、测试依赖）。
5. `codex-rs/apply-patch/BUILD.bazel:1-10`（Bazel compile_data，打包说明文档）。
6. `.ops/generate_daily_research_todo.sh:1-42`（从 checklist 生成当日 todo）。
7. `Docs/researches/blueprint_checklist.md:76`（本目录研究勾选项）。

## 依赖与外部交互

### 1) 代码依赖

1. `anyhow/thiserror`：错误聚合和上下文（`lib.rs:10-19`）。
2. `similar`：生成 unified diff（用于 verified action 计算）（`lib.rs:17,511-533`）。
3. `tree-sitter + tree-sitter-bash`：解析 shell heredoc 形式的 apply_patch 调用（`invocation.rs:240-368`；依赖定义在 `Cargo.toml:22-23`）。
4. `tempfile/assert_cmd/pretty_assertions/codex-utils-cargo-bin`：测试执行、二进制定位、断言 diff（`Cargo.toml:25-30`，`scenarios.rs:1-8`，`tool.rs:1-5`）。

### 2) 外部交互面

1. 文件系统：读 `patch.txt`、复制 `input/`、写/删/改文件、扫描 `expected/`（`scenarios.rs:33-53`，`lib.rs:289-329`）。
2. 进程调用：测试通过 `cargo_bin("apply_patch")` 启动真实可执行文件（`scenarios.rs:45-48`, `tool.rs:8-16`）。
3. 平台兼容：`snapshot_dir_recursive/copy_dir_recursive` 使用 `fs::metadata()` 跟随 symlink，兼容 Buck2 的 `__srcs` 布局（`scenarios.rs:92-95,113-114`）。

### 3) 协议/约束

1. patch 语言要求文件路径为相对路径（文档约束，`apply_patch_tool_instructions.md:69`）。
2. parser 在当前实现中默认 lenient 模式，允许 patch marker 周围空白（`parser.rs:23-24,47,154-163`），这与场景 `018/020` 的宽松输入测试呼应。
3. 场景断言故意不校验进程退出码，只比较最终文件树（`scenarios.rs:42-45`）。

## 风险、边界与改进建议

### 风险与边界

1. 非原子执行风险：`apply_hunks_to_files` 按顺序即时落盘，若后续 hunk 失败，前序成功修改会保留（`lib.rs:287-333`）；`015_failure_after_partial_success_leaves_changes` 已证明该行为是当前设计（`tool.rs:243-256`）。
2. 场景 harness 忽略 stdout/stderr 和 exit status（`scenarios.rs:42-48`），可能漏检“输出协议退化但最终态正确”的问题。
3. 未排序遍历目录（`scenarios.rs:18`），失败复现日志顺序可能受文件系统枚举顺序影响。
4. `Delete File` 对目录路径直接失败（`tool.rs:196-205`），当前场景未覆盖“误删目录”的邻接风险，需要依赖其它用例兜底。

### 改进建议

1. 给 `scenarios` 框架增加可选元数据（例如 `meta.toml`）：允许声明 `expect_exit_code`、`expect_stdout_contains`，在保持“最终态断言”优势的同时覆盖行为协议。
2. 为 `002_multiple_operations` 增加“失败中断型复合场景”变体（例如 Add 成功后 Update 失败），将“非原子特性”显式固化在本类复合场景旁，降低误读成本。
3. 在 `tests/suite/scenarios.rs` 中对目录名排序后再执行，保证跨平台顺序稳定。
4. 在 `scenarios/README.md` 补充“复合操作场景（如 002）验证顺序执行语义”的说明，帮助新维护者快速理解编号含义与覆盖边界。
