# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是场景 `007_rejects_missing_file_delete` 的输入快照目录，承担“删除失败前的工作区初始态”职责。

目录内容极小，仅有：

1. `foo.txt`，内容为 `stable`（`codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/input/foo.txt:1`）。

同级补丁为：

1. `*** Delete File: missing.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/patch.txt:1-3`）。

这意味着该 `input/` 的设计意图不是触发变更成功，而是故意构造“目标文件缺失”的负向执行环境：

1. 不提供 `missing.txt`，迫使 delete 操作报错。
2. 保留一个无关文件 `foo.txt`，用于校验失败后无副作用。
3. 与 `expected/foo.txt` 保持等值，形成状态回归锚点（`.../expected/foo.txt:1`）。

## 功能点目的

该目录服务于 `Delete File` 语义中的安全目标：删除失败时不得污染现有文件。

1. 失败可见性：缺失目标必须失败，不能“幂等成功”。
2. 状态稳定性：非目标文件应保持原样（本场景用 `foo.txt` 表达）。
3. 回归可移植性：通过 `input/ + patch.txt + expected/` 三件套抽象场景，可复用到其他实现（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。
4. 与邻近场景形成矩阵：
   - `006_rejects_missing_context` 校验 update 找不到上下文；
   - `007_rejects_missing_file_delete` 校验 delete 目标不存在；
   - `012_delete_directory_fails` 校验 delete 目标是目录时失败。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. `test_apply_patch_scenarios()` 遍历所有场景目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 将本目录 `input/` 复制到临时目录（`scenarios.rs:33-37,107-123`）。
3. 读取同级 `patch.txt`，执行 `apply_patch <patch>`（`scenarios.rs:39-48`）。
4. 场景测试故意不检查退出码，只比较最终文件树快照（`scenarios.rs:42-45,50-60`）。
5. 快照结构是 `BTreeMap<PathBuf, Entry>`，`Entry = File(Vec<u8>) | Dir`，因此 `foo.txt` 会做字节级一致性比较（`scenarios.rs:65-102`）。

### 2) 删除失败链路（为何本目录内容不变）

1. parser 将 `*** Delete File: missing.txt` 解析为 `Hunk::DeleteFile { path }`（`codex-rs/apply-patch/src/parser.rs:10-13,60-67,248-278`）。
2. `apply_patch()` -> `apply_hunks()` -> `apply_hunks_to_files()`（`codex-rs/apply-patch/src/lib.rs:183-213,216-266,279-339`）。
3. `Hunk::DeleteFile` 分支执行 `std::fs::remove_file(path)`（`lib.rs:301-304`）。
4. 因路径不存在，错误被包装为 `Failed to delete file missing.txt` 并写入 stderr（`lib.rs:253-256,302-303`），CLI 用例对该文案有精确断言（`codex-rs/apply-patch/tests/suite/tool.rs:114-123`）。
5. 本场景补丁只有一个 hunk，失败后不会有后续写入，故 `foo.txt` 保持 `stable`。

### 3) 数据结构/协议/命令

1. 协议语义：`DeleteFile` 是一类独立 file-op（`codex-rs/apply-patch/apply_patch_tool_instructions.md:14-16,44-47`）。
2. 数据结构：
   - 解析后 hunk：`Hunk::DeleteFile { path: PathBuf }`（`parser.rs:65-67`）。
   - 应用结果：`AffectedPaths { added, modified, deleted }`（`lib.rs:270-275`）。
3. 命令形态（与该场景等价）：

```bash
apply_patch "*** Begin Patch
*** Delete File: missing.txt
*** End Patch"
```

4. CLI 入口处理 argv/stdin 的统一入口为 `run_main()`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。

## 关键代码路径与文件引用

### 目标对象与同场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/input/foo.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/patch.txt:1-3`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/expected/foo.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`

### 调用方（谁消费该 input 目录）

1. `codex-rs/apply-patch/tests/all.rs:1-3`（集成测试入口）。
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`（模块聚合）。
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-37`（复制 `input/`）。
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`（与 `expected/` 对比）。
5. `codex-rs/apply-patch/tests/suite/tool.rs:114-123`（同语义 CLI 错误文案回归）。

### 被调用方（执行期实际进入）

1. `codex-rs/apply-patch/src/main.rs:1-2`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/parser.rs:248-278`
4. `codex-rs/apply-patch/src/lib.rs:279-339`
5. `codex-rs/apply-patch/src/lib.rs:301-304`

### 配置、测试、脚本、文档上下文依赖

1. 配置/构建：
   - `codex-rs/apply-patch/Cargo.toml:1-30`
   - `codex-rs/apply-patch/BUILD.bazel:1-11`
2. 上游工具配置：
   - `codex-rs/core/src/tools/spec.rs:257-263,321-379,2784-2804`
3. 上游调用链：
   - `codex-rs/core/src/tools/handlers/apply_patch.rs:170-177,241-244`
   - `codex-rs/core/src/tools/runtimes/apply_patch.rs:1-6,69-99`
4. 上游测试：
   - `codex-rs/core/tests/suite/apply_patch_cli.rs:474-503`
5. 研究任务脚本：
   - `.ops/generate_daily_research_todo.sh:4-41`
6. 研究清单：
   - `Docs/researches/blueprint_checklist.md:98`

## 依赖与外部交互

### 依赖

1. 运行依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`Cargo.toml:25-30`）。

### 外部交互

1. 文件系统交互：
   - fixture runner 复制 `input/` 到临时目录；
   - apply_patch 在临时目录执行 `remove_file`；
   - snapshot 读取文件字节做全量对比。
2. 子进程交互：通过 `Command::new(cargo_bin("apply_patch"))` 启动 CLI（`scenarios.rs:45-48`，`tool.rs:7-14`）。
3. 标准流交互：失败诊断写入 stderr（`lib.rs:253-256`）。
4. 跨 crate 交互：`codex-core` 会先调用 `maybe_parse_apply_patch_verified()`，对 delete 路径先读文件，缺失时在预检阶段报 `Failed to read ...`（`codex-rs/apply-patch/src/invocation.rs:132-183`）。

## 风险、边界与改进建议

### 风险

1. `scenarios.rs` 不断言退出码/stderr，只验证终态；若错误文案回归但文件状态没变，fixture 层可能漏检（`scenarios.rs:42-45`）。
2. 同一“删除缺失文件”在不同入口报错不同：
   - 裸 CLI：`Failed to delete file ...`（执行期）；
   - core 预检：`Failed to read ...`（验证期）。
3. 本目录覆盖面单一，仅验证 `ENOENT`，未覆盖权限拒绝、竞态删除等系统错误。

### 边界

1. 本目录仅表达“失败后的文件系统不变性”，不表达错误码/错误消息（这些由 `tool.rs` 和 core 测试补齐）。
2. 该用例为单 hunk，无法覆盖多 hunk 的部分成功副作用行为。

### 改进建议

1. 给场景框架增加可选元数据（如 `expected_exit_code`、`stderr_contains`），让负向 fixture 同时验证状态与诊断。
2. 为 delete 失败补充更多 fixture：权限拒绝、目录符号链接、只读文件系统。
3. 在场景遍历中增加稳定排序，提升 CI 失败定位一致性（当前直接 `read_dir` 遍历，`scenarios.rs:18-23`）。
4. 在文档中明确“core 预检错误”和“裸 CLI 执行错误”的语义差异，降低调用方误判风险。
