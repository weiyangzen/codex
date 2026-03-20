# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 对应场景：`013_rejects_invalid_hunk_header`

## 场景与职责

该目录是负向场景 `013_rejects_invalid_hunk_header` 的“最终状态基准（expected oracle）”，目录内仅包含 `foo.txt`，内容为 `stable`。

它的职责不是表达“补丁成功后结果”，而是表达“补丁被拒绝时，输入文件系统保持不变”。本场景中补丁头为非法值：

```patch
*** Begin Patch
*** Frobnicate File: foo
*** End Patch
```

该头不会命中 `Add/Delete/Update` 三类合法 hunk header，因此解析阶段应失败，执行阶段不得产生写入；`expected/foo.txt` 即用于约束这一无副作用语义。

与同场景目录分工：

1. `input/foo.txt`：提供初始稳定状态。
2. `patch.txt`：提供非法 hunk header 输入。
3. `expected/foo.txt`：提供失败后状态真值。

## 功能点目的

该目录覆盖的功能目的为：

1. 语法边界约束：仅允许 `*** Add File: ...`、`*** Delete File: ...`、`*** Update File: ...`。
2. 失败即停：解析失败后不可进入文件变更执行。
3. 负向回归锚点：防止未来放宽解析导致未知 header 被误当作合法操作。
4. 可验证副作用边界：通过文件树快照比较，确保失败路径不改文件内容。

该目录与 `tests/suite/tool.rs` 中的 `test_apply_patch_cli_rejects_invalid_hunk_header` 形成互补：

1. `expected/` 侧重最终文件系统状态。
2. `tool.rs` 侧重 stderr 文案与失败退出行为。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景执行流程（调用方）

`tests/suite/scenarios.rs` 中 `test_apply_patch_scenarios()` 会遍历 `fixtures/scenarios` 下所有目录，并调用 `run_apply_patch_scenario()`。

关键流程：

1. 将场景 `input/` 拷贝到 `tempdir()`。
2. 读取 `patch.txt` 并执行 `apply_patch <patch_body>` 子进程。
3. 递归快照 `expected/` 与临时目录，比较 `BTreeMap<PathBuf, Entry>` 完全一致。

其中 `Entry` 为：

1. `Entry::Dir`
2. `Entry::File(Vec<u8>)`

`expected/` 正是在第 3 步作为真值来源参与断言。

### 2) 非法 hunk header 的解析失败（被调用方）

`src/parser.rs` 的 `parse_one_hunk()` 先 `trim` 当前行，再按顺序尝试：

1. `*** Add File: `
2. `*** Delete File: `
3. `*** Update File: `

若都不匹配，则返回：

- `ParseError::InvalidHunkError`
- `line_number`（本场景为 2）
- message：`is not a valid hunk header ...`

这保证了 `*** Frobnicate File: foo` 会被拒绝。

### 3) CLI 输出与执行短路

`src/lib.rs::apply_patch()` 在 parse 失败时：

1. 将错误写到 stderr：`Invalid patch hunk on line {line_number}: {message}`。
2. 返回 `ApplyPatchError::ParseError`。
3. 不调用 `apply_hunks()`，因此无文件写入。

`src/standalone_executable.rs::run_main()` 接收该错误后返回退出码 `1`。

### 4) 协议与文档约束

协议文档 `apply_patch_tool_instructions.md` 明确文件操作头仅有 Add/Delete/Update 三种；fixtures 文档 `tests/fixtures/scenarios/README.md` 定义了 `input + patch + expected` 三件套组织方式。该 `expected/` 目录即是该协议中的最终态声明。

### 5) 复现/验证命令

1. 场景全集：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 错误文案：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_rejects_invalid_hunk_header`
3. core 集成校验：`cargo test -p codex-core --test suite apply_patch_cli_rejects_invalid_hunk_header`

## 关键代码路径与文件引用

### A. 目标目录与场景资产

1. `codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/expected/foo.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/input/foo.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/patch.txt`

### B. 调用方（测试入口）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs`（目录遍历、执行、快照比较）
2. `codex-rs/apply-patch/tests/suite/mod.rs`
3. `codex-rs/apply-patch/tests/all.rs`

### C. 被调用方（解析与 CLI）

1. `codex-rs/apply-patch/src/parser.rs`（`parse_one_hunk`）
2. `codex-rs/apply-patch/src/lib.rs`（`apply_patch` 错误分支）
3. `codex-rs/apply-patch/src/standalone_executable.rs`（参数读取与退出码）
4. `codex-rs/apply-patch/src/main.rs`

### D. 相关测试与上游链路

1. `codex-rs/apply-patch/tests/suite/tool.rs`（CLI stderr 精确断言）
2. `codex-rs/core/tests/suite/apply_patch_cli.rs`（工具链集成下的 verification failed）
3. `codex-rs/core/src/tools/handlers/apply_patch.rs`（`maybe_parse_apply_patch_verified` 预检）
4. `codex-rs/core/src/tools/runtimes/apply_patch.rs`（`codex --codex-run-as-apply-patch` 执行）
5. `codex-rs/arg0/src/lib.rs`（`--codex-run-as-apply-patch` 分发）

### E. 配置、构建、脚本、文档

1. `codex-rs/apply-patch/Cargo.toml`
2. `codex-rs/apply-patch/BUILD.bazel`
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`
5. `.ops/generate_daily_research_todo.sh`
6. `Docs/researches/blueprint_checklist.md`

## 依赖与外部交互

### 1) 依赖

场景相关链路主要依赖：

1. `anyhow` / `thiserror`：错误传递与上下文。
2. `assert_cmd` / `tempfile` / `pretty_assertions`：二进制测试、临时目录、断言可读性。
3. `codex_utils_cargo_bin`：在 Cargo/Bazel 环境下定位 `apply_patch` 可执行文件。
4. `tree-sitter` / `tree-sitter-bash`：用于 shell/heredoc 形态 `apply_patch` 解析（上游验证路径）。

### 2) 外部交互

1. 文件系统：复制 `input/`、执行补丁、快照 `expected/` 与实际目录。
2. 子进程：`Command::new(cargo_bin("apply_patch"))` 调起独立可执行。
3. 标准流：失败细节通过 stderr 输出。

### 3) 协议边界交互

1. 允许头部集合由协议文档和解析实现共同定义。
2. 该目录以静态文件快照方式参与“协议是否被正确拒绝”的最终判定。

## 风险、边界与改进建议

### 风险

1. `scenarios.rs` 当前不检查退出码与 stderr，仅比较文件树；若错误文案退化，此目录无法单独捕获。
2. 合法 hunk header 提示文案为固定字符串，未来协议扩展时可能与实现发生漂移。
3. 本目录只覆盖“完全未知 header”，未覆盖近似拼写/大小写/空白变体。

### 边界

1. 本目录只验证“解析失败无副作用”，不覆盖权限、沙箱、审批策略等路径。
2. 仅包含单文件 `foo.txt`，不覆盖目录层级或多文件并发修改等复杂状态。

### 改进建议

1. 为 fixture 场景引入可选 `stderr`/`exit_code` 断言文件，补齐负向场景可观测性。
2. 将合法 header 列表从单一常量源生成，减少文案与实现漂移风险。
3. 为相邻错误形式新增场景：大小写错误、多余空格、拼写近似 header。
4. 在 `scenarios/README.md` 明确“负向场景建议配套 tool.rs 文案断言”，统一测试分层约定。
