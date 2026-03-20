# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 场景关键词：`Delete File`、`成功删除`、`fixture e2e`、`最终态快照`

## 场景与职责

`020_delete_file_success` 是 `apply_patch` 场景集里“文件删除成功”的正向基线用例，用于验证最小删除补丁可以正确移除目标文件，同时保持无关文件不变。

目录结构及职责：

1. `patch.txt`：定义单一操作 `*** Delete File: obsolete.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/patch.txt:1`）。
2. `input/`：初始化工作区有两个文件，`keep.txt`（需保留）和 `obsolete.txt`（需删除）（`.../input/keep.txt:1`，`.../input/obsolete.txt:1`）。
3. `expected/`：只保留 `keep.txt`，表示补丁执行后期望的最终文件树（`.../expected/keep.txt:1`）。

在整体测试体系中，该目录不是解析器单测，而是端到端场景 fixture：由统一场景 runner 自动发现并执行，承担“删除语义可用 + 无副作用回归”职责（`codex-rs/apply-patch/tests/suite/scenarios.rs:11`）。

## 功能点目的

该场景要保护的行为契约：

1. `Delete File` 语法可被 parser 识别为 `Hunk::DeleteFile`（`codex-rs/apply-patch/src/parser.rs:271`）。
2. 执行器在 `DeleteFile` 分支调用 `std::fs::remove_file` 并成功删除目标（`codex-rs/apply-patch/src/lib.rs:301`）。
3. 成功路径会在摘要中登记 `D <path>`，与 add/modify 区分（`codex-rs/apply-patch/src/lib.rs:548`）。
4. 删除操作只影响指定路径，不会改动同目录其他文件（由 `keep.txt` 的 expected 快照表达）。

与相邻场景的分工：

1. `007_rejects_missing_file_delete` 覆盖“删除不存在文件失败”（`codex-rs/apply-patch/tests/suite/tool.rs:114`）。
2. `012_delete_directory_fails` 覆盖“删除目录失败”（`codex-rs/apply-patch/tests/suite/tool.rs:196`）。
3. `020_delete_file_success` 覆盖“目标是普通文件时成功删除”，形成 delete 语义的正负闭环。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) fixture 协议与场景数据

场景遵循 `scenarios` 约定：每个 case 固定由 `input/ + patch.txt + expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`）。

该场景补丁非常小：

```patch
*** Begin Patch
*** Delete File: obsolete.txt
*** End Patch
```

设计重点：

1. 使用相对路径 `obsolete.txt`，由运行时 `cwd` 解析。
2. 同时放置 `keep.txt`，让断言不仅验证“删掉了什么”，还验证“没误删什么”。

### 2) 调用链（调用方 -> 被调用方）

端到端执行链路如下：

1. `test_apply_patch_scenarios` 扫描 `fixtures/scenarios/*`，遇到目录即执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11`）。
2. `run_apply_patch_scenario` 将 `input/` 复制到临时目录，读取 `patch.txt`，启动 `apply_patch` 子进程（`.../scenarios.rs:30`、`:40`、`:45`）。
3. `apply_patch` 可执行入口从 argv/stdin 读取 PATCH 文本并调用库函数 `apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11`、`:51`）。
4. 库函数先 `parse_patch`，再进入 `apply_hunks_to_files`（`codex-rs/apply-patch/src/lib.rs:183`、`:279`）。
5. `Hunk::DeleteFile` 分支执行 `remove_file(path)`，成功后记录到 `AffectedPaths.deleted`（`codex-rs/apply-patch/src/lib.rs:301`、`:304`）。
6. 成功路径打印摘要 `Success...` + `D path`（`codex-rs/apply-patch/src/lib.rs:541`、`:549`）。
7. 场景 runner 不比较退出码，而是对 `expected` 与实际临时目录做字节级快照对比（`codex-rs/apply-patch/tests/suite/scenarios.rs:42`、`:55`、`:65`）。

### 3) 关键数据结构

1. `Hunk::DeleteFile { path }`：解析后的删除语义对象（`codex-rs/apply-patch/src/parser.rs:65`）。
2. `AffectedPaths { added, modified, deleted }`：执行结果聚合，驱动终端摘要输出（`codex-rs/apply-patch/src/lib.rs:271`）。
3. `Entry::File(Vec<u8>) | Entry::Dir`：场景测试快照结构，保证比较粒度是“目录树 + 文件字节内容”而非仅 stdout（`codex-rs/apply-patch/tests/suite/scenarios.rs:65`）。

### 4) 协议、命令与构建约束

1. 协议说明文档将 `Delete File` 定义为“删除已有文件，无后续内容行”（`codex-rs/apply-patch/apply_patch_tool_instructions.md:15`）。
2. parser 顶部注释同步给出 Lark 语法 `delete_hunk: "*** Delete File: " filename LF`（`codex-rs/apply-patch/src/parser.rs:12`）。
3. 场景回归命令：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`。
4. Bazel 构建通过 `codex-rust_crate(name = "apply-patch")` 暴露该 crate（`codex-rs/apply-patch/BUILD.bazel:5`）。

