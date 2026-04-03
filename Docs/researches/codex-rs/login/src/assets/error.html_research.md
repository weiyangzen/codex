# error.html 深度研究文档

## 场景与职责

`error.html` 是 Codex CLI 登录流程中的**错误页面模板**，用于在 OAuth 回调失败时向用户展示友好的错误信息。它是登录服务器 (`codex-rs/login/src/server.rs`) 在浏览器登录流程失败时返回给用户的最终 HTML 响应。

### 核心职责

1. **用户友好的错误展示**：将技术性的 OAuth 错误转换为可读的、品牌化的错误页面
2. **安全信息脱敏**：通过模板变量注入错误信息，避免在 HTML 中硬编码敏感内容
3. **品牌一致性**：使用 Codex/OpenAI 品牌元素（Logo、配色、字体）保持视觉一致性
4. **诊断信息保留**：在保护用户体验的同时，保留足够的技术细节供排查问题

### 使用场景

- OAuth 授权码交换失败
- 状态参数不匹配（CSRF 防护）
- 缺少 Codex 权限（`missing_codex_entitlement`）
- Token 持久化失败
- 工作区限制不匹配

---

## 功能点目的

### 1. 模板变量替换机制

页面包含 5 个模板变量，由 `server.rs` 中的 `render_login_error_page()` 函数在运行时替换：

| 变量 | 用途 | 注入内容 |
|------|------|----------|
| `__ERROR_TITLE__` | 页面主标题 | 根据错误类型动态生成 |
| `__ERROR_MESSAGE__` | 错误摘要 | 用户友好的错误描述 |
| `__ERROR_CODE__` | 错误代码 | OAuth 错误代码或内部代码 |
| `__ERROR_DESCRIPTION__` | 详细描述 | 技术细节或解决方案 |
| `__ERROR_HELP__` | 帮助文本 | 下一步操作建议 |

### 2. 特殊错误处理：Codex 权限缺失

针对 `missing_codex_entitlement` 错误有特殊处理逻辑：

```rust
// server.rs:1009-1027
if is_missing_codex_entitlement_error(code, error_description) {
    (
        "You do not have access to Codex".to_string(),
        "This account is not currently authorized to use Codex in this workspace.".to_string(),
        "Contact your workspace administrator to request access to Codex.".to_string(),
        "Contact your workspace administrator to get access to Codex..."
    )
}
```

这种错误通常发生在：
- 用户所属的工作区未启用 Codex 功能
- 用户需要联系管理员申请权限

### 3. HTML 转义安全

所有注入模板的内容都经过 `html_escape()` 函数处理，防止 XSS 攻击：

```rust
fn html_escape(input: &str) -> String {
    match ch {
        '&' => escaped.push_str("&amp;"),
        '<' => escaped.push_str("&lt;"),
        '>' => escaped.push_str("&gt;"),
        '"' => escaped.push_str("&quot;"),
        '\'' => escaped.push_str("&#39;"),
        _ => escaped.push(ch),
    }
}
```

---

## 具体技术实现

### 1. 页面结构与样式

#### 视觉设计
- **布局**：居中卡片式布局，最大宽度 680px
- **背景**：径向渐变背景（`#f7f8fb` → `#ffffff`）
- **卡片**：白色背景、圆角 16px、阴影效果
- **配色**：主文本 `#0d0d0d`，次要文本 `#5d5d5d`

#### 关键 CSS 类
```css
.container      /* 全屏居中容器 */
.card           /* 白色卡片主体 */
.brand          /* Logo + 品牌标题 */
.details        /* 错误详情区域（灰色背景） */
.details-row    /* 键值对布局（136px + 1fr） */
```

### 2. 内联资源

#### Favicon（内联 SVG）
使用 Data URI 嵌入 Codex Logo，避免外部请求：
```html
<link rel="icon" href='data:image/svg+xml,%3Csvg...' type="image/svg+xml">
```

#### Logo SVG
页面主体中的 Logo 使用内联 SVG，确保离线可用：
```html
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"...>
  <path stroke="#000" stroke-linecap="round" stroke-width="2.484".../>
</svg>
```

### 3. 响应式与兼容性

- **视口适配**：`min-height: 100vh` 确保全屏覆盖
- **字体栈**：`system-ui, -apple-system, BlinkMacSystemFont...` 跨平台兼容
- **代码换行**：`word-break: break-all` 防止长错误代码溢出

---

## 关键代码路径与文件引用

### 渲染调用链

```
server.rs:process_request() 
  → 匹配 "/auth/callback" 路径
    → OAuth 错误检查 (line 297-311)
    → Token 交换失败 (line 380-389)
    → 工作区限制失败 (line 329-339)
    → 持久化失败 (line 345-362)
  → login_error_response() (line 889-905)
    → render_login_error_page() (line 1002-1035)
      → include_str!("assets/error.html") (line 1007)
      → template.replace() 填充变量
```

