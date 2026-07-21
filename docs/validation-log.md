# harnessloop 验证与迭代记录

每一轮「发现问题 → 改插件 → 重装 → 复验」记一条。最新的记录放最上面。

条目模板：

```markdown
## YYYY-MM-DD <一句话标题>

- **场景**：在开发 app 的哪个环节、执行哪个 skill 时触发
- **现象**：框架实际行为（贴关键输出/文件状态）
- **预期**：框架应有的行为，依据（README/AGENTS.md/协议条款）
- **插件改动**：harnessloop submodule 中的 commit（`<sha> <subject>`），或"未改动，原因"
- **复验结果**：重装重启后同场景的行为；通过/未通过
- **遗留**：后续待办或新发现的关联问题
```

---

## 2026-07-22 hopper 使用观察：queue.md 写入/状态回写两个工程侧问题（D2 双轨派发时发现）

- **场景**：D2 消息 schema 双轨复核（T-014 grok / T-015 codex）派发过程中，边用 hopper 边记录的观察
- **现象**：①用 Python heredoc（`open(...).write()`）编辑 `.hopper/queue.md` 时曾出现改动未持久化的情况（疑似未 `flush`/未真正落盘，进程退出前缓冲区丢失）——换用 Edit 工具编辑 queue.md 后写入可靠、问题不再出现；②hopper 任务（T-014/T-015）在 vendor 侧完成、`.hopper/handoffs/T-0XX-output.md` 落盘 `status: done` 后，`queue.md` 表格里对应行的 `Status` 字段**不会自动**回写为 `done`——需要主会话手工核对 handoffs 产物后自行改字段，否则 queue.md 与实际任务终态之间存在状态漂移窗口
- **预期**：queue.md 作为 hopper 任务队列的单一事实源，编辑应可靠落盘；任务终态应能被追踪到而不依赖人工同步（依据 `.hopper/queue.md` 自身"Status values"字段设计意图）
- **插件改动**：无（本轮为纯使用观察，未触及 hopper-plugin/ 任何文件；是否需要在 hopper-dispatch 侧加自动状态回写机制留待后续评估）
- **复验结果**：✅ 观察成立——Edit 工具编辑 queue.md 全程可靠；status 字段本轮靠手工核对 `.hopper/handoffs/T-014-output.md`/`T-015-output.md` 的 `status: done` 后手动标记两行为 done
- **遗留**：教训固化——"queue.md 编辑用 Edit 工具、不要用 python heredoc 写入；派发/状态变更后建议尽快 commit 落盘"；hopper 任务完成后 queue.md 状态字段的自动回写（或至少一个"核对并同步"辅助命令）可作为 hopper-plugin 后续迭代候选，暂未开 evolution issue，先记录观察

---

## 2026-07-18 kata 第二迭代（2.15.4）：装机版校验缺陷根除 + 图误报豁免 + standalone 章节补齐

- **场景**：用户批准的四项候选批次，双 Sonnet 代理并行（A=三代码修复+版本，B=standalone 三章节），Fable 审查验收
- **现象**：①头号修复=schema/wiki-schema.json 未打包致装机版 schema_validate.py 从未能跑——单源迁入 plugin/schema/（全部活引用同步更新），模拟安装布局固化为 Test 63；终验从安装缓存路径（2.15.4 cache）命中原始 FileNotFoundError 复现路径→valid ②图误报两类豁免共享 STRUCTURAL_FILENAMES 单一事实源（Tests 64/65 注坏验证）③B 组 standalone 章节降级语义诚实（mcp-server 直接标 standalone 完全不可用并给替代方案）④版本判定：Sonnet 以先例分析（minor 仅留新技能能力）推翻主会话预设的 2.16.0，定 2.15.4 patch——委派模式中实现者反向纠正协调者的实例 ⑤新发现：Test 17 解析器测试不密封（被本机真实 wiki 绑定污染，git stash 基线确认既有）→下批候选
- **预期**：装机版与源码版行为一致
- **插件改动**：kata dada4fb（2.15.4，push 57d3e3d..dada4fb，版本同步条件满足）；Tests 63/64/65 新增
- **复验结果**：✅ 终验（缓存路径 schema_validate valid）、重装内容一致、smoke 套件除既有 Test 17 外全绿、build_skill_md --check 过
- **遗留**：Test 17 密封性（下批候选）；史官触发节点纪律本次首实战（版本 push→SendMessage 事件提示）

