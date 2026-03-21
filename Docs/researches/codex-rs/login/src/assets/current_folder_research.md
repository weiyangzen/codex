# Research: codex-rs/login/src/assets

## 概述

`codex-rs/login/src/assets` 目录包含 Codex CLI 登录流程中使用的静态 HTML 模板文件。这些文件是本地 OAuth 回调服务器 (`server.rs`) 向用户展示登录结果（成功或失败）的 UI 资源。

---

## 场景与职责

### 核心场景

该目录服务于 **Codex CLI 的浏览器登录流程**（Browser-based Login Flow）：

1. **成功场景**：用户通过浏览器完成 OAuth 授权后，被重定向到本地服务器 (`http://localhost:1455/success`)，展示 `success.html` 页面
2. **失败场景**：登录过程中出现错误（如权限拒绝、状态不匹配、token 交换失败等），展示 `error.html` 页面

### 职责定位

| 职责 | 说明 |
|------|------|
| **用户反馈** | 提供视觉友好的登录结果反馈，替代纯文本响应 |
| **品牌一致性** | 使用 OpenAI/Codex 品牌标识和设计风格 |
| **动态内容注入** | 通过模板变量 (`__ERROR_TITLE__`, `__ERROR_MESSAGE__` 等) 动态填充内容 |
| **可选重定向** | 成功页面支持自动跳转到组织设置页面（如需完成 onboarding） |

---

## 功能点目的

### 1. success.html - 登录成功页面

**文件路径**: `codex-rs/login/src/assets/success.html` (198 行)

**核心功能**:
- 显示 "Signed in to Codex" 成功消息
- 展示 Codex logo 和品牌标识
- **条件重定向逻辑**：通过 JavaScript 检测 `needs_setup` 参数
  - 若用户需要完成组织设置（新组织所有者），显示倒计时重定向到 `platform.openai.com/org-setup`
  - 否则显示 "You may now close this page"
- 从 URL 参数提取并传递：`id_token`, `org_id`, `project_id`, `plan_type`, `platform_url`

**关键设计元素**:
- 内嵌 SVG logo（Base64 编码的 favicon）
- CSS 变量支持暗色/亮色主题 (`var(--text-primary, #0D0D0D)`)
- 响应式布局（flexbox + 居中）

### 2. error.html - 登录错误页面

**文件路径**: `codex-rs/login/src/assets/error.html` (122 行)

**核心功能**:
- 显示结构化的错误信息卡片
- 支持模板变量替换：
  - `__ERROR_TITLE__` - 错误标题
  - `__ERROR_MESSAGE__` - 用户友好的错误描述
  - `__ERROR_CODE__` - 错误代码（如 `access_denied`）
  - `__ERROR_DESCRIPTION__` - 详细错误描述
  - `__ERROR_HELP__` - 帮助文本/操作建议

**特殊处理**:
- 针对 `missing_codex_entitlement` 错误有特殊文案：
  - 标题变为 "You do not have access to Codex"
  - 提示联系 workspace 管理员

**设计特点**:
- 渐变背景 (`radial-gradient`)
- 卡片式布局（圆角 + 阴影）
- 等宽字体显示技术细节（error code, details）

---

## 具体技术实现

### 模板渲染机制

两个 HTML 文件均通过 Rust 的 `include_str!` 宏在编译时嵌入二进制：

```rust
// server.rs 第 393 行
"/success" => {
    let body = include_str!("assets/success.html");
    HandledRequest::ResponseAndExit { ... }
}

// server.rs 第 1007 行
fn render_login_error_page(...) -> Vec<u8> {
    let template = include_str!("assets/error.html");
    template
        .replace("__ERROR_TITLE__", &html_escape(&title))
        .replace("__ERROR_MESSAGE__", &html_escape(&display_message))
        .replace("__ERROR_CODE__", &html_escape(code))
        .replace("__ERROR_DESCRIPTION__", &html_escape(&display_description))
        .replace("__ERROR_HELP__", &html_escape(&help_text))
        .into_bytes()
}
```

### 安全处理

**HTML 转义** (`server.rs` 第 1038-1051 行):
```rust
fn html_escape(input: &str) -> String {
    let mut escaped = String::with_capacity(input.len());
    for ch in input.chars() {
        match ch {
            '&' => escaped.push_str("&amp;"),
            '<' => escaped.push_str("&lt;"),
            '>' => escaped.push_str("&gt;"),
            '"' => escaped.push_str("&quot;"),
            '\'' => escaped.push_str("&#39;"),
            _ => escaped.push(ch),
        }
    }
    escaped
}
```

**目的**: 防止 XSS 攻击，确保动态注入的内容不会破坏 HTML 结构或执行恶意脚本。

### 成功页面的动态逻辑

```javascript
// success.html 第 159-194 行
const params = new URLSearchParams(window.location.search);
const needsSetup = params.get('needs_setup') === 'true';
const platformUrl = params.get('platform_url') || 'https://platform.openai.com';
const orgId = params.get('org_id');
const projectId = params.get('project_id');
const planType = params.get('plan_type');
const idToken = params.get('id_token');

if (needsSetup) {
    // 构建重定向 URL: /org-setup?p=planType&t=idToken&with_org=orgId&project_id=projectId
    // 3 秒倒计时后自动跳转
}
```

