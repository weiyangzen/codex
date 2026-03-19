# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属模块：`codex-rs/apply-patch`（crate: `codex-apply-patch`）

## 场景与职责

该目录是场景 `005_rejects_empty_patch` 的“初始文件系统输入快照”。目录当前只有一个业务文件：

1. `foo.txt`，内容为 `stable`（LF 结尾）。

它不负责描述补丁语法，而是承担“失败路径不变性基准”的职责：

1. `patch.txt` 只含 `*** Begin Patch` 与 `*** End Patch`，没有任何 hunk。
2. 该 patch 会在 `codex-apply-patch` 执行层被拒绝（`No files were modified.`）。
3. 因为应当失败且无副作用，`input/foo.txt` 必须与 `expected/foo.txt` 一致，作为状态回归锚点。

该目录与调用方 `tests/suite/scenarios.rs` 的关系是：每次场景执行前，runner 把 `input/` 复制到临时目录，再在该临时目录运行 `apply_patch`，最后把临时目录与 `expected/` 做全量快照对比。

## 功能点目的

`input/` 在本场景中的核心目的，是验证“空补丁不应修改任何文件”的契约。

1. 语法层允许空 hunk 集：`parse_patch_text()` 在只有边界标记时可返回 `hunks = []`。
2. 语义执行层禁止无操作补丁：`apply_hunks_to_files()` 对空 hunk 列表直接报错 `No files were modified.`。
3. 场景回放测试不依赖退出码，而依赖“目录终态与 expected 完全一致”；因此 `input/foo.txt` 是该契约的直接观测对象。
4. 在 core 链路中同一输入会被更早拒绝为 `patch rejected: empty patch`（安全评估层），但结果目标一致：不落盘改动。

因此，`input/` 不是“普通样例输入”，而是负向语义测试中的“副作用防线”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*` 目录。
2. `run_apply_patch_scenario()` 将 `input/` 递归复制到 `tempdir`。
3. 读取 `patch.txt` 并执行 `apply_patch <patch>`（`current_dir = tempdir`）。
4. 对 `expected/` 与 `tempdir` 生成 `BTreeMap<PathBuf, Entry>` 快照。
5. `assert_eq!(actual_snapshot, expected_snapshot)`，确保文件树字节级一致。

`Entry` 结构：

- `Entry::File(Vec<u8>)`
- `Entry::Dir`

这意味着 `foo.txt` 的内容、结尾换行、以及是否存在，都会被精确比较。

### 2) 空补丁的解析与执行分层

1. 解析器边界检查只要求首行/尾行匹配 patch marker，不强制至少一个 hunk。
2. 因此 `*** Begin Patch` + `*** End Patch` 会得到 `ApplyPatchArgs { hunks: vec![] }`。
3. `apply_patch()` 调用 `apply_hunks()`，再进入 `apply_hunks_to_files()`。
4. `apply_hunks_to_files()` 发现 `hunks.is_empty()` 时 `bail!("No files were modified.")`。
5. CLI 入口 `run_main()` 接收到错误返回退出码 `1`。

该分层解释了为什么本场景能够同时成立：

- parser 通过
- 执行失败
- 文件系统不变

### 3) 协议与命令形态

场景补丁协议（来自 `patch.txt`）：

```text
*** Begin Patch
*** End Patch
```

场景命令等价于：

```bash
apply_patch "*** Begin Patch
*** End Patch"
```

预期可观测行为：

1. `codex-apply-patch` CLI 返回失败状态。
2. stderr 包含 `No files were modified.`（在 `tool.rs` 有精确断言）。
3. `input/foo.txt` 复制后的临时文件保持 `stable`。

### 4) 与 core 工具链的实现差异

`codex-core` 的 `apply_patch` 处理链对空 patch 有前置拒绝：

1. `maybe_parse_apply_patch_verified()` 可将空补丁解析为 `ApplyPatchAction`（changes 为空）。
2. `assess_patch_safety()` 首先检查 `action.is_empty()`，直接返回 `SafetyCheck::Reject { reason: "empty patch" }`。
3. 上层对模型的输出文案是 `patch rejected: empty patch`，而不是 CLI 的 `No files were modified.`。

这属于“同一约束在不同层次的拦截策略差异”，但共同目标是阻止无意义写操作。

## 关键代码路径与文件引用

### 目标目录与同场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/input/foo.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/patch.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/005_rejects_empty_patch/expected/foo.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes`