### 核心代码位置

| 文件 | 函数/代码 | 职责 |
|------|----------|------|
| `server.rs:1002-1035` | `render_login_error_page()` | 渲染错误页面 |
| `server.rs:1037-1051` | `html_escape()` | HTML 转义 |
| `server.rs:907-930` | `oauth_callback_error_message()` | 错误消息映射 |
| `server.rs:888-905` | `login_error_response()` | 构建错误响应 |

### BUILD.bazel 配置

```bazel
codex_rust_crate(
    name = "login",
    crate_name = "codex_login",
    compile_data = [
        "src/assets/error.html",    # 编译时嵌入
        "src/assets/success.html",
    ],
)
```

`compile_data` 确保 HTML 文件在编译时可用，`include_str!` 宏将其嵌入二进制。

---

## 依赖与外部交互

### 1. 编译时依赖

| 依赖 | 用途 |
|------|------|
| `include_str!` | 编译时将 HTML 文件内容嵌入 Rust 二进制 |
| `BUILD.bazel` | 声明 `compile_data` 依赖，确保 Bazel 构建时文件可用 |

### 2. 运行时交互

| 交互方 | 方向 | 内容 |
|--------|------|------|
| 浏览器 | ← 输出 | HTTP 200 响应，Content-Type: text/html; charset=utf-8 |
| OAuth 回调 | → 输入 | error, error_description 查询参数 |
| 日志系统 | → 输出 | 结构化日志（不包含敏感错误详情） |

### 3. 相关模块

```
codex-rs/login/
├── src/
│   ├── server.rs          # 主服务器逻辑，调用 error.html
│   ├── device_code_auth.rs # 设备码登录（不使用此页面）
│   └── assets/
│       ├── error.html     # 本文件
│       └── success.html   # 成功页面
├── BUILD.bazel            # 构建配置
└── Cargo.toml             # 依赖声明
```

---

## 风险、边界与改进建议

### 1. 安全风险

#### 当前防护
- ✅ HTML 转义防止 XSS
- ✅ 敏感 URL 参数脱敏（`redact_sensitive_url_parts`）
- ✅ 结构化日志与面向用户的错误分离

#### 潜在风险
- ⚠️ **错误描述长度**：`error_description` 可能包含极长文本，需确保页面布局不被破坏
- ⚠️ **Unicode 处理**：`html_escape` 仅处理 ASCII 特殊字符，非 ASCII 字符直接透传

### 2. 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 空错误代码 | 显示 "unknown_error" | ✅ 合理降级 |
| 空错误描述 | 复用 message 内容 | ✅ 优雅处理 |
| 超长错误描述 | 依赖 `word-break: break-all` | ⚠️ 可能需滚动 |
| 特殊字符 | HTML 转义处理 | ✅ 安全 |

### 3. 改进建议

#### 短期优化
1. **添加错误代码搜索链接**
   ```html
   <a href="https://help.openai.com/codex-errors?code=__ERROR_CODE__">查找解决方案</a>
   ```

2. **添加重试按钮**
   ```html
   <button onclick="location.href='/auth/callback?retry=1'">重试登录</button>
   ```

3. **深色模式支持**
   ```css
   @media (prefers-color-scheme: dark) { ... }
   ```

#### 长期优化
1. **国际化 (i18n)**
   - 当前仅支持英文
   - 建议根据浏览器语言自动切换

2. **错误代码映射表**
   - 将更多 OAuth 错误代码映射为用户友好消息
   - 如 `invalid_grant` → "登录会话已过期，请重试"

3. **诊断模式**
   - 添加 "显示技术详情" 折叠区域
   - 包含请求 ID、时间戳等调试信息

### 4. 测试覆盖

相关测试位于 `codex-rs/login/tests/suite/login_server_e2e.rs`：

- `oauth_access_denied_missing_entitlement_blocks_login_with_clear_error`：验证权限缺失错误页面
- `oauth_access_denied_unknown_reason_uses_generic_error_page`：验证通用错误页面

测试断言检查：
- 页面包含预期标题
- 包含管理员联系指引
- 包含原始错误代码
- 不包含内部错误描述（如 `missing_codex_entitlement`）

---

## 总结

`error.html` 是 Codex CLI 登录体验的关键组成部分，在 OAuth 失败时提供：

1. **清晰的用户沟通**：将技术错误转换为用户可理解的语言
2. **品牌一致性**：保持与 OpenAI/Codex 品牌相符的视觉设计
3. **安全与隐私**：通过转义和脱敏保护用户信息
4. **可维护性**：模板化设计便于更新和扩展

该文件虽简单，但在用户首次接触 Codex CLI 的登录流程中扮演着重要的"最后一道防线"角色。
