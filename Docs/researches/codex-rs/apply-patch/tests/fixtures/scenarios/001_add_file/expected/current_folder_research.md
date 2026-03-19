# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属模块：`codex-rs/apply-patch`（crate: `codex-apply-patch`）

## 场景与职责

该目录是场景测试 `001_add_file` 的“最终状态断言源”，当前仅包含一个文件：

- `codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file/expected/bar.md:1`

在 `apply_patch` 场景体系中，`expected/` 负责定义补丁执行后的目标文件系统快照，不直接参与执行，只作为断言标准被读取和比对。该职责来自场景规范：每个场景由 `input/`（可选）、`patch.txt`、`expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。

对本目录而言，其语义非常明确：

1. 表示执行 `*** Add File: bar.md` 后，工作目录中应出现 `bar.md`。
2. 表示该文件内容必须是 `This is a new file\n`（文件展示为一行文本，末尾换行由补丁解析/写入流程产生）。
3. 为端到端测试提供最小成功路径（空初始目录 -> 新增单文件）。

## 功能点目的

围绕本目录的功能目标可拆为三层：

1. 协议层验证：验证 `Add File` 语义可落地为真实文件。
   - 场景补丁：`codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file/patch.txt:1-4`
2. 引擎层验证：验证解析与执行产物在文件系统层面一致。
   - 解析产生 `Hunk::AddFile`（`codex-rs/apply-patch/src/parser.rs:248-270`）
   - 执行写入磁盘（`codex-rs/apply-patch/src/lib.rs:289-300`）
3. 测试层验证：验证最终目录快照完全相等（而非仅检查返回码）。
   - 快照比较逻辑（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-58`）

因此，`expected/` 不是“示例文件夹”，而是该场景中唯一真值（source of truth）之一：补丁执行是否正确，最终由此目录裁定。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 测试入口遍历所有 scenario 目录：
   - `test_apply_patch_scenarios`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）
2. 对 `001_add_file` 执行 `run_apply_patch_scenario`：
   - 读取 `patch.txt`（`.../scenarios.rs:39-40`）
   - 在临时目录执行二进制 `apply_patch`（`.../scenarios.rs:45-48`）
   - 读取 `expected/` 与实际目录，构造快照并 `assert_eq!`（`.../scenarios.rs:51-58`）
3. 快照为 `BTreeMap<PathBuf, Entry>`，`Entry::File(Vec<u8>)` 按字节比较（`.../scenarios.rs:65-77`），避免文本编码差异导致误判。

### 2) 关键数据结构

1. `parser::Hunk`：补丁操作抽象，`AddFile { path, contents }` 表达新增文件（`codex-rs/apply-patch/src/parser.rs:58-76`）。
2. `AffectedPaths`：执行后按 `added/modified/deleted` 分类（`codex-rs/apply-patch/src/lib.rs:271-275`）。
3. `Entry`（测试侧）：目录快照节点，区分文件内容和目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-69`）。

### 3) 协议与格式

1. 补丁包裹标记：`*** Begin Patch` / `*** End Patch`（`parser.rs:31-32`）。
2. 新增文件标记：`*** Add File: <path>`（`parser.rs:33`, `apply_patch_tool_instructions.md:14-16`）。
3. 新增内容行：每行必须 `+` 前缀（`apply_patch_tool_instructions.md:45-46,67-69`）。
4. 本场景协议实例：
   - `*** Add File: bar.md`
   - `+This is a new file`
   （`codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file/patch.txt:2-3`）

### 4) 命令路径

1. 场景测试内部调用：`apply_patch <完整补丁文本>`（`scenarios.rs:45-47`）。
2. CLI 入口处理参数/stdin 后调用库函数 `apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
3. 库函数解析补丁并执行 hunk（`codex-rs/apply-patch/src/lib.rs:183-213,279-339`）。

## 关键代码路径与文件引用

### A. 目标目录与直接上下文

