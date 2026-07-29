---
task_id: exp-p4-B
adapter: grok
model: grok-4.5
effective_selector: grok-4.5
effective_selector_source: policy
status: done
mode: background
phase: done
adapter_status: success
---

# exp-p4-B · code-review-adversarial · harnessloop `8f92fa3` (v0.30.0)

**评审对象**：`harnessloop` commit `8f92fa378c64f915e8e8803d59b8e183c2957886`  
**主题**：修 CI windows-latest 连红（stdout 编码 + G22a premise）+ 补版本一致性守卫 G28  
**方法**：只读；`git show 8f92fa3` 全文 + 从该 commit `git archive` 抽出真实树做最小变异攻击；不改 `harnessloop/` 工作树。  
**Assumption (one line)**：验收口径以 commit 引入的 G28 决策规则（`len(discovered) >= 3` 且 `len(all_versions) <= 1`）为准，不依赖后续已合入的 v0.33.2 `\d` 扫除。

---

## Summary

Commit 在 Windows CI 两条真实失败路径上的修法是对的：UTF-8 `reconfigure` 防中文 `print` 崩整跑；G22a 三分支 `_case_fixture_class` + G24a 承接是诚实 skip，不是把断言删掉。版本漂移的**经典形态**（`.codex-plugin/plugin.json` = `"0.11.0"` ASCII 而其余为 `"0.30.0"`）会被 G28a 抓红，发现式 walk + G28c 新路径牙齿也成立。  
但 G28 把「无合格 semver 的 manifest」直接从比较集里丢弃，再配 `len(discovered) >= 3` 地板——使得**历史上掉队的那一个文件**只要把版本写成带尾空格 / `v` 前缀 / 空串 / 删键，守卫就变绿。这是可复现的 silent-zero，不是理论风险。另：`SEMVER_VERSION_RE` 用裸 `\d`（Python `re` Unicode 数字），与本仓已知正则陷阱同形。  
**Verdict：`REWORK`**（Windows 面可收；G28 静默放行必须先补牙再宣称「版本一致性守卫」落地）。

---

## Files touched

none（只读对抗审；产物仅本文件）

---

## Acceptance verification (6/6 attack-surface families)

### 1. Parser bypasses — **N/A for markdown parsers; partial on G28 JSON value filter**

本 commit 未引入新的 markdown/协议字段解析器。G28 的「解析」是 JSON `version` 值过滤：

- 只认 key 精确等于 `"version"` 且 `isinstance(str)` 且 `SEMVER_VERSION_RE.match`
- 整数 schema `"version": 1` 正确排除（G28d 有牙）— OK
- 但非严格 `X.Y.Z` 字符串被**静默丢弃**（见 §2），不是 fail-closed

无 inline-code / fenced-block / 全角标点字段行绕过（本变更无此类 parser）。

### 2. Silent zero-check — **FAIL（blocking）**

**根因（`scripts/validate.py` @ 8f92fa3）**：

```text
discover_manifest_versions:
  except (json.JSONDecodeError, OSError): continue   # L147-148
  if found: discovered[path] = found                   # L151-152  ← 零合格 semver ⇒ 文件不进集合

G28a:
  check(len(discovered) >= 3, ...)   # L219  ← 允许少发现 1 个仍绿
  check(len(all_versions) <= 1, ...) # L226
```

docstring L139-142 明文合法化该行为：*「yields zero qualifying semver strings … is simply omitted -- it has nothing to be inconsistent with」*——对「整仓从无 version 的 marketplace」成立，对**曾经必须有 version 的 plugin.json 删键/写畸形**不成立。

**最小攻击（真实 8f92fa3 树 + 只改 codex plugin.json）**：

| attack | codex `version` field | discovery | G28a |
|---|---|---|---|
| baseline | `0.30.0` | n=4 `['0.30.0']` | GREEN |
| classic drift (historical) | `0.11.0` | n=4 `['0.11.0','0.30.0']` | **RED**（好） |
| **trailing space on lag** | `0.11.0 ` | n=3 `['0.30.0']` | **GREEN** |
| **v-prefix lag** | `v0.11.0` | n=3 `['0.30.0']` | **GREEN** |
| **delete version key** | `<MISSING>` | n=3 `['0.30.0']` | **GREEN** |
| empty string | `""` | n=3 `['0.30.0']` | **GREEN** |
| prerelease | `0.30.0-rc.1` | n=3 `['0.30.0']` | **GREEN** |

