# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 关联场景：`020_delete_file_success`

## 场景与职责

该目录是场景 `020_delete_file_success` 的 expected 最终态目录，当前仅包含一个文件：

- `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/expected/keep.txt:1`

它在场景中的职责不是“执行删除”，而是作为断言真值（oracle）定义 patch 成功后的文件系统状态：

1. `obsolete.txt` 必须已被删除（通过 expected 中缺失该文件来表达）。
2. `keep.txt` 必须原样保留（通过 expected 中保留该文件与内容来表达）。

该职责由场景 runner 消费：`run_apply_patch_scenario()` 会比较“实际临时目录快照”与“expected 快照”，不一致即失败（`codex-rs/apply-patch/tests/suite/scenarios.rs:51`、`codex-rs/apply-patch/tests/suite/scenarios.rs:55`）。

## 功能点目的

该目录保护的功能点是 **Delete File 成功路径的最终态正确性**，具体包括：

1. 删除目标：`patch.txt` 指定 `*** Delete File: obsolete.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/patch.txt:2`）。
2. 非目标保持：输入中的 `keep.txt` 在输出中仍存在且内容不变（`input/keep.txt:1` 与 `expected/keep.txt:1`）。
3. 最终态而非过程态：场景测试重点是目录树/字节内容匹配，不直接断言 exit code/stderr（`codex-rs/apply-patch/tests/suite/scenarios.rs:42`）。

与相邻场景的分工：

1. `007_rejects_missing_file_delete` 覆盖“删除不存在文件失败”（`codex-rs/apply-patch/tests/suite/tool.rs:114`）。
2. `012_delete_directory_fails` 覆盖“Delete File 指向目录失败”（`codex-rs/apply-patch/tests/suite/tool.rs:196`）。
3. `020_delete_file_success/expected` 覆盖“普通文件删除成功后的最终态”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 场景发现：`test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*` 并逐目录执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11`）。
2. 输入准备：`input/` 被复制到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:34`、`codex-rs/apply-patch/tests/suite/scenarios.rs:36`）。
3. 执行补丁：读取 `patch.txt` 后启动 `apply_patch` 二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:40`、`codex-rs/apply-patch/tests/suite/scenarios.rs:45`）。
4. 解析 delete：parser 将 `*** Delete File:` 解析为 `Hunk::DeleteFile`（`codex-rs/apply-patch/src/parser.rs:271`）。
5. 应用 delete：执行器在 `Hunk::DeleteFile` 分支调用 `std::fs::remove_file(path)`（`codex-rs/apply-patch/src/lib.rs:301`、`codex-rs/apply-patch/src/lib.rs:302`）。
6. 最终断言：`snapshot_dir(expected)` 与 `snapshot_dir(actual)` 做深比较；`expected` 即本目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:52`、`codex-rs/apply-patch/tests/suite/scenarios.rs:53`、`codex-rs/apply-patch/tests/suite/scenarios.rs:56`）。

### 2) 关键数据结构

1. `Hunk::DeleteFile { path }`：delete 操作语义载体（`codex-rs/apply-patch/src/parser.rs:65`）。
2. `AffectedPaths { deleted, ... }`：执行结果聚合，成功时会输出 `D <path>` 摘要（`codex-rs/apply-patch/src/lib.rs:271`、`codex-rs/apply-patch/src/lib.rs:549`）。
3. `Entry::File(Vec<u8>) | Entry::Dir`：场景快照比较结构，确保 expected 目录断言是字节级（`codex-rs/apply-patch/tests/suite/scenarios.rs:65`、`codex-rs/apply-patch/tests/suite/scenarios.rs:67`）。

### 3) 协议与约束

1. 场景协议：每个 case 由 `input/ + patch.txt + expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:6`）。
2. patch 语法：`DeleteFile := "*** Delete File: " path NEWLINE`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:46`）。
3. 目录快照对比按文件字节内容进行，不依赖 stdout 文案（`codex-rs/apply-patch/tests/suite/scenarios.rs:100`、`codex-rs/apply-patch/tests/suite/scenarios.rs:101`）。
4. 行尾统一：fixtures 的 `.gitattributes` 固定 `eol=lf`，降低跨平台噪声（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`）。

### 4) 关键命令

1. 场景回归：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. delete 失败分支回归：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_rejects_missing_file_delete`
3. core 预检分支回归：`cargo test -p codex-core --test suite apply_patch_cli_delete_directory_reports_verification_error`

## 关键代码路径与文件引用

### 研究对象与场景资产

1. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/expected/keep.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/input/keep.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/input/obsolete.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/patch.txt:1`

### 直接调用方（消费 expected）

