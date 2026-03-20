# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/input`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 所属 crate：`codex-apply-patch`
- 目录实体：`lines.txt`

## 场景与职责

该目录是场景 `021_update_file_deletion_only` 的输入态目录，职责是提供 `apply_patch` 执行前的文件系统基线。

本目录仅包含一个文件：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/input/lines.txt:1`

该文件内容为三行：`line1`、`line2`、`line3`。场景同级 `patch.txt` 会用 `Update File` hunk 只删除中间行 `line2`，同级 `expected/lines.txt` 定义结果应为 `line1`、`line3`。

在场景矩阵中的定位：

1. 与 `020_delete_file_success` 互补：`020` 验证整文件删除（`Delete File`），本场景验证文件内行删除（`Update File`）。
2. 与 `016_pure_addition_update_chunk` 互补：`016` 是 only-add，本场景是 only-delete，共同约束 `Update File` 的单侧变更语义。
3. 与 `022_update_file_end_of_file_marker` 区分：`022` 关注 `*** End of File` 锚点，本场景关注普通上下文中的删除匹配。

## 功能点目的

围绕本 `input/` 目录，核心目标是验证：**当 patch 仅包含删除行（`-`）而没有新增行（`+`）时，`apply_patch` 能在正确位置删除目标行，且不误删其他上下文。**

该目录承担的测试价值：

1. 为 parser 提供真实输入，验证 `-line2` 可作为合法更新块内容，而不会被当成“空更新块”。
2. 为 replacement 算法提供最小 yet 足够的数据，使 `old_lines` 比 `new_lines` 长时的收缩替换可稳定落地。
3. 将断言聚焦于“中间行删除”这一行为，不受 rename、多文件或复杂上下文干扰。
4. 通过最终态对比，间接覆盖“删除后文件仍保留且为修改（M）而非删除（D）”的语义。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) fixture 协议与本场景资产

场景遵循统一 fixture 协议：每个用例由 `input/ + patch.txt + expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`）。

本场景三件套：

1. 输入态：`.../input/lines.txt`（3 行）。
2. 操作定义：`.../patch.txt`（`Update File: lines.txt`，删除 `line2`）。
3. 期望态：`.../expected/lines.txt`（2 行）。

### 2) 关键执行流程（调用方 -> 被调用方）

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*` 并逐目录执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11`）。
2. `run_apply_patch_scenario()` 将 `input/` 复制到临时目录根，再读取 `patch.txt`（`codex-rs/apply-patch/tests/suite/scenarios.rs:30`）。
3. 测试通过子进程调用 `apply_patch` 二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45`）。
4. CLI 入口 `run_main()` 解析参数或 stdin，转调库函数 `apply_patch()`（`codex-rs/apply-patch/src/standalone_executable.rs:11`）。
5. `apply_patch()` 先 `parse_patch()`，后进入 `apply_hunks_to_files()`（`codex-rs/apply-patch/src/lib.rs:183`、`codex-rs/apply-patch/src/lib.rs:279`）。
6. `UpdateFile` 分支调用 `derive_new_contents_from_chunks()` 计算新内容并回写（`codex-rs/apply-patch/src/lib.rs:306`、`codex-rs/apply-patch/src/lib.rs:348`）。
7. 最后用目录快照比较 `actual` 与 `expected`，以最终文件树和字节内容为判据（`codex-rs/apply-patch/tests/suite/scenarios.rs:51`、`codex-rs/apply-patch/tests/suite/scenarios.rs:71`）。

### 3) deletion-only 的数据结构落点

1. `Hunk::UpdateFile { path, move_path, chunks }` 承载本场景更新操作（`codex-rs/apply-patch/src/parser.rs:68`）。
2. `UpdateFileChunk` 中：
   - 上下文行（空格前缀）同时进入 `old_lines/new_lines`。
   - 删除行（`-` 前缀）仅进入 `old_lines`。
   对应实现见 `codex-rs/apply-patch/src/parser.rs:405`、`codex-rs/apply-patch/src/parser.rs:413`。
3. `compute_replacements()` 生成 `(start_index, old_len, new_lines)`；本场景是 `old_len > new_lines.len()` 的“收缩替换”（`codex-rs/apply-patch/src/lib.rs:386`）。
4. `apply_replacements()` 先删后插（倒序应用），最终达到“删中间行”效果（`codex-rs/apply-patch/src/lib.rs:478`）。
5. `seek_sequence()` 负责按多级容错匹配原文片段（精确/trim/Unicode 归一化）（`codex-rs/apply-patch/src/seek_sequence.rs:12`）。

### 4) 协议、命令、配置与上层路径

