# DIR `codex-rs/apply-patch/tests` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`codex-rs/apply-patch/tests` 是 `codex-apply-patch` 的集成测试层，职责不是验证单个函数细节，而是从“CLI 入口 + 文件系统结果”角度验证补丁语义是否稳定。

该目录承担三层验证职责：

1. CLI 基线行为验证：覆盖参数输入与 stdin 输入两条主链路，确保 `apply_patch` 最基本可用（`tests/suite/cli.rs:12`、`tests/suite/cli.rs:53`）。
2. 语义与错误行为验证：对 add/update/delete/move、覆盖、缺失上下文、空 patch、部分成功等行为做细粒度断言（`tests/suite/tool.rs:20-243`）。
3. 规格场景回放验证：通过 fixture 目录批量执行端到端场景，只比对“最终文件树状态”，形成可跨语言迁移的规范样例（`tests/suite/scenarios.rs:11`，`tests/fixtures/scenarios/README.md:2`）。

测试入口通过 `tests/all.rs` 聚合模块（`tests/all.rs:3`），并在 Windows 上跳过 `tool.rs`（`tests/suite/mod.rs:3`）。

## 功能点目的

1. `all.rs` / `suite/mod.rs`
- 目的：组织单一 integration test binary，避免测试散落。
- 特点：`tool` 模块使用 `#[cfg(not(target_os = "windows"))]`，说明当前有平台差异考虑。

2. `suite/cli.rs`
- 目的：验证 CLI 输入渠道（argv 与 stdin）一致性。
- 关键断言：
  - 成功时 stdout 必须为固定格式 `Success. Updated the following files:` + `A/M` 行。
  - 文件内容必须与 patch 结果一致。

3. `suite/tool.rs`
- 目的：覆盖补丁引擎主要行为与负向分支。
- 覆盖面：
  - 正向：多操作、多 chunk、move 到新目录。
  - 失败：空 patch、缺失上下文、删除不存在文件、空 update hunk、更新不存在文件、非法 hunk header、删除目录失败。
  - 边界语义：`Add` 覆盖已存在文件、`Move` 覆盖目标文件、失败后保留已成功变更（非事务）。

4. `suite/scenarios.rs`
- 目的：用数据驱动 fixture 目录批量回放 patch 语义，减少测试代码重复。
- 关键策略：
  - 每个场景目录包含 `input/`、`patch.txt`、`expected/`。
  - 运行后只比较最终文件树快照（不强制断言退出码/输出）。

5. `fixtures/scenarios/*`
- 目的：沉淀可读、可移植、可增量扩展的补丁规范样例。
- 当前共有 23 个场景目录（含 `020_*` 两个不同目录），覆盖 whitespace 容忍、Unicode、`*** End of File`、删除-only 等细节语义。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键执行流程

1. 测试通过 `codex_utils_cargo_bin::cargo_bin("apply_patch")` 解析可执行文件路径后，使用 `assert_cmd::Command` 启动进程（`tests/suite/cli.rs:5`，`tests/suite/tool.rs:7`）。
2. 在 `tempfile::tempdir()` 隔离目录中构造输入文件、执行 patch、读取实际文件内容做断言。
3. `apply_patch` 可执行链路：
- `apply-patch/src/main.rs:1` -> `codex_apply_patch::main()`
- `apply-patch/src/standalone_executable.rs:11` 解析 argv/stdin
- `apply-patch/src/lib.rs:183` `apply_patch()`
- `apply-patch/src/parser.rs:106` `parse_patch()`
- `apply-patch/src/lib.rs:216` `apply_hunks()` -> `apply_hunks_to_files()`
4. 规格场景链路：`test_apply_patch_scenarios()` 遍历目录并调用 `run_apply_patch_scenario()`（`tests/suite/scenarios.rs:11`、`:30`）。

### 2) 场景测试的数据结构与比较方法

`scenarios.rs` 定义：

- `Entry` 枚举（`File(Vec<u8>) | Dir`），表达目录快照节点（`tests/suite/scenarios.rs:65`）。
- `snapshot_dir()` 与 `snapshot_dir_recursive()` 返回 `BTreeMap<PathBuf, Entry>`，确保比较稳定且可深度比较（`tests/suite/scenarios.rs:71`、`:79`）。
- `copy_dir_recursive()` 复制 fixture `input/` 到临时目录后执行 patch（`tests/suite/scenarios.rs:107`）。

一个重要实现细节是使用 `fs::metadata()`（跟随符号链接）而不是 `symlink_metadata()`，用于兼容 Buck2 中 `__srcs` 可能为 symlink 的情况（`tests/suite/scenarios.rs:92`、`:113` 注释）。

### 3) 命令/协议与断言风格

1. 补丁协议采用 `*** Begin Patch` / `*** End Patch` 包裹，内部 `Add/Delete/Update/Move` 与 `@@` chunk，语义来源见 `tests/fixtures/scenarios/README.md:2` 及 crate 文档 `apply_patch_tool_instructions.md`。
2. `tool.rs` 倾向“命令行为断言”：同时断言退出状态、stdout/stderr 文案、文件内容（例如 `tests/suite/tool.rs:85`、`:98`、`:243`）。
3. `scenarios.rs` 倾向“最终状态断言”：不检查进程输出，仅比较 expected 与 actual 文件树（`tests/suite/scenarios.rs:42-45`）。