---

## 2026-07-17 Chronicler 史官体系建立：haiku 常驻记录角色 + 独立 PR wiki，首跑即产出三项发现

- **场景**：用户需求=为个人与产品 IP/PR 积累素材；设计并落地常驻轻量记录角色——.claude/agents/chronicler.md（haiku）+ 独立 PR wiki ~/.llm-wiki/surebeli-ip（milestones/stories/metrics/drafts/queries 五分类，audience/maturity 维度素材状态机）+ CLAUDE.md 五类触发节点纪律；关键设计=拉取式采集（tail 协议产物文件，harnessloop 协议零侵入）+ haiku 捕获/Sonnet 成稿两级流水
- **现象**：①首跑回填 15 页（7 milestones/4 stories/4 metrics）质量合格（PR 钩子成立、数据带出处、schema 全过）②haiku 层两个真实缺陷：index 计数虚报 18（实数 15，已修 1f1e7cf，记账规则补入章程）与回执语言漂移到日文（语言纪律补入章程）——两级流水设计的必要性首日即验证 ③用户定语言政策=中文主（SCHEMA Language Policy 落盘 4182224，15 页转换进行中）④意外发现 kata 真实打包缺陷：已安装缓存的 schema_validate.py 因 schema/wiki-schema.json 在仓库根未被打包（marketplace source=./plugin）而无法运行——装机版校验形同虚设，此前未暴露因一直用 submodule 源码路径；记为 kata 下轮迭代候选（与 standalone 三技能章节缺口并列）
- **预期**：记录零负担、素材可检索、协议不受污染
- **插件改动**：无；新 agent 定义 + PR wiki 三 commit（fe70f4d 回填/1f1e7cf 计数修正/4182224 语言政策）
- **复验结果**：✅ 角色卡生效（回退方式运行，reload 后成一等类型）、拉取式采集准确（页面事实与工程文件核对无臆造）、schema/维度合规
- **遗留**：15 页中文转换在途；chronicler 作为一等 agent 类型待 reload 验证；kata 打包缺陷待修（候选批次：schema 打包 + orphan 结构文件豁免 + 示例文本悬空链豁免 + standalone 三章节）

---

## 2026-07-17 kata 第二轮 ingest：update-vs-create 纪律验证通过 + 一次有教育意义的假警报

- **场景**：ingest harnessloop 严格审查报告（213 行 + findings.json 外部引用）到已有 15 页的 wiki——本轮考点是 update-vs-create 判定（防重复页堆）
- **现象**：①更新 4 页 / 新建 3 页，判定标准清晰（实体是否已有专属页 × 信息结构是否新概念——如 design-debt 活 backlog 与主页"版本演化叙事"是不同信息结构故新建）②零 schema 演化需求——首轮钉住的枚举当轮即发挥治理作用 ③新建 harnessloop-design-debt.md 活 backlog（P2 逐项 open/已修状态 + m7/nm11/nm12/n9 复测表），后续迭代可直接消费 ④主会话验收时一次假警报：graph neighbors 返回 0 被疑为断链，实为输出契约是 layers BFS 分层而非 neighbors 键——消费方读错契约，非 kata 缺陷；教训=断言工具缺陷前先核对输出 schema ⑤两个真实噪音级观察点：orphan 检测将 SCHEMA/log/index 结构文件计入 true_orphans、log.md 头部格式示例的字面 [[wikilink]] 被计为 dangling link——kata 候选小改进（结构文件豁免/示例文本豁免）
- **预期**：wiki 生长而非重复
- **插件改动**：无；wiki commit 51be94f（18 页，hub 网增强：harnessloop.md in/out 10→13）
- **复验结果**：✅ schema valid、更新纪律合规（updated bump + sources 追加）、design-debt 邻居网完整
- **遗留**：两个噪音级观察点作为 kata 下轮迭代候选；下一步候选=两份 capability-map ingest 或 wiki-query 回填闭环实测

---

## 2026-07-17 kata wiki 启动与首次 ingest：全链路 live 验证零缺陷，复利效应实证

