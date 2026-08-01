# kata 插件能力图谱

- **插件**：kata @ `1a120d4`（v2.15.2）
- **图谱生成日期**：2026-07-17
- **来源**：3 路并行深读（并非 3 次独立单读，而是同一批读取任务的 3 个视角）
  - Area A — 整体架构精读：18 个 wiki-* skill 全生命周期、文件协议、三层记忆 tier、自闭环设计
  - Area B — 读写权限边界分类 + 与本机已装 ak-wiki v1.8.0（改名前身）关系厘清
  - Area C — scripts/ 与 tests/ 结构、回归验证命令、CHANGELOG 修复史提炼
- **性质**：使用前快照（pre-use snapshot），不是使用后的验证结论——见文末说明

## 定位

kata 是一个**由 LLM 编译并持续维护的项目知识 wiki 插件**：扩展 Karpathy LLM-Wiki 理念（"compiled once, kept current"，非 RAG）——把项目业务语义（阈值、生命周期不变量、领域约定）编译进 wiki 页面本体，让 agent 写代码前先读约定而非每次查询重新推导。核心闭环：ingest → cross-link → query → filed-query 回填复利。当前定位 Phase 1：AI-paired engineering（Phase 2 团队 spec 仲裁仅在设计阶段）。它是 test-harnessloop 项目里继 harnessloop、hopper-plugin 之后**第三个被"边用边验证"方法论覆盖的插件**——本图谱是正式使用前的能力盘点，实战中的真实行为以 `docs/validation-log.md` 的实测记录为准。

---

## 边用边验证观察点（严重度排序，前置）

以下汇总三路读取的 `validation_watchpoints`（并前置个别标记安全风险的 `gotchas` 条目，如 session-ingest 外发风险），按"安全类 → 正确性类 → 版本核对类"排序合并去重，跨 Area 重复提及的观察点只保留一条、不逐 Area 重复列出。

### A. 安全类（路径穿越 / prompt 注入 / 涉密外发，最高优先级）

1. **spec_propagate.py 路径穿越修复史（v2.13.1 critical，已修，需观察复发）**——`spec_relationships` 的 `target` 字段曾可写 `../../` 或绝对路径，把 supersede banner / tier 归档翻转写到 wiki 根目录之外；现由 T-prop-6 回归测试护栏。**任何新的"按用户声明的 target 写文件"路径（auto-propagation Phase 3、federation 写路径等）都要对照 wiki-root 边界检查，不要预设穿越已根治。**
2. **外部插件 prompt 注入面（v1.4.0 command_template 移除史，长期加固机制）**——`.wiki-plugins.yaml` 的 `command_template` 字段因 shell 注入风险在 v1.4 被移除，改为 argv 数组 + `execve`（无 shell）；旧格式配置会被 `external_plugin_run.py` 直接拒绝执行。外部插件的返回内容会经注入标记消毒（`<system>`/`<|im_start|>`/"Ignore previous" 等 → `[[REDACTED-INJECTION-MARKER]]`）并按 `max_output_bytes`（1MiB）截断、子进程 env 走白名单、60s 超时。**验证外部插件接入时：确认配置用的是 `argv:` 而非旧 `command_template:`；检查落盘到 `raw/external/` 的文件 frontmatter 是否记录了消毒/截断事件。**
3. **session-ingest 涉密外发风险（未实现防护，待实战验证）**——`wiki-session-ingest` 写入的原始会话 dump 是 wiki 仓库内的 markdown 文件，会随 `wiki-sync` 一起 push 外发；`--scrub-secrets` 尚未实现。**涉密会话在 sync 前必须人工过目；此观察点当前仅为静态读到的风险点，尚待在真实多机同步场景中实战验证。**

### B. 正确性类