1. `codex-rs/apply-patch/tests/all.rs:1`
2. `codex-rs/apply-patch/tests/suite/mod.rs:2`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:30`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:51`
5. `codex-rs/apply-patch/tests/suite/scenarios.rs:71`

### 被调用方（生成 actual）

1. `codex-rs/apply-patch/src/main.rs:2`
2. `codex-rs/apply-patch/src/standalone_executable.rs:51`
3. `codex-rs/apply-patch/src/lib.rs:183`
4. `codex-rs/apply-patch/src/lib.rs:279`
5. `codex-rs/apply-patch/src/lib.rs:301`
6. `codex-rs/apply-patch/src/lib.rs:541`
7. `codex-rs/apply-patch/src/parser.rs:248`
8. `codex-rs/apply-patch/src/parser.rs:271`

### 配置、测试、脚本、文档与上游集成

1. `codex-rs/apply-patch/Cargo.toml:2`（crate 定义）
2. `codex-rs/apply-patch/BUILD.bazel:5`（Bazel crate 暴露）
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:15`（Delete File 语义说明）
4. `codex-rs/core/src/config/mod.rs:528`（`include_apply_patch_tool` 配置）
5. `codex-rs/core/src/tools/spec.rs:2784`（tool spec 注册 `apply_patch`）
6. `codex-rs/core/src/tools/handlers/apply_patch.rs:174`（verified 解析入口）
7. `codex-rs/core/src/tools/runtimes/apply_patch.rs:90`（`codex --codex-run-as-apply-patch` 调用）
8. `codex-rs/arg0/src/lib.rs:90`（内部 arg1 分发）
9. `codex-rs/core/tests/suite/apply_patch_cli.rs:536`（目录删除在 core 中的预检失败覆盖）
10. `.ops/generate_daily_research_todo.sh:5`（todo 从 checklist 生成）
11. `Docs/researches/blueprint_checklist.md:143`（本次勾选目标）

## 依赖与外部交互

### 1) 依赖

与该目录关联的执行链依赖（`codex-rs/apply-patch/Cargo.toml:18`）：

1. `anyhow` / `thiserror`：错误上下文与错误类型。
2. `similar`：update 分支 diff 生成（本场景虽不直接使用，但属于同执行链核心依赖）。
3. `tree-sitter` / `tree-sitter-bash`：shell/heredoc 形式 apply_patch 解析。
4. `assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`：集成测试运行与断言。

### 2) 外部交互

1. 文件系统：copy input、执行 `remove_file`、读取 expected/actual 文件字节（`codex-rs/apply-patch/tests/suite/scenarios.rs:107`、`codex-rs/apply-patch/src/lib.rs:302`、`codex-rs/apply-patch/tests/suite/scenarios.rs:100`）。
2. 子进程：场景测试通过 `cargo_bin("apply_patch")` 启动可执行文件（`codex-rs/apply-patch/tests/suite/scenarios.rs:45`）。
3. 标准流：CLI 成功输出摘要到 stdout；错误写 stderr（`codex-rs/apply-patch/src/standalone_executable.rs:49`、`codex-rs/apply-patch/src/lib.rs:255`）。
4. core 运行时交互：通过 runtime 自调用 codex 主进程执行 patch（`codex-rs/core/src/tools/runtimes/apply_patch.rs:88`、`codex-rs/core/src/tools/runtimes/apply_patch.rs:93`）。

## 风险、边界与改进建议

### 风险

1. `scenarios` runner 不断言退出码/stderr，仅看最终态；过程异常但结果巧合一致时可能漏检（`codex-rs/apply-patch/tests/suite/scenarios.rs:42`）。
2. 本 expected 仅覆盖“单文件删除 + 单文件保留”，对多删除/混合 hunk 顺序副作用覆盖不足。
3. 该目录只表达“保留了 keep.txt”，不直接表达“确实尝试删除了 obsolete.txt”，依赖执行链与其他测试共同保障。

### 边界

1. 不覆盖失败语义（缺失文件、目录、权限不足）；这些由 `tool.rs` 与 core suite 负向用例覆盖。
2. 不覆盖路径归一化细节（如 `./obsolete.txt`、嵌套路径、跨平台分隔符）。
3. 不覆盖审批/沙箱策略差异；该目录只处于场景最终态断言层。

### 改进建议

1. 为 `scenarios` 增加可选 `exit_code` 与 `stderr_contains` 断言元数据，补齐过程信号可观测性。
2. 增加删除成功变体场景：`delete_nested_file_success`、`delete_multiple_files_success`。
3. 增加“delete 与 update 混合且后续失败”的场景，显式锁定部分生效策略。
4. 在 `scenarios/README.md` 加入 delete 系列场景映射表（成功/失败/目录/缺失文件），降低维护认知成本。