## 关键代码路径与文件引用

### 目标目录（研究对象）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/patch.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/input/keep.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/input/obsolete.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/020_delete_file_success/expected/keep.txt:1`

### 直接调用方（场景执行框架）

1. `codex-rs/apply-patch/tests/all.rs:1`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`

### 被调用方（解析/执行）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11`
2. `codex-rs/apply-patch/src/lib.rs:183`
3. `codex-rs/apply-patch/src/lib.rs:279`
4. `codex-rs/apply-patch/src/lib.rs:301`
5. `codex-rs/apply-patch/src/lib.rs:537`
6. `codex-rs/apply-patch/src/parser.rs:248`
7. `codex-rs/apply-patch/src/parser.rs:271`

### 配置与上游集成路径（apply_patch 工具链上下文）

1. `codex-rs/core/src/config/mod.rs:528`（`include_apply_patch_tool` 开关说明）。
2. `codex-rs/core/src/tools/spec.rs:2784`（按 `apply_patch_tool_type` 注册 tool spec）。
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:170`（处理器中做 verified 解析与权限评估）。
4. `codex-rs/apply-patch/src/invocation.rs:132`（`maybe_parse_apply_patch_verified` 构建结构化变更）。
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69`（构造 `codex --codex-run-as-apply-patch` 运行命令）。
6. `codex-rs/arg0/src/lib.rs:90`（arg1 分发到 apply_patch 执行）。

### 关联测试与文档/脚本

1. `codex-rs/apply-patch/tests/suite/tool.rs:114`（缺失文件删除失败）。
2. `codex-rs/apply-patch/tests/suite/tool.rs:196`（删除目录失败）。
3. `codex-rs/apply-patch/src/lib.rs:593`（库内删除成功单测）。
4. `codex-rs/apply-patch/apply_patch_tool_instructions.md:40`（协议语法）。
5. `.ops/generate_daily_research_todo.sh:5`（todo 生成脚本读取 checklist）。
6. `Docs/researches/blueprint_checklist.md:142`（本次需要勾选项）。

## 依赖与外部交互

### 1) crate 与测试依赖

`codex-apply-patch` 依赖（`codex-rs/apply-patch/Cargo.toml:18`）：

1. `anyhow` / `thiserror`：错误类型与上下文。
2. `similar`：更新场景 unified diff 生成（虽然本场景是 Delete，不直接使用 diff）。
3. `tree-sitter` / `tree-sitter-bash`：解析 shell/heredoc 形式 apply_patch 调用（上游 handler 依赖）。
4. 测试依赖 `assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`（`.../Cargo.toml:25`）。

### 2) 文件系统与进程交互

1. 场景测试会真实创建临时工作目录并执行二进制子进程，属于黑盒集成验证（`tests/suite/scenarios.rs:31`、`:45`）。
2. 删除动作依赖宿主文件系统语义（`remove_file`），因此自然覆盖权限/类型等 OS 行为。
3. 快照比较基于 `Vec<u8>`，对文本编码或换行差异敏感；`scenarios/.gitattributes` 固定 LF，降低跨平台漂移风险（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`）。

### 3) 与 core/协议层交互

1. 在 core 流程里，`apply_patch` 不直接盲执行，会先经 `maybe_parse_apply_patch_verified` 抽取 `ApplyPatchAction`（`core/src/tools/handlers/apply_patch.rs:174`）。
2. runtime 再以最小环境发起实际执行，命令形态是 `codex --codex-run-as-apply-patch <patch>`（`core/src/tools/runtimes/apply_patch.rs:90`）。
3. arg0 统一分发机制确保 `apply_patch` 既可单独命令运行，也可作为 codex 内部子模式运行（`codex-rs/arg0/src/lib.rs:85`、`:90`）。

## 风险、边界与改进建议

### 风险

1. 场景 runner 不断言 exit status/stderr，只看最终文件树；若未来出现“退出异常但文件正确”的问题，此场景无法直接发现（`codex-rs/apply-patch/tests/suite/scenarios.rs:42`）。
2. 本场景仅覆盖单文件删除，不覆盖一次 patch 内多删除、删除与更新混合时的排序/短路行为。
3. 当前样例只用一层相对路径，不覆盖嵌套路径、`./` 前缀等路径归一化细节。

### 边界

1. 不覆盖失败分支（缺失文件、目录、权限不足）；这些由其他场景与 `tool.rs` 分担。
2. 不覆盖 core approval/guardian 交互，仅覆盖 `apply_patch` 二进制本身行为。
3. 不覆盖跨平台路径分隔符差异（Windows 风格路径）。

### 改进建议

1. 为 `scenarios` 框架增加可选 `exit_code`/`stderr` 断言文件，补齐“仅比最终态”的观测盲区。
2. 增加 `delete_nested_file_success` 与 `delete_multiple_files_success` fixture，完善删除路径覆盖面。
3. 增加“先删后改同路径”冲突场景，明确 apply 顺序与失败语义是否允许部分生效。
4. 在 `scenarios/README.md` 补充“正向/负向 delete 场景映射表”，方便维护者定位回归点。