### 4) 与上下游调用方/被调用方关系

上游调用方（谁触发这些测试）：

- `cargo test -p codex-apply-patch` 会执行该目录 integration tests。
- 工作区中 `codex-apply-patch` 由 `codex-rs/Cargo.toml:97` 注册并被 `core/arg0/exec` 依赖。

被调用方（测试调用了谁）：

- 直接调用 `apply_patch` 二进制。
- 二进制内部调用 `codex_apply_patch` 库（解析 + 应用）。
- 间接关联 `arg0` 的 `--codex-run-as-apply-patch` 契约（`arg0/src/lib.rs:90`、`:96`），用于主程序复用同一补丁执行逻辑。

## 关键代码路径与文件引用

测试主路径：

1. `codex-rs/apply-patch/tests/all.rs:3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-3`
3. `codex-rs/apply-patch/tests/suite/cli.rs:12-95`
4. `codex-rs/apply-patch/tests/suite/tool.rs:20-260`
5. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-126`
6. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-17`
7. `codex-rs/apply-patch/tests/fixtures/scenarios/*/patch.txt`
8. `codex-rs/apply-patch/tests/fixtures/scenarios/*/{input,expected}/...`

核心实现依赖路径（上下文）：

1. `codex-rs/apply-patch/src/main.rs:1`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11`
3. `codex-rs/apply-patch/src/lib.rs:183`（`apply_patch`）
4. `codex-rs/apply-patch/src/lib.rs:216`（`apply_hunks`）
5. `codex-rs/apply-patch/src/lib.rs:279`（`apply_hunks_to_files`）
6. `codex-rs/apply-patch/src/lib.rs:348`（内容推导）
7. `codex-rs/apply-patch/src/parser.rs:106`（语法解析）
8. `codex-rs/apply-patch/src/invocation.rs:132`（verified 解析，供 core/handler）
9. `codex-rs/core/src/tools/handlers/apply_patch.rs:174`（core 侧验证入口）
10. `codex-rs/core/src/tools/runtimes/apply_patch.rs:91`（通过 `--codex-run-as-apply-patch` 执行）

构建/配置路径：

1. `codex-rs/apply-patch/Cargo.toml:25-30`（dev-dependencies）
2. `codex-rs/apply-patch/Cargo.toml:11-12`（bin `apply_patch`）
3. `codex-rs/apply-patch/BUILD.bazel:5-10`（crate 与 `compile_data`）

## 依赖与外部交互

### 1) 依赖

测试相关依赖来自 `codex-rs/apply-patch/Cargo.toml`：

1. `assert_cmd`：进程调用与 stdout/stderr/exit code 断言。
2. `tempfile`：临时目录隔离。
3. `codex-utils-cargo-bin`：在 Cargo/Bazel 运行时定位 workspace 二进制。
4. `pretty_assertions`：更可读的差异输出。

### 2) 外部交互

1. 进程交互：每个测试实际启动 `apply_patch` 可执行文件。
2. 文件系统交互：创建、读取、修改、删除临时目录中的文件与目录。
3. 平台交互：
- `tool.rs` 在 Windows 默认不运行（减少平台差异噪音，但带来覆盖盲区）。
- `scenarios.rs` 通过 `metadata()` 兼容 Buck2 symlink 行为。

### 3) 文档与脚本上下文

1. 文档：`tests/fixtures/scenarios/README.md` 给出 fixture 结构规范。
2. 协议文档：`apply_patch_tool_instructions.md` 定义 patch 语言，对场景样例语义有约束作用。
3. 当前目录本身不包含独立测试脚本，执行入口由 Cargo test 驱动。

## 风险、边界与改进建议

### 风险与边界

1. `scenarios.rs` 不断言退出码与 stderr/stdout，只看最终文件树；若未来错误文案或退出码回归但文件恰好未变，可能漏检。
2. `test_apply_patch_scenarios` 依赖 `read_dir` 顺序（未排序）；虽然每个场景独立，但失败定位与日志稳定性可进一步优化。
3. `tool.rs` 被 `cfg(not(target_os = "windows"))` 屏蔽，导致一部分行为在 Windows 上缺乏同层断言。
4. fixture 编号存在 `020_delete_file_success` 与 `020_whitespace_padded_patch_marker_lines` 双编号，容易影响维护者阅读与增量命名。
5. 场景覆盖主要关注最终状态，尚未系统覆盖“权限拒绝/只读文件/路径越界”等与上层安全策略协同的行为。

### 改进建议

1. 给 `scenarios.rs` 增加可选模式：在需要时同时断言退出码（success/failure）与关键 stderr 片段。
2. 在遍历场景时先按目录名排序，提升执行稳定性与 CI 日志可读性。
3. 为 Windows 增加可运行的 `tool` 子集（或在 `scenarios.rs` 中补充等效错误语义断言），缩小平台覆盖差距。
4. 统一/重编场景编号（例如将第二个 `020_*` 调整为 `023_*`），并在 README 补充命名约定。
5. 为 fixtures 增加“语义标签表”（如 parse 容错、IO 错误、覆盖语义、EOF 处理），便于快速定位回归影响面。