4. **frontmatter YAML 解析脆弱（`|` 块标量、`&` 锚点不支持，长期已知、仅容错未根治）**——`wiki_lib._parse_yaml_block` 至今不支持这两种 YAML 语法；v2.8.1 前坏 frontmatter 会让 `discover_pages` 整体崩溃（`wiki-search`/`wiki-query`/`spec_preflight`/MCP server 全灭），v2.8.1 后改为单页 skip + stderr 记录（`[discover_pages] skipped <path>: <error>`，Test 30 回归护栏）。**遇到搜索/查询"缺页"先看 stderr 有没有 skipped 行，而非怀疑内容缺失；新 ingest 含复杂 YAML 的页面务必检查；写页面 frontmatter 一律用单行带引号字符串。**
5. **编码回归（cp1252/Windows，CHANGELOG 最高频缺陷类）**——2026-05-14 曾因 `subprocess.run(text=True)` 缺 `encoding=` 导致 Windows 下 `stdout=None → json.loads(None) TypeError`（4/4 Windows CI job 红）；v2.8.1 MCP stdio 也有过 cp1252 中文乱码。**任何新增 subprocess 调用或非 ASCII print 都是复发点；本机是 macOS，Windows 路径本地测不到，改动后必跑 `run_smoke_ci.py`。**
6. **静默失败模式（两处已修，验证新配置块时别假设校验已生效）**——v2.11.1 前坏 `.federation.yaml` 静默返回空 peer 列表（已改 stderr 警告）；v2.13.1 前 schema 的 `spec_authoring` 块因 `$defs` 未被 `properties` 引用，任意垃圾配置都静默通过校验（已修）。**新增/修改配置块后应重新跑 `schema_validate.py` 确认真的会拒绝坏值，不要凭旧印象。**
7. **联邦子进程泄漏（v2.11.1 H1 已修，L2-L5 遗留未修）**——`MCPClient.connect()` 失败曾泄漏孤儿子进程（T-fed-6 护栏）；仍遗留：`except Exception` 过宽、reader queue 无界、Windows 管道缓冲边界未处理。**多 peer / flaky peer 场景下验证联邦查询要盯进程残留，不能只看返回结果。**
8. **Phase 3（spec auto-propagation）结构性缺陷未修，全部推迟到 v1.14（尚未落地）**——Codex 审计 hold-for-changes 列了 6 项：banner 写后成孤儿、`supersedes→refines` 不可逆转、多 superseder 合并冲突、无事务、并发 ingest 竞态、federated/local key 碰撞；`docs/PRD-v1.14` 存在但 CHANGELOG 无 v1.14 发布记录。**生产 wiki 不要开 `auto_propagation.enabled: true`；如果已经开了，上述 6 个场景每个都要实测一遍再信任结果。**
9. **行为基线：单次 ingest 应触碰 10-15 页交叉引用**——若实际只写 1-2 页且无交叉引用，说明 orientation（先读 SCHEMA.md/index.md/log.md）被跳过，或页面创建策略被违反；这是最易复现的协议漂移信号。
10. **tier 计算基线：tier 绝不落入 frontmatter（`tier_override` 手动钉住除外）**，由 `published_at`/`ingested_at` 现场算出。若页面 frontmatter 出现字面 `tier:` 字段即为协议违规；改阈值应立即生效，可用于验证。
11. **log.md 格式基线**：条目须 `## [YYYY-MM-DD] action | Title` 前缀（可 grep）；`wiki-sync` 的 union+sort 合并与 canonical hash 去重都依赖这一规范格式，畸形条目会破坏去重。
12. **wiki-lint 应产出内容层检查（缺口/矛盾/schema 演化提案），不能只是结构修复**——若 lint 只报断链就是功能退化；`--fix` 只应用安全项，验证时确认没有被静默扩大范围。
13. **watcher / dream 隔离性基线**：`wiki-watch` 永不自动跑 ingest（只写队列文件 `.wiki-ingest-queue.json`，`--drain` 必须显式）；`wiki-dream` 只读 `log.md` + frontmatter 日期，绝不读 mtime/会话内容——`git clone` 后重跑 dream 结果应完全可复现，可用作验证手段。
14. **wiki-sync 脆弱路径**：v1.8 MVP 只有 `log.md` 有自定义 merge driver，`index.md` 走 git 默认 3-way 合并——双机并发 ingest 时 `index.md` 冲突风险最高；push 竞态重试上限 4 次（1/2/4s）耗尽后需手动重跑；`--dry-run` 号称零副作用但仍会 `git fetch`（写 `.git/refs/remotes/`）；T-sync-21 计时阈值有 flake 史（10s→15s 放宽，Windows 子进程抖动）。**smoke/sync 偶发失败先怀疑计时类测试而非自己的改动。**
15. **dogfood 已知未决**：v1.6 `wiki-dream --apply` 的 Week-1 接受率仅 14%（PRD gate 是 60%），结论是 `--apply` 原语可能与真实用户意图通道不匹配（用户实际更倾向手写 `tier_override`）。**验证 dream 建议时不要假设 `--apply` 是唯一的正确使用方式。**
16. **测试薄弱区（5 项，实测前心里有数）**：① agent 编排层零自动化测试——`wiki-ingest`/`wiki-query`/`wiki-import` 的编排逻辑、`wiki-session-ingest` 多选 UX、`lint`/`digest` 的 LLM 部分，测试只覆盖确定性脚本；② 联邦仅 stdio 同机验证过，SSE 未实现（M2 已知：preflight 传本地路径给 peer，SSE 落地即坏）；③ dreaming 质量基准只有 `market_research` 一个 fixture；④ macOS 不在 CI 矩阵（CI 只有 ubuntu+windows）；⑤ `dump-llm` 恒为全量、跨会话 sweep 不支持。
17. **fixture 与真实差距（v2.8.1 教训"smoke 绿、真实用户红"）**：合成 fixture 全 ASCII + 规范 frontmatter，真实 wiki（110 页中文 + 块标量 ADR）曾当天翻车。**验证真实行为时必须用含中文/坏 frontmatter 的样本，不能只信 smoke 全绿。**

### C. 版本核对类

18. **[已解决，留痕] 安装版本核对**——三路读取当时，本机实际加载的插件前缀是旧版 `ak-wiki:*`（改名前身，≈v1.7-2.1 时代，仅 13 个 skill：config/digest/dream/graph/import/ingest/init/lint/query/search/sync/tier/watch），而仓库 checkout 的是 `kata` v2.15.2（18 个 skill，新增 wiki-spec/wiki-mcp-server/wiki-federate/wiki-session-ingest/wiki-skill-create）——彼时的建议是"真实调用前先验证目标 skill 是否存在、参数是否与本文档一致"。**该观察点已在图谱生成当日解决**：用户决策卸载旧版 `ak-wiki` 插件，reload 后确认 `kata:*` v2.15.2 全部 18 个技能正确加载（含 `--tier`、`--enforce`、`session-ingest` 等仓库文档里标注为"后期新增"的能力/参数）。此条保留仅作为"读前状态 vs 读后已处理"的留痕对照，后续调用 kata:* 技能时不应再假设旧版共存或前缀-能力不匹配的问题仍然存在。
19. **三份 manifest 手动同步，无自动 drift 检查**：根 `plugin.json`（Copilot CLI 专用，含 Claude Code 会拒绝的 `skills` 字段）、`plugin/.claude-plugin/plugin.json`（Claude Code 规范入口）、`.claude-plugin/marketplace.json` 三处版本号需手动同步；当前均为 2.15.2，但 **`SKILL.md` frontmatter 的 `version` 字段实测仍停在 2.13.0**，与 `plugin.json` 的 2.15.2 不一致——仓库文档自身已存在版本漂移，CHANGELOG 自行把该同步机制标注为待办，是本次读取发现的候选首个 kata 迭代项。
20. **文档自述数字不可尽信**：`marketplace.json` 描述文本仍写"13 skills"（陈旧，实为 18）；`mcp_server.py` 版本号曾硬编码过期（已改为读 `plugin.json`）；`SKILL.md` 与实现的漂移发生过多次（"并行"表述夸大、asyncio vs threading 不符、`external://` 死 URI 残留）。**改版本号时 grep 三处 manifest；改行为时同步检查对应 SKILL.md 描述，不要相信文档自报的数字。**
21. **本环境职责冲突防线（读取当时状态，供交叉参考）**：读取当时本机同时可解析到 ak-wiki v1.8（已装）与 kata（未装）两套插件对同一 wiki 目录、同一 `.llm-wiki.yaml` 的绑定；原则是同一 wiki 的写操作只用一个插件、两代 `wiki-sync` 不可混跑同一仓库（报告目录不同：`~/.ak-wiki/` vs `~/.kata/`，锁不互通）。此项与上条"安装版本核对"关联的现状已随旧版卸载而改变，此处保留仅供理解原始读取时的判断依据，不代表当前仍需两代共存防线。

