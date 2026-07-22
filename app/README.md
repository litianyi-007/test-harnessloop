# app（D4 跨平台架构 monorepo 骨架）

这是 `test-harnessloop` 验证项目里被开发的目标 app（需求见 `../docs/app-requirements.md`）。
目录骨架据 D4 跨平台架构定稿（`~/.llm-wiki/agent-app-design/architecture/d4-cross-platform-arch.md`
v2.2，`design_status: confirmed`）§5.1 monorepo 骨架搭建：**各端原生 client（Mac 写 Swift、
Windows 写 C#）+ 共享契约（D2 消息 schema + codegen 产物 + 金标 parity 测试）**，不上 Rust
核心/TS sidecar/KMP/Electron。

## 当前状态（PRE-②/SG-1 轮）

```
app/
  contracts/
    d1/            # D1 语义的 TS 表达占位（沿用 wiki 现状为权威叙述，非 codegen 输入）——TODO
    d2/            # 【本轮主要产出】D2 机器可读 JSON Schema + codegen 管线 + 金标 fixture 骨架
      schema/      # JSON Schema（部分覆盖，见 d2/README.md 覆盖表）
      codegen/     # schema -> TS 已打通（quicktype/json-schema-to-typescript 二选一，见 codegen/README.md）；Swift/C# 待办
      fixtures/    # 2 个 fixture 样例，DSL 引 D4 §4.3（见 fixtures/README.md）
    d3/            # 【PRE-③ 并行产出，非本轮】D3 OpenAPI 契约草案（见该目录 README.md）
  generated/
    ts/            # 【已跑通】从 contracts/d2 codegen 的 TS 数据类型（d2.d.ts，仅供开发期 fixture 工具/oracle 使用）
    swift/         # 【TODO】从 contracts/d2 codegen 的 Swift 数据类型
    csharp/        # 【TODO】从 contracts/d2 codegen 的 C# 数据类型
  apps/
    mac/           # 【TODO，未来轮次】SwiftUI + 手写 Swift kernel-client + 传输适配
    windows/       # 【TODO，未来轮次】原生 UI + 手写 C# kernel-client + 传输适配
  parity/          # 【TODO，未来轮次】金标 parity 测试完整集合 + 三端 runner；本轮 fixture 样例暂放
                     在 contracts/d2/fixtures/，后续补齐 D4 §4.2 完整状态机清单时再迁移到本目录
                     （D4 §5.1 monorepo 骨架标准路径）
  docs/
    parity-matrix.md   # 【TODO，未来轮次】Mac→Win 跟随看板（D4 §5.3）
```

## D4 依赖状态

- **D4→D2（机器可读 schema，本轮解决的依赖）**：D2 v3（`design_status: confirmed`）此前只有
  TS-in-markdown，没有机器可读产物——这是 D4 §3.1/§7.1 指出的阻断性前置任务。本轮在
  `contracts/d2/schema/` 转录了骨架 + 最关键的几类（详见 `contracts/d2/README.md` 覆盖表），
  并打通了 `schema -> TS` 这一条 codegen 样板（已验证：Ajv 结构校验通过、`tsc --strict` 编译
  产物零错误）。**尚未完全闭合**——D4 §3.5 要求的"递归闭包"全量转录（5/8 方法 + 6/11 事件类型）
  与 Swift/C# 生成器均待后续轮次补齐。
- **D4→D3（正式 API 契约）**：由并行的 PRE-③ 轮次产出（`contracts/d3/README.md` +
  `openapi.yaml`，非本轮内容，见该目录说明），本轮未触碰。

## 契约优先流程（引 D4 §5.2，本轮起遵守）

加功能的标准顺序：①先改 `contracts/d2`（机器可读 schema）+ 补充/修订 `parity/fixtures/`
→②重新跑 codegen，`generated/{swift,csharp,ts}` 更新→③Mac 实现该功能，跑通对应 fixture→
④Windows 以 parity checklist 为验收依据跟随实现。本轮完成的是①的一个子集（骨架 + 代表性类型）
与②的 TS 分支打通，③④均未开始。
