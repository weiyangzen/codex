# DIR `codex-rs/apply-patch/tests/suite` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/suite`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`（package：`codex-apply-patch`，bin：`apply_patch`）

## 场景与职责

`codex-rs/apply-patch/tests/suite` 是 `codex-apply-patch` 的集成测试核心目录，重点验证“补丁工具作为可执行程序时”的行为一致性，而不是仅验证库内部函数细节。

该目录职责可分为三层：

1. CLI 输入链路验证：覆盖 argv 传参与 stdin 两种入口，确保 `apply_patch` 主入口行为一致（`codex-rs/apply-patch/tests/suite/cli.rs:12`, `53`）。
2. 行为语义与错误分支验证：对 add/update/delete/move、多 chunk、覆盖写入、解析错误、IO 错误等行为进行精确断言（`codex-rs/apply-patch/tests/suite/tool.rs:20-257`）。
3. 场景回放验证：基于 fixture 目录批量执行端到端 patch，并以“最终文件树快照”做一致性校验（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`）。

测试装配关系：

- `tests/all.rs` 将 `suite` 作为单个 integration test binary 的总入口（`codex-rs/apply-patch/tests/all.rs:1-3`）。
- `tests/suite/mod.rs` 在 Windows 上禁用 `tool` 模块，保留 `cli/scenarios`（`codex-rs/apply-patch/tests/suite/mod.rs:1-4`）。

## 功能点目的

### 1) `cli.rs`：CLI 基线路径可用性

目标是保证 `apply_patch` 作为命令行工具的最小可用闭环：

1. `test_apply_patch_cli_add_and_update`：通过 argv 传入 patch 完成新增与更新，断言 stdout 精确文本及最终文件内容（`codex-rs/apply-patch/tests/suite/cli.rs:12-50`）。
2. `test_apply_patch_cli_stdin_add_and_update`：通过 stdin 输入同等 patch，验证与 argv 分支一致（`codex-rs/apply-patch/tests/suite/cli.rs:53-91`）。

### 2) `tool.rs`：高密度行为与错误语义覆盖

该文件是 suite 中最核心的语义回归集合，目的包括：

1. 正向组合能力：多操作、多更新块、移动文件、目标目录自动创建（`tool.rs:20-82`）。
2. 错误语义稳定：空 patch、上下文缺失、删除不存在、更新不存在、非法 hunk header 等错误消息需稳定输出（`tool.rs:85-220`）。
3. 边界约束：`Move`/`Add` 覆盖已有目标、删除目录失败、更新后补尾部换行（`tool.rs:154-240`）。
4. 非事务语义验证：前序成功改动不会因后续失败回滚（`tool.rs:243-257`）。

### 3) `scenarios.rs`：数据驱动规范回放

目标是把 patch 语义沉淀为可迁移样例：

1. 遍历 `tests/fixtures/scenarios` 目录中的每个场景（`scenarios.rs:11-24`）。
2. 每个场景采用 `input/ + patch.txt + expected/` 结构（文档：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`）。
3. 运行后只比较最终文件树快照，避免测试代码对实现细节强耦合（`scenarios.rs:42-60`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程：从测试到补丁落盘

