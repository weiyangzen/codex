# frame_3.txt 研究文档

## 场景与职责

`frame_3.txt` 是 Codex TUI `hash` 动画变体的第 3 帧，在 36 帧动画序列中继续展示哈希图案的动态演变。

### 动画序列上下文
- **位置**: 第 3 帧 (索引 2)
- **时间**: 动画开始后 160-239ms
- **角色**: 延续前两帧的扩散效果，图案进一步演变

### 视觉特征
该帧相比前两帧，图案更加紧凑，中心区域的字符密度增加，边缘更加清晰。

## 功能点目的

### 动画节奏控制
作为序列的早期帧，它承担着：
1. 建立动画的视觉节奏
2. 展示图案的动态变化
3. 维持用户的视觉兴趣

### 字符分布分析
```
密度特征:
- 中心区域: █ 字符更集中
- 边缘区域: # 和 * 字符形成轮廓
- 过渡区域: - 和 . 字符填充
```

## 具体技术实现

### 索引计算
```rust
// 在 current_frame() 中的索引计算
let idx = ((elapsed_ms / 80) % 36) as usize;
// elapsed_ms = 160..239 -> idx = 2 -> frame_3.txt
```

### 内存布局
```
FRAMES_HASH 数组布局:
[0] frame_1.txt  -> 712 bytes
[1] frame_2.txt  -> 708 bytes
[2] frame_3.txt  -> 708 bytes  <-- 本帧
[3] frame_4.txt  -> 700 bytes
...
[35] frame_36.txt
```

## 关键代码路径与文件引用

### 渲染触发流程
```
1. tokio 定时器触发 (每 80ms)
2. FrameScheduler 接收调度请求
3. FrameRateLimiter 检查 120 FPS 限制
4. 发送 draw 通知到 TUI 事件循环
5. WelcomeWidget::render_ref() 被调用
6. AsciiAnimation::current_frame() 计算当前帧索引
7. 获取 frame_3.txt 内容
8. ratatui 渲染到终端
```

### 关键代码位置

**帧数组定义** (`frames.rs:52`):
```rust
pub(crate) const FRAMES_HASH: [&str; 36] = frames_for!("hash");
```

**动画变体列表** (`frames.rs:58-69`):
```rust
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,
    &FRAMES_CODEX,
    &FRAMES_OPENAI,
    &FRAMES_BLOCKS,
    &FRAMES_DOTS,
    &FRAMES_HASH,  // <-- 包含本帧
    &FRAMES_HBARS,
    &FRAMES_VBARS,
    &FRAMES_SHAPES,
    &FRAMES_SLUG,
];
```

## 依赖与外部交互

### 与其他帧的关系
```
frame_1.txt (起始) 
    ↓
frame_2.txt (演变)
    ↓
frame_3.txt (当前) <-- 图案更紧凑
    ↓
frame_4.txt (继续)
```

### 系统依赖图
```
frame_3.txt
    ↑
frames.rs (编译时嵌入)
    ↑
ascii_animation.rs (运行时选择)
    ↑
welcome.rs (渲染上下文)
    ↑
tui.rs (事件循环)
    ↑
main.rs (应用入口)
```

### 外部配置影响
| 配置项 | 影响 |
|--------|------|
| `animations_enabled` | 为 false 时不渲染任何帧 |
| 终端尺寸 | 小于 37×60 时跳过动画 |
| `FRAME_TICK_DEFAULT` | 控制帧切换速度 |

## 风险、边界与改进建议

### 潜在问题

1. **帧同步问题**
   ```rust
   // 如果系统负载高，可能导致：
   - 帧率下降（跳帧）
   - 动画不流畅
   ```

2. **内存占用**
   - 36 帧 × 平均 700 bytes ≈ 25 KB 静态数据
   - 嵌入在二进制中，运行时无额外分配

### 边界测试场景

| 场景 | 预期行为 |
|------|----------|
| 快速终端调整大小 | 动画可能暂时隐藏/显示 |
| 长时间运行 | 循环播放，无内存泄漏 |
| Ctrl+. 切换 | 切换到其他动画变体 |

### 改进建议

1. **性能优化**
   ```rust
   // 考虑使用 lazy_static 延迟加载（但当前编译时嵌入已足够高效）
   ```

2. **可测试性**
   ```rust
   // 建议添加帧内容测试
   #[test]
   fn test_frame_3_content() {
       assert!(FRAMES_HASH[2].contains('█'));
       assert_eq!(FRAMES_HASH[2].lines().count(), 17);
   }
   ```

3. **文档化**
   - 在每帧文件头部添加注释说明其在动画中的角色
   - 记录设计意图和视觉目标

### 监控指标
如需监控动画性能：
```rust
// 可添加的指标
- frame_render_duration: 单帧渲染耗时
- frame_skip_count: 跳帧计数
- animation_variant_switches: 变体切换次数
```

### 相关文件
- 同目录帧: `frame_1.txt` ~ `frame_36.txt`
- 动画变体目录: `codex-rs/tui/frames/{default,codex,openai,blocks,dots,hbars,vbars,shapes,slug}/`
