# codex-windows-sandbox-setup.manifest 研究文档

## 场景与职责

`codex-windows-sandbox-setup.manifest` 是 Windows 应用程序清单文件（Application Manifest），用于 `codex-windows-sandbox-setup.exe` 可执行文件。该文件在编译时通过 `build.rs` 嵌入到可执行文件中，控制 Windows 用户账户控制（UAC）行为和应用程序的权限请求方式。

## 功能点目的

### 1. UAC 执行级别控制
清单文件的核心功能是声明应用程序所需的执行权限级别，影响 Windows UAC（用户账户控制）的行为：

| 执行级别 | 说明 | 使用场景 |
|---------|------|---------|
| `asInvoker` | 以调用者的权限级别运行 | 不需要强制管理员权限 |
| `requireAdministrator` | 强制要求管理员权限 | 必须管理员才能运行 |
| `highestAvailable` | 使用调用者可用的最高权限 | 提升如果可能，否则以当前权限运行 |

### 2. UI 访问控制
`uiAccess` 属性控制应用程序是否可以绕过 UI 保护级别：
- `false`: 标准应用程序，受 UI 保护限制
- `true`: 辅助技术应用程序（如屏幕阅读器），需要签名和特定安装位置

### 3. 应用程序标识
清单文件还用于：
- 声明应用程序兼容性（Windows 版本兼容性）
- DPI 感知设置（高 DPI 显示支持）
- 长路径支持（Windows 10 1607+）

## 具体技术实现

### 清单文件内容
```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
```

### XML 结构解析

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
```
- XML 声明，指定版本、编码和独立标志
- `standalone="yes"` 表示不依赖外部 DTD

```xml
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
```
- 根元素，声明 Microsoft 程序集命名空间
- `manifestVersion="1.0"` 是标准版本

```xml
<trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
```
- 信任信息命名空间（注意是 v2）
- 包含安全相关的配置

```xml
<security>
  <requestedPrivileges>
    <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
  </requestedPrivileges>
</security>
```
- `requestedPrivileges`: 请求的权限集合
- `requestedExecutionLevel`: 执行权限级别
- `uiAccess`: UI 访问权限

### 嵌入机制
清单通过 `build.rs` 嵌入到可执行文件：

```rust
// build.rs
fn main() {
    let mut res = winres::WindowsResource::new();
    res.set_manifest_file("codex-windows-sandbox-setup.manifest");
    let _ = res.compile();
}
```

编译后，清单作为 RT_MANIFEST 资源（资源 ID 通常为 1）嵌入到 PE 文件中。

## 关键代码路径与文件引用

### 文件关系图
```
codex-windows-sandbox-setup.manifest
    │
    ├── 被 build.rs 读取
    │       └── winres::WindowsResource::set_manifest_file()
    │
    ├── 被 Bazel 跟踪
    │       └── BUILD.bazel 中的 build_script_data
    │
    └── 嵌入到 codex-windows-sandbox-setup.exe
            └── 作为 RT_MANIFEST 资源
```

### 引用点
| 文件 | 引用方式 | 用途 |
|------|---------|------|
| `build.rs` | `set_manifest_file("codex-windows-sandbox-setup.manifest")` | 构建时嵌入 |
| `BUILD.bazel` | `build_script_data = ["codex-windows-sandbox-setup.manifest"]` | Bazel 依赖跟踪 |

### 运行时行为
虽然清单指定 `asInvoker`，但实际的权限提升通过代码显式控制：

```rust
// src/setup_orchestrator.rs (简化)
fn run_setup_exe(payload: &ElevationPayload, needs_elevation: bool, ...) {
    if !needs_elevation {
        // 非提权模式：直接运行
        Command::new(&exe).arg(&payload_b64).status()
    } else {
        // 提权模式：使用 ShellExecuteExW 请求提升
        let verb_w = crate::winutil::to_wide("runas");  // "runas" verb 触发 UAC
        let mut sei: SHELLEXECUTEINFOW = ...;
        sei.lpVerb = verb_w.as_ptr();  // 请求提升
        unsafe { ShellExecuteExW(&mut sei) }
    }
}
```

## 依赖与外部交互

### Windows UAC 系统
清单文件与 Windows UAC 系统交互：

```
用户运行 codex-windows-sandbox-setup.exe
    │
    ├── Windows 读取嵌入的清单
    │       └── 发现 requestedExecutionLevel="asInvoker"
    │
    ├── 检查是否包含 "runas" verb（代码中设置）
    │       ├── 是 → 显示 UAC 提示
    │       └── 否 → 以当前权限运行
    │
    └── 执行应用程序
