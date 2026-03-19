# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属模块：`codex-rs/apply-patch`（crate：`codex-apply-patch`）

## 场景与职责

该目录是场景 `002_multiple_operations` 的“期望最终文件系统快照（source of truth）”，用于断言一次 patch 同时执行 `Add + Delete + Update` 后的结果是否正确。

目录内当前实体：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/modify.txt:1-2`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/nested/new.txt:1`

职责边界：

1. 不参与 patch 执行，只提供断言基线。
2. 通过“存在文件 + 文件字节内容 + 目录结构”三者共同定义成功状态。
3. 间接表达删除语义：`delete.txt` 不在 `expected/` 中，配合“全量快照相等”意味着删除必须生效。

场景规范来自 `scenarios` README：每个案例由 `input/ + patch.txt + expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`）。

## 功能点目的

围绕该 `expected/` 子目录，核心目的不是演示文本，而是固化复合操作契约：

1. 新增文件契约：`nested/new.txt` 必须被创建且内容为 `created\n`，证明 Add hunk 与父目录自动创建能力有效。
2. 修改文件契约：`modify.txt` 必须从 `line1\nline2\n` 变为 `line1\nchanged\n`，证明 Update hunk 正确替换目标行。
3. 删除文件契约：`input/delete.txt` 在结果中必须缺失，证明 Delete hunk 生效。
4. 目录结构契约：`nested/` 目录必须出现，证明执行器在写新文件前正确 `create_dir_all`。

这个目录与 `tool.rs` 的命令行断言测试形成互补：`tool.rs` 额外验证 stdout 的 `A/M/D` 输出，而 `expected/` 侧重最终状态全量一致性（`codex-rs/apply-patch/tests/suite/tool.rs:20-41`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 测试入口扫描场景目录并逐个执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario` 将 `input/` 复制到临时目录，读取 `patch.txt`，执行 `apply_patch` 二进制（`.../scenarios.rs:33-48`）。
3. 读取 `expected/` 与临时目录，分别构建快照并 `assert_eq!`（`.../scenarios.rs:50-58`）。
4. 快照算法递归采集目录节点与文件字节内容，比较类型为 `BTreeMap<PathBuf, Entry>`（`.../scenarios.rs:65-105`）。

### 2) 关键数据结构

1. 协议层：`Hunk::AddFile / DeleteFile / UpdateFile`（`codex-rs/apply-patch/src/parser.rs:58-76`）。
2. Update 粒度：`UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`（`parser.rs:90-104`）。
3. 执行结果：`AffectedPaths { added, modified, deleted }`，用于成功摘要输出（`codex-rs/apply-patch/src/lib.rs:271-275,537-551`）。
4. 场景断言结构：`Entry::File(Vec<u8>) | Entry::Dir`，确保文本与二进制都能精确比较（`scenarios.rs:65-69`）。

### 3) 协议与命令

`002_multiple_operations/patch.txt` 定义了三段连续操作（`codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/patch.txt:1-9`）：

1. `*** Add File: nested/new.txt`
2. `*** Delete File: delete.txt`
3. `*** Update File: modify.txt` + `@@` hunk

执行入口支持两类命令输入：

1. `apply_patch '<PATCH>'`（argv 传入）
2. `echo '<PATCH>' | apply_patch`（stdin 传入）

对应实现为 `standalone_executable::run_main`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。

### 4) 关键实现细节（与本目录断言直接相关）

1. Add hunk 解析连续 `+` 行并追加换行（`parser.rs:251-270`）。
2. Add 执行前自动创建父目录：`create_dir_all(parent)`（`lib.rs:290-296`），这正是 `expected/nested/new.txt` 能成立的前提。
3. Delete 执行调用 `remove_file`（`lib.rs:301-305`），最终通过 `expected` 快照缺失项体现。
4. Update 先通过 `compute_replacements` 定位旧行，再 `apply_replacements` 倒序替换（`lib.rs:386-474,478-501`）。
5. 更新后统一补末尾换行（`lib.rs:373-376`），保证 `expected/modify.txt` 的文本结尾稳定。

## 关键代码路径与文件引用

### A. 目标目录与同场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/modify.txt:1-2`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/nested/new.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/modify.txt:1-2`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/delete.txt:1`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/patch.txt:1-9`

### B. 调用方（消费 `expected/` 的逻辑）

1. `codex-rs/apply-patch/tests/all.rs:1-3`（集成测试聚合入口）。
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`（启用 `scenarios` 套件）。
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`（读 `expected/` 并比对）。
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:71-126`（目录快照递归与复制）。

