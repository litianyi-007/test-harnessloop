# test-harnessloop

通过开发一个真实 app 来验证 harnessloop 插件能力的实验项目。**app 是手段，harnessloop 的迭代验证才是目的。**

## 目录结构

- `harnessloop/` — git submodule，指向 `surebeli/harnessloop`。这是插件源码，发现框架问题时**直接在这里改**。
- `hopper-plugin/` — git submodule，指向 `surebeli/hopper-plugin`（marketplace 名 `agent-hopper`，插件 id `hopper@agent-hopper`）。第二个被测插件，任务分发到第三方 agents，同样直接迭代。
- `kata/` — git submodule，指向 `surebeli/kata`（marketplace 名 `kata`，插件 id `kata@kata`）。第三个被测插件，维护 LLM wiki 文档，同样直接迭代。
- `app/` — 被开发的验证 app（需求见 `docs/app-requirements.md`）。
- `docs/validation-log.md` — 每一轮「发现问题 → 改插件 → 重装 → 复验」的记录，是本项目的核心产出。
- `scripts/` — 插件迭代回路脚本（覆盖 harnessloop、hopper、kata 三个被测插件）。

## 插件迭代回路

`scripts/plugin-reinstall.sh [harnessloop|hopper|kata|all]` 每次运行都会把对应插件的全局 marketplace 重指到本项目的 submodule（不是 GitHub），所以插件改动不需要 push 就能生效（不带参数默认 `all`，三个插件依次重装；当前指向用 `scripts/plugin-status.sh [harnessloop|hopper|kata|all]` 确认）：

0. **先确认 submodule 没落后 upstream**（`scripts/plugin-status.sh <plugin>` 与 `plugin-reinstall.sh` 都会自动 fetch 并报「落后 N / 领先 M」；落后时给出警告）。**这一步不是形式**：2026-07-28 实测 hopper submodule 落后上游 65 个提交而无人察觉，在陈旧基线上做完的一整版改动（含版本 bump 与 CHANGELOG）全部作废、必须在上游最新提交之上重做。落后就先 `git -C <submodule> pull --ff-only`。fetch 失败/离线时脚本会如实标注「可能过时」，不会把「没刷新」报成「已是最新」。
1. 直接编辑源码：harnessloop 在 `harnessloop/plugins/harnessloop/`（skills 等）；hopper 在 `hopper-plugin/`（marketplace.json 里 `source` 是 `./`，即 submodule 根目录本身就是插件源码目录，不是子目录）；kata 在 `kata/plugin/`（marketplace.json 里 `source` 是 `./plugin`）。**不需要先 commit**——已实测：安装复制的是 submodule 工作区（含未提交改动）。
2. 运行 `scripts/plugin-reinstall.sh harnessloop`、`scripts/plugin-reinstall.sh hopper`、`scripts/plugin-reinstall.sh kata` 或不带参数一次重装三者（校验 manifest → 卸载 → 重装）。
3. **重启 Claude Code 会话**后新版本才会加载。
4. 复验之前失败的场景，结果记入 `docs/validation-log.md`。
5. 验证通过的插件改动在对应 submodule（`harnessloop/`、`hopper-plugin/` 或 `kata/`）内 commit；push 到各自 GitHub 仓库已是既定授权流程（`surebeli/harnessloop`、`surebeli/test-harnessloop`、`surebeli/hopper-plugin`、`surebeli/kata` 四仓同权，批次验收通过后无需逐次确认，见 `.harnessloop/state/control-contract.md`）——但三个插件（harnessloop / hopper-plugin / kata）push 前均须先 bump 版本信息，保持各自版本文件一致后才能 push；各插件的版本文件清单如下（2026-07-28 实测枚举；此前这里写的是「……等」，那个「等」藏了 hopper 的 4 处，实际漏改了一半，是仓库自己的一致性测试把人拦下来的）：

   - **harnessloop（3 处）**：`package.json`、`.claude-plugin/marketplace.json`、`plugins/harnessloop/.claude-plugin/plugin.json`。（无 CHANGELOG；发布记录写在 commit message 与 `docs/` 规格文档的实施记录节。）
   - **hopper-plugin（7 处 + CHANGELOG）**：`package.json`、`.claude-plugin/plugin.json`、`.codex-plugin/plugin.json`、`.claude-plugin/marketplace.json`（**顶层 `version` 与 `plugins[0].version` 两处**）、`cli/bin/hopper-dispatch` 的 `const VERSION`、`package-lock.json` 的 `version`、`commands/smoke.md`、`commands/vendors.md`，外加 `CHANGELOG.md` 新增条目。改完 `cli/` 下任何文件都要跑 `npm run sync:plugin` 同步 vendored 副本 `plugins/hopper/`（有测试守卫会红）。**别只靠这份清单**——`npm test` 里有 `version consistency` 与 `release metadata` 两条守卫会枚举真实位置，以它们为准；`tests/unit/vendored-plugin-sync.test.js` 里的版本号也是硬编码、需同步改。
   - **kata（4 处 + CHANGELOG）**：`plugin/.claude-plugin/plugin.json`、`.claude-plugin/marketplace.json` 的 `plugins[0].version`、**顶层 `plugin.json`**、**`SKILL.md` frontmatter 的 `version:` 行**，外加 `CHANGELOG.md`。后两处最容易漏——枚举方法：`grep -rl <当前版本号> kata --exclude-dir=.git --exclude-dir=node_modules | grep -v /tests/`（`tests/_codex_install/` 下的 SKILL.md 是安装快照产物，不手改）。

用 `scripts/plugin-status.sh [harnessloop|hopper|kata|all]` 可对照 submodule 状态与全局实际安装的版本。

## Hopper vendor 角色