### 直接调用方（场景执行）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`（遍历场景）
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30`（复制 input）
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:45`（执行 apply_patch）
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:55`（快照断言）
5. `codex-rs/apply-patch/tests/suite/scenarios.rs:65`（快照结构定义）

### 被调用方（解析与执行）

1. `codex-rs/apply-patch/src/parser.rs:154`（parse_patch_text）
2. `codex-rs/apply-patch/src/parser.rs:226`（边界检查）
3. `codex-rs/apply-patch/src/lib.rs:183`（apply_patch）
4. `codex-rs/apply-patch/src/lib.rs:216`（apply_hunks）
5. `codex-rs/apply-patch/src/lib.rs:279`（空 hunk 报错）
6. `codex-rs/apply-patch/src/standalone_executable.rs:11`（CLI 入口）

### 相关测试与上游消费

1. `codex-rs/apply-patch/tests/suite/tool.rs:85`（CLI 空补丁失败断言）
2. `codex-rs/core/src/safety.rs:36`（core 对空 patch 前置拒绝）
3. `codex-rs/core/tests/suite/apply_patch_cli.rs:511`（core 侧空补丁集成断言）
4. `codex-rs/core/src/tools/handlers/apply_patch.rs:174`（verified parse 入口）
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs:88`（`--codex-run-as-apply-patch` 执行）
6. `codex-rs/arg0/src/lib.rs:90`（arg0 分发到 apply_patch 实现）

### 配置、构建、脚本与文档

1. `codex-rs/apply-patch/Cargo.toml`（crate 与 bin 定义）
2. `codex-rs/apply-patch/BUILD.bazel`（compile_data 打包说明文档）
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md`（协议说明）
4. `codex-rs/core/src/tools/handlers/tool_apply_patch.lark`（freeform grammar，要求 hunk+）
5. `.ops/generate_daily_research_todo.sh`（每日 todo 生成）
6. `Docs/researches/blueprint_checklist.md`（研究清单来源）

## 依赖与外部交互

### 依赖

`codex-apply-patch` 相关依赖（与本场景最相关）：

1. `anyhow` / `thiserror`：错误分层与错误文案。
2. `assert_cmd` / `tempfile` / `pretty_assertions` / `codex-utils-cargo-bin`：场景与 CLI 测试启动、隔离目录、快照比较。
3. `tree-sitter` / `tree-sitter-bash`：`invocation.rs` 中 shell/heredoc 解析（本场景非主路径但属于上下游入口依赖）。

### 外部交互

1. 文件系统交互：复制 `input/`、读取 `patch.txt`、运行后读取临时目录文件字节。
2. 进程交互：测试进程通过 `Command::new(cargo_bin("apply_patch"))` 启动子进程。
3. 标准流交互：空补丁失败信息通过 stderr 输出。
4. 运行时分发：在完整 Codex 可执行链中通过 `arg0` 与 secret arg1 路由至同一 apply_patch 执行实现。

### 配置面

1. `include_apply_patch_tool` / `Feature::ApplyPatchFreeform` 影响工具是否向模型暴露。
2. `apply_patch_tool_type`（Freeform/Function）影响工具协议层形态。
3. 对本场景而言，这些配置改变“调用入口”，不改变“空补丁必须失败且不改盘”的底层语义。

## 风险、边界与改进建议

### 风险与边界

1. `scenarios.rs` 只比最终状态，不断言退出码与 stderr；单靠本目录无法发现错误文案回归。
2. parser 与 grammar 存在分层差异：
   - `parser.rs` 允许空 patch（hunks 可为空）。
   - `tool_apply_patch.lark` 定义为 `hunk+`。
   这会在不同入口导致错误发生层级不同。
3. 当前 `input/` 仅单文件场景，不能覆盖“空 patch 对多文件/多层目录输入”的稳定性边界。
4. 该场景依赖 `expected/foo.txt` 与 `input/foo.txt` 的严格一致；若有人误改其中任一文件，场景语义会被弱化或改变。

### 改进建议

1. 为 scenarios 增加可选元数据（如 `expected_exit_code`、`stderr_contains`），让 `005` 类负向用例具备行为断言而不仅是状态断言。
2. 增加“多文件 input 的空补丁”变体，验证无副作用范围不受文件数量影响。
3. 在 `safety_tests.rs` 增加 `action.is_empty()` 的专门单元测试，避免 core 前置拒绝逻辑无回归保护。
4. 在 `tests/fixtures/scenarios/README.md` 明确“负向场景建议配套 `tool.rs` 的 stderr/退出码断言”规范，降低遗漏。