---

## 按 Area 分节详情

> 三个 Area 的原始读取视角不同（整体架构 / 读写边界与 ak-wiki 关系 / scripts·tests 结构与修复史提炼），内容有重叠但各有侧重，为保证技术细节完整不做跨 Area 删减；`validation_watchpoints` 已抽取到上一节，此处不再重复列出。

### Area A — 整体架构与全生命周期能力

> 原始定位：kata 插件（litianyi-007/kata，仓库副本 v2.15.2，位于 `/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/kata/`）—— 实现并扩展 Karpathy LLM-Wiki 理念的 Claude Code 插件：由 LLM 编译并持续维护的项目知识 wiki（"compiled once, kept current"，非 RAG）。Phase 1 定位是 AI-paired engineering：把项目业务语义（阈值、生命周期不变量、领域约定）编译进 wiki，让 agent 写代码前先读约定。核心闭环：ingest → cross-link → query → filed-query 回填复利

**capabilities**

- 18 个 wiki-* skills 全生命周期：init(交互式按域提议分类)/import(5 阶段批量迁移+checkpoint 断点续传)/ingest(单源+图片本地化+自定义维度提示)/search(3-pass 冷启动扫描, >500 页自动 shell 到 qmd)/graph(frontmatter 过滤/BFS neighbors/最短路桥接概念/hubs/orphans, 无持久图库每次现扫)/tier/digest/query(带引用+置信度分级+回填)/lint(结构+内容缺口+schema 演化提案)/config/dream/watch/sync/spec/session-ingest/mcp-server/federate/skill-create
- 文件协议：SCHEMA.md=权威配置(页面类型/frontmatter 字段/tag taxonomy/创建策略/自定义维度/tier 阈值/wiki_id, 用户可编辑、与 wiki 共演化)；index.md=按分类分区的内容目录(查询先读 index)；log.md=append-only 日志, 格式 `## [YYYY-MM-DD] action | Title` 可 grep；raw/=不可变源(articles/papers/transcripts/external/imported/assets)；{categories}/=按域生成(软件项目常为 modules/features/bugs/decisions/queries/lessons)
- 三层记忆 tier：active(<365d)/archived(365-730d)/frozen(>730d)，由 published_at(回退 ingested_at) 即时计算、绝不落盘 frontmatter，页面 tier=其引用源的最新 tier，支持 tier_override 手动钉住；wiki-tier --show/--preview/--pin
- 自定义 frontmatter 维度：SCHEMA.md custom_dimensions 声明(name/type/required/refresh_on/applies_to)，ingest/import 按 refresh_on 提示，--set k=v 跳过提示，wiki-graph/Dataview 可查询
- 查询回填复利：wiki-query --file 把实质性答案写为 queries/*.md hub 页(4+ 页综合/新对比/涌现洞见即回填)；置信度四档 0.0-1.0 显式报告；真值变更时先呈现新旧矛盾再答
- 多机同步 wiki-sync：log.md 自定义 merge driver(union+sort+canonical hash 去重)，wiki_id 身份校验，force-push 检测，本地锁，sync 报告放 ~/.kata/sync-reports/(仓库外防自冲突)
- 自动做梦 wiki-dream：co-occurrence 策略(实体重叠 0.5/tag 复兴 0.2/引用命中 0.4)对 frozen/archived 页评分，候选写 dreaming/{date}.md，--apply 才升 tier；只读 log.md+frontmatter 日期，git clone 可复现
- watcher(wiki-watch)：轮询 raw/ 新文件入队，--drain 显式批处理，守护进程绝不自动 ingest
- spec 历史管理 wiki-spec：preflight 扫描相关先例 spec，spec_relationships frontmatter(supersedes/refines/extends/parallel/contradicts)入图，lineage 树视图(ASCII/JSON/Mermaid)
- work-loop bridge wiki-skill-create：生成项目本地 SKILL.md(<project>/.claude/skills/)，把 kata 查询/回填包进项目实际工作管线，4 模式 issue-fix/feature-build/bug-debug/custom，9 项静态校验+sentinel 注释
- session-ingest：增量捕获当前 CLI 会话的 keeper 洞见走标准 ingest 管线(Claude Code/Codex JSONL 适配器)
- 外部 fallback：.wiki-plugins.yaml 注册 argv 形式 CLI(逐 token 无 shell)，query miss → 外部工具 → stdout 存 raw/external/ → ingest 闭环
- 生态兼容：wiki 即 Obsidian vault([[wikilink]]/Graph view/Dataview/Web Clipper/Marp)；默认 git repo；可作 MCP server；4 条安装路径(Claude Code 插件/Codex 生成 skills/单文件 SKILL.md standalone/Copilot CLI)
- 确定性 Python 脚本(纯 stdlib, Python 3.10+)位于 plugin/scripts/：wiki_init/wiki_sync/merge_log/graph_query/search_naive/tier_compute/spec_preflight/schema_validate 等 22 个

**usage_entrypoints**

- 本机注意：当前环境已安装的是旧名前缀 ak-wiki:（kata v2.0.0 改名前叫 ak-wiki），仅 13 个 skills（ak-wiki:wiki-init/-ingest/-search/-graph/-tier/-digest/-query/-lint/-config/-dream/-watch/-sync/-import），缺 session-ingest/spec/skill-create/federate/mcp-server；真实调用应走 Skill tool 的 ak-wiki:wiki-* 名字，而 README 里的 /kata: 前缀对应 v2.x 新装
- 初始化：/kata:wiki-init --path=~/.llm-wiki/my-project --domain="..." [--categories=a,b,c] [--enable-sync] [--enable-dreaming] [--non-interactive]；脚本等价 python plugin/scripts/wiki_init.py --domain ... --categories ...；随后手动 git init -b main && git add . && git commit
- 单源入库：/kata:wiki-ingest <url|file|text> [--no-discuss] [--no-images] [--set project=alpha,owner=ops] [--batch]
- 批量迁移：/kata:wiki-import <path> --format=folder|obsidian|notion|confluence [--dry-run] [--resume]（--resume 仅在 .wiki-import-checkpoint.json 存在时）
- 检索：/kata:wiki-search <query> [--tag=..] [--type=..] [--tier=active|all|archived|frozen]（默认只查 active）
- 问答：/kata:wiki-query "问题" [--file] [--format=markdown|table|slides|chart|canvas] [--tier=..] [--external|--no-external]
- 图查询：/kata:wiki-graph --neighbors=<page> --depth=2 --format=mermaid | --shortest-path=a,b | --hubs | --orphans | --query="type: entity AND tags contains X" | --mode spec-history --seed <spec.md>
- 健康与概览：/kata:wiki-digest [--since=7d]；/kata:wiki-lint [--fix|--report-only]；/kata:wiki-tier --show|--preview --set-active=540d|--pin=<page>:active
- 同步：/kata:wiki-sync [--dry-run|--auto]（cron 链：wiki-sync --auto && wiki-dream）
- 做梦：/kata:wiki-dream [--apply --pages 1,3,5] [--explain <page>]；watcher：/kata:wiki-watch --start|--status|--drain|--stop
- spec 与工作流：/kata:wiki-spec preflight --new-spec <path> [--enforce]；/kata:wiki-session-ingest [--full]；/kata:wiki-skill-create [--pattern issue-fix|feature-build|bug-debug|custom] [--target claude-code|codex]
- 配置：/kata:wiki-config --show | --get memory_tiers.active_days | --set dreaming.confidence_threshold 0.55 | --validate
- 项目绑定：项目根放 .llm-wiki.yaml(wiki_path: ~/.llm-wiki/necall 或 project: necall，且应 gitignore)；或全局 ~/.llm-wiki/registry.yaml 的 projects: 映射；临时切换 export WIKI_PATH=... 或 LLM_WIKI_PROJECT=...
- Standalone 路径：把仓库根 SKILL.md 整文件粘给任意 LLM 即可运行同一协议（无 Python 脚本、无 sync 自动化）

**key_concepts**

- 编译而非检索：知识编译一次持续保鲜，交叉引用写进页面本体而非每次查询重推；'Retrieval re-asks. Compilation remembers.'
- 分工铁律：人只管选源、提问、编辑 SCHEMA.md；LLM 做全部记账(摘要/交叉引用/归档/一致性)，人(几乎)不写 wiki 页
- raw/ 不可变：修正写进 wiki 页而非源文件；文件系统是唯一事实来源(也是图本身，无第二数据存储)
- Orientation guard：任何 ingest/query/lint/digest 前必读 SCHEMA.md+index.md+近期 log.md，跳过会造成重复页和漏交叉引用
- Schema 治理：想加 taxonomy 外的 tag 或新页面类型时，暂停并提案 SCHEMA.md diff 而非静默漂移；一次操作触碰 10+ 现有页要先确认
- 复利效应：单次 ingest 通常触碰 10-15 页；一个 filed query 可 +17 条边成为 hub，下个 agent 会话先落到 hub 再写代码
- 宿主项目与 wiki 分离：插件全局装一次，wiki 内容独立于 ~/.llm-wiki/<project>/；9 级路径解析：--path/--wiki → WIKI_PATH → cwd 已在 wiki 根 → LLM_WIKI_PROJECT@LLM_WIKI_HOME → 最内层 .llm-wiki.yaml/.kata.yaml → ~/.llm-wiki/registry.yaml → git 根目录名 → 旧 ~/.kata/config.yaml → ~/.llm-wiki/common
- 初始化：/kata:wiki-init 交互式(域→分类→约定→建 raw/ 目录→写 SCHEMA.md/index.md/log.md)，最后建议 git init(不代做)；在项目 git repo 内运行默认建 ~/.llm-wiki/{repo-name}
- search vs graph：wiki-search 答'关于 X 我们有什么'(文本相关性)，wiki-graph 答'什么与 X 相连'(结构)；两者互补
- 分层产品模型：Base(Karpathy 原则) → Core(自闭环+做梦) → Phase 1 AI-paired engineering(现行) → Phase 2 团队 spec 仲裁(仅设计)

**gotchas**

- .llm-wiki.yaml 是单路径缓存：一个文件只能绑一个 wiki，写多条 wiki_path 只保留最后一条；多 wiki 用 registry.yaml 或每 repo 一个绑定文件；解析取离 cwd 最内层的绑定
- 路径解析未命中任何绑定时静默落到 ~/.llm-wiki/common —— 调用前先确认实际落点，别把项目知识写进 common
- query/import/dream 不会自动创建未初始化的 wiki，必须先 wiki-init；wiki-init 也不代跑 git init（只写 SCHEMA.md/.gitignore/.gitattributes 并建议）
- wiki_id 绝不可手改（SCHEMA.md ## Identity），sync 身份校验靠它；重置须 wiki-init --refresh-id 且所有对端一起重置
- 双机同日各跑 wiki-dream 会在 dreaming/YYYY-MM-DD.md 上产生普通 git 冲突（该目录无 merge driver）；只在一台机跑 dream cron 或错峰
- 中断的 wiki-import（残留 .wiki-import-lock / .wiki-import-checkpoint.json）会硬阻塞所有机器的 sync，先 --resume 或清理 checkpoint
- session-ingest 的原始会话 dump 是 wiki 仓库内 markdown，会随 wiki-sync 外发——涉密会话同步前必须过目（--scrub-secrets 尚未实现）
- SHM Phase 3 自动传播（supersedes → banner+归档+反链）默认关闭：源 spec 后续删除 supersedes 声明时无法自动回滚，事务性 reland 在 PRD-v1.14 里
- wiki-config --set 只能改已有标量：不能新增键/新 YAML 块/列表索引（custom_dimensions[0].x 不可达）；旧 wiki 补 dreaming: 块要手编 SCHEMA.md
- Standalone(SKILL.md) 路径无确定性脚本：>100 页搜索/图查询变慢，且无 wiki-sync 自动合并
- tag/页面类型必须在 SCHEMA.md taxonomy 内，否则应提案 schema diff 而非直接用；raw/ 只读，纠错写 wiki 页
- SKILL.md frontmatter version 停在 2.13.0 而 plugin.json 是 2.15.2 —— 仓库文档自身存在版本漂移；根 plugin.json(Copilot 用) 与 plugin/.claude-plugin/plugin.json(Claude Code 用) 需手动同步版本且字段故意不同(根有 skills 字段，Claude Code 的 manifest 必须没有)

---

### Area B — 读写权限边界分类 + 与本机已装 ak-wiki v1.8.0 的关系厘清

> 原始定位：kata 插件（litianyi-007/kata v2.15.2，位于 `/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/kata/`）——LLM wiki 维护系统；及其与本机已装 ak-wiki v1.8.0（`/Users/litianyi/Documents/Code/_ai-goods/AK-llm-wiki`）的关系厘清

**capabilities**

- 18 个 skill 全在 plugin/skills/ 下，均 user-invocable。按读写边界分类——纯只读：wiki-search（3-pass 检索，免 orientation）、wiki-graph（frontmatter 查询/邻居/最短路/hub/orphan，现算不建图库）、wiki-federate（跨 wiki MCP 查询，边界上强制只读，kata:// URI 引用）、wiki-mcp-server（把 wiki 暴露为 stdio MCP server，硬边界：ingest/import/pin/apply/enforce 永不跨 MCP 暴露）、wiki-digest（活动/主题/tier 分布报告）、wiki-config --show/--get/--explain/--validate、wiki-tier --show/--preview、wiki-lint --report-only、wiki-spec preflight（不带 --enforce 时纯 advisory）
- 写 wiki 的 skill：wiki-init（生成 SCHEMA.md/index.md/log.md/分类目录，支持 --non-interactive --template market_research）、wiki-ingest（写 raw/ + 建改页面 + 更新 index.md/log.md；有 --no-spec-preflight/--set/--page-type 等旁路）、wiki-import（批量迁移 Obsidian/Notion/Confluence/目录树，checkpoint 可续传）、wiki-session-ingest（读当前 CLI 会话转录→raw dump→多选知识点→走 ingest 管线，v2.14 起默认增量模式）、wiki-query --file（答案回灌 queries/；外部插件 fallback 输出存 raw/external/ 再 ingest 闭环）、wiki-lint --fix、wiki-tier --set-*/--pin（改 SCHEMA.md 阈值/页面 tier_override）、wiki-dream（默认写候选报告到 dreaming/{date}.md，--apply 写 tier_override: active 到页面 frontmatter，绝不自动 apply）、wiki-config --set（改 SCHEMA.md 标量）、wiki-spec --enforce + Phase 3 auto-propagation（会改被 supersede 的目标页：banner + spec_superseded_by + tier 归档翻转）
- 写 wiki 之外位置的 skill：wiki-sync（git pull/merge/push wiki 仓库，log.md union+sort 合并驱动；报告写 ~/.kata/sync-reports/ 避免自冲突；import 进行中/merge 进行中/身份不匹配/force-push/无关历史 5 种硬停）、wiki-watch（守护进程只写 .wiki-ingest-queue.json，绝不自动跑 ingest，drain 必须显式）、wiki-skill-create（在**项目仓库**生成项目本地 SKILL.md，把 kata query/ingest 织入项目工作流的 7 步闭环；4 种 pattern × 4 种 supplement-action snippet）
- templates/ 的角色：templates/market_research/{SCHEMA.md,index.md} 是 wiki_init.py --template market_research 写入的领域 starter（13 个分类、tag 分类学、memory tiers、dreaming 配置齐全），示范 SCHEMA.md 应有的全部配置块
- schema/wiki-schema.json 的角色：JSON Schema (draft 2020-12)，校验 wiki 的 SCHEMA.md 内嵌 YAML 配置块（wiki_id/categories/frontmatter_fields/tag_taxonomy/memory_tiers/custom_dimensions/page_creation_policy/sync/dreaming/spec_authoring/external_plugins 等 15 个顶层属性）；skills 行动前应先用 plugin/scripts/schema_validate.py 校验；同脚本 --validate-plugins-yaml 校验 .wiki-plugins.yaml
- plugin/CLAUDE.md 定义全局守则：wiki 路径解析链（--path → WIKI_PATH → cwd 在 wiki 内 → LLM_WIKI_PROJECT/LLM_WIKI_HOME → .llm-wiki.yaml/.kata.yaml → ~/.llm-wiki/registry.yaml → git 根名 → 默认 ~/.llm-wiki/common）；orientation guard（新会话先读 SCHEMA.md/index.md/log.md，init 和 search 豁免）；immutability guard（raw/ 只读）；scope guard（一次动 ≥10 页需确认）；schema guard（新页面类型/新 tag 先提议改 SCHEMA.md 而非静默漂移）
- 与 ak-wiki 的关系：同一产品谱系，kata 是 v2.0.0 rebrand 后的继承者（CHANGELOG 原文 'previously ak-wiki'）。ak-wiki v1.8.0 = 改名前快照（13 skills：config/digest/dream/graph/import/ingest/init/lint/query/search/sync/tier/watch）；kata v2.15.2 新增 5 个：wiki-spec(v1.13)/wiki-mcp-server+wiki-federate(v1.12)/wiki-session-ingest(v1.11)/wiki-skill-create(v1.15)。磁盘 wiki 格式跨代兼容，两插件会解析到同一 wiki 目录