- **场景**：用户主导、主会话引导完成 kata 完整启动链——wiki-init 向导（域=AI 插件工程验证知识库、6 分类、plugin enum 维度、sync 就绪、git 化）→ 项目绑定（.llm-wiki.yaml + gitignore，实测绑定解析未回落 common）→ 首次 wiki-ingest（源=docs/validation-log.md 8 条记录）
- **现象**：①单源触达 15 页 + 38 对双向交叉引用——复利效应首次实证 ②kata 行为验证零缺陷：orientation guard 未跳过、自定义维度提示如期触发（用户答 cross）、raw 不可变捕获、schema guard 生效（写页代理对 3 处边界提案而非漂移）③验收三连全绿：schema_validate 0 错、三段检索命中排序合理（vendors/codex.md 居首）、图 hub 结构符合预期（plugins/harnessloop.md in/out 各 10）④首轮 schema 演化即发生：用户批准 type 枚举钉住、vendor 8 家全量预列（含 claude 标签作用域消歧）、sources 双形式约定——"SCHEMA 与 wiki 共演化"的设计当天走通 ⑤init 硬规则（wiki 不入源仓）纠正了我们此前"docs 文档 wiki 化"的直觉
- **预期**：kata 核心闭环（init→bind→ingest→search/graph/validate→schema 演化）全部可用
- **插件改动**：无（纯使用验证）；wiki 仓库三 commit：88cdd68（init）/0e4a496（首批 15 页）/7582f8d（schema 演化）
- **复验结果**：✅ 全链路通过
- **遗留**：sync remote 未配（休眠通道，多机需求出现时启用）；wiki-query 回填闭环与 session-ingest 待后续实战；下一步候选源=harnessloop-review-20260716.md（80 条发现）与两份 capability-map

---

## 2026-07-17 kata 首次迭代：版本漂移修复 + 内容审计发现两处协议文本缺口（2.15.3）

- **场景**：能力图谱发现的 kata 仓库版本漂移（根 SKILL.md frontmatter 2.13.0 vs 四处 manifest 2.15.2），用户指示优先修复；kata 首次走三插件迭代回路
- **现象**：①漂移为单点（仅根 SKILL.md frontmatter），但 CHANGELOG 内容审计（2.13.1→2.15.2 逐条判定）发现两处真实协议文本缺口——wiki-spec 的路径穿越防护说明（v2.13.1 安全加固）与 wiki-skill-create 的 --supplement-action 目录（v2.15.1）从未同步进 standalone 协议文本 ②注坏验证：精确复现原始漂移场景（SKILL.md 改回 2.13.0）新 Test 62 必挂并列出四源值 ③主会话验收时复现修复代理预警的既有环境问题（~/.git-ai/bin/git 封装在 fake-HOME 下 exit 126 致 sync 测试假性失败，真实 git 绕行后全绿）——顺带定位了本会话所有 git 操作报 syntax error 的根源 ④发现遗留结构缺口：session-ingest/federate/mcp-server 三技能在 standalone SKILL.md 从无独立章节（早于基线，记入 CHANGELOG 留后续）
- **预期**：版本单一事实源 + 机械防复发
- **插件改动**：kata 57d3e3d（v2.15.3，push 1a120d4..57d3e3d，四仓授权+版本同步条件满足）；Test 62 版本一致性守卫自动纳入 pre-commit 与 CI
- **复验结果**：✅ run_smoke.py 全绿（真实 git 下）、build_skill_md --check、dreaming eval gate precision/recall 1.0；重装 v2.15.3 内容级一致
- **遗留**：三技能 standalone 章节缺口（kata 后续迭代候选）；本机 git-ai 封装脚本自身的 bash 语法错误（用户环境，非本项目范围，建议用户抽空修）

---

## 2026-07-17 kata 引入：第三个被测插件入回路，同名碰撞排障与旧版退役