### C. 被调用方（场景执行会进入的实现）

1. `codex-rs/apply-patch/src/main.rs:1-3`（CLI 入口）。
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`（参数/stdin 处理与退出码协议）。
3. `codex-rs/apply-patch/src/parser.rs:154-183,248-340`（patch 解析与 hunk 分类）。
4. `codex-rs/apply-patch/src/lib.rs:183-213,279-339`（apply 与文件落盘）。
5. `codex-rs/apply-patch/src/lib.rs:535-551`（`A/M/D` 摘要输出）。

### D. 配置、测试、脚本、文档上下文

1. 配置：`codex-rs/apply-patch/Cargo.toml:1-30`（crate/bin 与依赖）。
2. 配置：`codex-rs/apply-patch/BUILD.bazel:1-10`（Bazel 目标与 compile_data）。
3. 文档：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`（场景目录约定）。
4. 文档：`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`（patch 协议说明）。
5. 规范文件：`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`（强制 LF）。
6. 测试：`codex-rs/apply-patch/tests/suite/tool.rs:20-41`（同语义 CLI 校验）。
7. 脚本：`.ops/generate_daily_research_todo.sh:1-42`（从 checklist 生成每日研究 TODO）。

### E. 生产链路关联（同语义上游）

1. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-179`（handler 先 verified parse 再执行）。
2. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`（构造 `codex --codex-run-as-apply-patch <patch>`）。
3. `codex-rs/arg0/src/lib.rs:85-107`（arg0 分发到 `codex_apply_patch::main/apply_patch`）。

## 依赖与外部交互

1. 文件系统交互：读取 fixture、复制输入目录、执行新增/删除/修改并回读快照（`scenarios.rs:33-53`, `lib.rs:289-329`）。
2. 进程交互：场景测试通过 `cargo_bin("apply_patch")` 启动真实二进制（`scenarios.rs:45-48`）。
3. 测试依赖：`tempfile`（隔离目录）、`pretty_assertions`（可读 diff）、`codex-utils-cargo-bin`（定位 repo 与二进制）。
4. 平台兼容：快照与复制使用 `fs::metadata()` 跟随 symlink，兼容 Buck2 `__srcs`（`scenarios.rs:92-95,113-114`）。
5. 协议交互：patch 语言要求显式 Begin/End 与 Add/Delete/Update header；路径要求相对路径（`apply_patch_tool_instructions.md:41-50,69`）。

## 风险、边界与改进建议

### 风险与边界

1. 场景框架默认不校验退出码与 stderr/stdout，只看最终文件树（`scenarios.rs:42-48`）；若输出协议回归但文件结果正确，场景测试可能无感。
2. `expected/` 仅覆盖成功路径状态，不表达失败中断时“部分已落盘”行为；该行为由独立测试覆盖（`tool.rs:243-256`）。
3. 当前目录只含文本小文件，未覆盖二进制内容、权限位、时间戳等元数据差异。
4. 场景遍历未排序（`scenarios.rs:18`），批量失败日志顺序可随文件系统枚举变化。

### 改进建议

1. 给场景机制增加可选元数据（如 `meta.toml`），支持 `expected_exit_code` / `expected_stdout_contains`，与 `expected/` 快照形成双重断言。
2. 在 `002_multiple_operations` 旁新增“复合操作部分失败”镜像场景，明确非原子语义边界。
3. 在 `scenarios.rs` 中按目录名排序执行，提升跨平台复现稳定性。
4. 为 `expected/` 相关场景补充二进制样例（例如 `.bin` 文件），验证 `Entry::File(Vec<u8>)` 在非文本输入下的稳健性。
