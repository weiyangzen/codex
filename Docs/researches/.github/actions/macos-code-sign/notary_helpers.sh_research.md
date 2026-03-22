# notary_helpers.sh 研究文档

## 场景与职责

`notary_helpers.sh` 是一个 Bash 脚本库，为 `macos-code-sign` GitHub Action 提供 Apple 公证（Notarization）相关的辅助函数。该脚本被设计为可复用的函数库，通过 `source` 命令在 Action 的多个步骤中加载使用。

### 核心职责
1. **封装公证提交流程**：提供统一的 `notarize_submission` 函数
2. **处理公证状态解析**：解析 `notarytool` 的 JSON 输出
3. **错误处理和报告**：在公证失败时提供清晰的错误信息
4. **集成 GitHub Actions**：使用 GitHub 的 notice 注解显示公证结果

### 使用场景
该脚本在 `action.yml` 中被加载两次：
1. **二进制公证步骤**（行 165）：`source "$GITHUB_ACTION_PATH/notary_helpers.sh"`
2. **DMG 公证步骤**（行 211）：同上

---

## 功能点目的

### notarize_submission 函数

**函数签名**：
```bash
notarize_submission() {
  local label="$1"      # 提交标签（用于日志识别）
  local path="$2"       # 待公证文件路径
  local notary_key_path="$3"  # P8 格式公证密钥路径
}
```

**目的**：将指定文件提交给 Apple Notary Service 进行公证，并同步等待结果。

**前置条件检查**：
1. 验证 `APPLE_NOTARIZATION_KEY_ID` 环境变量存在
2. 验证 `APPLE_NOTARIZATION_ISSUER_ID` 环境变量存在
3. 验证密钥文件存在且可读
4. 验证待公证文件存在

**核心流程**：
1. 调用 `xcrun notarytool submit` 提交文件
2. 使用 `--output-format json` 获取结构化输出
3. 使用 `--wait` 同步等待公证完成
4. 解析 JSON 提取 `status` 和 `id`
5. 输出 GitHub Actions notice 注解
6. 验证状态为 `Accepted`，否则退出

---

## 具体技术实现

### 环境变量依赖

| 变量名 | 来源 | 用途 |
|--------|------|------|
| `APPLE_NOTARIZATION_KEY_ID` | Action 输入 | Apple Developer 密钥标识符 |
| `APPLE_NOTARIZATION_ISSUER_ID` | Action 输入 | Apple Developer 团队 Issuer ID |

### notarytool 调用

```bash
xcrun notarytool submit "$path" \
  --key "$notary_key_path" \
  --key-id "$APPLE_NOTARIZATION_KEY_ID" \
  --issuer "$APPLE_NOTARIZATION_ISSUER_ID" \
  --output-format json \
  --wait
```

**参数说明**：
- `--key`：P8 格式的私钥文件路径
- `--key-id`：App Store Connect API 密钥 ID（10 字符）
- `--issuer`：App Store Connect Issuer ID（UUID 格式）
- `--output-format json`：输出 JSON 格式便于解析
- `--wait`：阻塞直到公证完成（成功或失败）

### JSON 输出解析

```bash
local status submission_id
status=$(printf '%s\n' "$submission_json" | jq -r '.status // "Unknown"')
submission_id=$(printf '%s\n' "$submission_json" | jq -r '.id // ""')
```

**预期 JSON 结构**：
```json
{
  "message": "Successfully uploaded file",
  "id": "2efe0f31-5b5b-4b1b-8e1e-1e1e1e1e1e1e",
  "path": "/path/to/file.zip",
  "status": "Accepted"
}
```

**可能的状态值**：
- `Accepted`：公证通过
- `Invalid`：公证失败（包存在问题）
- `In Progress`：正在处理（使用 `--wait` 时不会返回此状态）

### GitHub Actions 集成

```bash
echo "::notice title=Notarization::$label submission ${submission_id} completed with status ${status}"
```

这会在 GitHub Actions 日志中生成一个可点击的 notice 注解，显示在 PR 或工作流运行摘要中。

### 错误处理

