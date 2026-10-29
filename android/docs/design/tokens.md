本文件从 `packages/ui/src/theme/runtime-theme-token-installer.ts` 的字面量原样抽出。屏幕规格只许引用这些 CSS 变量名，不许改名。安装顺序与圆角覆盖见 [design-system.md](./design-system.md)。

## RUNTIME_PALETTE

| CSS 变量 | light | dark |
| --- | --- | --- |
| `--sand-bg-base` | `#fcfcfc` | `#070707` |
| `--sand-bg-subtle` | `#f7f7f7` | `#111111` |
| `--sand-bg-elevated` | `#fcfcfc` | `#181818` |
| `--sand-bg-fade-base` | `#fcfcfc00` | `#07070700` |
| `--sand-bg-fade-subtle` | `#f7f7f700` | `#11111100` |
| `--sand-bg-scrim` | `#14141480` | `#141414b2` |
| `--sand-bg-scrim-heavy` | `#141414e5` | `#141414f2` |
| `--sand-text-primary` | `#141414` | `#fcfcfc` |
| `--sand-text-secondary` | `#14141499` | `#fcfcfc99` |
| `--sand-text-tertiary` | `#14141466` | `#fcfcfc66` |
| `--sand-text-disabled` | `#1414144d` | `#fcfcfc4d` |
| `--sand-text-on-primary` | `#fcfcfc` | `#141414` |
| `--sand-text-on-color` | `#fcfcfc` | `#fcfcfc` |
| `--sand-text-neutral` | `#3d3d3d` | `#b7b7b7` |
| `--sand-text-neutral-disabled` | `#77777721` | `#77777733` |
| `--sand-text-accent` | `#0c64c1` | `#459ffe` |
| `--sand-text-accent-disabled` | `#1084fe2b` | `#1084fe52` |
| `--sand-text-success` | `#009957` | `#38d591` |
| `--sand-text-success-disabled` | `#00c97221` | `#00c97233` |
| `--sand-text-warning` | `#c27400` | `#ffaf38` |
| `--sand-text-warning-disabled` | `#ff980021` | `#ff980033` |
| `--sand-text-danger` | `#c21d2e` | `#ff5667` |
| `--sand-text-danger-disabled` | `#ff263c2b` | `#ff263c52` |
| `--sand-text-supplementary1` | `#c24e00` | `#ff8838` |
| `--sand-text-supplementary1-disabled` | `#ff670021` | `#ff670033` |
| `--sand-text-supplementary2` | `#734f2e` | `#ae8968` |
| `--sand-text-supplementary2-disabled` | `#97683d21` | `#97683d33` |
| `--sand-text-supplementary3` | `#008f7e` | `#38cbba` |
| `--sand-text-supplementary3-disabled` | `#00bca621` | `#00bca633` |
| `--sand-text-supplementary4` | `#6e44c1` | `#a97efe` |
| `--sand-text-supplementary4-disabled` | `#9159fe21` | `#9159fe33` |
| `--sand-text-supplementary5` | `#c22476` | `#ff5eb1` |
| `--sand-text-supplementary5-disabled` | `#ff309b21` | `#ff309b33` |
| `--sand-text-shimmer-base` | `#14141466` | `#fcfcfc66` |
| `--sand-text-shimmer-highlight` | `#141414` | `#fcfcfc` |
| `--sand-border-subtle` | `#1414140d` | `#fcfcfc0d` |
| `--sand-border-weak` | `#1414141a` | `#fcfcfc1a` |
| `--sand-border-default` | `#14141426` | `#fcfcfc26` |
| `--sand-border-strong` | `#1414144d` | `#fcfcfc4d` |
| `--sand-border-focus` | `#14141466` | `#fcfcfc66` |
| `--sand-border-accent` | `#459ffe` | `#0c64c1` |
| `--sand-border-accent-subtle` | `#1084fe2b` | `#1084fe52` |
| `--sand-border-success` | `#38d591` | `#009957` |
| `--sand-border-success-subtle` | `#00c9722b` | `#00c97252` |
| `--sand-border-warning` | `#ffaf38` | `#c27400` |
| `--sand-border-warning-subtle` | `#ff98002b` | `#ff980052` |
| `--sand-border-danger` | `#ff5667` | `#c21d2e` |
| `--sand-border-danger-subtle` | `#ff263c2b` | `#ff263c52` |
| `--sand-border-supplementary5-subtle` | `#ff309b2b` | `#ff309b52` |
| `--sand-border-cutout-on-base` | `#fcfcfc` | `#141414` |
| `--sand-border-cutout-on-subtle` | `#f7f7f7` | `#111111` |
| `--sand-border-cutout-on-elevated` | `#fcfcfc` | `#181818` |
| `--sand-fill-primary` | `#070707` | `#fafafa` |
| `--sand-fill-primary-hover` | `#2f2f2f` | `#d5d5d5` |
| `--sand-fill-primary-disabled` | `#14141426` | `#fcfcfc26` |
| `--sand-fill-secondary` | `#77777717` | `#7777772c` |
| `--sand-fill-secondary-hover` | `#7777772b` | `#77777752` |
| `--sand-fill-secondary-disabled` | `#77777710` | `#77777724` |
| `--sand-fill-secondary-solid` | `#f3f3f3` | `#151515` |
| `--sand-fill-secondary-solid-hover` | `#eeeeee` | `#181818` |
| `--sand-fill-ghost-hover` | `#77777717` | `#7777772c` |
| `--sand-fill-ghost-selected` | `#7777772b` | `#77777752` |
| `--sand-fill-elevated` | `#fcfcfc` | `#2f2f2f` |
| `--sand-fill-elevated-hover` | `#77777717` | `#77777733` |
| `--sand-fill-bubble-agent` | `#eeeeee` | `#262626` |
| `--sand-fill-bubble-user` | `#070707` | `#5a5a5a` |
| `--sand-fill-bubble-user-disabled` | `#14141426` | `#fcfcfc26` |
| `--sand-fill-control-checked` | `#070707` | `#5a5a5a` |
| `--sand-fill-control-checked-hover` | `#2f2f2f` | `#777777` |
| `--sand-fill-control-checked-disabled` | `#14141426` | `#fcfcfc26` |
| `--sand-fill-control-track` | `#1414141a` | `#fcfcfc1a` |
| `--sand-fill-control-track-disabled` | `#77777710` | `#77777724` |
| `--sand-fill-neutral` | `#777777` | `#777777` |
| `--sand-fill-neutral-hover` | `#5a5a5a` | `#959595` |
| `--sand-fill-neutral-disabled` | `#7777772b` | `#77777752` |
| `--sand-fill-neutral-subtle` | `#77777717` | `#7777772c` |
| `--sand-fill-accent` | `#1084fe` | `#1084fe` |
| `--sand-fill-accent-hover` | `#0c64c1` | `#459ffe` |
| `--sand-fill-accent-disabled` | `#1084fe2b` | `#1084fe52` |
| `--sand-fill-accent-subtle` | `#1084fe17` | `#1084fe2c` |
| `--sand-fill-accent-subtle-hover` | `#1084fe2b` | `#1084fe52` |
| `--sand-fill-accent-subtle-disabled` | `#1084fe10` | `#1084fe24` |
| `--sand-fill-success` | `#00c972` | `#00c972` |
| `--sand-fill-success-hover` | `#009957` | `#38d591` |
| `--sand-fill-success-disabled` | `#00c9722b` | `#00c97252` |
| `--sand-fill-success-subtle` | `#00c97217` | `#00c9722c` |
| `--sand-fill-success-subtle-hover` | `#00c9722b` | `#00c97252` |
| `--sand-fill-success-subtle-disabled` | `#00c97210` | `#00c97224` |
| `--sand-fill-warning` | `#ff9800` | `#ff9800` |
| `--sand-fill-warning-hover` | `#c27400` | `#ffaf38` |
| `--sand-fill-warning-disabled` | `#ff98002b` | `#ff980052` |
| `--sand-fill-warning-subtle` | `#ff980017` | `#ff98002c` |
| `--sand-fill-warning-subtle-hover` | `#ff98002b` | `#ff980052` |
| `--sand-fill-warning-subtle-disabled` | `#ff980010` | `#ff980024` |
| `--sand-fill-danger` | `#ff263c` | `#ff263c` |
| `--sand-fill-danger-hover` | `#c21d2e` | `#ff5667` |
| `--sand-fill-danger-disabled` | `#ff263c2b` | `#ff263c52` |
| `--sand-fill-danger-subtle` | `#ff263c17` | `#ff263c2c` |
| `--sand-fill-danger-subtle-hover` | `#ff263c2b` | `#ff263c52` |
| `--sand-fill-danger-subtle-disabled` | `#ff263c10` | `#ff263c24` |
| `--sand-fill-supplementary1` | `#ff6700` | `#ff6700` |
| `--sand-fill-supplementary1-hover` | `#c24e00` | `#ff8838` |
| `--sand-fill-supplementary1-disabled` | `#ff67002b` | `#ff670052` |
| `--sand-fill-supplementary1-subtle` | `#ff670017` | `#ff67002c` |
| `--sand-fill-supplementary2` | `#97683d` | `#97683d` |
| `--sand-fill-supplementary2-hover` | `#734f2e` | `#ae8968` |
| `--sand-fill-supplementary2-disabled` | `#97683d2b` | `#97683d52` |
| `--sand-fill-supplementary2-subtle` | `#97683d17` | `#97683d2c` |
| `--sand-fill-supplementary3` | `#00bca6` | `#00bca6` |
| `--sand-fill-supplementary3-hover` | `#008f7e` | `#38cbba` |
| `--sand-fill-supplementary3-disabled` | `#00bca62b` | `#00bca652` |
| `--sand-fill-supplementary3-subtle` | `#00bca617` | `#00bca62c` |
| `--sand-fill-supplementary4` | `#9159fe` | `#9159fe` |
| `--sand-fill-supplementary4-hover` | `#6e44c1` | `#a97efe` |
| `--sand-fill-supplementary4-disabled` | `#9159fe2b` | `#9159fe52` |
| `--sand-fill-supplementary4-subtle` | `#9159fe17` | `#9159fe2c` |
| `--sand-fill-supplementary5` | `#ff309b` | `#ff309b` |
| `--sand-fill-supplementary5-hover` | `#c22476` | `#ff5eb1` |
| `--sand-fill-supplementary5-disabled` | `#ff309b2b` | `#ff309b52` |
| `--sand-fill-supplementary5-subtle` | `#ff309b17` | `#ff309b2c` |
| `--sand-shadow-control` | `#0000001f` | `#00000000` |
| `--sand-shadow-inline-ambient` | `#00000014` | `#00000000` |
| `--sand-shadow-inline-key` | `#0000000f` | `#00000000` |
| `--sand-shadow-popover-ambient` | `#0000001a` | `#00000000` |
| `--sand-shadow-popover-key` | `#0000001a` | `#00000000` |
| `--sand-shadow-modal-ambient` | `#0000001a` | `#00000000` |
| `--sand-shadow-modal-key` | `#0000001a` | `#00000000` |
| `--sand-shadow-window-ambient` | `#0000008f` | `#00000000` |
| `--sand-shadow-window-edge` | `#0000001a` | `#00000000` |
| `--sand-shadow-ring` | `#e4e4e40a` | `#e4e4e400` |

