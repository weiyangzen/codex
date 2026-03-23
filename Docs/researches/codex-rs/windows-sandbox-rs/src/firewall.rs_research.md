# firewall.rs 研究文档

## 场景与职责

`firewall.rs` 实现 Windows 防火墙规则管理，用于为沙箱用户创建出站网络阻断规则。这是网络隔离策略的关键组件，通过 Windows 防火墙 API 实现进程级别的网络访问控制。

该模块在以下场景中使用：
- 沙箱设置阶段创建防火墙规则
- 为离线沙箱用户阻断出站网络连接
- 确保网络隔离策略在系统层面强制执行

## 功能点目的

### 1. 出站阻断规则管理
- **`ensure_offline_outbound_block`**: 确保离线出站阻断规则存在
- 为指定 SID 的用户创建出站阻断规则
- 使用 Windows 防火墙 API（`INetFwPolicy2`, `INetFwRule3`）

### 2. 规则生命周期管理
- 规则名称固定：`codex_sandbox_offline_block_outbound`
- 支持规则更新（幂等操作）
- 规则描述：`Codex Sandbox Offline - Block Outbound`

### 3. 用户范围限定
- 使用 `LocalUserAuthorizedList` 限定规则作用范围
- 仅阻断指定 SID 的出站连接
- 不影响其他用户或系统进程

### 4. 协议覆盖
- 阻断所有 IP 协议（`NET_FW_IP_PROTOCOL_ANY`）
- 覆盖 TCP、UDP 和所有其他协议

## 具体技术实现

### 关键常量

```rust
// 规则标识（稳定，不随安装变化）
const OFFLINE_BLOCK_RULE_NAME: &str = "codex_sandbox_offline_block_outbound";
const OFFLINE_BLOCK_RULE_FRIENDLY: &str = "Codex Sandbox Offline - Block Outbound";

// SDDL 格式的用户授权列表
// O:LS - 所有者: 本地系统
// D:(A;;CC;;;{offline_sid}) - DACL: 允许 CC（通用连接）给指定 SID
let local_user_spec = format!("O:LSD:(A;;CC;;;{offline_sid})");
```

### 执行流程

```
ensure_offline_outbound_block(offline_sid, log)
  └─> format!("O:LSD:(A;;CC;;;{offline_sid})") -> local_user_spec
  └─> CoInitializeEx(None, COINIT_APARTMENTTHREADED)
  │     └─> 如果失败: 返回 COM 初始化错误
  └─> (|| -> Result<()> {
  │     CoCreateInstance(NetFwPolicy2) -> policy
  │     policy.Rules() -> rules
  │     ensure_block_rule(
  │         &rules,
  │         OFFLINE_BLOCK_RULE_NAME,
  │         OFFLINE_BLOCK_RULE_FRIENDLY,
  │         NET_FW_IP_PROTOCOL_ANY.0,
  │         &local_user_spec,
  │         offline_sid,
  │         log
  │     )
  │ })()
  └─> CoUninitialize()
  └─> 返回结果
```

### 规则创建/更新流程

```
ensure_block_rule(rules, internal_name, friendly_desc, protocol, local_user_spec, offline_sid, log)
  └─> rules.Item(&name) -> 尝试获取现有规则
  └─> 如果存在:
  │     └─> cast::<INetFwRule3>() -> rule
  └─> 如果不存在:
  │     └─> CoCreateInstance(NetFwRule) -> new_rule
  │     └─> new_rule.SetName(&name)
  │     └─> configure_rule(...) // 预配置
  │     └─> rules.Add(&new_rule)
  │     └─> new_rule -> rule
  └─> configure_rule(&rule, friendly_desc, protocol, local_user_spec, offline_sid)
  │     └─> SetDescription
  │     └─> SetDirection(NET_FW_RULE_DIR_OUT)
  │     └─> SetAction(NET_FW_ACTION_BLOCK)
  │     └─> SetEnabled(VARIANT_TRUE)
  │     └─> SetProfiles(NET_FW_PROFILE2_ALL)
  │     └─> SetProtocol(protocol)
  │     └─> SetLocalUserAuthorizedList(local_user_spec)
  │     └─> 读取验证 LocalUserAuthorizedList 包含 offline_sid
  └─> log_line(log, "firewall rule configured ...")
  └─> Ok(())
```

### 规则配置详情

```rust
fn configure_rule(
    rule: &INetFwRule3,
    friendly_desc: &str,
    protocol: i32,
    local_user_spec: &str,
    offline_sid: &str,
) -> Result<()> {
    unsafe {
        rule.SetDescription(&BSTR::from(friendly_desc))?;
        rule.SetDirection(NET_FW_RULE_DIR_OUT)?;        // 出站
        rule.SetAction(NET_FW_ACTION_BLOCK)?;           // 阻断
        rule.SetEnabled(VARIANT_TRUE)?;                 // 启用
        rule.SetProfiles(NET_FW_PROFILE2_ALL.0)?;       // 所有配置文件
        rule.SetProtocol(protocol)?;                     // 所有协议
        rule.SetLocalUserAuthorizedList(&BSTR::from(local_user_spec))?;
    }
    
    // 读取验证
    let actual = unsafe { rule.LocalUserAuthorizedList() }?;
    let actual_str = actual.to_string();
    if !actual_str.contains(offline_sid) {
        return Err(SetupFailure::new(
            SetupErrorCode::HelperFirewallRuleVerifyFailed,
            format!("offline firewall rule user scope mismatch...")
        ));
    }
    Ok(())
}
```

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 场景 |
|--------|------|
| `setup_orchestrator.rs` | 沙箱设置阶段创建防火墙规则 |