**usage_entrypoints**

- 本环境现状：只有 /ak-wiki:wiki-*（v1.8）已装可用；/kata:wiki-* 尚未安装。装 kata 走 Claude Code：/plugin marketplace add <kata路径或 litianyi-007/kata> 再 /plugin install kata（入口 .claude-plugin/marketplace.json → source: ./plugin → plugin/.claude-plugin/plugin.json）
- slash 形式（装好后）：/kata:wiki-init、/kata:wiki-ingest <url|file|text>、/kata:wiki-search <query> [--tier=active|all]、/kata:wiki-query <question> [--file] [--format=table|slides|chart]、/kata:wiki-lint [--fix|--report-only]、/kata:wiki-tier --show、/kata:wiki-dream [--apply --pages 1,2,3]、/kata:wiki-sync [--auto|--dry-run]、/kata:wiki-spec preflight --new-spec <path> [--enforce]、/kata:wiki-federate search <q> --peers=a,b、/kata:wiki-session-ingest、/kata:wiki-skill-create --pattern issue-fix、/kata:wiki-watch --start/--status/--drain、/kata:wiki-config --show
- 不装插件的直跑脚本（macOS 用 python3，文档示例的 py -3 是 Windows）：python3 plugin/scripts/wiki_init.py --non-interactive --template market_research --path <wiki>；search_naive.py（搜索）；lint_naive.py（结构 lint，JSON 输出）；digest.py（活动/库存统计）；tier_compute.py；graph_query.py；spec_preflight.py / spec_propagate.py；wiki_dream.py；wiki_sync.py；wiki_watch.py；session_ingest.py；skill_scaffold.py（discover/render，--supplement-action source-search|web-search|doc-lookup|custom）；schema_validate.py <wiki>/SCHEMA.md 与 --validate-plugins-yaml；external_plugin_run.py --plugin X --query Q [--auto]
- MCP server 形式：python3 plugin/scripts/mcp_server.py --wiki ~/.llm-wiki/<name>，注册进 .claude/settings.json 的 mcpServers；暴露 wiki-search/wiki-graph(只读子集)/wiki-spec-preflight(仅 advisory)，wiki-query 明确不暴露
- 验证入口：python3 tests/run_smoke.py（30+ smoke 测试，.githooks/pre-commit 也跑它）；tests/run_dreaming_eval.py 配 dreaming fixtures
- wiki 绑定：项目根放 .llm-wiki.yaml（单路径 cache，应加入 .gitignore）或注册 ~/.llm-wiki/registry.yaml；多 wiki 共存靠 registry 或每目录绑定（最内层优先）