**Expected（若守卫兑现「版本一致」）**：含掉队/缺席 version 的 manifest → RED，并点名该路径。  
**Actual**：文件被过滤掉；其余三份一致 + `n>=3` → GREEN。  
**最狠一刀**：历史 bug 本体是 codex 停在 `0.11.0`；写成 `"0.11.0 "`（多一个尾空格）即可让**新建的 G28 对同一掉队文件静默放行**。开关握在被审计方手里。

**牙齿缺口**：G28b/c 只证明「合法不同 semver → 红」与「新路径被发现」；**没有** mutation 证明「缺键 / 非 semver 字符串 → 必须红」。绿的是发现机制，不是一致性语义的完备性。

`validate_manifests()` 虽会 `read_json` 四个已知路径（坏 JSON 会炸），但**从不要求 version 键存在**——与 G28 静默丢弃叠加后，删 version 全链路仍可绿。

### 3. Regex class traps (`\d` vs `[0-9]`) — **FAIL（secondary, reproducible）**

```text
L106: SEMVER_VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")
```

| input | `^\d+\.\d+\.\d+$` | `^[0-9]+\.[0-9]+\.[0-9]+$` |
|---|---|---|
| `0.11.0` | match | match |
| `０.１１.０` (U+FF10…) | **match** | no match |
| `١.٢.٣` (Arabic-Indic) | **match** | no match |

- 全角掉队 vs ASCII 其余 → 两字符串不等 → G28a **RED**（碰巧抓住）
- **四份全角相同** `０.３０.０` → G28a **GREEN**（把非 ASCII「版本」当成一致的合法 semver 集合）
- 注释/提交说明写的是 `\d+.\d+.\d+`，未声明 Unicode 数字意图

本仓后续在 v0.33.2 把同一 `SEMVER_VERSION_RE` 改成 `[0-9]` 并立 G35 扫除，侧面印证此为真实缺陷族；**但 8f92fa3 当下已带病合入**。

### 4. Cross-time-layer joins — **PASS / N/A**

无 round / decision / 跨轮账本 join。G28 只扫当前工作区 manifest；G22a/G29 是即时 fixture。不存在「用今日盘状态回判已关闭轮」路径。

### 5. Teeth shape vs property / green-by-construction — **PASS_WITH_NOTE**

| teeth | 判定 |
|---|---|
| G28b 变异合法 semver → 多版本 | **有牙**（属性级） |
| G28c 全新路径进入 discovery | **有牙**（反枚举） |
| G28d 整数 schema version 忽略 | **有牙** |
| G28 **缺键/畸形 version** | **无牙**（见 §2） |
| G29a `encode("cp1252")` 抛错 | **有牙**（证真实 crash 串） |
| G29a `stdout.encoding is utf-8` | **弱**：UTF-8 宿主上**无 reconfigure 也绿**；不证明 reconfigure 承重，只证明「当前进程是 UTF-8」 |
| G29b `_case_fixture_class` 三 fake | **有牙**（三分支在 macOS 可测） |
| G22a resolve-folds skip 文案引用 G24a | **诚实**：G24a 确以 symlink 测 `_same_dir` 不等拼写（L4780 一带） |

Windows 端到端无本机实跑——commit message 已诚实登记；不另作 FAIL。

### 6. OUT-column honesty — **FAIL（claims > code）**

| 声称 | 实际 |
|---|---|
| 「断言全一致，报错点名掉队文件」 | 仅对**进入 discovered 集合且为严格 X.Y.Z** 的值一致；掉队文件可通过不匹配过滤**不被点名** |
| 「发现而非枚举」 | walk 是发现式 — **成立**（G28c） |
| G28 地板 `>= 3` | 允许历史掉队路径完全不参与比较仍绿；「至少 3」不是「四份权威 manifest 皆在且一致」 |
| G29 防 Windows 崩 | reconfigure 方向正确；牙齿在非 Windows 上对 reconfigure **非破坏性对照** |