1. 测试通过 `codex_utils_cargo_bin::cargo_bin("apply_patch")` 解析二进制路径（`cli.rs:6`, `tool.rs:8`, `scenarios.rs:45`）。
2. `assert_cmd::Command` 在 `tempfile::tempdir()` 下执行子进程并断言结果（`cli.rs:24-30`, `tool.rs:30-33`）。
3. 被测程序执行链路：
- `codex-rs/apply-patch/src/main.rs:1-3`
- `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
- `codex-rs/apply-patch/src/lib.rs:183-266`
- `codex-rs/apply-patch/src/lib.rs:279-339`
- `codex-rs/apply-patch/src/parser.rs:106-183`

4. suite 断言与实现输出的契约点：
- 成功摘要必须符合 `print_summary` 格式（`codex-rs/apply-patch/src/lib.rs:537-552`），因此 `cli.rs/tool.rs` 对 stdout 进行完整字符串匹配。
- 错误消息来自 parse/apply 阶段，`tool.rs` 通过 stderr 全量匹配固定回归面。

### 2) `scenarios.rs` 的数据结构与快照算法

`scenarios.rs` 使用以下结构完成“最终态比较”：

1. `Entry` 枚举：`File(Vec<u8>) | Dir`（`scenarios.rs:65-69`）。
2. `snapshot_dir()`：返回 `BTreeMap<PathBuf, Entry>`，保证 key 有序，便于稳定 diff（`scenarios.rs:71-77`）。
3. `snapshot_dir_recursive()`：
- 使用 `fs::metadata()`（跟随 symlink），兼容 Buck2 `__srcs` 符号链接（`scenarios.rs:92-99`）。
- 文件节点读取原始字节，避免编码假设（`scenarios.rs:100-101`）。

4. `copy_dir_recursive()`：把 `input/` 复制到临时目录，保持目录结构（`scenarios.rs:107-125`）。

### 3) 协议与命令

suite 直接使用 apply-patch 协议文本（`*** Begin Patch` / `*** End Patch`，`Add/Delete/Update/Move`，`@@`，可选 `*** End of File`）：

- 协议文档：`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`
- 解析实现：`codex-rs/apply-patch/src/parser.rs:31-39`, `248-434`
- freeform grammar 镜像：`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-19`

### 4) 调用方与被调用方上下文依赖

调用方（谁依赖 suite 测试结果）：

1. `cargo test -p codex-apply-patch` 触发 `tests/all.rs`，执行 `suite/*` 模块。
2. CI/Bazel 运行时仍依赖同一测试逻辑；`codex-utils-cargo-bin` 负责解决 Cargo/Bazel 下二进制定位差异（`codex-rs/utils/cargo-bin/src/lib.rs:33-69`）。

被调用方（suite 实际触发的生产代码）：

1. `codex-apply-patch` CLI 与库（`src/main.rs`, `src/standalone_executable.rs`, `src/lib.rs`, `src/parser.rs`, `src/seek_sequence.rs`）。
2. 上游集成链路的契约验证间接受 suite 保护：
- core handler 在执行前走 `maybe_parse_apply_patch_verified`（`codex-rs/core/src/tools/handlers/apply_patch.rs:174`, `272`）。
- shell handler 对 `apply_patch` 命令做拦截（`codex-rs/core/src/tools/handlers/shell.rs:397-411`）。
- runtime 使用 `--codex-run-as-apply-patch` 自调用（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-94`）。
- arg0 对该参数与别名进行分发（`codex-rs/arg0/src/lib.rs:85-107`）。

## 关键代码路径与文件引用

### A. 目标目录（直接研究对象）

1. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
2. `codex-rs/apply-patch/tests/suite/cli.rs:1-91`
3. `codex-rs/apply-patch/tests/suite/tool.rs:1-257`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:1-126`

### B. 测试入口与配置

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/Cargo.toml:25-30`（`assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`）
3. `codex-rs/apply-patch/Cargo.toml:11-14`（`apply_patch` bin）
4. `codex-rs/apply-patch/BUILD.bazel:5-10`（crate 与 compile_data）

### C. 被测核心实现

1. `codex-rs/apply-patch/src/main.rs:1-3`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/lib.rs:183-266`（入口 + 错误输出）
4. `codex-rs/apply-patch/src/lib.rs:279-339`（落盘）
5. `codex-rs/apply-patch/src/lib.rs:386-474`（replacement 计算）
6. `codex-rs/apply-patch/src/parser.rs:106-183`, `248-434`
7. `codex-rs/apply-patch/src/seek_sequence.rs:12-110`

### D. 文档与脚本上下文

1. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`
4. `Docs/researches/blueprint_checklist.md:154`（当前研究对象任务条目）
5. `.ops/generate_daily_research_todo.sh:1-42`（由 checklist 生成每日 todo）

## 依赖与外部交互

### 1) 测试依赖

1. `assert_cmd`：进程级断言（退出码、stdout、stderr）。
2. `tempfile`：隔离测试目录，防污染。
3. `codex-utils-cargo-bin`：统一 Cargo/Bazel 下 `apply_patch` 路径解析（`codex-rs/utils/cargo-bin/src/lib.rs:39`, `168`）。
4. `pretty_assertions`：目录快照或字符串不一致时提供可读 diff。

### 2) 外部交互面

1. 子进程执行：每个测试都会拉起 `apply_patch` 可执行文件。
2. 文件系统读写：创建/删除/移动文件与目录，读取 byte 内容比对。
3. 运行时环境差异：
- `tool` 模块 Windows 下不启用（`mod.rs:3`）。
- runfiles 环境由 `codex-utils-cargo-bin` 处理（`codex-rs/utils/cargo-bin/README.md:3-16`）。

### 3) 配置/测试/脚本/文档联动

1. 配置：`Cargo.toml` 决定 suite 的 dev-dependencies 与测试可执行入口。
2. 测试数据：`fixtures/scenarios/*` 提供输入与期望态。
3. 脚本：`.ops/generate_daily_research_todo.sh` 读取 `blueprint_checklist.md` 生成当日研究待办。
4. 文档：`apply_patch_tool_instructions.md` 与 `tool_apply_patch.lark` 共同定义 patch 协议，suite 测试样例对齐该契约。

## 风险、边界与改进建议

### 风险与边界

1. `scenarios.rs` 不断言退出码/stdout/stderr，只比较最终文件树（`scenarios.rs:42-48`），会漏掉“输出文案回归但文件状态不变”的问题。
2. 场景遍历使用 `fs::read_dir` 原始顺序（`scenarios.rs:18`），执行顺序在不同平台/文件系统上可能不稳定。
3. `tool.rs` 在 Windows 不执行（`mod.rs:3`），错误语义覆盖存在平台盲区。
4. `tool.rs` 对 stderr/stdout 做完整字符串匹配，回归发现能力强，但对文案改动极其敏感，维护成本较高。
5. 当前 suite 主要覆盖 `apply_patch` 单工具语义，不覆盖 core 审批/策略（越界、权限提升）全链路，这些由上层测试承担。

### 改进建议

1. 为 `scenarios` 增加可选元数据（如 `expect_exit`、`expect_stderr_contains`），在保持最终态对比简洁性的同时补足命令通道断言。
2. 对场景目录名做排序后执行，提升可复现性与 CI 日志可读性。
3. 在 Windows 补充一组可执行的 `tool` 子集，或将关键错误语义转入跨平台场景测试。
4. 将 `tool.rs` 中重复的 patch 构造与断言片段抽成局部 helper，减少样板并降低新增场景成本。
5. 在 `tests/fixtures/scenarios/README.md` 增补“哪些语义由 suite 覆盖、哪些由 core 层覆盖”的边界说明，帮助维护者选择正确测试层。