```

### 与代码的协作
| 机制 | 控制方 | 行为 |
|------|--------|------|
| 清单 `asInvoker` | 清单文件 | 不强制 UAC 提示 |
| `ShellExecuteExW` + `runas` | 代码 | 显式请求 UAC 提升 |
| `CreateProcess` | 代码 | 以当前权限运行 |

这种设计允许灵活控制：
- **刷新模式** (`refresh_only=true`): 不需要提权，直接运行
- **完整设置模式**: 通过 `runas` 显式请求管理员权限

### 安全上下文
```
┌─────────────────────────────────────────────────────────────┐
│  Administrator (管理员)                                      │
│  ├── 可以创建用户账户                                        │
│  ├── 可以修改系统 ACL                                       │
│  └── 可以配置防火墙规则                                      │
│                                                              │
│  codex-windows-sandbox-setup.exe (需要此权限级别)            │
│  └── 创建：CodexSandboxOffline, CodexSandboxOnline 用户     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Standard User (标准用户)                                    │
│                                                              │
│  codex-command-runner.exe (在此上下文中运行)                 │
│  └── 受限 Token，只能访问允许的路径                          │
└─────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 风险点

1. **权限提升路径不一致**:
   - 清单指定 `asInvoker`，但代码中可能请求 `runas`
   - 这可能导致安全审计时的困惑
   - **建议**: 添加注释说明设计意图

2. **清单被忽略的风险**:
   - 如果 `build.rs` 失败或被跳过，可执行文件可能没有清单
   - Windows 会应用默认的 UAC 行为（通常是 `asInvoker`）

3. **兼容性考虑**:
   - 旧版 Windows（如 Windows 7）可能不完全支持所有清单功能
   - 需要测试不同 Windows 版本的行为

### 边界条件

| 场景 | 行为 |
|------|------|
| 清单缺失 | Windows 默认行为（asInvoker） |
| 清单格式错误 | 应用程序可能无法启动 |
| 用户拒绝 UAC | `ShellExecuteExW` 返回错误代码 1223 (ERROR_CANCELLED) |
| 非管理员用户 | 需要管理员凭据才能继续 |

### 改进建议

1. **添加兼容性声明**:
   ```xml
   <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
   <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
     <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
       <application>
         <!-- Windows 10 -->
         <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
         <!-- Windows 8.1 -->
         <supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}"/>
       </application>
     </compatibility>
     <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
       <security>
         <requestedPrivileges>
           <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
         </requestedPrivileges>
       </security>
     </trustInfo>
   </assembly>
   ```

2. **添加长路径支持**（Windows 10 1607+）:
   ```xml
   <application xmlns="urn:schemas-microsoft-com:asm.v3">
     <windowsSettings>
       <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
     </windowsSettings>
   </application>
   ```

3. **添加 DPI 感知**:
   ```xml
   <application xmlns="urn:schemas-microsoft-com:asm.v3">
     <windowsSettings>
       <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
       <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">permonitorv2,permonitor,system</dpiAwareness>
     </windowsSettings>
   </application>
   ```

4. **考虑使用 requireAdministrator**:
   如果设置工具几乎总是需要管理员权限，可以考虑：
   ```xml
   <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
   ```
   
   **利弊分析**:
   - **优点**: 用户双击时自动触发 UAC，不需要代码处理
   - **缺点**: 即使是刷新模式也需要管理员权限，不够灵活
   
   **当前设计（asInvoker + 代码控制）更灵活**，推荐保持。

5. **添加版本信息**:
   可以考虑在清单中包含程序集版本信息：
   ```xml
   <assemblyIdentity 
     version="1.0.0.0"
     processorArchitecture="*"
     name="OpenAI.CodexWindowsSandboxSetup"
     type="win32"
   />
   ```

### 调试和验证

验证清单是否正确嵌入：
```powershell
# 使用 PowerShell 查看 PE 文件中的清单
[System.Reflection.Assembly]::LoadFile("C:\path\to\codex-windows-sandbox-setup.exe").GetManifestResourceStream("1").Read

# 或使用 mt.exe（Visual Studio 工具）
mt.exe -inputresource:codex-windows-sandbox-setup.exe;#1 -out:extracted.manifest
```

检查 UAC 行为：
```powershell
# 查看可执行文件的 UAC 设置
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
```