- **场景**：kata（surebeli/kata v2.15.2，LLM wiki 文档维护插件）按既有模式引入 test-harnessloop（submodule + 本地 marketplace 重指 + 脚手架脚本扩为三插件）——继 harnessloop、hopper-plugin 之后第三个纳入"边用边验证"回路的插件
- **现象**：①CHANGELOG 揭示 kata 即 ak-wiki 的改名后继（v2.0.0 rebrand，原文 "previously ak-wiki"），与本机已装旧版 ak-wiki@ak-llm-wiki v1.8.0 技能全同名碰撞（wiki-init/ingest/search/... 等 13 个同名），会话启动时只加载旧版 ak-wiki:* 前缀技能，新装的 kata:* 技能被压制、不可见 ②用户决策卸载旧版 ak-wiki 插件，reload 后确认 kata:* 前缀 v2.15.2 全部 18 个技能正确加载（含 session-ingest/spec/skill-create/federate/mcp-server 5 个新增技能）③三路并行深读同时发现 kata 的一条休眠外部通道（wiki-sync 依赖的 git remote，当前未配置/未激活）与仓库自身的版本漂移（SKILL.md frontmatter 停在 2.13.0，而 plugin.json/marketplace.json 已是 2.15.2）——后者被列为候选的首个 kata 迭代项 ④能力图谱生成过程中遭遇 API 529（服务端持续过载）连续 5 次重试才完成，累计中断约 40 分钟，期间 Workflow 的 resume 机制与退避重试策略均生效，最终三路读取任务完整拿到结果
- **预期**：kata 应能沿用此前 hopper-plugin 的引入模式顺利接入——submodule 落地、本地 marketplace 重新指向、脚手架脚本从两插件扩为三插件，且会话内 kata:* 技能前缀与仓库文档能力集（18 个 skill）一致，不受本机已装同源旧插件影响
- **插件改动**：无（本轮为纯引入，未触及 kata/ submodule 或 harnessloop/hopper-plugin 任何文件）
- **复验结果**：✅ `plugin-status` 显示 kata 内容级一致（与 submodule commit `1a120d4` / v2.15.2 一致）；卸载旧版 ak-wiki 并 reload 后，kata:* 全部 18 个技能实际调用可见（非仅静态清单），同名碰撞问题解除
- **遗留**：仓库自身版本漂移（SKILL.md frontmatter 2.13.0 vs plugin.json 2.15.2）待修，是候选的首个 kata 迭代项；把项目知识 wiki 化（`docs/validation-log.md`、`docs/*-capability-map.md` 等文档编译进 kata wiki）作为 kata 首个实战使用场景候选，尚待真实执行；`wiki-session-ingest` 涉密会话随 `wiki-sync` 外发的观察点（`--scrub-secrets` 未实现）目前仅为静态读到的风险点，待真实多机同步场景实战验证

---

## 2026-07-17 hopper-plugin 0.31.0 发布：首次授权 push，政策层从纪律升级为机制

- **场景**：hopper 边用边验证进入迭代阶段——用户采纳"effort 预制 + model 选择规则"三层政策方案并授权 push（附版本同步硬条件）；同一发布收拢三个批次：脚手架抽象档位化、--check-model 三档断言器、政策层机械化四项（dispatcher 政策消费/clamp 可见化/verified-latest 哨兵/setup 政策 lint）
- **现象**：①全 vendor probe 实测 8/8 连通，codex bundled 目录含本机旧 CLI 不可用的 5.6 代——"目录收录≠本机可用"成为 --check-model 三档语义的设计依据 ②codex CLI 升级到 0.144.5 后 gpt-5.6-sol/terra/luna 三模型 live 微测全部可用，knownGood 更新（版本门槛注记）③项目 AGENTS.md 政策列迁移为机器语法后 lint 零 unparseable 零警告，迁移中发现两个真实解析陷阱（转义竖线列错位、反引号破坏 OOB 判定）④批次 2 顺带修复 --write frontmatter 记录未解析字面量的真 bug ⑤API 中断两次（会话额度/服务端错误），SendMessage 续跑机制两次成功恢复
- **预期**：政策三层结构（frame 抽象档位 → AGENTS.md 项目政策 → 派发实例落盘）自洽运转
- **插件改动**：hopper-plugin 6fbcf3a（v0.31.0，首次授权 push eceee81..6fbcf3a）；定向单测批次合计 250+ 全绿，全量回归 845/852（7 失败为环境缺 express 的既有 dashboard 测试）
- **复验结果**：✅ 重装 v0.31.0 内容级一致；--setup 政策段在真实项目三态判定正确；--check-model 六案例全对；回落链/clamp/哨兵实跑验证
- **遗留**：评审行 Effort policy 静态 lint 显示 unbound（设计使然——vendor 派发时随机绑定，届时 per-vendor 表生效）；dashboard 测试的 express 环境缺口（上游既有）；README 版本徽章 0.12.0 历史遗留漂移（未在本批范围）

---