## SAND_DATA

| CSS 变量 | light | dark |
| --- | --- | --- |
| `--sand-data-gray-1` | `#b7b7b7` | `#3d3d3d` |
| `--sand-data-gray-2` | `#959595` | `#5a5a5a` |
| `--sand-data-gray-3` | `#777777` | `#777777` |
| `--sand-data-gray-4` | `#5a5a5a` | `#959595` |
| `--sand-data-gray-5` | `#3d3d3d` | `#b7b7b7` |
| `--sand-data-blue-1` | `#80befe` | `#084382` |
| `--sand-data-blue-2` | `#459ffe` | `#0c64c1` |
| `--sand-data-blue-3` | `#1084fe` | `#1084fe` |
| `--sand-data-blue-4` | `#0c64c1` | `#459ffe` |
| `--sand-data-blue-5` | `#084382` | `#80befe` |
| `--sand-data-red-1` | `#ff8c98` | `#82131f` |
| `--sand-data-red-2` | `#ff5667` | `#c21d2e` |
| `--sand-data-red-3` | `#ff263c` | `#ff263c` |
| `--sand-data-red-4` | `#c21d2e` | `#ff5667` |
| `--sand-data-red-5` | `#82131f` | `#ff8c98` |
| `--sand-data-orange-1` | `#ffae78` | `#823500` |
| `--sand-data-orange-2` | `#ff8838` | `#c24e00` |
| `--sand-data-orange-3` | `#ff6700` | `#ff6700` |
| `--sand-data-orange-4` | `#c24e00` | `#ff8838` |
| `--sand-data-orange-5` | `#823500` | `#ffae78` |
| `--sand-data-yellow-1` | `#ffc878` | `#824e00` |
| `--sand-data-yellow-2` | `#ffaf38` | `#c27400` |
| `--sand-data-yellow-3` | `#ff9800` | `#ff9800` |
| `--sand-data-yellow-4` | `#c27400` | `#ffaf38` |
| `--sand-data-yellow-5` | `#824e00` | `#ffc878` |
| `--sand-data-green-1` | `#78e2b4` | `#00673a` |
| `--sand-data-green-2` | `#38d591` | `#009957` |
| `--sand-data-green-3` | `#00c972` | `#00c972` |
| `--sand-data-green-4` | `#009957` | `#38d591` |
| `--sand-data-green-5` | `#00673a` | `#78e2b4` |
| `--sand-data-cyan-1` | `#78dbd0` | `#006055` |
| `--sand-data-cyan-2` | `#38cbba` | `#008f7e` |
| `--sand-data-cyan-3` | `#00bca6` | `#00bca6` |
| `--sand-data-cyan-4` | `#008f7e` | `#38cbba` |
| `--sand-data-cyan-5` | `#006055` | `#78dbd0` |
| `--sand-data-purple-1` | `#c5a7fe` | `#4a2d82` |
| `--sand-data-purple-2` | `#a97efe` | `#6e44c1` |
| `--sand-data-purple-3` | `#9159fe` | `#9159fe` |
| `--sand-data-purple-4` | `#6e44c1` | `#a97efe` |
| `--sand-data-purple-5` | `#4a2d82` | `#c5a7fe` |
| `--sand-data-magenta-1` | `#ff91ca` | `#82184f` |
| `--sand-data-magenta-2` | `#ff5eb1` | `#c22476` |
| `--sand-data-magenta-3` | `#ff309b` | `#ff309b` |
| `--sand-data-magenta-4` | `#c22476` | `#ff5eb1` |
| `--sand-data-magenta-5` | `#82184f` | `#ff91ca` |
| `--sand-data-brown-1` | `#c8af98` | `#4d351f` |
| `--sand-data-brown-2` | `#ae8968` | `#734f2e` |
| `--sand-data-brown-3` | `#97683d` | `#97683d` |
| `--sand-data-brown-4` | `#734f2e` | `#ae8968` |
| `--sand-data-brown-5` | `#4d351f` | `#c8af98` |
| `--sand-gradient-bg1-fade` | `linear-gradient(to bottom, var(--sand-bg-base), var(--sand-bg-fade-base))` | `linear-gradient(to bottom, var(--sand-bg-base), var(--sand-bg-fade-base))` |
| `--sand-gradient-bg2-fade` | `linear-gradient(to bottom, var(--sand-bg-subtle), var(--sand-bg-fade-subtle))` | `linear-gradient(to bottom, var(--sand-bg-subtle), var(--sand-bg-fade-subtle))` |
| `--sand-gradient-text-shimmer` | `linear-gradient(90deg, var(--sand-text-shimmer-base) 0%, var(--sand-text-shimmer-base) 25%, var(--sand-text-shimmer-highlight) 60%, var(--sand-text-shimmer-base) 75%, var(--sand-text-shimmer-base) 100%)` | `linear-gradient(90deg, var(--sand-text-shimmer-base) 0%, var(--sand-text-shimmer-base) 25%, var(--sand-text-shimmer-highlight) 60%, var(--sand-text-shimmer-base) 75%, var(--sand-text-shimmer-base) 100%)` |
| `--sand-blur-background` | `24px` | `24px` |