**key_concepts**

- 三层架构：raw/（不可变源，agent 只读）→ wiki 页面（agent 全权维护的 markdown）→ SCHEMA.md（用户可编辑、随 wiki 共同演化的权威约定，skills 读取并执行而非硬编码）
- 编译一次持续保鲜（vs RAG 每查重算）：交叉引用已建好、矛盾已标记；人只管投喂源和提问，agent 做全部记账
- memory tiers（active/archived/frozen）：由 published_at/ingested_at 现场计算、不落 frontmatter；页面 tier = 其引用源中最新 tier；tier_override 可手工 pin；查询类 skill 默认 --tier=active
- auto-dreaming：wiki-dream 用 co-occurrence 策略对照近期活动重估 frozen/archived 页面，候选人工确认后 --apply 复活——'frozen → resurgent' 是市场研究 wiki 的高频模式
- 自闭环原则：一切外部输入（外部插件输出、联邦结果、会话转录）都先落 raw/ 再走 wiki-ingest 管线，未来查询命中本地；v2.5.0 删除 external_sources 正是为守住此原则
- spec history management（v1.13）：新 spec 落库前 preflight 扫描既有 spec，声明 supersedes/refines/extends/parallel/contradicts 关系，可选 enforce 拒绝未表态的 ingest
- cross-wiki federation（v1.12）：每个 kata 既是 MCP server 又是 client，kata://<peer>/<path> URI 引用，跨边界只读，peer wiki_id 先验身
- work-loop bridge（v1.15）：wiki-skill-create 把'干活前查 kata、干完回灌 kata'固化为项目本地 skill 的结构默认，而非靠自觉

