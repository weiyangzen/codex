# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/input/dir` 研究文档

## 场景与职责
该目录是 `apply_patch` 场景 `012_delete_directory_fails` 的输入态关键对象，作用是构造“目标路径存在，但类型是目录”的前置条件。

场景整体契约来自 fixtures 规范：每个场景由 `input/`、`patch.txt`、`expected/` 组成，测试通过比较最终文件系统状态判断行为正确性（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-7`）。

在本场景中：
- `input/dir/foo.txt` 用来保证 `dir` 真实存在且非空（`codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/input/dir/foo.txt:1`）。
- patch 请求 `*** Delete File: dir`（`codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/patch.txt:1-3`）。
- 期望状态仍保留 `dir/foo.txt`，验证“删除目录应失败且不改变状态”（`codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected/dir/foo.txt:1`）。

因此，这个目录的职责不是提供业务内容，而是为类型约束测试提供最小、稳定、可复现的目录实体。

## 功能点目的
该目录对应的功能点是：
- 验证 `Delete File` 只允许删除普通文件，不允许目录。
- 验证失败路径下不会误删目录内容（即补丁失败时保持原状）。
- 与缺失文件删除场景（如 `missing.txt`）形成互补：这里不是“路径不存在”，而是“路径类型不匹配”。

它保障的是文件系统操作的安全边界，防止补丁执行器把目录当文件处理而造成不可预期副作用。

## 具体技术实现（关键流程/数据结构/协议/命令）
1. 场景加载与执行
- `test_apply_patch_scenarios` 遍历 `fixtures/scenarios` 下所有目录并逐个执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:10-25`）。
- `run_apply_patch_scenario` 将 `input/` 递归复制到临时目录、读取 `patch.txt`、运行 `apply_patch` 二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-48`）。
- 该函数故意不校验退出码，而是做“最终状态快照对比”（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-60`）。

2. 协议与解析
- `Delete File` 是 apply-patch 语法中的一类 hunk（`delete_hunk`），由 parser 解析为 `Hunk::DeleteFile { path }`（`codex-rs/apply-patch/src/parser.rs:10-13,60-67`）。
- 路径通过 `resolve_path(cwd)` 解析为绝对目标路径（`codex-rs/apply-patch/src/parser.rs:78-85`）。

3. 执行与错误传播
- CLI 入口 `run_main()` 读取参数/STDIN，调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
- `apply_patch` 解析补丁后进入 `apply_hunks`（`codex-rs/apply-patch/src/lib.rs:182-213`）。
- `apply_hunks_to_files` 遇到 `Hunk::DeleteFile` 时调用 `std::fs::remove_file(path)`（`codex-rs/apply-patch/src/lib.rs:287-305`）。
- 当 `path` 指向目录时，`remove_file` 返回 I/O 错误，外层通过 `with_context` 形成 `Failed to delete file <path>` 并写入 stderr（`codex-rs/apply-patch/src/lib.rs:302-304,253-256`）。

4. 与显式 CLI 单测的对应关系
- `test_apply_patch_cli_delete_directory_fails` 直接构造目录 `dir`，断言 stderr 为 `Failed to delete file dir`（`codex-rs/apply-patch/tests/suite/tool.rs:196-205`）。
- fixtures 场景侧重“最终状态不变”；tool 单测侧重“错误文案和失败语义”，两者形成互补覆盖。

5. 相关数据结构
- 解析层：`Hunk::DeleteFile { path: PathBuf }`（`codex-rs/apply-patch/src/parser.rs:60-67`）。
- 执行结果层：`AffectedPaths { added, modified, deleted }`，本场景失败时不会产生 `deleted` 记录（`codex-rs/apply-patch/src/lib.rs:271-275,334-338`）。

## 关键代码路径与文件引用
- 场景输入对象：`codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/input/dir/foo.txt:1`
- 场景补丁：`codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/patch.txt:1-3`
- 场景期望：`codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected/dir/foo.txt:1`
- fixtures 契约说明：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-7`
- 场景测试主流程：`codex-rs/apply-patch/tests/suite/scenarios.rs:10-63`
- 目录快照/复制机制：`codex-rs/apply-patch/tests/suite/scenarios.rs:71-126`
- 目录删除失败 CLI 单测：`codex-rs/apply-patch/tests/suite/tool.rs:196-205`
- 协议语法与 `Delete File` hunk：`codex-rs/apply-patch/src/parser.rs:10-13,60-67`
- CLI 入口与命令参数模式：`codex-rs/apply-patch/src/standalone_executable.rs:11-58`
- 删除执行与错误包装：`codex-rs/apply-patch/src/lib.rs:287-305`
- 失败输出路径：`codex-rs/apply-patch/src/lib.rs:253-256`

## 依赖与外部交互
1. 代码依赖
- crate：`codex-apply-patch`（`codex-rs/apply-patch/Cargo.toml:1-13`）。
- 主要依赖：`anyhow`（错误上下文）、`thiserror`（错误类型）、`similar`（diff）、`tree-sitter` + `tree-sitter-bash`（命令/补丁解析上下文）（`codex-rs/apply-patch/Cargo.toml:18-23`）。
- 测试依赖：`assert_cmd`、`codex-utils-cargo-bin`、`tempfile`、`pretty_assertions`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

2. 外部交互
- 文件系统：读 `patch.txt`/`input`，写临时目录，执行 `remove_file` 删除目标路径。
- 进程：测试通过 `Command::new(cargo_bin("apply_patch"))` 启动二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
- 标准流协议：成功输出变更摘要到 stdout，失败输出错误到 stderr（`codex-rs/apply-patch/src/lib.rs:247-256,537-551`）。

3. 配置层面
- 本场景无独立配置文件；行为由 patch 文本与当前工作目录共同决定。
- 目录路径解析依赖执行时 `cwd`，由场景 runner 的 `current_dir(tmp.path())` 固定（`codex-rs/apply-patch/tests/suite/scenarios.rs:47`）。

## 风险、边界与改进建议
1. 风险
- fixtures 场景不校验退出码，仅校验最终状态；若将来出现“错误退出码异常但状态巧合一致”，该测试无法发现。
- 当前错误文案以 `Failed to delete file <path>` 为主，不显式呈现底层 `Is a directory`，对排障细节不够友好。

2. 边界
- `Delete File` 仅覆盖普通文件删除；目录删除需单独语义（目前明确不支持）。
- 本目录是“非空目录”样本；未覆盖空目录、符号链接目录、权限受限目录等变体。

3. 改进建议
- 在场景 runner 增加“可选退出码断言”机制：允许部分负向场景同时断言失败退出码与最终状态。
- 增加目录类型错误的细分 fixture（空目录/符号链接/权限不足），提高跨平台一致性保障。
- 统一错误输出策略：在保留用户友好文案的同时附带底层 `os error` 摘要，提升可诊断性。
