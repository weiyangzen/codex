# frame_36.txt 研究文档

## 场景与职责

`frame_36.txt` 是 Codex TUI 应用服务器欢迎界面动画的 ASCII 艺术帧文件，属于 **vbars**（垂直条形图）动画变体的第 36 帧。该帧是 36 帧循环的最后一帧，负责与第 1 帧形成无缝循环。

## 功能点目的

1. **循环闭合**：36 帧循环的最后一帧
2. **无缝衔接**：与第 1 帧形成无缝循环
3. **周期完成**：完成 2.88 秒的动画周期

## 具体技术实现

### 文件规格
- **尺寸**：17 行 x 40 列
- **字符集**：Unicode 方块元素字符
- **文件大小**：1176 字节
- **帧索引**：35（0-based）

### 周期闭合
```
帧 36（本帧）→ 帧 1（下一周期开始）
```

### 技术实现
```rust
let idx = ((elapsed_ms / 80) % 36) as usize;
// 当 idx = 35 时，返回 frame_36.txt
// 下一帧 idx = 0，返回 frame_1.txt
```

### 循环验证
为确保无缝循环，第 36 帧的内容应与第 1 帧有足够相似性。

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/frames/vbars/frame_36.txt` | 本文件 |
| `codex-rs/tui_app_server/src/frames.rs` | 帧数组 |
| `codex-rs/tui_app_server/src/onboarding/welcome.rs` | 渲染 |

### 数组定义
```rust
pub(crate) const FRAMES_VBARS: [&str; 36] = [
    include_str!("../frames/vbars/frame_1.txt"),   // index 0
    ...
    include_str!("../frames/vbars/frame_36.txt"),  // index 35 (本文件)
];
```

## 依赖与外部交互

### 编译时
- `include_str!` 宏嵌入
- `frames_for!` 宏批量处理

### 运行时
- `AsciiAnimation::current_frame()` 计算索引
- `% 36` 运算实现循环

## 风险、边界与改进建议

### 风险
1. **循环跳跃**：第 36 帧到第 1 帧有明显跳跃
2. **视觉断裂**：用户能感知到循环点
3. **状态不连续**：首尾帧状态差异过大

### 边界
- 循环最后一帧
- 与第 1 帧的衔接

### 改进建议
1. **首尾对比**：详细对比第 36 帧与第 1 帧的内容
2. **闭合优化**：优化帧内容使循环更平滑
3. **插值过渡**：考虑在运行时进行帧插值
4. **周期测试**：自动化测试循环的流畅度
5. **用户反馈**：收集用户对动画循环的反馈

### 验证方法
```bash
# 对比第 36 帧与第 1 帧
diff codex-rs/tui_app_server/frames/vbars/frame_36.txt \
     codex-rs/tui_app_server/frames/vbars/frame_1.txt
```