---

## 关键代码路径与文件引用

### 调用链

```
用户浏览器
    ↓ (OAuth callback)
server.rs /auth/callback 处理器
    ↓ (登录成功)
server.rs compose_success_url() 构建重定向 URL
    ↓
浏览器重定向到 /success
    ↓
server.rs /success 路由返回 success.html
    ↓ (或登录失败)
server.rs render_login_error_page() 渲染 error.html
```

### 关键文件引用

| 引用位置 | 文件 | 用途 |
|---------|------|------|
| `server.rs:393` | `success.html` | 成功页面响应 |
| `server.rs:1007` | `error.html` | 错误页面模板 |
| `server.rs:788-834` | `compose_success_url()` | 构建带参数的成功 URL |
| `server.rs:1002-1035` | `render_login_error_page()` | 渲染错误页面 |

### BUILD.bazel 配置

需确保 HTML 文件被包含在编译依赖中：
```bazel
rust_library(
    name = "login",
    srcs = glob(["src/**/*.rs"]),
    compile_data = glob(["src/assets/**/*"]),  # 关键配置
    ...
)
```

---

## 依赖与外部交互

### 内部依赖

| 依赖 | 说明 |
|------|------|
| `server.rs` | 主要调用方，处理 HTTP 路由和模板渲染 |
| `lib.rs` | 模块声明 (`mod server;`) |
| `codex-core` | 提供 `AuthDotJson`, `TokenData`, `save_auth` 等认证逻辑 |

### 外部交互

| 交互方 | 说明 |
|--------|------|
| **用户浏览器** | 渲染 HTML 页面，执行 JavaScript |
| **platform.openai.com** | 成功页面可能重定向到的组织设置页面 |
| **OAuth 授权服务器** | 登录流程的发起方 (auth.openai.com) |

### 无运行时依赖

HTML 文件是静态资源：
- 无外部 CSS/JS CDN 依赖（全部内联）
- 无图片资源依赖（SVG 内联或 Base64 编码）
- 无字体依赖（使用系统字体栈）

---

## 风险、边界与改进建议

### 当前风险

1. **模板变量硬编码**
   - 风险：变量名拼写错误（如 `__ERROR_TITLE__` vs `__ERROR_TILE__`）会导致替换失败，用户看到原始模板文本
   - 缓解：单元测试覆盖错误页面渲染 (`login_server_e2e.rs` 第 259-323 行)

2. **JavaScript 依赖**
   - 风险：用户禁用 JavaScript 时，`success.html` 的重定向逻辑失效
   - 现状：有 `<noscript>` 降级显示 "You may now close this page"

3. **XSS 防护依赖手动转义**
   - 风险：若忘记调用 `html_escape`，注入内容可能包含 `<script>` 标签
   - 现状：所有动态内容均经过转义

### 边界情况

| 场景 | 行为 |
|------|------|
| URL 参数缺失 | `success.html` 使用默认值（如 `platform_url` 默认为 `https://platform.openai.com`） |
| 超大错误消息 | `html_escape` 预分配容量，但超长文本可能破坏布局 |
| 非浏览器访问 | 返回纯 HTML，无 API JSON 响应 |

### 改进建议

1. **模板引擎迁移**
   - 当前：字符串替换 (`String::replace`)
   - 建议：使用轻量级模板引擎（如 `handlebars` 或 `tera`）
   - 收益：类型安全、自动转义、模板预编译

2. **国际化 (i18n) 支持**
   - 当前：硬编码英文文本
   - 建议：提取字符串到资源文件，支持多语言

3. **无障碍 (a11y) 增强**
   - 当前：基本 `aria-hidden` 使用
   - 建议：添加 `role="alert"` 到错误消息，增强屏幕阅读器支持

4. **测试覆盖**
   - 当前：E2E 测试验证页面内容包含特定字符串
   - 建议：添加快照测试（snapshot testing）验证完整 HTML 输出

5. **构建时验证**
   - 建议：在 CI 中验证 HTML 文件存在且语法有效（使用 `html-validate` 等工具）

---

## 附录：文件清单

```
codex-rs/login/src/assets/
├── error.html   # 122 行 - 登录错误页面模板
└── success.html # 198 行 - 登录成功页面模板
```

## 附录：相关测试

```
codex-rs/login/tests/
├── suite/login_server_e2e.rs  # E2E 测试（验证成功/失败页面内容）
└── suite/device_code_login.rs # 设备码登录测试
```

关键测试用例：
- `oauth_access_denied_missing_entitlement_blocks_login_with_clear_error` - 验证错误页面显示特定文案
- `oauth_access_denied_unknown_reason_uses_generic_error_page` - 验证通用错误处理
- `end_to_end_login_flow_persists_auth_json` - 验证成功流程