## NZN_TOKENS

| CSS 变量 | light | dark |
| --- | --- | --- |
| `--nuum-text-red-primary` | `#c21d2e` | `#ff5667` |
| `--nuum-icon-red-primary` | `#c21d2e` | `#ff5667` |
| `--nuum-bg-red-primary` | `#ff263c` | `#ff263c` |
| `--nuum-bg-red-secondary` | `#ff263c17` | `#ff263c2c` |
| `--nuum-text-orange-primary` | `#c24e00` | `#ff8838` |
| `--nuum-icon-orange-primary` | `#c24e00` | `#ff8838` |
| `--nuum-bg-orange-primary` | `#ff6700` | `#ff6700` |
| `--nuum-bg-orange-secondary` | `#ff670017` | `#ff67002c` |
| `--nuum-text-yellow-primary` | `#c27400` | `#ffaf38` |
| `--nuum-icon-yellow-primary` | `#c27400` | `#ffaf38` |
| `--nuum-bg-yellow-primary` | `#ff9800` | `#ff9800` |
| `--nuum-bg-yellow-secondary` | `#ff980017` | `#ff98002c` |
| `--nuum-text-green-primary` | `#009957` | `#38d591` |
| `--nuum-icon-green-primary` | `#009957` | `#38d591` |
| `--nuum-bg-green-primary` | `#00c972` | `#00c972` |
| `--nuum-bg-green-secondary` | `#00c97217` | `#00c9722c` |
| `--nuum-text-cyan-primary` | `#008f7e` | `#38cbba` |
| `--nuum-icon-cyan-primary` | `#008f7e` | `#38cbba` |
| `--nuum-bg-cyan-primary` | `#00bca6` | `#00bca6` |
| `--nuum-bg-cyan-secondary` | `#00bca617` | `#00bca62c` |
| `--nuum-text-blue-primary` | `#0c64c1` | `#459ffe` |
| `--nuum-icon-blue-primary` | `#0c64c1` | `#459ffe` |
| `--nuum-bg-blue-primary` | `#1084fe` | `#1084fe` |
| `--nuum-bg-blue-secondary` | `#1084fe17` | `#1084fe2c` |
| `--nuum-text-magenta-primary` | `#c22476` | `#ff5eb1` |
| `--nuum-icon-magenta-primary` | `#c22476` | `#ff5eb1` |
| `--nuum-bg-magenta-primary` | `#ff309b` | `#ff309b` |
| `--nuum-bg-magenta-secondary` | `#ff309b17` | `#ff309b2c` |
| `--nuum-text-purple-primary` | `#6e44c1` | `#a97efe` |
| `--nuum-icon-purple-primary` | `#6e44c1` | `#a97efe` |
| `--nuum-bg-purple-primary` | `#9159fe` | `#9159fe` |
| `--nuum-bg-purple-secondary` | `#9159fe17` | `#9159fe2c` |