（用户决策 2026-07-17，详见 `.hopper/AGENTS.md`、`.harnessloop/setup/data-sources.md`、`.harnessloop/setup/cost-context-policy.md`）

- **入选 vendor 只有 `codex` 与 `grok`**，其余 hopper 已注册的 vendor（kimi/opencode/copilot/agy/mimo/claude 等）未入选，暂不路由。
  - `codex`：对抗/验收评审随机池成员 + 研究备选。
  - `grok`：对抗/验收评审随机池成员 + 研究主力。
- **对抗评审（`code-review-adversarial`/`code-review-acceptance`）** 从 codex/grok 中随机挑一家；随机发生在主会话写 queue.md 该任务行 `Vendor` 列的那一刻，hopper 的路由逻辑本身仍是确定性的静态查表。
- **实现类（写代码，`code-impl`）绝不派第三方 vendor**——一律由主会话的 claude-sonnet-5 子代理执行，hopper 不参与实现类任务的派发。
- **codex 评审三项强制核对**：codex 沙箱不可靠地降级为只读、且存在跨仓 review 被全局 skill 劫持的已知问题（`hopper-plugin/ISSUE-codex-review-hijack.md`，未修）。每次 codex 评审完成后必须核对：(a) 实际审查对象是否为 brief 指定目标；(b) 产物是否落在 brief 指定路径；(c) 不得仅凭 exit 0 / codex 自述 success 采信。

> Dispatch contract (per-vendor --model/--reasoning/--sandbox/--timeout, perms, cwd): see `.hopper/DISPATCH.md` (hopper-generated, do not hand-edit). Never hand-copy vendor invocation strings.

- 三个插件（harnessloop / hopper-plugin / kata）push 前均须 bump 版本信息、保持多处版本文件一致，否则不得 push：见「插件迭代回路」第 5 步与 `.harnessloop/state/control-contract.md`（Irreversible or external-system write 例外条款，user-confirmed 2026-07-17）。版本位置以各仓库实际布局为准：hopper-plugin 见上；kata 是 `plugin/.claude-plugin/plugin.json`、`.claude-plugin/marketplace.json`、`CHANGELOG.md`。

## Chronicler 史官纪律

本项目工程侧产出（三插件迭代、round 收盘、issue 开闭）与「这段应用旅程值得对外讲的故事」
是两件事，后者交给项目级 agent `chronicler`（`.claude/agents/chronicler.md`，model: haiku）
专职处理，与主会话的工程执行彻底分开：

- **角色与落点**：chronicler 是本项目的史官，只把工程事件转译成 PR/IP 叙事素材（里程碑/
  故事弧/可引用数据），写入个人 PR wiki `~/.llm-wiki/surebeli-ip`（区别于工程侧 wiki
  `~/.llm-wiki/test-harnessloop`，两者不要混淆）。它不改本项目仓、不改任何插件 submodule。
- **五类触发节点**：轮次收盘、goal 归档、evolution issue 开闭、插件版本 push、live
  showcase 时刻——主会话在这五类事件发生时，应 `SendMessage` 给会话内已有的 chronicler
  实例（无实例则用 `Agent` 起一个 `subagent_type: chronicler`），事件提示一行即可（比如
  "round 0004 收盘了""issue 0009 关了"），具体挖掘细节由 chronicler 自己去拉取。
- **拉取式设计原则**：harnessloop 协议文本本身不因为 chronicler 的存在而改一个字——不
  新增"记录钩子"、不在 round-summary.md/decision.md 模板里插入 PR 素材字段。触发是主会话
  的一行提示，挖掘是 chronicler 自己按固定素材源拉取，工程协议与叙事记录两条线永不交叉。
- **每周素材盘点**：可跑 `/kata:wiki-digest --path ~/.llm-wiki/surebeli-ip` 看这周攒了
  哪些 raw 素材、有没有可以升级成 story 的簇。成熟到能成稿的素材簇，由 Sonnet（不是
  chronicler 本身，chronicler 用 haiku 只管素材拉取）做一次编辑 pass，提炼进
  `~/.llm-wiki/surebeli-ip/drafts/`。

## 凭证守门（2026-07-26 泄漏事件后强制）

本仓是 **PUBLIC**，且 evidence/vendor 原始日志由子代理自动写入——真实凭证曾因此进公开历史
（`docs/security-incident-20260726.md`）。新 clone / 换机器后**必须先装本地钩子**（`.git/hooks` 不版本化）：

```bash
printf '#!/usr/bin/env bash\nexec "$(git rev-parse --show-toplevel)/scripts/check-secrets.sh" --staged\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

- 轮换任何凭证后重跑 `./scripts/check-secrets.sh --update-digests`（让 CI 的 L1-digest 跟上）。
- `.hopper/AGENTS.md` 纪律：任务 brief 里**绝不写真实凭证**，一律给参数名 + "从环境变量/channel-params 读"。

## 约束

- app 的开发过程必须走 harnessloop 框架（skill 真实调用名带双前缀：`harnessloop:harnessloop-init` → `harnessloop:harnessloop-loop` / `harnessloop:harnessloop-continue` 等；`harnessloop:init` 这类短写只是触发短语，不是合法 skill 名），不要绕开框架直接开发——绕开就失去了验证意义。
- 遇到框架缺陷、协议疑问，先用 `harnessloop:harnessloop-issue` 记录，再动手改源码。
- `.harnessloop/` 状态文件是被测行为的一部分，纳入 git 提交，不要 gitignore。
- 主仓库 commit 时注意 submodule 指针：只有当 `harnessloop/` 或 `hopper-plugin/` 内的改动已在各自 submodule 里 commit 后，主仓库才应更新指针。
- hopper 的验证方式是边用边验证：后续任务中实际调用其 dispatch/monitor 能力并记录问题。
