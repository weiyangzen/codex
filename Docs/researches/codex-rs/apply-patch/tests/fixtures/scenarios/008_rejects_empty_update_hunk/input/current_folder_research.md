# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是场景 `008_rejects_empty_update_hunk` 的输入快照目录，职责是为“空 Update hunk 被拒绝”提供最小可复现初始文件系统。

当前目录只有一个文件：

1. `foo.txt`，内容 `stable`（`codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/input/foo.txt:1`）。

同级场景补丁是：

1. `*** Begin Patch`
2. `*** Update File: foo.txt`
3. `*** End Patch`

（`codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/patch.txt:1-3`）

这意味着该 `input/` 的核心职责不是驱动成功更新，而是：

1. 提供一个“确实存在的更新目标文件”（避免把失败原因混淆成“文件不存在”）。
2. 在补丁被解析器拒绝后，作为“状态无副作用”对照基线。
3. 与 `expected/foo.txt` 保持字节级一致（均为 `stable\n`），证明失败发生在写盘前（`.../expected/foo.txt:1`）。

## 功能点目的

该目录服务的功能点是“非法 Update 结构的早失败（fail-fast）语义”，具体目标：

1. **语法完整性**：`Update File` 不能只有头；至少应包含一个可解析的变更 chunk。
2. **错误可诊断**：错误必须明确定位为 `Invalid patch hunk on line 2`，并给出 `... is empty` 原因。
3. **副作用隔离**：解析失败时不触发 `apply_hunks`，任何文件内容均不应变化。
4. **覆盖边界区分**：与邻近场景形成负向矩阵：
   - `005_rejects_empty_patch`：补丁中完全没有 hunk；
   - `008_rejects_empty_update_hunk`：有 update 头但无 chunk；
   - `009_requires_existing_file_for_update`：chunk 合法但更新目标文件不存在。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. `tests/suite/scenarios.rs` 的 `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios` 下每个目录并执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 会把当前目录 `input/` 复制到临时目录（`.../scenarios.rs:33-37,107-123`）。
3. 读取同级 `patch.txt` 并启动 `apply_patch` 子进程（`.../scenarios.rs:39-48`）。
4. 场景测试有意不检查退出码，只比较最终目录快照（`.../scenarios.rs:42-45,50-60`）。
5. 因 parse 阶段报错，临时目录保持 `foo.txt=stable`，与 `expected/` 一致。

### 2) 解析与拒绝机制

1. CLI 从 `src/main.rs` 进入 `standalone_executable::run_main()`，将 patch 参数交给 `crate::apply_patch()`（`codex-rs/apply-patch/src/main.rs:1-2`，`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
2. `apply_patch()` 先调用 `parse_patch()`，解析失败时写 stderr：`Invalid patch hunk on line {line_number}: {message}`（`codex-rs/apply-patch/src/lib.rs:183-207`）。
3. `parse_patch_text()` 从第 2 行起循环调用 `parse_one_hunk()` 解析 hunk（`codex-rs/apply-patch/src/parser.rs:154-176`）。
4. 在 `parse_one_hunk()` 的 `Update File` 分支中，若遍历后 `chunks.is_empty()`，立即返回：`Update file hunk for path '{path}' is empty`（`codex-rs/apply-patch/src/parser.rs:279-323`）。
5. 该错误由 `apply_patch()` 包装输出，形成与 CLI 测试一致的报错文案（`codex-rs/apply-patch/tests/suite/tool.rs:127-135`）。

### 3) 数据结构与协议

1. 解析结果结构为 `ApplyPatchArgs { patch, hunks, workdir }`（`codex-rs/apply-patch/src/lib.rs:85-90`）。
2. Hunk 枚举为 `AddFile/DeleteFile/UpdateFile`；其中 `UpdateFile` 必须携带非空 `chunks: Vec<UpdateFileChunk>` 才能进入执行（`codex-rs/apply-patch/src/parser.rs:61-76,294-323`）。
3. core 侧 freeform 语法定义 `update_hunk: ... change_move? change?`（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:8`），但 crate 实现通过 `chunks.is_empty()`进一步收紧，拒绝语义空 update。