## THEME_PALETTE_MAPPING

| CSS 变量 | light | dark |
| --- | --- | --- |
| `--nuum-text-primary` | `var(--sand-text-primary)` | `var(--sand-text-primary)` |
| `--nuum-text-secondary` | `var(--sand-text-secondary)` | `var(--sand-text-secondary)` |
| `--nuum-text-tertiary` | `var(--sand-text-tertiary)` | `var(--sand-text-tertiary)` |
| `--nuum-text-quaternary` | `#1414144d` | `#fcfcfc4d` |
| `--nuum-text-invert` | `var(--sand-text-on-color)` | `var(--sand-text-on-color)` |
| `--nuum-text-accent` | `var(--sand-text-accent)` | `var(--sand-text-accent)` |
| `--nuum-text-link` | `var(--sand-text-accent)` | `var(--sand-text-accent)` |
| `--nuum-foreground` | `var(--sand-fill-bubble-user)` | `var(--sand-fill-bubble-user)` |
| `--nuum-icon-primary` | `var(--sand-text-primary)` | `var(--sand-text-primary)` |
| `--nuum-icon-secondary` | `var(--sand-text-secondary)` | `var(--sand-text-secondary)` |
| `--nuum-icon-tertiary` | `var(--sand-text-tertiary)` | `var(--sand-text-tertiary)` |
| `--nuum-icon-quaternary` | `#1414144d` | `#fcfcfc4d` |
| `--nuum-icon-accent-primary` | `var(--sand-text-accent)` | `var(--sand-text-accent)` |
| `--nuum-bg-editor` | `var(--sand-bg-base)` | `var(--sand-bg-base)` |
| `--nuum-bg-chrome` | `var(--sand-bg-subtle)` | `var(--sand-bg-subtle)` |
| `--nuum-bg-elevated` | `var(--sand-bg-elevated)` | `var(--sand-bg-elevated)` |
| `--nuum-bg-input` | `var(--sand-fill-elevated)` | `var(--sand-fill-elevated)` |
| `--nuum-bg-card` | `var(--sand-fill-secondary)` | `var(--sand-fill-secondary)` |
| `--nuum-bg-quaternary` | `var(--sand-fill-secondary)` | `var(--sand-fill-secondary)` |
| `--nuum-bg-quinary` | `var(--sand-fill-secondary-disabled)` | `var(--sand-fill-secondary-disabled)` |
| `--nuum-bg-tertiary` | `var(--sand-fill-ghost-hover)` | `var(--sand-fill-ghost-hover)` |
| `--nuum-bg-secondary` | `var(--sand-fill-ghost-selected)` | `var(--sand-fill-ghost-selected)` |
| `--nuum-bg-active` | `var(--sand-fill-ghost-selected)` | `var(--sand-fill-ghost-selected)` |
| `--nuum-bg-hover` | `var(--sand-fill-ghost-hover)` | `var(--sand-fill-ghost-hover)` |
| `--nuum-bg-selected` | `var(--sand-fill-ghost-selected)` | `var(--sand-fill-ghost-selected)` |
| `--nuum-bg-focused` | `var(--sand-fill-ghost-selected)` | `var(--sand-fill-ghost-selected)` |
| `--nuum-bg-primary` | `var(--sand-fill-ghost-selected)` | `var(--sand-fill-ghost-selected)` |
| `--nuum-bg-accent` | `var(--sand-fill-accent)` | `var(--sand-fill-accent)` |
| `--nuum-bg-accent-hover` | `var(--sand-fill-accent-hover)` | `var(--sand-fill-accent-hover)` |
| `--nuum-bg-accent-secondary` | `var(--sand-fill-accent-subtle)` | `var(--sand-fill-accent-subtle)` |
| `--nuum-bg-accent-tertiary` | `var(--sand-fill-accent-subtle)` | `var(--sand-fill-accent-subtle)` |
| `--nuum-bg-accent-quaternary` | `var(--sand-fill-accent-subtle)` | `var(--sand-fill-accent-subtle)` |
| `--nuum-accent-color` | `var(--sand-fill-accent)` | `var(--sand-fill-accent)` |
| `--nuum-stroke-primary` | `#14141433` | `#fcfcfc33` |
| `--nuum-stroke-secondary` | `var(--sand-border-default)` | `var(--sand-border-default)` |
| `--nuum-stroke-tertiary` | `#1414141a` | `#fcfcfc1a` |
| `--nuum-stroke-quaternary` | `#1414140d` | `#fcfcfc0d` |
| `--nuum-stroke-focused` | `var(--sand-border-focus)` | `var(--sand-border-focus)` |
| `--nuum-stroke-accent` | `var(--sand-fill-accent)` | `var(--sand-fill-accent)` |
| `--nuum-stroke-red` | `var(--sand-fill-danger)` | `var(--sand-fill-danger)` |
| `--nuum-stroke-cyan-primary` | `#008f7e` | `#38cbba` |
| `--nuum-border-color` | `var(--sand-border-default)` | `var(--sand-border-default)` |
| `--nuum-text-git-added-primary` | `var(--sand-text-success)` | `var(--sand-text-success)` |
| `--nuum-text-git-removed-primary` | `var(--sand-text-danger)` | `var(--sand-text-danger)` |
| `--nuum-box-shadow-sm` | `0 1px 3px 0 var(--sand-shadow-control)` | `0 1px 3px 0 var(--sand-shadow-control)` |
| `--nuum-box-shadow-md` | `0 10px 20px -3px var(--sand-shadow-popover-ambient), 0 4px 6px -4px var(--sand-shadow-popover-key), 0 0 0 1px var(--sand-shadow-ring)` | `0 10px 20px -3px var(--sand-shadow-popover-ambient), 0 4px 6px -4px var(--sand-shadow-popover-key), 0 0 0 1px var(--sand-shadow-ring)` |
| `--nuum-box-shadow-lg` | `0 22px 70px 4px var(--sand-shadow-window-ambient), 0 0 0 0.5px var(--sand-shadow-window-edge)` | `0 22px 70px 4px var(--sand-shadow-window-ambient), 0 0 0 0.5px var(--sand-shadow-window-edge)` |
| `--nuum-shadow-md` | `0 10px 20px -3px var(--sand-shadow-popover-ambient), 0 4px 6px -4px var(--sand-shadow-popover-key), 0 0 0 1px var(--sand-shadow-ring)` | `0 10px 20px -3px var(--sand-shadow-popover-ambient), 0 4px 6px -4px var(--sand-shadow-popover-key), 0 0 0 1px var(--sand-shadow-ring)` |
| `--nuum-shadow-primary` | `#1414144d` | `#1414144d` |
| `--sand-agent-selected-fill` | `var(--sand-fill-ghost-selected)` | `var(--sand-fill-ghost-selected)` |
| `--sand-floating-control-surface` | `var(--sand-fill-elevated)` | `var(--sand-fill-elevated)` |
| `--ui-tooltip-border-width` | `0.5px` | `0.5px` |
| `--ui-tooltip-border-radius` | `6px` | `6px` |
| `--ui-tooltip-box-shadow` | `0 4px 12px -1px var(--sand-shadow-inline-ambient), 0 2px 4px -2px var(--sand-shadow-inline-key), 0 0 0 1px var(--sand-shadow-ring)` | `0 4px 12px -1px var(--sand-shadow-inline-ambient), 0 2px 4px -2px var(--sand-shadow-inline-key), 0 0 0 1px var(--sand-shadow-ring)` |
| `--ui-tooltip-font-size` | `12px` | `12px` |
| `--ui-tooltip-line-height` | `16px` | `16px` |
| `--ui-tooltip-letter-spacing` | `0` | `0` |
| `--ui-tooltip-padding-y` | `4px` | `4px` |
| `--ui-tooltip-padding-x` | `6px` | `6px` |

