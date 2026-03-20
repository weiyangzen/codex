# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 关联语义：非法 hunk header 拒绝（invalid hunk header rejection）

## 场景与职责

`013_rejects_invalid_hunk_header` 是 `apply_patch` fixtures 中的语法负向场景，专门验证“文件操作头（hunk header）不在协议允许集合内时，补丁必须被拒绝，且文件系统保持不变”。

该目录内部三件套如下：

1. `patch.txt`：故意使用非法头 `*** Frobnicate File: foo`（`codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/patch.txt:1-3`）。
2. `input/foo.txt`：输入态文件内容 `stable`（`.../input/foo.txt:1`）。
3. `expected/foo.txt`：期望输出仍为 `stable`，表达“解析失败无副作用”（`.../expected/foo.txt:1`）。

在场景体系中的职责定位：

1. 与 `008_rejects_empty_update_hunk`、`005_rejects_empty_patch` 形成“语法层失败”测试簇，覆盖不同语法错误形态。
2. 和 `tests/suite/tool.rs` 中同名测试互补：fixture 场景验证最终文件树不变；tool 测试验证 stderr 文案与退出状态。
3. 作为 `parse_one_hunk` 未命中 Add/Delete/Update 三种前缀分支时的稳定回归锚点，防止未来放宽错误头部导致误执行。

## 功能点目的

该场景要锁定的功能契约是：

1. `apply_patch` 仅接受三类文件级 hunk 头：`*** Add File: ...`、`*** Delete File: ...`、`*** Update File: ...`（协议文档 `codex-rs/apply-patch/apply_patch_tool_instructions.md:12-17`）。
2. 解析器遇到未知头时必须返回 `InvalidHunkError`，并携带明确“合法头列表”提示（`codex-rs/apply-patch/src/parser.rs:335-340`）。
3. CLI 层应将解析错误规范化为 `Invalid patch hunk on line ...` 输出到 stderr（`codex-rs/apply-patch/src/lib.rs:195-203`）。
4. 错误不应产生任何落盘写入；fixture 以 `expected == input` 约束该副作用边界（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。

对应回归价值：

1. 防止模型或调用方拼错头部时被“宽松解析”为合法操作。
2. 防止解析错误回退到执行逻辑并意外改写文件。
3. 保证错误反馈可诊断，方便上层工具和用户定位输入问题。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景回放流程（调用方）

`tests/suite/scenarios.rs` 会统一遍历 `fixtures/scenarios/*`，对每个目录执行同一流程：

1. 将场景 `input/` 复制到 `tempdir()`（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`）。
2. 读取 `patch.txt` 并运行 `apply_patch <patch_body>`（`.../scenarios.rs:39-48`）。
3. 对 `expected/` 与临时目录做递归快照比较（`.../scenarios.rs:50-60,65-105`）。

这里有一个关键点：该 runner 明确“不检查 exit status”，只以最终文件树为准（`.../scenarios.rs:42-45`）。因此本场景的断言重点是“失败后不改文件”。

### 2) 解析核心：非法头部如何被拒绝（被调用方）

`parse_one_hunk()` 的逻辑顺序（`codex-rs/apply-patch/src/parser.rs:248-341`）：

1. `first_line = lines[0].trim()`，允许 marker 前后空白容忍（`.../parser.rs:250`）。
2. 依次尝试 `strip_prefix(ADD_FILE_MARKER / DELETE_FILE_MARKER / UPDATE_FILE_MARKER)`（`.../parser.rs:251-333`）。
3. 若全部未命中，返回：
   - `ParseError::InvalidHunkError`
   - message 含当前头部文本与合法头部列表（`.../parser.rs:335-338`）
   - `line_number` 由上层循环传入（当前场景是第 2 行）。

由于 `*** Frobnicate File: foo` 不匹配任何合法前缀，直接命中第 3 步。

### 3) CLI 错误输出与退出码

`apply_patch()` 在 parse 失败时不会进入落盘执行，而是：

1. 匹配 `InvalidHunkError` 分支，写 stderr：
   `Invalid patch hunk on line {line_number}: {message}`（`codex-rs/apply-patch/src/lib.rs:195-203`）。
2. 返回 `ApplyPatchError::ParseError`（`.../lib.rs:204`）。
3. `standalone_executable::run_main()` 捕获错误后返回退出码 `1`（`codex-rs/apply-patch/src/standalone_executable.rs:51-58`）。

对应代码驱动测试：`test_apply_patch_cli_rejects_invalid_hunk_header()` 精确断言上述 stderr 文本（`codex-rs/apply-patch/tests/suite/tool.rs:210-218`）。

### 4) 协议与文档约束

1. 协议文档在 `apply_patch_tool_instructions.md` 明确仅有三类文件操作头（`codex-rs/apply-patch/apply_patch_tool_instructions.md:12-17`）。
2. fixtures 总体协议在 `scenarios/README.md` 定义为 `input/ + patch.txt + expected/`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`）。
3. `.gitattributes` 强制 LF（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`），避免跨平台换行导致的误判。

### 5) 相关命令（验证与复现）

1. 执行场景集合：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 执行同语义 CLI 文案测试：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_rejects_invalid_hunk_header`
3. 手动复现：
   - `apply_patch "*** Begin Patch\n*** Frobnicate File: foo\n*** End Patch"`

