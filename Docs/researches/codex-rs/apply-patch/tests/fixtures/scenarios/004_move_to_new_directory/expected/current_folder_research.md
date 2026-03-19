# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属测试体系：`codex-rs/apply-patch/tests/suite/scenarios.rs` 的目录驱动 E2E 场景
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是场景 `004_move_to_new_directory` 的“最终状态真值（oracle）”目录，用于定义在执行一次 `apply_patch` 后，临时工作目录必须达到的文件树与文件内容。

目录内容：

1. `expected/renamed/dir/name.txt`：迁移后的目标文件，内容应为 `new content`。
2. `expected/old/other.txt`：无关文件，内容保持 `unrelated file`，用于证明补丁不会误伤同目录其他文件。

它不承载“如何执行”的逻辑，而承载“执行后应该是什么”的契约；执行逻辑由 `patch.txt` + 测试回放器负责，`expected/` 只负责最终断言基准。

在此场景中，它验证了三件事同时成立：

1. 文件路径已从 `old/name.txt` 移到 `renamed/dir/name.txt`。
2. 目标文件内容已按 hunk 更新（`old content -> new content`）。
3. 与补丁无关的同层文件保持不变（`old/other.txt`）。

## 功能点目的

`expected/` 目录针对 `*** Move to:` 语义提供最小且关键的验收目标，目的包括：

1. **验证“更新+迁移”组合语义**：`Update File` hunk 不是只改内容，也要改变路径。
2. **验证目录自动创建效果**：目标路径位于新目录 `renamed/dir`，期望目录存在且文件写入成功。
3. **验证源路径不应残留目标文件**：由于快照是“全目录精确对比”，`old/name.txt` 若残留会导致失败。
4. **验证副作用边界**：`old/other.txt` 保留，证明 patch 作用范围仅在命中的文件路径上。

该目录与 `010_move_overwrites_existing_destination` 构成互补：

1. `004` 关注“迁移到新目录（目录原本缺失）”。
2. `010` 关注“迁移到已存在目标文件时的覆盖行为”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景执行关键流程

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`，遇到 `004_move_to_new_directory` 即执行。
2. `run_apply_patch_scenario()` 将 `input/` 拷贝到临时目录。
3. 从 `patch.txt` 读取补丁文本并以 `apply_patch <patch>` 形式执行二进制。
4. 执行后对比：
   - 期望：`snapshot_dir(expected/)`
   - 实际：`snapshot_dir(tmp/)`
5. 两边都是 `BTreeMap<PathBuf, Entry>`（`Entry::Dir` 或 `Entry::File(Vec<u8>)`），必须完全一致。

这意味着 `expected/` 目录是此场景最终断言数据源，而不是示例文件。

### 2) 协议层（patch 文本）与 expected 的映射关系

场景 patch（`004_move_to_new_directory/patch.txt`）核心片段：

```patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-old content
+new content
```

解析结果在 `parser.rs` 中会形成：

1. `Hunk::UpdateFile { path: old/name.txt, move_path: Some(renamed/dir/name.txt), chunks: ... }`
2. `chunks` 描述文本替换，最终导出 `new_contents`。

`expected/` 中的 `renamed/dir/name.txt = new content` 就是该结构在文件系统层面的预期投影。

### 3) 执行器语义如何落到 expected

`lib.rs::apply_hunks_to_files()` 中，`UpdateFile + move_path` 的路径：

1. 读取源文件并通过 chunk 计算 `new_contents`。
2. `create_dir_all(dest.parent())` 保证新目录存在。
3. `write(dest, new_contents)` 写目标文件。
4. `remove_file(path)` 删除源文件。
5. 记录 summary 为 `M <dest>`。

因此 `expected/` 必须包含新路径文件与未修改的旁路文件，并且不应出现旧路径 `old/name.txt`。

### 4) 数据结构与断言机制

场景断言依赖如下结构：

1. `Entry::Dir`：目录存在性进入断言。
2. `Entry::File(Vec<u8>)`：文件按字节比较而非“文本近似”。
3. `BTreeMap<PathBuf, Entry>`：确定序比较，避免遍历顺序干扰。

结论：`expected/` 的每个目录节点和文件内容都直接影响测试 pass/fail。

### 5) 相关命令与脚本

1. 单场景所属测试集运行：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 同语义 CLI 测试：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_moves_file_to_new_directory`
3. 研究待办刷新脚本：`bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 目标目录与场景输入

1. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed/dir/name.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/old/other.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/name.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/other.txt`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/patch.txt`

### B. 场景回放与 expected 对比逻辑

1. `codex-rs/apply-patch/tests/suite/scenarios.rs`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`