## CORE_CSS 第一段 `:root` 色种

这是 `--nuum-accent`、`--nuum-chrome`、`--nuum-editor` 等种子。同文件后面的别名段，以及 `Ezn()` 写出的 `NZN_TOKENS` / `THEME_PALETTE_MAPPING`，会覆盖同名变量。屏幕读生效值，不读被覆盖前的种子。被覆盖关系见 design-system。

| CSS 变量 | light | dark |
| --- | --- | --- |
| `--nuum-accent` | `#1084fe` | `#1084fe` |
| `--nuum-action-label` | `#fcfcfc` | `#ffffff` |
| `--nuum-added` | `#00c972` | `#00c972` |
| `--nuum-base` | `#141414` | `#fcfcfc` |
| `--nuum-blue` | `#1084fe` | `#1084fe` |
| `--nuum-brand` | `#f54e00` | `#f54e00` |
| `--nuum-chrome` | `#f7f7f7` | `#111111` |
| `--nuum-cyan` | `#00bca6` | `#00bca6` |
| `--nuum-danger` | `#c21d2e` | `#ff5667` |
| `--nuum-diff-added-line-background` | `#00c97217` | `#00c9722c` |
| `--nuum-diff-added-text-background` | `#00c97210` | `#00c97224` |
| `--nuum-diff-removed-line-background` | `#ff263c17` | `#ff263c2c` |
| `--nuum-diff-removed-text-background` | `#ff263c10` | `#ff263c24` |
| `--nuum-editor` | `#fcfcfc` | `#141414` |
| `--nuum-focus` | `#459ffe` | `#0c64c1` |
| `--nuum-green` | `#00c972` | `#00c972` |
| `--nuum-magenta` | `#ff309b` | `#ff309b` |
| `--nuum-modified` | `#ff9800` | `#ff9800` |
| `--nuum-orange` | `#ff6700` | `#ff6700` |
| `--nuum-purple` | `#9159fe` | `#9159fe` |
| `--nuum-red` | `#ff263c` | `#ff263c` |
| `--nuum-removed` | `#c21d2e` | `#ff5667` |
| `--nuum-sidebar` | `#f7f7f7` | `#111111` |
| `--nuum-success` | `#00c972` | `#00c972` |
| `--nuum-terminal-ansi-black` | `#141414` | `#181818` |
| `--nuum-terminal-ansi-blue` | `#0c64c1` | `#80befe` |
| `--nuum-terminal-ansi-bright-black` | `#141414bd` | `#fcfcfcbd` |
| `--nuum-terminal-ansi-bright-blue` | `#1084fe` | `#e9f4ff` |
| `--nuum-terminal-ansi-bright-cyan` | `#00bca6` | `#e8f9f7` |
| `--nuum-terminal-ansi-bright-green` | `#00c972` | `#e8faf2` |
| `--nuum-terminal-ansi-bright-magenta` | `#ff309b` | `#ffecf6` |
| `--nuum-terminal-ansi-bright-red` | `#ff263c` | `#ffebed` |
| `--nuum-terminal-ansi-bright-white` | `#ffffff` | `#ffffff` |
| `--nuum-terminal-ansi-bright-yellow` | `#ff9800` | `#fff6e8` |
| `--nuum-terminal-ansi-cyan` | `#008f7e` | `#78dbd0` |
| `--nuum-terminal-ansi-green` | `#009957` | `#78e2b4` |
| `--nuum-terminal-ansi-magenta` | `#c22476` | `#ff91ca` |
| `--nuum-terminal-ansi-red` | `#c21d2e` | `#ff8c98` |
| `--nuum-terminal-ansi-white` | `#fcfcfc` | `#f3f3f3` |
| `--nuum-terminal-ansi-yellow` | `#c27400` | `#ffc878` |
| `--nuum-untracked` | `#008f7e` | `#38cbba` |
| `--nuum-warn` | `#ff9800` | `#ff9800` |
| `--nuum-yellow` | `#ff9800` | `#ff9800` |