---

## Findings（severity）

### MUST-FIX-1 — G28 silent-zero on non-qualifying / missing version

- **家族**：silent zero-check  
- **位置**：`scripts/validate.py` `discover_manifest_versions` L147-152 + G28a L219-228  
- **复现**：见上表 Attack trailing-space / delete-key / v-prefix  
- **处方（审，不实现）**：
  1. 凡 basename ∈ `{package.json,plugin.json,marketplace.json}` 且 JSON 可解析：若存在任意 string `"version"` 键但**不**匹配 ASCII semver → **红并点名**（不要丢弃）  
  2. 对**已知必须带插件版本**的路径（至少两个 `plugin.json` + root `package.json` + claude `marketplace.json` 的 plugins[].version）：缺键 → **红**  
  3. 地板改为「权威集合全员在场」或 `n == expected` 的发现结果交叉，而不是 `>= 3`  
  4. 增 G28e 牙齿：对 fixture 写入 `"0.11.0 "` / 删键 → 必须 FAIL

### MUST-FIX-2 — `SEMVER_VERSION_RE` 裸 `\d`

- **家族**：regex class trap  
- **位置**：L106  
- **复现**：`re.match(r'^\d+\.\d+\.\d+$', '０.１１.０')` → match；`[0-9]` → None  
- **处方**：`^[0-9]+\.[0-9]+\.[0-9]+$`；牙齿断言全角数字**不得**进入 discovered 集合

### NOTE-1 — G29a 编码断言在 UTF-8 宿主 green-by-construction

不阻断合并意图，但若声称「teeth 证明 reconfigure 承重」，应在子进程里把 stdout 绑到 cp1252 pipe 做破坏性对照，而不是只读 `sys.stdout.encoding`。

### NOTE-2 — Windows 面（编码 + G22a）审查通过

- `reconfigure(encoding="utf-8", errors="backslashreplace")` 在 import 后、任何 check 打印前；`errors` 选型正确  
- `_case_fixture_class` 运行时探测、不硬编码 `sys.platform`；resolve-folds 分支诚实 skip 并指向 G24a  
- 版本四文件 bump 至 `0.30.0`（含长期停在 `0.11.0` 的 codex plugin.json）— 漂移本身在本 commit 已修

---

## Decisions / deviations

- 以 8f92fa3 树为唯一真理源；不把后续 v0.33.2 的修复算作本 commit 已具备的能力（仅作「缺陷族真实」旁证）。  
- 未跑完整 `validate.py`（避免与当前工作树/新版本混跑）；G28 决策逻辑按该 commit 源码逐字复刻于 tempfile 攻击中。  
- invalid JSON 静默 `continue` 对**已知四路径**会被 `validate_manifests` 的 `json.loads` 先炸，故不单列 MUST-FIX；对仅 G28 发现的新路径仍属 soft spot。

---

## Open questions

- none（攻击已闭合；处方级收口不依赖用户答疑）

---

## Verdict

**REWORK**

Windows CI 两条修复与 G28 对「干净 ASCII 版本漂移」的抓取成立；**不能**在 G28 静默放行（缺键 / 尾空格 / `v` 前缀等）与裸 `\d` 未修的情况下标 PASS。主阻断 = MUST-FIX-1；MUST-FIX-2 同批应收。

---

## Next recommendation

1. 按 MUST-FIX-1/2 改 G28：fail-closed 畸形/缺席 version + `[0-9]` semver + 权威路径全员在场断言 + G28e 破坏性牙齿。  
2. 可选：G29a 加子进程 cp1252 pipe 破坏对照，去掉 green-by-construction。  
3. 复验命令（概念）：对 archive(8f92fa3 修后树) 写入 `"version": "0.11.0 "` 于 codex plugin.json → `validate.py` 必须非 0 且消息含该路径。  
4. 再开一轮 acceptance 审确认静默放行表全红、经典 `0.11.0` 仍红、干净树仍绿。  
5. Windows 面可依赖 CI `windows-latest` 实跑关账（作者已声明无本机 Windows）。