1. 工具协议定义 `HunkLine := (" " | "-" | "+") text`，本场景属于标准删除型 hunk（`codex-rs/apply-patch/apply_patch_tool_instructions.md:49`）。
2. `codex-apply-patch` 同时提供库与二进制（`codex-rs/apply-patch/Cargo.toml:2`、`codex-rs/apply-patch/Cargo.toml:12`）。
3. Bazel 将 `apply_patch_tool_instructions.md` 打入 `compile_data`，保证构建可见性（`codex-rs/apply-patch/BUILD.bazel:8`）。
4. 在 `core` 中，工具启用受配置影响：`include_apply_patch_tool` 与 `apply_patch_tool_type`（`codex-rs/core/src/config/mod.rs:528`、`codex-rs/core/src/tools/spec.rs:2784`）。
5. handler 先做 verified 解析，再走审批与 runtime（`codex-rs/core/src/tools/handlers/apply_patch.rs:174`）。
6. runtime 实际执行 `codex --codex-run-as-apply-patch <patch>`（`codex-rs/core/src/tools/runtimes/apply_patch.rs:91`）。
7. `arg0` 分发层接收该内部参数并调用统一实现（`codex-rs/arg0/src/lib.rs:90`）。

### 5) 常用验证命令

1. 仅场景集：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 全 crate：`cargo test -p codex-apply-patch`
3. 刷新研究待办：`bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 目标目录与同级场景资产

1. `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/input/lines.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/patch.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/expected/lines.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`

### B. 直接调用方（测试入口）

1. `codex-rs/apply-patch/tests/all.rs:1`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:30`
5. `codex-rs/apply-patch/tests/suite/scenarios.rs:51`

### C. 被调用方（解析与执行）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11`
2. `codex-rs/apply-patch/src/lib.rs:183`
3. `codex-rs/apply-patch/src/lib.rs:279`
4. `codex-rs/apply-patch/src/lib.rs:306`
5. `codex-rs/apply-patch/src/lib.rs:348`
6. `codex-rs/apply-patch/src/lib.rs:386`
7. `codex-rs/apply-patch/src/lib.rs:478`
8. `codex-rs/apply-patch/src/parser.rs:343`
9. `codex-rs/apply-patch/src/seek_sequence.rs:12`

### D. 上游配置与运行链

1. `codex-rs/core/src/config/mod.rs:528`
2. `codex-rs/core/src/tools/spec.rs:2784`
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:174`
4. `codex-rs/apply-patch/src/invocation.rs:132`
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69`
6. `codex-rs/arg0/src/lib.rs:90`

### E. 脚本与研究流程文件

1. `Docs/researches/blueprint_checklist.md:150`
2. `.ops/generate_daily_research_todo.sh:5`
3. `.ops/research_guard.sh:205`

## 依赖与外部交互

### 1) crate 与测试依赖

`codex-apply-patch` 关键依赖（`codex-rs/apply-patch/Cargo.toml:18`）：

1. `anyhow` / `thiserror`：错误建模与上下文传播。
2. `similar`：在 verified 路径生成 unified diff。
3. `tree-sitter` / `tree-sitter-bash`：shell/heredoc 形式 `apply_patch` 识别。
4. `assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`：场景测试与断言基础设施。

### 2) 文件系统与进程交互

1. 测试时将 `input/` 复制到临时目录；`input/lines.txt` 成为真实落盘目标文件。
2. 以子进程方式调用 `apply_patch`，不是 mock。
3. `Update File` 路径执行“读取原文件 -> 匹配替换 -> 覆盖写回”。
4. 最终通过目录快照比较进行端到端断言。

### 3) 与 core/审批/沙箱的外部交互

1. 生产链路中先验证 patch，再执行审批策略（workspace 内自动、越界需审批或拒绝）。
2. runtime 在沙箱尝试中执行内部命令，环境最小化，避免泄漏。
3. `arg0` 机制保证别名调用与内部调用落到同一 `codex_apply_patch::apply_patch()` 实现。

### 4) 文档与脚本交互

1. 场景协议文档：`tests/fixtures/scenarios/README.md`。
2. 工具协议文档：`apply_patch_tool_instructions.md`。
3. 研究流程以 `blueprint_checklist.md` 为真源，`generate_daily_research_todo.sh` 负责生成日待办。

## 风险、边界与改进建议

### 风险

1. `scenarios` runner 不校验 exit code/stderr，仅比最终态；过程异常信息覆盖较弱。
2. 本输入仅三行且上下文唯一，无法暴露重复片段下的定位歧义风险。
3. 删除型 hunk 对匹配策略敏感，若后续调整 `seek_sequence` 容错等级，可能出现误匹配或漏匹配回归。

### 边界

1. 不覆盖 `Move to`、多文件事务性、权限失败、目录删除等分支。
2. 不覆盖 `*** End of File` 锚点语义（由 `022` 场景承担）。
3. 不覆盖 core UI/事件层展示细节；这里只验证文件系统最终态。

### 改进建议

1. 在 `tests/suite/scenarios.rs` 增加可选元数据（例如 `expect_exit_code`、`stderr_contains`），补强过程信号。
2. 新增 deletion-only 变体：首行删除、尾行删除、重复上下文多处删除，增强定位稳定性覆盖。
3. 在 `scenarios/README.md` 增加 only-add / only-delete / eof-anchor 的覆盖矩阵索引，降低维护者定位成本。
4. 在 core `apply_patch_cli` 增补与 `021` 一一对应的 deletion-only 用例，形成 fixture 与上层集成测试的对照闭环。