| 错误场景 | 处理方式 |
|---------|---------|
| 缺少环境变量 | 输出错误信息，退出码 1 |
| 密钥文件不存在 | 输出错误信息，退出码 1 |
| 待公证文件不存在 | 输出错误信息，退出码 1 |
| 无法获取 submission ID | 输出错误信息，退出码 1 |
| 状态不是 `Accepted` | 输出包含 submission ID 的错误信息，退出码 1 |

---

## 关键代码路径与文件引用

### 当前文件
- **路径**：`.github/actions/macos-code-sign/notary_helpers.sh`
- **类型**：Bash 函数库脚本
- **行数**：46 行

### 调用方
- **`.github/actions/macos-code-sign/action.yml`**：
  - 第 165 行：`source "$GITHUB_ACTION_PATH/notary_helpers.sh"`（二进制公证步骤）
  - 第 211 行：`source "$GITHUB_ACTION_PATH/notary_helpers.sh"`（DMG 公证步骤）

### 函数调用链

```
action.yml (Sign macOS binaries step)
  └── source notary_helpers.sh
        └── notarize_binary() function
              └── notarize_submission "codex" "$archive_path" "$notary_key_path"
                    └── xcrun notarytool submit ...

action.yml (Sign and notarize macOS dmg step)
  └── source notary_helpers.sh
        └── notarize_submission "$dmg_name" "$dmg_path" "$notary_key_path"
              └── xcrun notarytool submit ...
```

### 文件位置关系

```
.github/actions/macos-code-sign/
├── action.yml           # 主 Action 定义，引用 notary_helpers.sh
└── notary_helpers.sh    # 本文件，被 action.yml source
```

---

## 依赖与外部交互

### 系统依赖

| 工具 | 用途 | 来源 |
|------|------|------|
| `xcrun` | 调用 Xcode 工具链 | Xcode Command Line Tools |
| `notarytool` | Apple 公证 CLI 工具 | Xcode 13+ |
| `jq` | JSON 解析 | 需预先安装（GitHub Actions macOS runner 默认包含） |
| `printf` | 安全的字符串输出 | POSIX shell 内置 |

### Apple 服务交互

**Apple Notary Service**：
- 端点：由 `notarytool` 内部管理（无需配置）
- 认证：JWT（使用 P8 密钥 + Key ID + Issuer ID 签名）
- 协议：HTTPS

**认证流程**：
1. `notarytool` 使用 P8 密钥生成 JWT
2. JWT 包含 Issuer ID 和 Key ID
3. Apple 验证 JWT 并授权公证提交

### GitHub Actions 集成

| 功能 | 实现方式 |
|------|---------|
| 日志注解 | `echo "::notice title=Notarization::..."` |
| 错误报告 | 输出到 stderr，退出码非零 |

---

## 风险、边界与改进建议

### 已知风险

#### 1. 缺少超时控制
- **风险**：`notarytool --wait` 可能无限期阻塞（虽然罕见）
- **现状**：依赖调用方的超时机制（GitHub Actions 作业超时）
- **建议**：考虑添加 `timeout` 包装器：
  ```bash
  submission_json=$(timeout 600 xcrun notarytool submit ...)
  ```

#### 2. 缺少重试机制
- **风险**：网络瞬态故障可能导致公证提交失败
- **现状**：单次提交，失败即退出
- **建议**：添加指数退避重试：
  ```bash
  for attempt in 1 2 3; do
    if submission_json=$(xcrun notarytool submit ...); then
      break
    fi
    [[ $attempt -lt 3 ]] && sleep $((attempt * 30))
  done
  ```

#### 3. 依赖 jq 工具
- **风险**：假设 `jq` 已安装，但某些精简环境可能没有
- **现状**：直接使用 `jq` 而不检查存在性
- **缓解**：GitHub Actions macOS runner 默认包含 `jq`
- **建议**：添加存在性检查或提供 fallback 方案

#### 4. 缺少详细日志
- **风险**：公证失败时难以诊断问题
- **现状**：仅输出最终状态
- **建议**：在失败时调用 `notarytool log` 获取详细日志：
  ```bash
  if [[ "$status" != "Accepted" ]]; then
    echo "Fetching notarization log..."
    xcrun notarytool log "$submission_id" \
      --key "$notary_key_path" \
      --key-id "$APPLE_NOTARIZATION_KEY_ID" \
      --issuer "$APPLE_NOTARIZATION_ISSUER_ID"
    exit 1
  fi
  ```

