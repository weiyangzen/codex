# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 关联场景：`020_delete_file_success`

## 场景与职责

该目录是 `apply-patch` 场景测试 `020_delete_file_success` 的输入态目录，负责定义补丁执行前的真实文件系统起点。当前包含两个文件：

1. `keep.txt`：非目标文件，必须保持不变（`codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/input/keep.txt:1`）。
2. `obsolete.txt`：删除目标文件，对应补丁中的 `*** Delete File: obsolete.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/input/obsolete.txt:1`，`codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/patch.txt:2`）。

在测试职责上，本目录并不直接参与解析或执行，而是被场景 runner 复制到临时目录后，作为 `apply_patch` 可执行程序的工作目录初始状态（`codex-rs/apply-patch/tests/suite/scenarios.rs:30`、`codex-rs/apply-patch/tests/suite/scenarios.rs:36`、`codex-rs/apply-patch/tests/suite/scenarios.rs:45`）。

## 功能点目的

该目录要验证的核心目的是“删除语义的正向可用性 + 非目标文件不受影响”：

1. 删除命中：`obsolete.txt` 在输入中存在，保证 `Delete File` 语义走成功分支，而不是“缺失文件”错误分支。
2. 变更隔离：`keep.txt` 作为旁路文件，证明删除操作是点状影响，不会误改同目录其他文件。
3. 最终态可比：配合 `expected/keep.txt`，可以通过目录快照做字节级比对，验证执行后只少一个文件（`codex-rs/apply-patch/tests/suite/scenarios.rs:52`、`codex-rs/apply-patch/tests/suite/scenarios.rs:53`）。

该目标与其他删除用例形成互补：

1. 缺失文件失败：`007_rejects_missing_file_delete`（`codex-rs/apply-patch/tests/suite/tool.rs:114`）。
2. 删除目录失败：`012_delete_directory_fails`（`codex-rs/apply-patch/tests/suite/tool.rs:196`）。
3. 本目录对应场景：普通文件删除成功（正向基线）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程（从 input 到断言）

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios` 下全部目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11`）。
2. 对 `020_delete_file_success` 调用 `run_apply_patch_scenario()`，把 `input/` 递归复制到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:30`、`codex-rs/apply-patch/tests/suite/scenarios.rs:36`、`codex-rs/apply-patch/tests/suite/scenarios.rs:107`）。
3. 读取 `patch.txt` 后执行 `cargo_bin("apply_patch")` 子进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:45`）。
4. `apply_patch` 在库层解析为 `Hunk::DeleteFile`（`codex-rs/apply-patch/src/parser.rs:271`），执行器调用 `std::fs::remove_file(path)`（`codex-rs/apply-patch/src/lib.rs:301`、`codex-rs/apply-patch/src/lib.rs:302`）。
5. 执行后对比 `expected/` 与临时目录快照，断言目录树与文件字节完全一致（`codex-rs/apply-patch/tests/suite/scenarios.rs:52`、`codex-rs/apply-patch/tests/suite/scenarios.rs:53`、`codex-rs/apply-patch/tests/suite/scenarios.rs:71`）。

### 2) 关键数据结构

1. `Hunk::DeleteFile { path }`：解析阶段删除语义实体（`codex-rs/apply-patch/src/parser.rs:65`）。
2. `AffectedPaths { deleted, .. }`：应用阶段累计变更结果，成功输出 `D <path>`（`codex-rs/apply-patch/src/lib.rs:271`、`codex-rs/apply-patch/src/lib.rs:537`）。
3. `Entry::File(Vec<u8>) | Entry::Dir`：场景快照对比结构（`codex-rs/apply-patch/tests/suite/scenarios.rs:65`）。

### 3) 协议与命令

