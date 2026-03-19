# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属模块：`codex-rs/apply-patch`（crate: `codex-apply-patch`）

## 场景与职责

该目录是 `007_rejects_missing_file_delete` 场景的期望终态（expected oracle），用于验证 `Delete File` 操作在目标不存在时的失败行为不会污染工作目录。

目录结构极小，仅包含：

1. `foo.txt`，内容为 `stable`（LF 结尾）。

该目录的职责不是表达“删除成功”，而是表达“删除失败后保持不变”：

1. 场景回放框架会把 `input/` 复制到临时目录执行补丁，再与本目录逐字节对比。
2. 若 `missing.txt` 删除失败但 `foo.txt` 被误改、误删，测试会立刻失败。
3. 它与 `tool.rs` 的 stderr 文案断言共同构成“状态 + 诊断”双重回归保护。

## 功能点目的

本目录服务的功能点是 `*** Delete File: <path>` 的失败语义边界，具体目标：

1. 缺失目标（`missing.txt`）必须报错，不能静默成功。
2. 非目标文件（`foo.txt`）必须保持原样，确保失败无副作用。
3. 在 fixture 体系中将“失败语义”转为稳定、可移植的文件系统终态断言。

与相邻负向场景的分工：

1. `006_rejects_missing_context`：更新时找不到旧行。
2. `007_rejects_missing_file_delete`：删除时目标文件不存在。
3. `012_delete_directory_fails`：删除目标是目录而非普通文件。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景回放流程

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*` 并逐个执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 将 `input/` 拷贝到 `tempdir`，读取 `patch.txt` 并执行 `apply_patch <patch>`（`scenarios.rs:30-48`）。
3. 该测试故意不校验退出码，仅对比执行后目录快照与 `expected/`（`scenarios.rs:42-45,50-60`）。
4. 快照结构是 `BTreeMap<PathBuf, Entry>`，`Entry = File(Vec<u8>) | Dir`，因此 `foo.txt` 采用字节级比较（`scenarios.rs:65-105`）。

### 2) 删除缺失文件的实现链路

1. 解析层：`parse_patch()` 将 `*** Delete File: missing.txt` 解析成 `Hunk::DeleteFile { path }`（`codex-rs/apply-patch/src/parser.rs:106-113,248-278`）。
2. 执行层：`apply_patch()` -> `apply_hunks()` -> `apply_hunks_to_files()`（`codex-rs/apply-patch/src/lib.rs:183-213,216-339`）。
3. 删除动作：`Hunk::DeleteFile` 分支调用 `std::fs::remove_file(path)`（`lib.rs:301-304`）。
4. 路径不存在会触发 I/O 错误，被包装为 `Failed to delete file missing.txt` 并写入 stderr（`lib.rs:253-256,302-303`）。
5. 本场景补丁只有一个 delete hunk，失败后没有后续写入步骤，因此临时目录应与本 `expected/` 完全一致。

### 3) 协议与命令

1. 语法协议（Lark）在 `tool_apply_patch.lark`：`delete_hunk: "*** Delete File: " filename LF`（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-8`）。
2. 工具说明文档同样定义了 Delete File 语义（`codex-rs/apply-patch/apply_patch_tool_instructions.md:14-16,41-47`）。
3. 场景命令等价于：

```bash
apply_patch "*** Begin Patch
*** Delete File: missing.txt
*** End Patch"
```

### 4) 与上游 verified 路径的关系

1. 在 `codex-core` 中，`apply_patch` 会先走 `maybe_parse_apply_patch_verified()`（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`）。
2. verified 阶段对 delete 会先读原文件内容，缺失时提前报 `Failed to read ...`（`codex-rs/apply-patch/src/invocation.rs:170-183`）。
3. 因此两条链路的诊断文案不同：
   - 裸 `apply_patch` CLI：`Failed to delete file ...`（执行期）。
   - core verified：`Failed to read ...`（预检期）。
4. 本目录属于 `apply-patch` crate fixture，主要锚定“文件系统终态不变”，而非上游文案一致性。

## 关键代码路径与文件引用

### 目标目录与直接上下文

1. `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/expected/foo.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/input/foo.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/patch.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes`

### 调用方（消费 expected 的测试）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:50`
4. `codex-rs/apply-patch/tests/suite/tool.rs:114`
5. `codex-rs/apply-patch/tests/all.rs:1`

### 被调用方（解析/执行）

1. `codex-rs/apply-patch/src/main.rs:1`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11`
3. `codex-rs/apply-patch/src/lib.rs:183`
4. `codex-rs/apply-patch/src/lib.rs:216`
5. `codex-rs/apply-patch/src/lib.rs:279`
6. `codex-rs/apply-patch/src/lib.rs:301`
7. `codex-rs/apply-patch/src/parser.rs:248`
8. `codex-rs/apply-patch/src/invocation.rs:132`

### 配置、脚本与跨模块链路

1. `codex-rs/apply-patch/Cargo.toml`
2. `codex-rs/apply-patch/BUILD.bazel:3-10`
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-244`
4. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`
5. `codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-19`
6. `codex-rs/core/tests/suite/apply_patch_cli.rs:474-503`
7. `.ops/generate_daily_research_todo.sh:4-41`
8. `Docs/researches/blueprint_checklist.md:97`

## 依赖与外部交互

### 依赖

1. 运行依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`Cargo.toml:25-30`）。
3. 构建配置：Bazel 通过 `compile_data` 暴露 `apply_patch_tool_instructions.md`（`codex-rs/apply-patch/BUILD.bazel:8-10`）。

### 外部交互

1. 文件系统交互：测试框架复制 `input/`、读取 `patch.txt`、执行后快照目录（`tests/suite/scenarios.rs`）。
2. 进程交互：通过 `cargo_bin("apply_patch")` 启动子进程执行补丁（`scenarios.rs:45-48`，`tool.rs:7-17`）。
3. 标准流交互：失败信息写入 stderr，`tool.rs` 对文案做精确断言（`tool.rs:117-122`）。
4. 上游工具链交互：`codex-core` 通过 verified + runtime 自调用 `--codex-run-as-apply-patch` 执行（`core/src/tools/handlers/apply_patch.rs`，`core/src/tools/runtimes/apply_patch.rs`，`codex-rs/exec/tests/suite/apply_patch.rs:20-40`）。

## 风险、边界与改进建议

### 风险

1. `scenarios.rs` 不校验退出码和 stderr，若只回归了错误文案但终态未变，fixture 场景无法发现。
2. 裸 CLI 与 core verified 对同一 missing delete 返回不同错误上下文（`delete` vs `read`），调用方处理成本上升。
3. 本 expected 目录只覆盖单文件、不覆盖权限错误、并发删除（TOCTOU）等系统级失败。

### 边界

1. 该目录只表达“负向终态不变”，不表达错误消息、退出码、审批流程。
2. 只适用于 `apply-patch` fixture 回放框架，不直接覆盖 `core` 的审批/沙箱策略。

### 改进建议

1. 为 `tests/suite/scenarios.rs` 增加可选元数据断言（如 `expected_exit_code`、`stderr_contains`），让负向用例同时验证状态与诊断。
2. 在 `tests/fixtures/scenarios/README.md` 补充“负向场景需配套 tool/core 文案断言”的约定，减少误用 expected-only 的风险。
3. 增加 delete 失败细分场景（权限拒绝、符号链接、只读挂载），补齐非 `ENOENT` 覆盖。
4. 统一或文档化 CLI 与 core verified 的错误语义差异，降低上游处理复杂度。