## 2026-07-17 hopper 首次实战：T-001 第三方对抗评审全链路走通，抓到 harnessloop 两个真缺陷

- **场景**：hopper 引入后首个真实派发——`.hopper/queue.md` T-001，codex 对 harnessloop submodule commit 6936fbc（setup wizard 完整实现）做只读对抗评审，兼验证 `hopper-plugin/ISSUE-codex-review-hijack.md` 记录的观察点
- **现象**：①首派 400 失败——vendor 默认模型 `gpt-5.6-sol` 超出本机 codex CLI 版本；新观察点：vendor 默认模型不可信，须钉缓存模型名而非依赖 vendor 默认值 ②重派 `--model gpt-5.5`（xhigh）成功，5 分钟（299.8s），结果 REWORK + 3 findings，107,893 tokens ③派发方按 `.hopper/AGENTS.md`「Codex 评审强制核对」三项逐一核对，全部通过：审查对象确为 brief 指定的目标（真实 commit/路径）、产物落在 brief 指定路径、两条 findings 经独立复现成立 ④跨仓劫持（ISSUE-codex-review-hijack 记录的已知问题）本次未复发——EXECUTION MODE 前导有效 ⑤同时坐实该 ISSUE 的另一半已知问题：review 任务在 codex 落地时仍是 `danger-full-access`，实证「不可靠地降级为只读」——只读性目前只能靠 brief 约定，没有机械保证 ⑥`--watch` 两次（首派失败、重派成功）均在终态正确退出，无悬挂
- **预期**：hopper 的 dispatch 生命周期（init-tasks → 预检三连 → dispatch → watch → result → 强制核对）应在真实任务上端到端可用，且暴露的观察点应可沉淀为后续验证清单（依据 `.hopper/AGENTS.md` Codex 评审强制核对条款、`hopper-plugin/ISSUE-codex-review-hijack.md`）
- **插件改动**：hopper 无改动（本轮为纯使用验证，未触及 hopper-plugin/ 任何文件）；harnessloop 因本次 findings 另开修复任务 TH-0009（见对应 evolution issue）
- **复验结果**：✅ 全链路走通——init-tasks → 预检三连 → dispatch → watch → result → 三项强制核对，均按预期完成
- **遗留**：finding 3（validate fixture 自证性问题）记录为已知局限，暂不重构；codex 默认模型不可信问题可考虑上报 hopper 上游，建议增加缓存模型名的 fallback 机制，避免 vendor 端默认值漂移导致派发直接 400

---

## 2026-07-17 setup wizard goal 完结：S4 live 验收通过，首个 dogfooding goal 达成

- **场景**：用户亲自 live 首跑 setup wizard（goal 20260716-001-setup-wizard round 0004，S4 live acceptance）——`/reload-plugins` 热加载插件后直接运行 `$harnessloop-setup`，无需重启会话
- **现象**：wizard 审阅模式正确识别既有五文件完成度 4/5，仅追问缺失类别（External Tools），用户选择记录 GitHub 条目；哨兵写入符合设计（`.harnessloop/setup/data-sources.md` External Tools 表新增 GitHub 行，user-confirmed）；完成度报告全部符合设计预期。另有一项新发现值得记录：`/reload-plugins` 热加载即刻生效，无需重启整个会话——这是比"重启会话"更快的插件生效路径，此前 round 0002 evidence-index.md E4 曾记录"已加载的 SKILL 文本钉在会话启动快照，落后于磁盘"的局限，本次实测 `/reload-plugins` 可绕开该局限，值得在后续 dogfooding 中优先尝试
- **预期**：wizard 五步流程（含审阅模式的"仅问缺口"设计）应在真实项目上端到端可用，而非仅在骨架项目/dry-run 中验证（依据 goal.md Success Condition 与 rounds/0003 round-summary.md Next Proposed Scope）
- **插件改动**：未改动（本条为纯验收记录，round 0003 已完成全部实现交付，round 0004 仅为 S4 live 验收 + 三项 Required Human Decisions 收口，未触及 harnessloop/ submodule 任何文件）
- **复验结果**：✅ 通过。`check_setup.py` 复核本项目返回完成度 5/5、`complete: true`，exit 0；收盘门 `verify_protocol.py` exit 0
- **遗留**：无。goal 20260716-001-setup-wizard 三项 Required Human Decisions（live 首跑、三档预设默认值"保持默认"、"7/7→8/8"阈值表述更新）全部解决，goal 判定 achieved 并归档（见 `.harnessloop/goals/20260716-001-setup-wizard/goal.md` ## Status、`.harnessloop/goals/20260716-001-setup-wizard/rounds/0004/decision.md`）。TH-0008（第三类 Rule B 误报，框架级问题）仍 open，与本 goal 归档无关，留待独立处理