## 关键代码路径与文件引用

### A. 目标目录（研究对象）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/patch.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/input/foo.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/013_rejects_invalid_hunk_header/expected/foo.txt`

### B. 直接调用方（测试入口与场景驱动）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-60`（fixture 回放主流程）

### C. 同语义校验测试（stderr/退出码）

1. `codex-rs/apply-patch/tests/suite/tool.rs:210-218`（非法 hunk header 的错误输出断言）
2. `codex-rs/apply-patch/src/parser.rs:673-681`（`parse_one_hunk("bad")` 的单测，验证同类错误分支）

### D. 被调用方（解析与执行链路）

1. `codex-rs/apply-patch/src/parser.rs:248-341`（hunk header 分派与 InvalidHunkError）
2. `codex-rs/apply-patch/src/lib.rs:183-205`（parse 失败 -> stderr 输出）
3. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`（CLI 输入与退出码）
4. `codex-rs/apply-patch/src/main.rs:1-3`（bin 入口）

### E. 上游集成链路（补充上下文依赖）

1. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-175,241-244`：tool handler 复用 `maybe_parse_apply_patch_verified`，验证失败返回 `apply_patch verification failed: ...`。
2. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`：通过 `codex --codex-run-as-apply-patch <patch>` 执行已验证补丁。
3. `codex-rs/arg0/src/lib.rs:90-107`：识别 `--codex-run-as-apply-patch` 并调用 `codex_apply_patch::apply_patch`。

### F. 配置/构建/脚本/文档路径

1. `codex-rs/apply-patch/Cargo.toml:1-30`（crate、bin、测试依赖）
2. `codex-rs/apply-patch/BUILD.bazel:3-10`（`apply_patch_tool_instructions.md` 作为 compile_data）
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`（协议文档）
4. `Docs/researches/blueprint_checklist.md:122`（本次 checklist 项）
5. `.ops/generate_daily_research_todo.sh:1-42`（根据 checklist 生成当日 todo）

## 依赖与外部交互

### 1) 运行/测试依赖

`codex-apply-patch` 的该场景相关依赖来自 `Cargo.toml`（`codex-rs/apply-patch/Cargo.toml:18-30`）：

1. 运行时：`anyhow`、`thiserror`（错误建模）、`tree-sitter`/`tree-sitter-bash`（shell heredoc 解析，供上游调用路径）。
2. 测试时：`assert_cmd`（执行二进制）、`tempfile`（隔离目录）、`pretty_assertions`（差异输出）、`codex-utils-cargo-bin`（跨 Cargo/Bazel 定位 `apply_patch`）。

### 2) 外部交互面

1. 文件系统：`input` 拷贝、`expected` 快照读取、临时目录中文件可能被修改。
2. 子进程：场景测试通过 `Command::new(cargo_bin("apply_patch"))` 调起独立进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. 标准流：非法头错误走 stderr；本场景不依赖 stdout。

### 3) 与上层系统交互

1. 在 core 工具链里，`apply_patch` 先被 verified 解析，非法 header 在执行前即失败并返回模型可读错误（`codex-rs/core/src/tools/handlers/apply_patch.rs:241-244`）。
2. 运行时环境最小化由 runtime 层控制（`codex-rs/core/src/tools/runtimes/apply_patch.rs:96-100`），但本场景属于解析前置失败，不触达实际写盘命令。

## 风险、边界与改进建议

### 风险

1. `scenarios.rs` 不校验 stderr/exit code，仅比文件树；若未来错误文案退化，本场景不会发现（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-45`）。
2. 合法 header 列表字符串目前是硬编码在错误信息里（`codex-rs/apply-patch/src/parser.rs:337`），若协议新增 header，容易出现“实现支持了但错误文案未同步”的一致性风险。
3. 当前场景只覆盖“完全未知 header”，未覆盖大小写偏差、拼写近似、多余空格等邻近错误输入。

### 边界

1. 本场景验证的是语法拒绝与副作用边界，不覆盖权限拒绝、路径越界、审批策略等安全链路（这些在 `core` 层测试覆盖）。
2. 由于 parser 对 marker 有 `trim()` 宽容（`codex-rs/apply-patch/src/parser.rs:250`），本场景无法证明“前后空白是否应被拒绝”，那是 `017/018/020_*` 系列场景职责。

### 改进建议

1. 在 fixture 框架中增加可选元数据（如 `stderr_contains.txt`、`exit_code.txt`），让语法负向场景同时覆盖“最终态 + 错误通路”。
2. 将合法 header 列表抽为单一常量源（或由 marker 常量动态拼接）以避免协议与错误文案漂移。
3. 增补邻近输入场景：
   - `*** add file:`（大小写变化）
   - `*** Update  File:`（双空格）
   - `*** Frobnicate File: foo` 前置/后置空白
   以更细粒度约束容错边界。
4. 在 `scenarios/README.md` 增加“负向场景建议同步在 `tool.rs` 校验 stderr/exit”说明，明确 fixture 与代码测试的职责分层。
