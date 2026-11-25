# 动效

时长与缓动只用 [design-system.md](./design-system.md) §6 的 `--nuum-duration-*` 与 `--nuum-easing-*`。开箱的毫秒数来自 `packages/ui/src/conversation/nunu-unboxing-motion.ts`，不新做一套。

`@Environment(\.accessibilityReduceMotion)` 为真时，对应 Mac 的 `prefers-reduced-motion: reduce`。

## accessibilityReduceMotion

| 表面 | 行为 |
| --- | --- |
| 开箱 | 不启动动画时钟。第一帧就是终态。见下一节 |
| 开箱之后的待机摆动 | 不播放。Mac 在 reduced 时也不 `scheduleIdle` |
| 彩纸 | 不生成 |
| 列切换、资料栏、对话框 | 直接到打开或关闭，不用 `--nuum-duration-slower` |
| 资料工牌倾斜 | 保持正对。Mac 在 reduced 或 `pointerType === "touch"` 时已经不倾斜。iOS 触控同样不倾斜 |
| 色点、侧栏 chevron | 无 transition |
| 泳道滚动 | 不用平滑，直接定位。与 `work-content.tsx` 在 reduced 时用 `instant` 相同 |
| 成员状态气泡、拖拽提示 | 无循环动画 |
| 「工作中」标签脉冲 | 静止。颜色仍是 `--nuum-text-tertiary` |

## 开箱终态

Mac 的时间轴：

| 常数 | 毫秒 | 含义 |
| --- | --- | --- |
| `UNBOX_DURATION` | 1500 | 包装打开结束 |
| `CONFETTI_START` | 1020 | 彩纸开始 |
| `CONFETTI_DURATION` | 3600 | 彩纸持续 |
| `UNBOX_PLAYBACK_DURATION` | 4620 | 彩纸结束 |

`sampleUnboxing(1500)` 的终值：`open = 1`，`untie = 1`，`reveal = 1`，`packaging = 0`，`approach = 1`，`jump = 0`，手臂与头回到 `NUNU_REST`。Mac 在 `prefers-reduced-motion: reduce` 时把时钟设成 `UNBOX_PLAYBACK_DURATION`，彩纸采样返回空，姿态仍是休息态。

`accessibilityReduceMotion` 为真时，iOS 直接画这一终态，不经过 1500 ms，也不播到 4620 ms 的彩纸：

- 包装不可见
- 矢量全身 Nunu 位于开箱区域中央，尺寸 190 pt（Mac WebGL 失败时的 `AgentAvatar` `fullBody` `size={190}`）
- 无跃起、无招手、无彩纸
- 区域高度仍是 280 pt；窗口高度 `< 640 pt` 时为 192 pt（`agent-creation.css`）

不要求 3D。不创建 WebGL，不加载 `BODY_ASSETS`，不 portal 彩纸 canvas。

减弱动态效果关闭时，可以用 1500 ms 把包装透明度从 1 收到 0、把 Nunu 从 0.92 放到 1。缓动 `--nuum-easing-out-strong`。到 1500 ms 必须与终态重合。不使用 three.js，不使用 `UNBOX_PACKAGES` 的网格，不加载 webm。包装种类 `soft-tray | paper-fold | round-box` 只决定开场的 2D 剪影（圆角矩形、折线卡片、圆），颜色用该 Nunu 的 `value` 混 `--sand-bg-elevated`。`accessibilityReduceMotion` 为真时这三种剪影都不画。

实现验收：`accessibilityReduceMotion` 打开创建页时不注册动画时钟。与 WP-08 的界面测试一致。

## 头像状态

`AgentAvatarState`：`idle | thinking | working | waiting | error | sending | receiving | happy | wave`。

用矢量形状表达，不播 `actions-atlas.png` 或 webm：

| 状态 | 矢量 |
| --- | --- |
| `idle` | 静止 |
| `thinking` / `working` | 形状缓慢上下 2 pt。`accessibilityReduceMotion` 为真时静止，旁边的文字仍在 |
| `waiting` | 静止，右下角 8 pt 点，颜色 `--sand-fill-warning` |
| `error` | 静止，右下角 8 pt 点，颜色 `--sand-fill-danger` |
| `sending` / `receiving` | 静止。方向靠 peer 行的文案，不靠位移动画 |
| `happy` / `wave` | 资料页打招呼时形状放大到 1.04 再回到 1，时长 `--nuum-duration-slower`。`accessibilityReduceMotion` 为真时保持 1 |

运行中的 8 pt 状态点用 `--sand-fill-accent`。`idle` 的点透明，与 `.sand-status-dot.is-idle` 相同。

## 流式

文本按 delta 追加，不打字机逐字补间。正在思考且还没有工具时，显示 key `思考中`，文字可用 `--sand-gradient-text-shimmer`。`accessibilityReduceMotion` 为真时 shimmer 停在 `--sand-text-tertiary`。