1. 场景协议：`input/ + patch.txt + expected/` 三段式（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`）。
2. patch 语法：`DeleteFile := "*** Delete File: " path NEWLINE`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:46`）。
3. 行尾约束：fixtures 使用 `.gitattributes` 固定 LF，减少跨平台快照噪声（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`）。
4. 常用回归命令：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
   - `cargo test -p codex-apply-patch --test all test_apply_patch_cli_rejects_missing_file_delete`

### 4) 与上游工具链的连接

虽然本目录属于 `codex-apply-patch` 测试夹具，但 `apply_patch` 在真实会话中还会经 `core` 路径调用：

1. handler 先执行 `maybe_parse_apply_patch_verified()` 得到结构化变更（`codex-rs/core/src/tools/handlers/apply_patch.rs:174`，`codex-rs/apply-patch/src/invocation.rs:132`）。
2. runtime 构造 `codex --codex-run-as-apply-patch <patch>` 执行命令（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69`、`codex-rs/core/src/tools/runtimes/apply_patch.rs:91`）。
3. `arg0` 根据 `CODEX_CORE_APPLY_PATCH_ARG1` 分发到 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:90`）。

## 关键代码路径与文件引用

### 研究对象（input 目录）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/input/keep.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/input/obsolete.txt:1`

### 同场景核心文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/patch.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/expected/keep.txt:1`

### 直接调用方（场景框架）

1. `codex-rs/apply-patch/tests/all.rs:1`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:30`
5. `codex-rs/apply-patch/tests/suite/scenarios.rs:45`

### 被调用方（解析与执行）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11`
2. `codex-rs/apply-patch/src/lib.rs:183`
3. `codex-rs/apply-patch/src/lib.rs:279`
4. `codex-rs/apply-patch/src/lib.rs:301`
5. `codex-rs/apply-patch/src/parser.rs:248`
6. `codex-rs/apply-patch/src/parser.rs:271`

### 配置、文档、脚本与集成路径

1. `codex-rs/apply-patch/Cargo.toml:2`
2. `codex-rs/apply-patch/BUILD.bazel:5`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`
4. `codex-rs/apply-patch/apply_patch_tool_instructions.md:15`
5. `codex-rs/core/src/config/mod.rs:531`
6. `codex-rs/core/src/tools/spec.rs:2784`
7. `.ops/generate_daily_research_todo.sh:5`
8. `Docs/researches/blueprint_checklist.md:144`

## 依赖与外部交互

### 1) 依赖（crate 与测试）

`codex-apply-patch` 关键依赖（`codex-rs/apply-patch/Cargo.toml:18`）：

1. `anyhow` / `thiserror`：错误传播与上下文。
2. `similar`：update diff 生成（同执行器路径共享依赖）。
3. `tree-sitter` / `tree-sitter-bash`：shell/heredoc apply_patch 识别。
4. `assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`：集成测试运行、临时目录与断言。

### 2) 外部交互（文件系统/进程/标准流）

1. 文件系统：复制输入目录、删除目标文件、读取 expected/actual 做快照比对。
2. 进程：测试通过子进程运行 `apply_patch` 可执行文件，不是直接函数调用。
3. 标准流：成功时输出摘要，失败时输出错误；但场景测试默认不对 stdout/stderr 逐字断言。

### 3) 与 core 的行为差异

1. 直接运行 `apply_patch` 时，删除失败主要在 `remove_file` 阶段报错（`codex-rs/apply-patch/src/lib.rs:302`）。
2. 在 core handler 链路中，`maybe_parse_apply_patch_verified` 会提前读取目标文件内容，缺失文件会在“预检阶段”失败（`codex-rs/apply-patch/src/invocation.rs:170`、`codex-rs/apply-patch/src/invocation.rs:176`）。

## 风险、边界与改进建议

### 风险

1. 场景 runner 只比较最终文件树，不校验退出码与 stderr，过程异常信息可能被忽略。
2. `020_delete_file_success/input` 仅覆盖平铺路径删除，不覆盖子目录或路径规范化变体。
3. 场景编号存在两个 `020_*` 目录，按 `read_dir` 顺序遍历时对“编号有序性”不可依赖。

### 边界

1. 不覆盖权限问题、目录误删、缺失文件等失败语义（由其他场景承担）。
2. 不覆盖 core 审批/沙箱策略，仅覆盖 `codex-apply-patch` 场景夹具执行链。
3. 输入文件内容极简（单词文本），未覆盖编码、二进制、超长行等边界。

### 改进建议

1. 为 `scenarios` 增加可选 `exit_code` / `stderr_contains` 断言元数据，提升失败可观测性。
2. 新增 `delete_nested_file_success` 与 `delete_multiple_files_success` 输入目录，扩展删除正向覆盖。
3. 在 `scenarios/README.md` 增加“删除类场景矩阵”，明确成功/失败用例与职责分工。
4. 统一场景编号（避免重复 `020`），降低维护者对执行顺序与定位的歧义。