**gotchas**

- kata 在本会话未安装——available skills 只有 ak-wiki:* 前缀；直接喊 /kata:wiki-* 会失败，先装 marketplace 或直跑 plugin/scripts/*.py
- raw/ 绝对只读：纠错写 wiki 页面，永不改源文件；wiki-watch 守护进程也只写队列文件
- 一次操作 ≥10 个既有页面必须先向用户确认（scope guard）；新 tag/新页面类型先提议改 SCHEMA.md（schema guard）
- .llm-wiki.yaml 是单路径 cache（一文件一 wiki），且属每机本地状态应进 .gitignore；共享映射放 ~/.llm-wiki/registry.yaml
- wiki-dream 和 wiki-watch 都设计为'绝不自动写'：dream 的 apply、watch 的 drain 都必须显式触发
- MCP server 的 stdout 是 JSON-RPC 线路，诊断只能走 stderr；注册多个 wiki 就注册多个 server 实例
- kata 的 skill 输出有统一格式契约（[Operation]/[Changes]/[Summary]/[Suggested next]），验证行为时可据此核对声称的 Created/Updated 文件列表是否与磁盘一致
- docs/ 目录混有 PRD/TRD/dogfood 记录和 essay 草稿，是设计史料不是使用文档；以 plugin/CLAUDE.md、各 SKILL.md 和 CHANGELOG 为准

---

### Area C — scripts/ 与 tests/ 结构、回归验证命令、CHANGELOG 修复史提炼

> 原始定位：kata 插件（litianyi-007/kata v2.15.2，LLM wiki 维护）—— scripts/ 与 tests/ 结构、回归验证命令、CHANGELOG 修复史提炼（仓库根：`/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/kata`）

**capabilities**

- 18 个 skill（plugin/skills/）：wiki-init/ingest/search/query/graph/tier/digest/lint/import/dream/watch/sync/config/spec/session-ingest/mcp-server/federate/skill-create；确定性算法全部落在 plugin/scripts/ 的 22 个 stdlib-only Python 脚本（wiki_lib.py 为共享库：页面发现、frontmatter/YAML 子集解析、图构建、tier 计算）
- spec 历史管理（v1.13 SHM）：spec_preflight.py（advisory + --enforce 门禁，exit 2=strict 拒绝）、spec_propagate.py（supersedes 自动传播：banner+反链+tier 翻转，opt-in PREVIEW）、graph_query.py --mode spec-history（text/json/mermaid 血缘视图）
- 跨 wiki 联邦（v1.12）：mcp_server.py（JSON-RPC 2.0 stdio，只读工具 wiki-search/wiki-graph/wiki-spec-preflight，写技能硬边界不暴露）、federation_client.py（MCPClient + kata:// URI + .federation.yaml 注册表，ThreadPoolExecutor 并行 fan-out，5s/peer 超时）
- 会话摄取（v1.11/v2.14）：session_ingest.py detect/dump/dump-llm/state/config，支持 Claude Code + Codex JSONL 增量 dump（状态文件 raw/sessions/.session-ingest-state.yaml），其它 CLI 走 LLM-dump 全量
- 工作循环桥（v1.15）：skill_scaffold.py discover/render/verify/list-patterns，4 模板（issue-fix/feature-build/bug-debug/custom）+ 4 supplement-action snippet，生成带 kata:generated-skill 哨兵注释的项目本地 skill
- 测试基础设施：tests/run_smoke.py（约 61 个冒烟测试，自建 50 页合成 fixture，纯 stdlib，Py3.10+）、run_smoke_ci.py（CI 环境仿真包装器）、run_dreaming_eval.py（dreamer 精确率/召回率基准门禁）、build_fixture.py / build_dreaming_fixture.py（fixture 生成器，产物 gitignored）
- 外部插件安全运行器 external_plugin_run.py：argv 列表制（无 shell）、替换后 shell 元字符拒绝、prompt-injection 标记消毒、输出限量 1MiB/超时 60s、子进程 env 白名单

**key_concepts**

- wiki 是单根自闭合编译产物：~/.llm-wiki/{project}/，SCHEMA.md 唯一权威配置，raw/ 不可变，index.md+log.md；三层记忆 tier（active/archived/frozen，按 published_at 计算，可用 frontmatter tier_override: active 钉住）
- 多 wiki 解析链（wiki_lib.find_wiki_root）：--wiki/--path → WIKI_PATH → LLM_WIKI_PROJECT → 项目本地 .llm-wiki.yaml/.kata.yaml（单路径缓存，建议 gitignore）→ ~/.llm-wiki/registry.yaml → git repo 名 → ~/.llm-wiki/common；KATA_HOME/~/.kata 为机器级状态
- v2.0.0 品牌重构：/ak-wiki:* → /kata:*，AK_WIKI_HOME → KATA_HOME；注意本机当前安装的插件前缀仍是 ak-wiki:（仅 13 个 skill，约 v1.x 版本），而 checkout 的仓库是 v2.15.2 kata（18 skill）——调用时前缀与能力集不匹配要先确认
- 三份 manifest 需同步 bump：根 plugin.json（Copilot CLI 专用）、plugin/.claude-plugin/plugin.json（Claude Code 规范入口）、.claude-plugin/marketplace.json；当前均为 2.15.2，但无自动 drift 检查
- spec_authoring 分相开关：Phase 0 advisory（v2.2）→ Phase 2 enforce（v2.4，enforcement_score_threshold/mode）→ Phase 3 auto_propagation（v2.12，默认 off，PREVIEW）→ Phase 4 lineage view（v2.13）；Phase 1 external_sources 已在 v2.5.0 整体移除（违反自闭合原则，ADR 记录）
- kata:// URI 双形态：kata://<peer-name>/<path>（日常）与 kata://<wiki_id-uuid>/<path>（长期引用）；联邦只读契约，peer wiki 永不被写，跨 wiki supersede 记进本地 .spec-reverse-index.yaml

**usage_entrypoints**

- 主回归命令：python tests/run_smoke.py（约 61 测试，exit 0/1，Py3.10+ 纯 stdlib；pre-commit 与 CI 都跑它）
- 推送前 CI 仿真：python tests/run_smoke_ci.py（假 HOME、剥离 KATA_HOME/LLM_WIKI_* 等开发机状态、空 git 全局配置、PYTHONUTF8=1；--keep 保留假 HOME 供尸检；失败自动保留）
- dreamer 质量门禁：python tests/run_dreaming_eval.py --fixture market_research --gate（precision≥0.7 / recall≥0.5，CI 在 smoke 后跑）
- 文档同步检查：python scripts/build_skill_md.py --check（根 SKILL.md 技能表 drift，exit 1 = 需跑无参版本重新生成）
- fixture 重建：python tests/build_fixture.py --out tests/fixture（50 页合成 wiki；植入 hub=attention/transformer、orphan-page、frozen>730d 页、最短路 attention→transformer→claude-3）
- 钩子启用：git config --local core.hooksPath .githooks；CI 全量：.github/workflows/test.yml（ubuntu+windows × py3.10-3.13，PYTHONUTF8=1，另有 schema-check job：python -m compileall plugin/scripts/ tests/ + wiki-schema.json JSON 合法性）
- skill 调用形态：/kata:wiki-*（v2.x）；本机已装插件是 ak-wiki:wiki-*（旧版 13 skill）。脚本直调：python plugin/scripts/<script>.py，如 spec_preflight.py --new-spec <draft> [--enforce] [--federate]、graph_query.py --mode spec-history --seed <page> --format mermaid、session_ingest.py detect|dump|state show、skill_scaffold.py discover|render|verify
- MCP server：python plugin/scripts/mcp_server.py --wiki <path>（无 SCHEMA.md 拒绝启动；只读工具面）

**gotchas**

- 运行任何验证命令都会写文件：run_smoke.py 重建 tests/fixture（gitignored）+ 多个临时目录；run_dreaming_eval.py 在仓库根写 _tmp_dream_<fixture>.json；run_smoke_ci.py 建假 HOME 临时目录（失败时强制保留）。『只读』阶段不要跑
- wiki_lib 的 YAML 子集解析器不支持 `|` 块标量和 &锚点 —— 页面 frontmatter 用了会被跳过（v2.8.1 后 skip+log 到 stderr，之前直接炸整个 discover_pages）。写页面时 frontmatter 一律单行带引号字符串
- Windows/编码是头号历史雷区（tests/AUTOMATED_TESTS.md 是强制规范）：subprocess.run(text=True) 必须显式 encoding='utf-8' + 子进程 PYTHONIOENCODING=utf-8；env= 传 dict 是替换不是合并；git fixture 必须 config core.autocrlf=false + 本地身份；路径断言用 pathlib 不用裸字符串；本机是 macOS，CI 只有 ubuntu+windows，windows 行为本地测不到——改动后必跑 run_smoke_ci.py
- .federation.yaml 的 command: 数组里 Windows 盘符路径必须加引号（裸冒号被 YAML 子集当映射分隔符）；command 写成字符串而非列表会被 list() 拆成单字符（v2.11.1 M4 已加校验）
- 布尔配置只认字面 true：auto_propagation.enabled 与 enforce_relationship_declaration 在 v2.13.1 后用 `value is True` 判断，字符串 'false'/'true' 都不生效
- run_smoke.py 的 run() 默认允许 exit code {0,1} —— 脚本以 1 失败退出时测试不报错，只有 JSON 解析失败才 FAIL；新增断言要注意这个宽松默认
- pre-commit（git config --local core.hooksPath .githooks 启用）Stage 0 合规黑名单扫描（.compliance-blocklist.txt，含 author/committer 身份）无条件执行；smoke+SKILL.md drift 仅在 plugin/scripts|skills|schema|tests|scripts|SKILL.md|CHANGELOG 变更时执行
- 改 plugin/skills/*/SKILL.md 的 frontmatter（name/version/description/argument-hint）必须跑 scripts/build_skill_md.py 重新生成根 SKILL.md 的自动表格，否则 --check 在 CI/pre-commit 挡下

---

## 使用须知

本图谱是**使用前快照**（基于 2026-07-17 的一次只读并行精读），不是实测结论。三路读取过程中已经发现至少一处仓库自身的版本漂移（`SKILL.md` frontmatter 停在 2.13.0，而 `plugin.json`/`marketplace.json` 已是 2.15.2，见「版本核对类」第 19 条）、一处在读取当天于本机被主动解决的环境状态变化（旧版 `ak-wiki:*` 卸载、`kata:*` v2.15.2 全部 18 技能加载，见「版本核对类」第 18 条），这本身说明静态阅读的结论有时效性，需要动态复核。**一旦在真实任务中使用 kata，凡是实战发现与本图谱不符之处，一律以实测为准，并记入 `docs/validation-log.md`。**