### C. 解析与执行（被调用实现）

1. `codex-rs/apply-patch/src/parser.rs`（`MOVE_TO_MARKER`、`Hunk::UpdateFile.move_path`）
2. `codex-rs/apply-patch/src/lib.rs`（`apply_hunks_to_files`、`derive_new_contents_from_chunks`、`print_summary`）
3. `codex-rs/apply-patch/src/standalone_executable.rs`（CLI 参数/STDIN入口）
4. `codex-rs/apply-patch/src/invocation.rs`（verified 解析与 `move_path` 绝对路径化）

### D. 直接/旁路测试调用方

1. `codex-rs/apply-patch/tests/suite/tool.rs`（`test_apply_patch_cli_moves_file_to_new_directory`）
2. `codex-rs/apply-patch/tests/suite/cli.rs`
3. `codex-rs/apply-patch/tests/all.rs`
4. `codex-rs/apply-patch/tests/suite/mod.rs`

### E. 配置、构建与跨 crate 入口

1. `codex-rs/apply-patch/Cargo.toml`
2. `codex-rs/apply-patch/BUILD.bazel`
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md`
4. `codex-rs/core/src/tools/handlers/apply_patch.rs`
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs`
6. `codex-rs/arg0/src/lib.rs`

### F. 本任务相关运维文件

1. `Docs/researches/blueprint_checklist.md`
2. `.ops/generate_daily_research_todo.sh`
3. `Docs/researches/todos_20260320.md`

## 依赖与外部交互

### 1) crate 级依赖

`codex-apply-patch` 的关键依赖（影响该场景语义或测试执行）：

1. `anyhow` / `thiserror`：错误传播与上下文。
2. `similar`：生成 unified diff（用于 verified 变更信息）。
3. `tree-sitter` / `tree-sitter-bash`：解析 shell heredoc 形式 `apply_patch` 调用。
4. 测试依赖 `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`。

### 2) 文件系统交互

该场景的核心外部交互面是本地文件系统：

1. 读取源文件 `old/name.txt`。
2. 创建目录 `renamed/dir`（若不存在）。
3. 写入目标文件 `renamed/dir/name.txt`。
4. 删除原文件 `old/name.txt`。
5. 保持其他文件（如 `old/other.txt`）不变。

### 3) 进程交互

1. 测试通过 `Command::new(cargo_bin("apply_patch"))` 启动子进程执行 patch。
2. `core` 集成场景下通过 `--codex-run-as-apply-patch` 进行自调用执行。
3. `arg0` 提供 `apply_patch` 别名与参数分发，统一落到 `codex_apply_patch::apply_patch()`。

### 4) 文档与规范交互

1. `tests/fixtures/scenarios/README.md` 定义了 `input/patch/expected` 三件套场景规范。
2. `apply_patch_tool_instructions.md` 规定了 `*** Move to:` 的协议位置和语法。

## 风险、边界与改进建议

### 风险与边界

1. **最终态对比但不校验退出码**：`scenarios.rs` 当前仅比较目录快照，不直接断言子进程退出码与 stderr；若某些失败路径“恰好”产出匹配文件树，回放可能漏掉行为差异。
2. **非原子更新**：`move` 采用“写新文件 + 删旧文件”，中间步骤失败会出现部分完成状态（仓库中已有 `015_failure_after_partial_success_leaves_changes` 体现这种策略）。
3. **覆盖语义需认知**：目标路径存在文件时会被写入覆盖，`004` 不覆盖该分支，需结合 `010` 理解完整行为。
4. **expected 目录最小化覆盖**：当前只覆盖“新目录迁移成功+无关文件保留”，未覆盖权限、只读目录、路径冲突、并发写入等异常边界。

### 改进建议

1. 在场景 fixture 增加可选元数据（如 `expect_exit_code`、`expect_stderr_substr`），让目录驱动测试同时覆盖行为与最终态。
2. 增加 `move_to_non_writable_directory_fails` 场景，明确权限错误下的文件树预期。
3. 在 `apply_patch_tool_instructions.md` 追加“Move to 覆盖目标文件”的显式说明，降低调用侧误解。
4. 为 `004` 增加 sibling 场景：同为新目录迁移，但包含多 chunk 更新，验证“复杂编辑 + 迁移 + 目录创建”组合路径。