1. `codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file/expected/bar.md:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/001_add_file/patch.txt:1-4`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`

### B. 调用方（谁使用 `expected/`）

1. 场景总入口：`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`
2. 单场景执行：`codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`
3. 快照构建与递归遍历：`codex-rs/apply-patch/tests/suite/scenarios.rs:71-126`

### C. 被调用方（场景执行会走到哪里）

1. `apply_patch` 二进制入口：`codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. 解析入口：`codex-rs/apply-patch/src/parser.rs:106-183`
3. Add hunk 解析：`codex-rs/apply-patch/src/parser.rs:248-270`
4. Add file 落盘：`codex-rs/apply-patch/src/lib.rs:289-300`
5. 成功摘要输出：`codex-rs/apply-patch/src/lib.rs:537-551`

### D. 生产链路关联（同语义上游）

1. 工具处理器重解析并校验补丁：`codex-rs/core/src/tools/handlers/apply_patch.rs:170-178`
2. 运行时将补丁封装为 `codex --codex-run-as-apply-patch <patch>`：`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-94`
3. `arg0` 分发 `--codex-run-as-apply-patch` 到 `codex_apply_patch::apply_patch`：`codex-rs/arg0/src/lib.rs:89-107`

### E. 配置/构建/脚本/文档依赖

1. crate 与 bin 定义：`codex-rs/apply-patch/Cargo.toml:1-30`
2. Bazel compile_data（工具说明文档打包）：`codex-rs/apply-patch/BUILD.bazel:3-10`
3. 工具协议文档：`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`
4. checklist 条目：`Docs/researches/blueprint_checklist.md:75`
5. todo 生成脚本：`.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

### 1) 测试依赖

1. `codex-utils-cargo-bin`：定位 `repo_root()` 与 `cargo_bin("apply_patch")`（`scenarios.rs:1,12,45`）。
2. `tempfile`：创建隔离临时目录（`scenarios.rs:8,31`）。
3. `pretty_assertions`：快照不一致时输出可读 diff（`scenarios.rs:2,55-58`）。

### 2) 文件系统交互

1. 读取 `patch.txt` 与 `expected/`。
2. 在临时目录创建/写入 `bar.md`。
3. 通过 `fs::metadata()` 跟随 symlink 兼容 Buck2 `__srcs`（`scenarios.rs:92-95,113-114`）。

### 3) 进程与协议交互

1. 测试进程拉起外部二进制 `apply_patch`（`scenarios.rs:45-48`）。
2. 生产态中可由 core/runtime/arg0 链路间接调用同一执行逻辑（见上节 D）。
3. 协议交互严格依赖补丁语法约束（Begin/End、Add File、`+` 内容行）。

## 风险、边界与改进建议

### 风险与边界

1. 场景比较只关心“最终文件树”，不直接断言退出码与 stderr/stdout（`scenarios.rs:42-48`）。
2. 本目录只覆盖单文件正向路径，未覆盖：
   - 空文件新增
   - 深层目录新增
   - 与已有文件冲突（该语义由 `011_add_overwrites_existing_file` 覆盖）
3. `AddFile` 当前语义是覆盖写（`std::fs::write`），这在安全敏感流程中可能需更显式策略（`lib.rs:297-299`）。
4. 场景遍历未排序（`scenarios.rs:18`），失败时报告顺序可能随文件系统返回而变化。

### 改进建议

1. 为场景框架增加可选行为断言字段（例如 `expected_exit`, `expected_stdout`），与最终态断言互补。
2. 为 `001_add_file` 同类能力新增更细粒度场景：
   - `Add File` 到多级目录，验证父目录自动创建；
   - `Add File` 空内容，验证空文件语义；
   - `Add File` 非 ASCII 内容，验证编码一致性。
3. 在 `test_apply_patch_scenarios` 中按目录名排序执行，提升失败复现稳定性。
4. 在 `scenarios/README.md` 明确“001 为基线最小成功路径”，避免把该场景误解为完整 Add 语义覆盖。
