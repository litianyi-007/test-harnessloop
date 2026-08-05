# Migration log

由 `hopper-dispatch --migrate-config` 追加写入，只增不改。

## hopper v0.48.1（此前水印：无）

- applied `scaffold-stamp` — 写入 / 刷新 scaffold 版本水印（后续漂移检测的基线）
- applied `dispatch-md-regenerate` — 重新生成 DISPATCH.md（100% 由适配器生成，无手写内容可丢）