### 边界条件

| 场景 | 行为 |
|------|------|
| 空 `label` | 允许，但 notice 显示效果不佳 |
| 文件路径包含空格 | 正确处理（变量引用加引号） |
| 非常大的文件 | 受限于 notarytool 和 Apple 服务限制 |
| 网络中断 | `notarytool` 会报错，函数退出 |

### 改进建议

#### 1. 添加详细日志获取
在公证失败时自动获取详细日志，帮助诊断问题：

```bash
notarize_submission() {
  # ... existing code ...
  
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization failed for ${label} (submission ${submission_id}, status ${status})"
    
    # 尝试获取详细日志
    if [[ -n "$submission_id" ]]; then
      echo "Fetching detailed log..."
      xcrun notarytool log "$submission_id" \
        --key "$notary_key_path" \
        --key-id "$APPLE_NOTARIZATION_KEY_ID" \
        --issuer "$APPLE_NOTARIZATION_ISSUER_ID" 2>&1 || true
    fi
    
    exit 1
  fi
}
```

#### 2. 支持异步公证模式
当前使用 `--wait` 同步等待，可以添加异步模式支持：

```bash
notarize_submit_async() {
  # 提交但不等待
  local submission_json
  submission_json=$(xcrun notarytool submit "$path" ... --no-wait)
  # 保存 submission_id 供后续轮询
  echo "$submission_id" > "${RUNNER_TEMP}/notary_${label}.id"
}

notarize_poll() {
  # 轮询指定 submission_id 的状态
  local submission_id="$1"
  xcrun notarytool wait "$submission_id" ...
}
```

#### 3. 添加进度指示
对于大文件，公证上传可能需要时间，可以添加进度输出：

```bash
# notarytool 本身不支持进度条，但可以通过包装实现
echo "Submitting $label for notarization..."
submission_json=$(xcrun notarytool submit "$path" ...)
echo "Upload complete, waiting for processing..."
```

#### 4. 支持 stapler 操作
虽然 stapler 在 action.yml 中直接调用，但可以考虑将 stapler 功能也封装到本脚本：

```bash
staple_artifact() {
  local path="$1"
  if ! xcrun stapler staple "$path"; then
    echo "Failed to staple $path"
    exit 1
  fi
}
```

#### 5. 添加验证函数
```bash
verify_notarization() {
  local path="$1"
  if ! xcrun spctl --assess --type open "$path" 2>/dev/null; then
    echo "Notarization verification failed for $path"
    return 1
  fi
}
```

### 与相关组件的关系

```
┌─────────────────────────────────────────────────────────────┐
│                    macos-code-sign Action                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Configure Apple code signing                         │  │
│  │  - Create keychain                                    │  │
│  │  - Import certificate                                 │  │
│  └───────────────────────────────────────────────────────┘  │
│                         ↓                                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Sign macOS binaries                                  │  │
│  │  - codesign --options runtime                         │  │
│  └───────────────────────────────────────────────────────┘  │
│                         ↓                                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Notarize macOS binaries                              │  │
│  │  - source notary_helpers.sh ◄─────────────────────┐   │  │
│  │  - notarize_submission()                          │   │  │
│  │    - xcrun notarytool submit --wait               │   │  │
│  └───────────────────────────────────────────────────────┘  │
│                         ↓                                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Sign and notarize macOS dmg                          │  │
│  │  - codesign                                           │  │
│  │  - notarize_submission() ◄──────────────────────────┘   │  │
│  │  - xcrun stapler staple                               │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 历史背景

`notarytool` 是 Apple 在 2021 年推出的新工具，用于替代旧的 `altool`：
- `altool`：已弃用，使用 Apple ID + 应用专用密码认证
- `notarytool`：现代工具，使用 App Store Connect API 密钥（P8）认证

本脚本使用 `notarytool`，符合 Apple 的最新最佳实践。