---

## 2026-07-16 P1 setup wizard：harnessloop 首个 dogfooding goal 三轮完成

- **场景**：用 harnessloop 自身协议开发 setup wizard（goal 20260716-001-setup-wizard，rounds 0001-0003：round 0001 design 首次对抗评审 negative → round 0002 design-v2 复审 positive → round 0003 implement 先对抗评审 negative 后 minimal-fix 复核通过）
- **现象**：对抗评审两轮 negative 各拦下真实缺陷——设计轮（round 0001）M1（continue/loop 门语义与"每步可跳过"承诺自相矛盾，实测锁死本项目自身 continue）、M2（cost-context-policy 29 槽位判定算法无小节作用域定义、不可无歧义求值）、M3（lite 档 Evidence contract revision 条款与 harnessloop-evidence SKILL 强制人工确认硬约束冲突）三处必修项，另有 S1-S10 十项建议修复；实现轮（round 0003）M-A（wizard SKILL 引用不存在的 `todo_count` 字段、保留已废弃合并语义）、M-B（表格数据行判定过松、S1 哨兵锚定被任意杂文本旁路，实测证伪）、M-C（新技能家族配套缺口——`agents/openai.yaml` 与三处文档技能清单，scope-lock 规划遗漏）三处必修项，均按 minimal-fix 修复。机械门（verify_protocol.py Rule B）三类实战误报全部处置：TH-0006（正则/glob/裸域名等 6 条误报，已修复）、TH-0007（解析基准缺 `.harnessloop` 根导致 6 条误报，已修复，且是 round 0002 严格审查提前预测方案的逐字应验）、TH-0008（第三类——讨论语境中间目录相对片段误报，仍 open，已提出"项目树后缀匹配回退"增强提案，当前以 `verify:ignore` 手工止血 3 条）。文件契约两次纠正主会话转述漂移：一次是 round 0001 对协议硬约束的核对过程中，manifest "90 槽位"总数以设计文档原文为准较正，未被会话转述带偏；另一次是 round 0002 decision.md 裁决 (a) 纠正的"等核心文件"被主会话简化转述为"任一文件"（round 0001 decision.md:18 原文核实后以文件原文为准）。scope-lock 在 round 0003 内从 v1 扩围至 v2，走的是 control-contract.md 既定的"Scope-lock mutation: main session 自主（版本递增留痕）"授权路径，而非临时越权。另沉淀一条委派模式经验：批准的规格偏离（todo 双字段方案）必须同步广播给全部并行代理——本轮因未同步广播致 3 处接缝失配，主会话集成审查抓 2 处、对抗评审补抓 1 处
- **预期**：协议各机制（评审门/机械门/scope-lock/self-audit/决策留痕）应在真实 goal 中全部被触发且有效，而非仅存在于文档描述（依据 harnessloop/AGENTS.md 与 harnessloop-loop SKILL 协议条款）
- **插件改动**：harnessloop submodule 待提交 0.11.0（新增 `harnessloop-setup` skill + `check_setup.py` + `control-contract-profiles.md`；四个既有 SKILL.md 接线；`validate.py` 新增第 3 阶段共 8 阶段 28 断言；`harnessloop-setup/agents/openai.yaml`；README.md/docs/usage.md/docs/harnessloop-framework.md 三处技能清单更新）
- **复验结果**：✅ `npm run validate` 8/8（含新增断言，合计 28 断言全绿）；`claude plugin validate --strict` 通过；`verify_protocol.py` exit 0（TH-0008 三条 `verify:ignore` 豁免不影响判定）；所有新增 Python 代码在本机 Python 3.9.4（pyenv）实测无异常
- **遗留**：S4 live acceptance 待用户重启会话运行 `$harnessloop-setup` 首跑（round 0004，见 `.harnessloop/goals/20260716-001-setup-wizard/rounds/0004/scope-lock.md`）；TH-0008 增强提案待上游评估假阴性风险后决定是否实现；三档预设（lite/standard/strict）默认值最终措辞与 thresholds.md/setup/data-sources.md 中"7/7→8/8"阈值表述两项 Required Human Decisions 待用户确认