### 4) 命令复现

最小复现命令：

```bash
apply_patch "*** Begin Patch
*** Update File: foo.txt
*** End Patch"
```

预期 stderr：

```text
Invalid patch hunk on line 2: Update file hunk for path 'foo.txt' is empty
```

与 `tool.rs` 断言一致（`codex-rs/apply-patch/tests/suite/tool.rs:130-135`）。

## 关键代码路径与文件引用

### 目标对象与同场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/input/foo.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/patch.txt:1-3`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/008_rejects_empty_update_hunk/expected/foo.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`

### 调用方（消费该 input 目录）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-37`（复制 `input/`）
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`（快照断言）
5. `codex-rs/apply-patch/tests/suite/tool.rs:127-135`（同语义 stderr 断言）

### 被调用方（解析/执行链）

1. `codex-rs/apply-patch/src/main.rs:1-2`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/lib.rs:183-213`
4. `codex-rs/apply-patch/src/parser.rs:154-176`
5. `codex-rs/apply-patch/src/parser.rs:279-323`
6. `codex-rs/apply-patch/src/parser.rs:469-480`（解析器单测）

### 配置、测试、脚本、文档上下文

1. crate 配置：`codex-rs/apply-patch/Cargo.toml:1-30`
2. Bazel 暴露与 compile_data：`codex-rs/apply-patch/BUILD.bazel:1-11`
3. 工具协议说明：`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`
4. core 工具处理链：`codex-rs/core/src/tools/handlers/apply_patch.rs:170-245`
5. core runtime 自调用：`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`
6. 研究任务脚本：`.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

### 依赖

1. 运行依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 外部交互

1. **文件系统**：场景框架复制 `input` 到临时目录，并把 `actual` 与 `expected` 做字节级快照比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:71-102,107-123`）。
2. **子进程**：通过 `Command::new(cargo_bin("apply_patch"))` 执行 CLI（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. **标准流**：parse 错误写入 stderr；成功时才会写 summary 到 stdout（`codex-rs/apply-patch/src/lib.rs:191-203,248-251`）。
4. **上游 core 交互**：core handler 会先调用 `maybe_parse_apply_patch_verified()`；若解析失败，转换成 `apply_patch verification failed: ...` 返回模型层（`codex-rs/core/src/tools/handlers/apply_patch.rs:174,241-244`）。

## 风险、边界与改进建议

### 风险

1. `scenarios.rs` 当前不校验 exit code/stderr，只看最终状态；报错文案退化可能漏检（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-45`）。
2. 该 `input/` 只覆盖“update 头为空”路径，未覆盖“仅 `*** Move to` 且无 chunk”的空 update 变体。
3. 场景遍历来自 `read_dir`，未显式排序，失败输出顺序在不同文件系统实现上可能不稳定（`codex-rs/apply-patch/tests/suite/scenarios.rs:18-23`）。

### 边界

1. 本目录验证的是“解析期失败后的状态不变性”，不是错误码契约；错误文本契约由 `tests/suite/tool.rs` 负责。
2. 本目录为单文件、单 hunk 负向场景，不覆盖多 hunk、部分成功后失败等副作用边界（对应 `015_failure_after_partial_success_leaves_changes`）。

### 改进建议

1. 给场景框架补充可选元数据断言（如 `expected_exit_code`、`stderr_contains`），让负向场景同时覆盖状态与诊断。
2. 新增 fixture：`Update File + Move to` 但无 chunk，明确锁定 rename 分支下的空 hunk 拒绝行为。
3. 在 `core` 端到端测试补充该错误分支，验证 `verification failed` 包装文案与 patch 语义一致。
4. 对场景目录名排序执行，提升 CI 失败复现性与排障稳定性。
