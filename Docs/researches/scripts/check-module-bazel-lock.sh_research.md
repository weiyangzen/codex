# check-module-bazel-lock.sh 深度研究文档

## 场景与职责

`check-module-bazel-lock.sh` 是一个 Bazel 依赖锁文件检查脚本，用于确保 `MODULE.bazel.lock` 文件与 `MODULE.bazel` 中声明的依赖保持一致。该脚本是 Bazel 构建系统的配套工具，主要服务于以下场景：

1. **CI/CD 依赖一致性检查**：在持续集成中验证锁文件是否最新
2. **防止依赖漂移**：确保团队成员使用一致的依赖版本
3. **构建可复现性**：保证不同环境、不同时间的构建使用相同的依赖

### 在构建系统中的地位

该脚本是 Bazel 模块化构建系统（Bzlmod）的配套检查工具。Bazel 使用 `MODULE.bazel` 声明依赖，`MODULE.bazel.lock` 锁定具体版本。

### 在 justfile 中的集成

```just
# justfile
[no-cd]
bazel-lock-check:
    ./scripts/check-module-bazel-lock.sh
```

## 功能点目的

### 1. 锁文件新鲜度检查
- **目的**：验证 `MODULE.bazel.lock` 是否反映了 `MODULE.bazel` 的最新状态
- **机制**：使用 Bazel 的 `--lockfile_mode=error` 模式
- **失败条件**：如果锁文件过期，命令返回非零退出码

### 2. 开发者指导
- **目的**：当检查失败时，提供清晰的修复指导
- **输出**：
  ```
  MODULE.bazel.lock is out of date.
  Run 'just bazel-lock-update' and commit the updated lockfile.
  ```

## 具体技术实现

### 核心命令

```bash
bazel mod deps --lockfile_mode=error
```

#### 命令解析
- `bazel mod deps`：显示模块依赖图
- `--lockfile_mode=error`：如果锁文件需要更新，返回错误而非自动更新

### 脚本实现

```bash
#!/usr/bin/env bash
set -euo pipefail

if ! bazel mod deps --lockfile_mode=error; then
  echo "MODULE.bazel.lock is out of date."
  echo "Run 'just bazel-lock-update' and commit the updated lockfile."
  exit 1
fi
```

### 关键特性

| 特性 | 实现 |
|------|------|
| 严格错误处理 | `set -euo pipefail` |
| 条件判断 | `if ! command` 检查命令失败 |
| 用户指导 | 清晰的错误信息和修复步骤 |

## 关键代码路径与文件引用

### 脚本本身
- **路径**：`scripts/check-module-bazel-lock.sh` (8 行)
- **Shebang**：`#!/usr/bin/env bash`

### 相关文件
- **模块声明**：`MODULE.bazel` - 定义项目依赖
- **锁文件**：`MODULE.bazel.lock` - 锁定依赖的确切版本

### 调用方
- **justfile**：`just bazel-lock-check` 命令
- **潜在 CI 集成**：可在 Bazel 相关 CI 工作流中调用

### 配套命令（justfile）
```just
[no-cd]
bazel-lock-update:
    bazel mod deps --lockfile_mode=update
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 | 版本要求 |
|------|------|----------|
| Bazel | 构建系统 | 支持 Bzlmod 的版本 |
| bash | 脚本执行 | 任何现代版本 |

### Bazel 模块系统
- **Bzlmod**：Bazel 的新模块系统，替代旧的 `WORKSPACE` 系统
- **锁文件机制**：类似 npm 的 `package-lock.json` 或 Cargo 的 `Cargo.lock`

### 执行环境
- 需要安装 Bazel
- 需要在项目根目录执行（或正确配置 WORKSPACE）
- 需要 `MODULE.bazel` 和 `MODULE.bazel.lock` 文件存在

## 风险、边界与改进建议

### 已知风险

1. **Bazel 版本兼容性**
   - 风险：不同 Bazel 版本可能生成不同的锁文件格式
   - 缓解：项目应通过 `.bazelversion` 文件锁定 Bazel 版本

2. **网络依赖**
   - 风险：`bazel mod deps` 可能需要网络访问解析依赖
   - 场景：在隔离网络环境中可能失败

3. **性能问题**
   - 风险：大型项目的依赖解析可能较慢
   - 影响：CI 流水线耗时增加

### 边界情况

1. **锁文件不存在**
   - Bazel 行为：可能自动创建或报错（取决于配置）
   - 建议：确保锁文件已提交到版本控制

2. **MODULE.bazel 未修改**
   - 行为：检查快速通过
   - 性能：Bazel 会缓存依赖解析结果

3. **并发执行**
   - 风险：多个进程同时执行可能导致竞争条件
   - 缓解：CI 环境通常串行执行

### 改进建议

1. **添加详细模式**
   ```bash
   # 建议添加 verbose 选项
   if [[ "${VERBOSE:-}" == "1" ]]; then
       bazel mod deps --lockfile_mode=error --verbose
   else
       bazel mod deps --lockfile_mode=error
   fi
   ```

2. **锁文件存在性预检查**
   ```bash
   # 建议添加
   if [[ ! -f MODULE.bazel.lock ]]; then
       echo "Error: MODULE.bazel.lock not found."
       echo "Run 'just bazel-lock-update' to create it."
       exit 1
   fi
   ```

3. **Bazel 版本检查**
   ```bash
   # 建议添加版本兼容性检查
   REQUIRED_BAZEL_VERSION=$(cat .bazelversion)
   CURRENT_BAZEL_VERSION=$(bazel --version)
   ```

4. **CI 集成优化**
   - 建议：在 `.github/workflows/bazel.yml` 中明确添加此检查
   - 收益：确保每个 PR 都验证锁文件一致性

5. **错误信息国际化**
   - 建议：支持多语言错误信息（如需要）
   - 实现：通过环境变量切换语言

### 相关文档

- [Bazel Bzlmod 文档](https://bazel.build/external/module)
- [Lockfile 模式说明](https://bazel.build/external/lockfile)
- 项目内：`MODULE.bazel` 文件头部的注释说明