## 2026-07-16 P0 修复批次：审查驱动的四组框架缺陷闭环（Sonnet 执行 / Fable 审查模式首次运行）

- **场景**：docs/harnessloop-review-20260716.md 严格审查（80 条确认发现）后的 P0 修复批次；首次采用「写入任务委派 Sonnet 5 子代理、主会话 Fable 5 只读审查验收」工作模式，三个子代理并行修复
- **现象（修复前）**：①verify_protocol.py 机械门在已安装项目中零触发路径（12 个 SKILL.md 无一运行它）；②round_cost.py 按行累加同一 message 的多行 usage，实测 3.03x 虚高（审查报告区间 2.3–4.1x）；③secrets SKILL 硬编码仓库相对路径在安装后不可达，脚本调用写法三种并存；④channel_params.py 明文 store 0644 非原子写、二次 add 重置元数据、set→add 转换残留明文、audit 对 git 已跟踪 store 全盲
- **预期**：机械门在每轮收盘与 continue 门运行；成本账单按 message 计费一次；所有脚本路径用 <skill-dir>/<plugin-root> 占位符可解析；明文值 0600 原子落盘且绝不进入 git 可见区
- **插件改动**：submodule 三个 commit——0829b03（A 组：verify_protocol 接线 + 路径统一）、c221273（B 组：message.id 分组去重 + marker v2 跨窗口 pending 携带 + validate 阶段 6 回归断言）、66093fd（C 组：channel_params 加固 + channel-params.json.* 通配 ignore）
- **审查交互**：主会话审查共退回三轮补修——A 组 2 处同主题路径残留 + evolution issue 的 Created by 元数据不实（写成 fable-5，实为 sonnet-5 执行）；B 组 1 处注释与行为不符（stale pending 实为携带而非丢弃）；C 组 3 处新引入的泄露面（临时文件/损坏备份/.bak 均不被 gitignore 模式覆盖、备份继承 0644 权限）。三个代理均一次性完成补修
- **复验结果**：✅ 通过。`npm run validate` 7/7 全绿（含 B 组 6 条新增去重断言，修复前必挂）；plugin-reinstall.sh 重装后缓存与 submodule 工作区内容级一致（sha 66093fd）；B 组用本机真实 transcript 独立复算与修复后输出精确一致
- **遗留**：channel_params 并发写为 last-writer-wins（无文件锁，超出本批范围）；round_cost 尾部开放 message 延迟计费为有意取舍；validate 阶段 3 尚无 C 组五项新行为的固定 fixture；对应 evolution issue：TH-0002~TH-0005（.harnessloop/meta/evolution-issues/0002-0005）

## 2026-07-16 init 首触即崩：init_project.py 不兼容 Python 3.9

- **场景**：首次执行 `harnessloop:harnessloop-init` skill，按其 Preferred Setup 调用插件缓存内的 `init_project.py --project <本项目>`
- **现象**：`TypeError: write_text() got an unexpected keyword argument 'newline'`（init_project.py:76），退出码 1；7 个目录已建、0 个文件写入，项目半初始化。本机 python3 = 3.9.4（pyenv）
- **预期**：init 一次成功，产出 7 目录 + 12 文件骨架（依据 harnessloop-init SKILL.md Output Contract 与 init_project.py 设计）
- **插件改动**：init_project.py:76 改用 `path.open("w", encoding="utf-8", newline="\n")` 写入（`Path.write_text(newline=)` 是 3.10+ API，`open(newline=)` 全版本可用且语义等价）；submodule 内 commit 见 git log
- **复验结果**：✅ 通过。harnessloop 自身 `npm run validate` 7/7（其中第 2 关 init 冒烟正是用本机 3.9.4 执行，修复前必挂）；`scripts/plugin-reinstall.sh` 重装后重跑 initializer，12 个文件全部写入、幂等补齐半初始化状态、退出 0
- **遗留**：上游未声明最低 Python 版本（作者对抗性审查中的已知问题 n9），本例实际把隐性门槛抬到了 3.10；已记 evolution issue `.harnessloop/meta/evolution-issues/0001-init-project-py39-write-text-crash.md`，submodule 修复待 push 上游