## 字体、间距、字号、圆角、高度、时长、缓动

两种 mode 相同。单位是 CSS px。Android 按 1 px = 1 dp 取用，不另起 sp 阶梯。`--nuum-radius-base` 到 `--nuum-radius-3xl` 的生效值以 `RADIUS_CSS` 为准，见 design-system，下表是 CORE_CSS 里先写上的值。

| CSS 变量 | CORE_CSS 值 |
| --- | --- |
| `--nuum-font-family-sans` | `-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif` |
| `--nuum-font-family-mono` | `ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace` |
| `--nuum-scrollbar-vertical-size` | `14px` |
| `--nuum-scrollbar-horizontal-size` | `12px` |
| `--nuum-scrollbar-thumb-background` | `color-mix(in srgb, var(--nuum-base) 14%, transparent)` |
| `--nuum-scrollbar-thumb-hover-background` | `color-mix(in srgb, var(--nuum-base) 22%, transparent)` |
| `--nuum-scrollbar-thumb-active-background` | `color-mix(in srgb, var(--nuum-base) 26%, transparent)` |
| `--nuum-syntax-foreground` | `#141414EB` |
| `--nuum-syntax-background` | `#FCFCFC` |
| `--nuum-syntax-keyword` | `#B3003F` |
| `--nuum-syntax-string` | `#9E94D5` |
| `--nuum-syntax-function` | `#DB704B` |
| `--nuum-syntax-number` | `#B8448B` |
| `--nuum-syntax-comment` | `#141414AD` |
| `--nuum-syntax-constant` | `#206595` |
| `--nuum-syntax-parameter` | `#141414EB` |
| `--nuum-syntax-punctuation` | `#141414EB` |
| `--nuum-syntax-link` | `#206595` |
| `--nuum-syntax-string-expression` | `#9E94D5` |
| `--nuum-syntax-tag` | `#B3003F` |
| `--nuum-syntax-attribute` | `#141414EB` |
| `--nuum-syntax-property` | `#141414EB` |
| `--nuum-syntax-type` | `#206595` |
| `--nuum-syntax-variable` | `#141414EB` |
| `--nuum-syntax-class` | `#206595` |
| `--nuum-syntax-language-variable` | `#B3003F` |
| `--nuum-syntax-constant-variable` | `#206595` |
| `--nuum-duration-instant` | `50ms` |
| `--nuum-duration-fast` | `100ms` |
| `--nuum-duration-normal` | `150ms` |
| `--nuum-duration-slow` | `200ms` |
| `--nuum-duration-slower` | `300ms` |
| `--nuum-easing-default` | `ease` |
| `--nuum-easing-in` | `ease-in` |
| `--nuum-easing-out` | `ease-out` |
| `--nuum-easing-in-out` | `ease-in-out` |
| `--nuum-easing-in-strong` | `cubic-bezier(0.895, 0.03, 0.685, 0.22)` |
| `--nuum-easing-out-strong` | `cubic-bezier(0.165, 0.84, 0.44, 1)` |
| `--nuum-easing-out-quint` | `cubic-bezier(0.16, 1, 0.3, 1)` |
| `--nuum-easing-in-out-strong` | `cubic-bezier(0.77, 0, 0.175, 1)` |
| `--nuum-spacing-1` | `4px` |
| `--nuum-spacing-2` | `8px` |
| `--nuum-spacing-3` | `12px` |
| `--nuum-spacing-4` | `16px` |
| `--nuum-spacing-5` | `20px` |
| `--nuum-spacing-6` | `24px` |
| `--nuum-spacing-7` | `28px` |
| `--nuum-spacing-8` | `32px` |
| `--nuum-spacing-9` | `36px` |
| `--nuum-spacing-10` | `40px` |
| `--nuum-spacing-11` | `44px` |
| `--nuum-spacing-12` | `48px` |
| `--nuum-spacing-13` | `52px` |
| `--nuum-spacing-14` | `56px` |
| `--nuum-spacing-15` | `60px` |
| `--nuum-spacing-16` | `64px` |
| `--nuum-spacing-17` | `68px` |
| `--nuum-spacing-18` | `72px` |
| `--nuum-spacing-19` | `76px` |
| `--nuum-spacing-20` | `80px` |
| `--nuum-spacing-ne-0-25` | `-1px` |
| `--nuum-spacing-ne-0-5` | `-2px` |
| `--nuum-spacing-ne-0-75` | `-3px` |
| `--nuum-spacing-ne-1` | `-4px` |
| `--nuum-spacing-ne-1-25` | `-5px` |
| `--nuum-spacing-ne-1-5` | `-6px` |
| `--nuum-spacing-ne-1-75` | `-7px` |
| `--nuum-spacing-ne-2` | `-8px` |
| `--nuum-spacing-ne-2-25` | `-9px` |
| `--nuum-spacing-ne-2-5` | `-10px` |
| `--nuum-spacing-ne-2-75` | `-11px` |
| `--nuum-spacing-ne-3` | `-12px` |
| `--nuum-spacing-ne-3-25` | `-13px` |
| `--nuum-spacing-ne-3-5` | `-14px` |
| `--nuum-spacing-ne-3-75` | `-15px` |
| `--nuum-spacing-ne-4` | `-16px` |
| `--nuum-spacing-ne-4-25` | `-17px` |
| `--nuum-spacing-ne-4-5` | `-18px` |
| `--nuum-spacing-ne-4-75` | `-19px` |
| `--nuum-spacing-ne-5` | `-20px` |
| `--nuum-spacing-0-25` | `1px` |
| `--nuum-spacing-0-5` | `2px` |
| `--nuum-spacing-0-75` | `3px` |
| `--nuum-spacing-1-25` | `5px` |
| `--nuum-spacing-1-5` | `6px` |
| `--nuum-spacing-1-75` | `7px` |
| `--nuum-spacing-2-25` | `9px` |
| `--nuum-spacing-2-5` | `10px` |
| `--nuum-spacing-2-75` | `11px` |
| `--nuum-spacing-3-25` | `13px` |
| `--nuum-spacing-3-5` | `14px` |
| `--nuum-spacing-3-75` | `15px` |
| `--nuum-spacing-4-25` | `17px` |
| `--nuum-spacing-4-5` | `18px` |
| `--nuum-spacing-4-75` | `19px` |
| `--nuum-spacing-5-5` | `22px` |
| `--nuum-spacing-6-5` | `26px` |
| `--nuum-spacing-7-5` | `30px` |
| `--nuum-spacing-8-5` | `34px` |
| `--nuum-spacing-9-5` | `38px` |
| `--nuum-radius-none` | `0px` |
| `--nuum-radius-xs` | `2px` |
| `--nuum-radius-sm` | `4px` |
| `--nuum-radius-base` | `6px` |
| `--nuum-radius-lg` | `8px` |
| `--nuum-radius-xl` | `12px` |
| `--nuum-radius-2xl` | `14px` |
| `--nuum-radius-3xl` | `16px` |
| `--nuum-radius-4xl` | `18px` |
| `--nuum-radius-full` | `9999px` |
| `--nuum-height-xs` | `20px` |
| `--nuum-height-sm` | `24px` |
| `--nuum-height-base` | `28px` |
| `--nuum-height-lg` | `32px` |
| `--nuum-font-size-xs` | `11px` |
| `--nuum-font-size-sm` | `12px` |
| `--nuum-font-size-base` | `13px` |
| `--nuum-font-size-lg` | `14px` |
| `--nuum-line-height-xs` | `14px` |
| `--nuum-line-height-sm` | `16px` |
| `--nuum-line-height-base` | `18px` |
| `--nuum-line-height-lg` | `22px` |
| `--nuum-letter-spacing-xs` | `0.07px` |
| `--nuum-letter-spacing-sm` | `0px` |
| `--nuum-letter-spacing-base` | `-0.08px` |
| `--nuum-letter-spacing-lg` | `-0.15px` |
| `--nuum-letter-spacing-xl` | `0.08px` |
| `--nuum-letter-spacing-2xl` | `-0.46px` |
| `--nuum-letter-spacing-3xl` | `-0.26px` |
| `--nuum-elevation-1` | `1` |
| `--nuum-elevation-2` | `2` |