### 代码引用路径

```
codex-rs/windows-sandbox-rs/src/firewall.rs
  ├─> 依赖: codex_windows_sandbox::SetupErrorCode, SetupFailure
  └─> Windows API: windows crate (Win32::NetworkManagement::WindowsFirewall)
```

## 依赖与外部交互

### 内部依赖
- **`codex_windows_sandbox`**: `SetupErrorCode`, `SetupFailure` 错误类型

### 外部依赖
- **windows crate**（非 windows-sys）：使用 COM 接口需要
  - `windows::Win32::NetworkManagement::WindowsFirewall`: 防火墙 API
  - `windows::Win32::System::Com`: COM 初始化
  - `windows::core::BSTR`: COM 字符串类型

### Windows API 使用

| API | 用途 |
|-----|------|
| `CoInitializeEx` | 初始化 COM（单元线程模式） |
| `CoCreateInstance` | 创建防火墙策略/规则对象 |
| `CoUninitialize` | 清理 COM |
| `INetFwPolicy2::Rules` | 获取规则集合 |
| `INetFwRules::Item` | 获取现有规则 |
| `INetFwRules::Add` | 添加新规则 |
| `INetFwRule3` 接口 | 配置规则属性 |

### COM 接口

| 接口 | 用途 |
|------|------|
| `INetFwPolicy2` | 防火墙策略管理 |
| `INetFwRules` | 规则集合操作 |
| `INetFwRule3` | 规则属性配置（需要 Windows Vista+） |

## 风险、边界与改进建议

### 安全风险

1. **防火墙服务依赖**
   - 依赖 Windows 防火墙服务运行
   - 如果服务停止，规则不生效
   - 建议：检查服务状态并警告用户

2. **管理员权限要求**
   - 修改防火墙规则需要管理员权限
   - 非提升进程无法调用此功能
   - 当前设计符合（仅在设置阶段调用）

3. **规则冲突**
   - 如果存在其他允许规则，可能优先于阻断规则
   - Windows 防火墙规则评估顺序复杂
   - 建议：文档化规则优先级建议

4. **COM 安全**
   - 使用 `COINIT_APARTMENTTHREADED`
   - 确保在 STA 线程调用
   - 当前实现正确，但需注意调用上下文

### 边界条件

| 边界 | 处理 |
|------|------|
| COM 初始化失败 | 返回 `HelperFirewallComInitFailed` |
| 策略访问失败 | 返回 `HelperFirewallPolicyAccessFailed` |
| 规则创建失败 | 返回 `HelperFirewallRuleCreateOrAddFailed` |
| 验证失败 | 返回 `HelperFirewallRuleVerifyFailed` |
| 规则已存在 | 更新配置（幂等） |
| 非 Windows | 模块被条件编译排除（`#![cfg(target_os = "windows")]`） |

### 改进建议

1. **服务状态检查**
   ```rust
   // 在 CoInitializeEx 后检查防火墙服务状态
   use windows::Win32::System::Services::{OpenSCManagerW, OpenServiceW, QueryServiceStatus};
   // 如果服务未运行，返回特定错误建议用户启动
   ```

2. **规则优先级管理**
   ```rust
   // 当前: 不设置优先级
   // 建议: 设置较高优先级确保阻断生效
   rule.SetGrouping(&BSTR::from("Codex Sandbox"))?;
   // 或考虑使用 Windows 防火墙高级安全（WFAS）API
   ```

3. **日志增强**
   ```rust
   // 当前: 仅记录成功配置
   // 建议: 记录规则变更详情（创建 vs 更新）
   ```

4. **清理机制**
   - 当前规则永久存在
   - 建议：提供卸载/清理功能，移除创建的规则

5. **IPv6 特定规则**
   - 当前使用 `NET_FW_IP_PROTOCOL_ANY`
   - 考虑是否需要 IPv4/IPv6 分离控制

6. **应用路径限制**
   - 当前仅基于用户 SID 限制
   - 建议：可选添加应用路径限制，更精确控制

7. **错误恢复**
   ```rust
   // 当前: 验证失败即返回错误
   // 建议: 重试机制或回滚部分创建
   ```

### 测试分析

当前模块无单元测试。建议补充：

| 测试场景 | 说明 |
|----------|------|
| 规则创建 | 验证新规则正确创建 |
| 规则更新 | 验证现有规则更新（幂等） |
| 验证失败 | 模拟验证失败场景 |
| COM 错误 | 模拟 COM 初始化失败 |
| 服务停止 | 验证防火墙服务停止时的行为 |

### 注意事项

1. **Windows 版本兼容性**
   - 使用 `INetFwRule3` 接口（Windows Vista+）
   - 不支持 Windows XP
   - 当前最低支持版本合理

2. **组策略冲突**
   - 如果组策略限制防火墙规则修改，操作可能失败
   - 错误信息应明确指示组策略可能原因

3. **多用户场景**
   - 规则基于用户 SID
   - 同一机器上多个沙箱用户各自有独立规则

4. **性能考虑**
   - COM 初始化和接口创建有开销
   - 建议批量操作而非频繁调用
