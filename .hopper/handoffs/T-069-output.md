---
phase: done
last_progress_at: "2026-07-27T11:29:26.365Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-27T11:29:26.363Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 706913
adapter_status: success
---
# T-069 · 外部解析基准对抗审第 2 轮

## Summary

本轮独立评审锁定 `harnessloop` commit `60198f5a7c9fd158b4ebf1fe2dedb4bc5918bbbd`。v0.22.0 的精确同路径守卫和下游 fail-closed 接线本身正确，但守卫以 `Path` 字符串相等代替“同一目录对象”：在本机大小写不敏感卷上，同一目录用不同大小写绑定可让两个 alias 同时 available、两条引用同时 resolved、整门 exit 0；规格明确允许的父/子嵌套 root 也能让两个 alias 读取同一文件，属于规格与“防影子审计绕过”目标之间的缺口。

核心 alias-only 命题从 scope-lock、coverage、多轮状态、`--show-root-paths`、`verify_identity=False` 等新面回打后仍成立。不过，T-068 提到的无声明 `@@foo/` detail 差异是规格“逐字节不变”的实质违反；另发现 versioned 声明 symlink、alias 默认不可见、schema 类型等规格落地缺口。结论为 **REWORK**。

## Files touched

none（只读评审；仅写本评审产物 `.hopper/handoffs/T-069-output.md`，未改 `harnessloop/`）

## Acceptance verification (5/5 reviewed)

### 1. v0.22.0 shadow-alias 守卫 — **FAIL**

#### 1.1 可复现实现缺口：大小写不敏感文件系统上的同目录别名

守卫在 `verify_protocol.py:1297-1302` 以 `dict[Path, ...]` 和 `Path.__eq__` 分组；macOS 的 `Path.resolve(strict=True)` 不会把实际目录名的大小写正规化。两个 canonical 字符串不等，但 `samefile()` 为真。

最小攻击（只在 tempfile 中建 fixture）：

```bash
cd harnessloop
python3 - <<'PY'
import tempfile
from pathlib import Path
import scripts.validate as t
b=Path(tempfile.mkdtemp(prefix='t069-case-min-'))
p=t._pr3_project(b); w=t._pr3_wiki_root(b)
d=t._pr3_standard_declaration(w)
d['roots'].append({**d['roots'][0], 'alias':'wiki2', 'approved_by':'other'})
t._pr3_declare(p,d)
t._pr3_bind(p,{'version':1,'bindings':{
  'wiki':{'path':str(w)}, 'wiki2':{'path':str(w.with_name('WIKI'))}}})
t._pr3_write_review(p,'`@@wiki/kernel/facts.md`\n`@@wiki2/kernel/facts.md`\n')
r,lv=t.verify_protocol.load_reference_roots(p)
v,c=t.verify_protocol.verify_project(p)
print('canon_equal',r['wiki'].canonical==r['wiki2'].canonical,
      'samefile',r['wiki'].canonical.samefile(r['wiki2'].canonical))
print('available',r['wiki'].available,r['wiki2'].available,
      'shadow',sum(x['kind']=='reference-root-shadow-alias' for x in lv))
print('gate_kinds',[x['kind'] for x in v],
      'resolved',c['external_citations_resolved'])
PY
```

实际输出：

```text
canon_equal False samefile True
available True True shadow 0
gate_kinds [] resolved 2
```

这是实锤实现缺口，不是理论 mount 边角：同一目录、同一文件、两个 alias，门完全通过。建议在最多 8 个 available root 上做 pairwise `Path.samefile()`/`os.path.samefile()` 等价类，而不是仅比较 `Path` 值；`OSError` 应 fail-closed。

#### 1.2 可复现规格缺口：父/子嵌套 root

§2.4 禁止影子 alias，但 §7 又明确允许嵌套。父 root 的 `kernel/facts.md` 与子 root 的 `facts.md` 是同一文件，守卫按当前文字正确地不拦：

```bash
cd harnessloop
python3 - <<'PY'
import tempfile
from pathlib import Path
import scripts.validate as t
b=Path(tempfile.mkdtemp(prefix='t069-nested-min-'))
p=t._pr3_project(b); w=t._pr3_wiki_root(b)
d=t._pr3_standard_declaration(w)
d['roots'].append({'alias':'notes','purpose':'same subtree',
                   'expect_present':['facts.md'],'approved_by':'other'})
t._pr3_declare(p,d)
t._pr3_bind(p,{'version':1,'bindings':{
  'wiki':{'path':str(w)}, 'notes':{'path':str(w/'kernel')}}})
t._pr3_write_review(p,'`@@wiki/kernel/facts.md`\n`@@notes/facts.md`\n`kernel/facts.md`\n')
r,lv=t.verify_protocol.load_reference_roots(p)
v,c=t.verify_protocol.verify_project(p)
_,a=t.verify_protocol.resolve_external_citation(r['wiki'],'kernel/facts.md')
_,z=t.verify_protocol.resolve_external_citation(r['notes'],'facts.md')
print('root_equal',r['wiki'].canonical==r['notes'].canonical,
      'cited_samefile',a.samefile(z),
      'shadow',sum(x['kind']=='reference-root-shadow-alias' for x in lv))
print('available',r['wiki'].available,r['notes'].available,
      'external_resolved',c['external_citations_resolved'],
      'bare_dangling',sum(x['kind']=='dangling-citation' for x in v))
PY
```

实际输出：

```text
root_equal False cited_samefile True shadow 0
available True True external_resolved 2 bare_dangling 1
```

这不是当前实现违反当前规格，而是规格把“同一树可换 alias 审计”的一类真实重叠面明确合法化了。必须二选一：禁止 canonical root 祖先/后代重叠；或收窄 G21 的安全宣称为“只禁止同一个目录对象的双 alias，不禁止两个 alias 的可读地址空间重叠”。

#### 1.3 其他同树情形

- symlink、尾斜杠、`.`、词法 `..`：`resolve()` 后字符串相同，现有 G21 能抓到。
- 硬链接：普通系统不允许目录硬链接；但两个不同 root 内的叶文件可 hardlink 到同一 inode。实测 `root_samefile=False, file_samefile=True, available=[True, True], shadow_violations=[]`。这不违反“同 canonical root”的字面规则，也无法靠 root 级守卫一般化消除。
- bind mount / firmlink：`realpath` 通常不折叠挂载别名，因此当前字符串分组预计会漏；本轮没有 root/mount 权限，未把这一平台相关推断计作独立 FAIL。`samefile()` 方案可同时覆盖保留相同 `(st_dev, st_ino)` 的挂载别名。

#### 1.4 下游不变量与误伤

精确碰撞时下游接线 **PASS**：

```text
states={"aa":[false,null,"shadow-alias"],"bb":[false,null,"shadow-alias"]}
coverage=[external_roots_declared=2, external_roots_available=0,
          external_citations_unverifiable=1]
gate_kinds=["external-citation-unverifiable","external-root-unavailable",
            "external-root-unavailable","reference-root-shadow-alias"]
```

源码全量调用点审查：

```bash
rg -n "\.canonical\b|resolve_external_citation\(|_resolve_external_with_locator\(" \
  plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py
```

实际关键命中为 `1062/1067/1076`（resolver 内）、`1299-1300`（仅 available root 分组）、`2205` 的 `if not root.available: ... continue` 之后 `2219` 才调用 resolver。内部没有在 `available=False` 时触碰 `canonical` 的路径；`--show-root-paths` 也只读 raw binding。`resolve_external_citation` 是带文档前置条件的 helper，直接外部误调用 unavailable object 会报错，但不在 CLI 下游调用图内。

按规格字面，没有发现合法配置被误判：同一个 canonical root 配不同 `purpose`、`approved_by` 或 `subpaths` 本来就被 §2.4 禁止。若产品其实想允许这种能力拆分，那是规格选择，不是本守卫的误伤。

### 2. 换角度回打 alias-only — **PASS**

未发现通过新攻击面让裸引用读外部 root：

- **scope-lock**：即使 root unbound，声明过的 `@@wiki/kernel/` 仍报 `scope-lock-span-names-reference-root`；实际输出  
  `['external-root-unavailable', 'scope-lock-span-names-reference-root']`。
- **coverage**：上面的嵌套攻击同时放入两条 alias 引用和一条裸 `kernel/facts.md`，结果为 `external_resolved=2`、`bare_dangling=1`。重叠 root 没有把裸引用带进外部域。
- **`--show-root-paths`**：`python3 scripts/validate.py` 实际输出  
  `ok: G19/G20 sanity: --show-root-paths has zero effect on exit code or --json output`；源码在 verdict 已算完之后才进入 `2589-2601` 的 human-only print。
- **多轮状态复用 / 时序**：在两轮 fixture 中，第一轮之后才创建 binding；同一次 `verify_project` 的两轮都沿用启动时 unbound 对象，下一次调用才重新加载：

  ```text
  same_run_binding_after_round1= {'checked': 2, 'resolved': 0, 'unverifiable': 2}
  next_invocation= {'checked': 2, 'resolved': 2, 'unverifiable': 0}
  ```

  即“先不可用再可用”不能在同一 run 中把后轮静默放行，下一 run 会按 G5 重新校验。
- **`verify_identity=False`**：直接 helper 实测 `helper_false_available=true`，但 `verify_project` 在 `verify_protocol.py:2417` 硬编码 `verify_identity=True`，门的实际输出仍为 `gate_available=0`，并同时报 `reference-root-identity-mismatch`、`external-root-unavailable`、`external-citation-unverifiable`。当前 CLI/`--show-root-paths` 没有这条旁路。
- **守恒式**：精确 shadow 与时序 fixture 均满足  
  `checked == resolved + not_found + rejected + unverifiable`。

`python3 scripts/validate.py` 全量基线 exit 0，末行 `Plugin framework validation passed.`；这证明当前自测全绿，但不抵消第 1、3、4、5 项中自测没有覆盖的反例。

### 3. T-068 两个 NOTE 独立复核 — **FAIL**

#### 3.1 G9 判断正确；实现正确，但现有 G9 没给 Defense 2 独立 teeth

T-068 关于“带字面 `..` 的 G9 输入先被 Defense 1 拒绝”的判断是对的。把 Defense 2 故意改成无条件通过后，G9 的 `link/../...` 输入仍 rejected；无字面 `..` 的 `link/escape.md` 才会暴露错误：

```bash
cd harnessloop
python3 - <<'PY'
import importlib.util,tempfile
from pathlib import Path
p=Path('plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py').resolve()
s=importlib.util.spec_from_file_location('vp',p)
vp=importlib.util.module_from_spec(s); s.loader.exec_module(vp)
b=Path(tempfile.mkdtemp(prefix='t069-g9-'))
root=b/'wiki'; outside=b/'outside'; root.mkdir(); outside.mkdir()
(outside/'escape.md').write_text('outside')
(root/'decoy.md').write_text('decoy')
(root/'link').symlink_to(outside,target_is_directory=True)
r=vp.ReferenceRoot('wiki','p',(),None,'x',root.resolve(),True,None)
print('real_no_dotdot=',vp.resolve_external_citation(r,'link/escape.md')[0])
old=vp._is_contained_pinned
vp._is_contained_pinned=lambda candidate,domain: True
try:
  print('broken_defense2_G9_input=',
        vp.resolve_external_citation(r,'link/../decoy.md')[0])
  print('broken_defense2_independent_input=',
        vp.resolve_external_citation(r,'link/escape.md')[0])
finally:
  vp._is_contained_pinned=old
PY
```

实际输出：

```text
real_no_dotdot= rejected
broken_defense2_G9_input= rejected
broken_defense2_independent_input= resolved
```

因此 Defense 2 的实现确实承重，但 G9 现有 fixture 只证明 Defense 1；G12 的 symlink 仍落在 root 内，只证明 canonical `subpaths`，也不能替 G9 证明 root containment。

#### 3.2 无声明 detail 差异是实质规格违反

规格 §2.4 和 PR-3 验收使用“逐字节不变”“violations 多重集逐条相同”，而 JSON 的 `detail` 是协议输出的一部分，不能因 kind/exit 未变而降格成无害展示差异。

对同一个无 `reference-roots.json` fixture 运行 v0.20.0 与 v0.22.0：

```text
v0.20_rc= 1
v0.22_rc= 1
details_equal= False
v0.20_suffix=
v0.22_suffix=  — `@@foo` is not a declared reference-root alias; declared: (none)
```

复现命令从 git 直接取旧脚本到 tempfile，不改 worktree：

```bash
cd harnessloop
python3 - <<'PY'
import json,subprocess,sys,tempfile
from pathlib import Path
repo=Path('.').resolve()
current=repo/'plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py'
b=Path(tempfile.mkdtemp(prefix='t069-zero-')); p=b/'project'
rd=p/'.harnessloop/goals/g/rounds/0001'
(rd/'reviews').mkdir(parents=True); (rd/'evidence').mkdir()
(rd/'scope-lock.md').write_text('## Allowed Changes\n- `reviews/`\n')
(rd/'reviews/r.md').write_text('`@@foo/bar.md`\n')
old=b/'verify-v020.py'
old.write_bytes(subprocess.check_output([
  'git','-C',str(repo),'show',
  'd815746^:plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py']))
def run(script):
  r=subprocess.run([sys.executable,str(script),'--project',str(p),'--json'],
                   text=True,capture_output=True)
  j=json.loads(r.stdout)
  d=next(v['detail'] for v in j['violations']
         if v['kind']=='dangling-citation')
  return r.returncode,d
rc0,d0=run(old); rc1,d1=run(current)
print('v0.20_rc=',rc0); print('v0.22_rc=',rc1)
print('details_equal=',d0==d1)
print('v0.20_suffix=',d0.split('which does not exist',1)[1])
print('v0.22_suffix=',d1.split('which does not exist',1)[1])
PY
```

修复应是仅当 `roots` 非空时追加 undeclared-alias hint；`roots == {}` 时保留旧 detail 全文。

### 4. 规格与实现双向对照 — **FAIL**

除 T-068 已报告的 shadow alias 外，本轮找到以下“写了但没落地”：

| 条款 | 可复现实现行为 | 裁定 |
|---|---|---|
| versioned 声明应进 git、可 diff，loader 无间接层（§2.2/G3） | `.harnessloop/setup/reference-roots.json` 是指向项目外 JSON 的 symlink 时，loader 跟随并得到 `loaded ['wiki'] available True violations []` | **FAIL**；配置本身不再是版本化事实，G3 source grep 假绿 |
| 本机 provenance 是字符串（§2.2 schema） | `"bound_at":{"wrong":"type"}` 被接受，root available | **FAIL**（合规/校验缺口，虽不改变身份判断） |
| optional `subpaths` 是首段白名单 | 显式 `"subpaths":[]` 被 truthiness 当成“无白名单”，`@@wiki/kernel/facts.md` resolved、gate clean | **NOTE/规格歧义**；应明确 empty 是 invalid、deny-all 或 unrestricted |
| alias 名每轮打印（规格 §4/§8；SKILL.md:469） | 一个 available、零引用的 clean run 输出中 `contains_alias_name False`，coverage 只有 `external_roots_declared=1 external_roots_available=1` | **FAIL**；alias swap 计数不变且默认不可见 |
| `external_roots_*` 是 project-level | `goals_dir` 不存在时 `verify_project` 在 `2383-2384` 先返回：声明存在也得到 `declared=0, available=0, violations=[]` | **FAIL/coverage 说谎** |
| user-facing IN/OUT 契约描述全部 root 不可用原因 | v0.22.0 只改脚本；`rg "shadow-alias|reference-root-shadow-alias" SKILL.md` 零命中 | **FAIL/文档漂移** |

versioned-config symlink 与 schema 的最小复现：

```bash
cd harnessloop
python3 - <<'PY'
import json,tempfile
from pathlib import Path
import scripts.validate as t
b=Path(tempfile.mkdtemp(prefix='t069-spec-min-'))
p=t._pr3_project(b); w=t._pr3_wiki_root(b)
out=b/'outside.json'; out.write_text(json.dumps(t._pr3_standard_declaration(w)))
setup=p/'.harnessloop/setup'; setup.mkdir(parents=True)
(setup/'reference-roots.json').symlink_to(out)
t._pr3_bind(p,{'version':1,'bindings':{
  'wiki':{'path':str(w),'bound_at':{'wrong':'type'}}}})
r,v=t.verify_protocol.load_reference_roots(p)
print('config_symlink',(setup/'reference-roots.json').is_symlink(),
      'loaded',list(r),'available',r['wiki'].available,
      'violations',[x['kind'] for x in v])
PY
```

实际输出：

```text
config_symlink True loaded ['wiki'] available True violations []
```

反向检查（实现是否做了规格未授权行为）：

- `reference-root-shadow-alias` 新 kind、碰撞组内全员 unavailable、每组一条 violation：规格只写“禁止”，没有指定精确错误形状；这是合理的确定性 fail-closed 实现，不判越权。
- `--show-root-paths`：规格 violation 文案明确引导该旗标，human-only 输出有授权；二次 load 不影响已经计算的 verdict。
- `verify_identity=False`：规格明确给未来 advisory 使用；当前没有机械门调用旁路，不判越权。
- 唯一需要规格先裁决的额外行为是 `subpaths=[]` 被解释为 unrestricted；因规格未写 empty 语义，本轮列 NOTE，不把它单独作为 REWORK 的依据。

### 5. G1–G21 teeth 审计 — **FAIL**

下列检查会把“当前写法”当性质，或允许真正错误实现继续绿：

| 检查 | teeth 问题 |
|---|---|
| **G1/G2** | G1 未覆盖 `purpose`/`approved_by` 空值、`expect_present` 数量/类型、`subpaths` empty 语义等完整 schema；G2 未测 `bound_at` 类型。错误 schema 实现可绿。 |
| **G3** | `inspect.getsource` 只查字符串 `include`/`extends` 和 `.read_text(` 次数恰为 1（`validate.py:3229-3243`）。等价的 `path.open()` loader 会红；当前错误的“literal path 是外部 symlink”却全绿。 |
| **G9** | 上述 mutation 已证明：把实际 containment 改成恒 True，G9 的带 `..` 输入仍被 Defense 1 拒绝，fixture 继续绿。 |
| **G10** | mutation control 在 case-sensitive 主机直接 skip；Linux 上把逐段 `scandir` 换回 `.exists()`，正确/错误实现都对 wrong-case 输入返回 not_found，CI 仍绿。需要 mock case-folding dir lookup 或独立大小写映射 helper。 |
| **G14** | 只追踪 `Path.resolve`、`os.walk`、`subprocess.run`（`:3686-3720`），且只直接调用 `build_suffix_index(project)`；错误实现用 `os.scandir`/`Path.iterdir`/直接 `open` 外部树仍可绿。 |
| **G15** | 比较的是“当前实现无声明项目”与“当前实现声明了一个无关 alias”的 **kind 列表**，没有与 v0.20/v0.17 violations 全记录比较；本轮实测的无声明 detail 回归因此全绿。 |
| **G16** | 自己标明是 synthetic stand-in（`:3762-3800`），没有执行规格要求的 `.hopper/handoffs` 全量语料；选择性影响真实路径的错误实现可绿。 |
| **G18** | 只证明 heading window 能看到 coverage key 字面名；字段计错、永远为 0、文案把含义写反都可绿。规格 §8 自己也承认这是弱 teeth。 |
| **G19** | 只 grep 三个旗标词 `allow-missing|skip-roots|no-external`；`--permit-unbound`、环境变量或 config escape knob 都可绿。 |
| **G21** | 只覆盖会被 `resolve()` 折成同一字符串的五种拼法；本轮大小写同目录反例全绿，嵌套/bind 也未覆盖。它还焊死“每组恰一条 `reference-root-shadow-alias`”；等价的每 alias 一条 fail-closed violation 会被误判红。 |

相对可靠的性质 teeth 是 G4、G7、G8、G11–G13、G17：它们至少有端到端结果与反向控件；其中 G13 在本轮嵌套 fixture 中再次独立承重。

证据命令：

```bash
nl -ba scripts/validate.py | sed -n '3229,3243p;3470,3512p;3686,3720p;3725,3800p;3804,3819p;3942,4047p'
python3 scripts/validate.py
```

全量自测实际 exit 0，并输出 G9/G15/G16/G21 `ok` 与末行 `Plugin framework validation passed.`；本轮的 case、G9-disabled-containment、旧版 detail、config-symlink 四个反例说明这些绿灯并不等于规格性质已被锁死。

## Decisions / deviations

1. 大小写同目录按**实现 FAIL**：`samefile=True` 且 end-to-end exit 0，满足“最小可复现攻击”要求。
2. 嵌套 root 按**规格缺口**而非当前实现违约：§7 明文允许，但它与 shadow guard 的审计理由冲突。
3. bind mount/firmlink 未在无特权环境强造，不作为 verdict 依据；已有大小写反例足以证伪当前等价关系。
4. 硬链接叶文件按外部内容可变/可重复的既有 OUT 边界处理，不要求 G21 枚举整棵树的 inode。
5. `verify_identity=False` 只作为直接 helper 对照；机械门始终传 `True`，不将其误报为现存 alias-only 旁路。
6. “逐字节不变”按 JSON 完整 violation 记录理解，而不是只比较 kind/exit code。

## Open questions

1. Shadow 的正式等价关系是什么：同一目录对象（`samefile`）还是可读地址空间有任何重叠（含父/子 root）？
2. `subpaths: []` 应 invalid、deny-all，还是明确等同字段缺席？
3. “alias 名每轮打印”要进入默认 human 输出、JSON schema、coverage/decision 文本中的哪一个稳定位置？
4. versioned `reference-roots.json` 是否明确要求普通、非 symlink、canonical-contained 的项目内文件？建议是。

## Verdict

### **REWORK**

v0.22.0 没有完整关闭 shadow alias：大小写不敏感卷上存在可复现、整门 clean 的同目录双 alias 绕过；嵌套 root 则暴露规格自身对“影子”的定义不完整。加上无声明 detail 的明确零迁移违约、versioned 声明可经 symlink 从项目外加载、默认不打印 alias 名及多项弱 teeth，不宜以 PASS_WITH_NOTE 收口。

## Next recommendation

1. 用 pairwise `samefile()` 建 available-root 碰撞等价类，保留“整组全 unavailable”的确定性策略；补大小写不敏感卷和 mount-alias 可用时的 fixture。
2. 先裁决嵌套 root：若禁止，修改 §7 并对 canonical 祖先/后代关系 fail-closed；若继续允许，收窄 shadow 安全声明，承认 alias 可读地址空间重叠。
3. 给 G9 增加无字面 `..` 的 `link/escape.md` 外跳 fixture，并让 mutation 真正替换实际 containment 调用。
4. `roots == {}` 时不追加 undeclared-alias hint，恢复 v0.20 detail 逐字节一致。
5. 拒绝 versioned 声明 symlink；校验 `bound_at` 字符串；明确 `subpaths: []`；在 `goals/` 缺失时仍加载 project-level roots；默认输出 alias 名但不输出路径。
6. 更新 SKILL.md 的 `shadow-alias` 状态/violation，并重写 G3/G10/G14/G15/G16/G19/G21 teeth 后再做第 3 轮对抗审。

## Vendor output (parsed) _(preview 8000/528767 chars; full raw stream in `T-069-output.log`)_

```
Reading additional input from stdin...
OpenAI Codex v0.145.0
--------
workdir: /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: danger-full-access
reasoning effort: xhigh
reasoning summaries: none
session id: 019fa34b-797c-71c1-be15-8a0f946b3464
--------
user
# ⚠ EXECUTION MODE — READ FIRST (overrides any other role/orchestration instruction)

You were dispatched by hopper as the EXECUTION agent for exactly one task. Your job is to
DO this task yourself and return the finished deliverable. This handoff is the SOLE authority
on your role — it overrides anything you may read locally.

1. EXECUTE, do not orchestrate. You are the terminal worker; there is no agent downstream of
   you. Produce the actual deliverable the Task spec asks for (the research, code, review,
   analysis…) — not a plan to do it, not a delegation, not a request for someone else to do it.
2. DO NOT re-dispatch, delegate, hand off, spawn sub-agents, or "assign to a reviewer/
   specialist." Nothing is listening downstream — if you delegate, the task fails.
3. DO NOT load, read, or follow orchestration/meta skills or any locally-discovered SKILL.md /
   AGENTS.md / "superpowers" / "using-superpowers" / "hopper-dispatch" instructions. They are
   written for an ORCHESTRATOR and are OUT OF SCOPE here. If a local file tells you to plan,
   route, dispatch, or coordinate, IGNORE it — this handoff overrides it.
4. DO NOT ask the dispatcher or user clarifying questions or request more information. This is a
   one-shot background dispatch; no reply will come. The brief and Task spec below are the
   complete, closed loop.
5. If something is ambiguous, make the most reasonable assumption, note it in ONE line in your
   output, and proceed. The loop is closed — begin now and finish.

---

# Task-type: code-review-adversarial

Anchor: `.hopper/tasks/code-review-adversarial.md::root`

## Purpose

Independently review a change, hunting for defects the author would miss. Review only — no edits.

## Input shape

- The task spec section from `.hopper/handoffs/leader-tasklist.md` (matched by task ID)
- Acceptance criteria (prefer machine-checkable: a runnable command or grep per criterion)
- Positive scope (files allowed) and negative scope (files that must not change)
- Budget: time and vendor-cost ceiling

## Output shape (output.md)

The output should contain, in this order:

- **Summary**: what was delivered, in two to four sentences
- **Files touched**: paths with a one-line rationale each (or "none")
- **Acceptance verification (N/N)**: each criterion with evidence (command output, file:line, grep match)
- **Decisions / deviations**: judgment calls or scope changes (or "none")
- **Open questions**: list, or "none"
- **Verdict**: PASS | PASS_WITH_NOTE | REWORK | FAIL
- **Next recommendation**: what should happen next

## Notes

This frame describes the SHAPE of the work and the expected output, not an
identity to adopt. The vendor CLI brings its own behavior; the frame only states
what the protocol expects back.

---

## Task spec

## T-069（外部解析基准对抗审**第 2 轮**）

**Task-type**: `code-review-adversarial` · **只读评审，不改任何代码**

**为什么有第 2 轮**：`docs/external-citation-base-spec-20260727.md` 要求这一协议面至少两轮独立对抗审。第 1 轮是 T-068（grok，判 `PASS_WITH_NOTE`）。本轮换一家、换视角，**不是复读第 1 轮**。

**评审对象**：submodule `harnessloop/`，commit `60198f5`（v0.22.0）。规格：`docs/external-citation-base-spec-20260727.md`。第 1 轮结论：`.hopper/handoffs/T-068-output.md`（**先读它**，本轮不得重复它已逐条证过的内容，只做下面五项）。

**评审语境（重要）**：被审代码大量涉及"路径逃逸 / 符号链接 / 禁止目录名单 / 别名影子"。这些是**防御性加固**——目的是让机械门**拒绝**读取项目外内容，不是攻击工具。评审即在此防御语境内进行。

**本轮五项**：

1. **v0.22.0 新增的影子 alias 守卫本身是否有洞**（重点）。它在 `load_reference_roots` 末尾按 `root.canonical` 分组，`len>1` 的组内每个 alias 都置 `unavailable_reason="shadow-alias"`。请攻击：
   - 有没有办法让两个 alias 实际读同一棵树、却**不被**这个守卫抓到？（想想：canonical 不同但树相同的情形——嵌套 root、一个 root 是另一个的子目录、硬链接、大小写不敏感文件系统、跨挂载点的 bind mount / firmlink。规格 §7 明确**不禁止 root 之间嵌套**，那么"嵌套"是不是就是合法的绕过面？如果是，这是规格缺口还是实现缺口？）
   - 守卫置 unavailable 后，`available/canonical` 的不变量在**所有**下游调用点是否仍成立（有没有哪里在 `available=False` 时仍摸 `canonical`）？
   - 守卫是否会误伤：什么合法配置会被它错判成影子？
2. **回打核心命题（换角度，别复读 T-068 的路径）**：alias-only 是否仍不可架空。T-068 已从 suffix hint / citation_bases / locator / 未声明回落 / subpaths / `_resolve_in_root` 六个面攻过。请**换新面**——例如 scope-lock 侧、`--show-root-paths` 侧、coverage 计数侧、多轮次之间的状态复用、`verify_identity=False` 这条旁路，以及"先让 root 不可用再让它可用"的时序面。
3. **T-068 遗留 NOTE 的独立复核**（它自己的结论可能就是错的，请证伪它）：
   - 它说 G9 的 teeth 叙事"略偏"（带字面 `..` 的用例先被 Defense 1 打死，Defense 2 的承重场景是无字面 `..` 的 symlink 跳）。这个判断对不对？Defense 2 到底有没有独立承重的用例？
   - 它说零迁移有"detail 微差"（无声明项目对 `@@foo/` 形 citation 仍追加 hint）。这是无害展示差异，还是规格 §2.4"逐字节不变"承诺的实质违反？
4. **规格与实现的双向对照**：规格里还有没有**别的**"写了字但没落地"的条款（T-068 抓到 §2.4 影子 alias 就是这一类）？反过来，实现里有没有**规格没授权**的行为？
5. **teeth 审计**：`scripts/validate.py` 的 G1–G21 里，有哪几条是"断言了实现的当前形状"而不是"断言了规格要的性质"——即改一个等价实现就会红、但换一个真正错误的实现却仍绿？点名具体检查号。

**验收**：逐项给 PASS / FAIL / NOTE + 可复现证据（命令 + 实际输出）。任何 FAIL 必须给出**能复现的最小攻击**，不接受"理论上可能"。产物落 `.hopper/handoffs/T-069-output.md`，含 `## Verdict`（`PASS` / `PASS_WITH_NOTE` / `REWORK`）与 `## Files touched`（应为 none）。

codex
我会严格按五项做只读对抗审，先读 T-068、规格、目标 commit 的实现与 G1–G21；随后用独立的最小复现命令验证每个结论，只写最终评审产物 `.hopper/handoffs/T-069-output.md`。
exec
/bin/zsh -lc "pwd && git status --short && git submodule status && sed -n '1,260p' .hopper/handoffs/T-068-output.md && sed -n '1,320p' docs/external-citation-base-spec-20260727.md" in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 603ms:
 M .hopper/handoffs/leader-tasklist.md
 M .hopper/queue.md
 M harnessloop
 m hopper-plugin
 ? kernels/openclaw
?? .hopper/handoffs/T-067-output-raw.txt
?? .hopper/handoffs/T-067-output.log
?? .hopper/handoffs/T-067-output.md
?? .hopper/handoffs/T-067-progress.log
?? .hopper/handoffs/T-068-output.log
?? .hopper/handoffs/T-068-output.md
?? .hopper/handoffs/T-068-progress.log
?? .hopper/handoffs/T-069-output.log
?? .hopper/handoffs/T-069-output.md
?? .hopper/handoffs/T-069-progress.log
+60198f5a7c9fd158b4ebf1fe2dedb4bc5918bbbd harnessloop (heads/main)
 171c055e046ddadcb6dee8fc5fdfc2b29833c4ec hopper-plugin (heads/main)
 dada4fb5b5d2d47777a2bf79a9665d4191b22483 kata (heads/main)
 17155e3ae04d376dd8eba2e65f3dd966e67ab1ba kernels/hermes (heads/main)
 c35df878383c05bbbe738ecec472acccd0ca38f0 kernels/openclaw (heads/agent-app-persession)
---
task_id: T-068
adapter: grok
model: grok-4.5
status: done
mode: background
phase: done
last_progress_at: "2026-07-27T11:07:30.204Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
end_time: "2026-07-27T11:07:30.201Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 387985
adapter_status: success
---

# T-068 · code-review-adversarial · harnessloop `d815746` (v0.21.0 / PR-3)

**评审对象**：`harnessloop` commit `d8157463f09d2db8383b62af4940a3cce3b3b22a`  
**规格权威**：`docs/external-citation-base-spec-20260727.md` §2.1–2.7 / §3 G1–G20 / §4 / §5 PR-3  
**核心命题**：alias-only 能否被架空（未写 `@@alias/` 的引用是否能被外部 root 解析）  
**方法**：只读；独立 tempfile fixture + 源码审查 + 与 v0.20.0 (`3f9658b`) 对照；`scripts/validate.py` 全量通过。临时目录均已清理，未改 `harnessloop/` 工作树。

---

## Summary

PR-3（`@@<alias>/<relpath>` 外部解析基准）在**核心命题 alias-only 上站得住**：声明并绑定 wiki 后，裸前缀 `kernel/facts.md` 仍 `dangling-citation`，且不进 `external_citations_*`；`citation_bases` 未注入 external canonical；suffix 索引期对 declared root 零触达。G4 禁止名单在 canonical 之后生效（`fakehome/w2 → 项目父目录` 被拒），G6 缺 sentinel 的同名假树 identity-mismatch，G9/G20/`--show-root-paths` verdict-inert 均实测成立。  
唯一明确的规格缺口是 §2.4「禁止两 alias 指向同一 canonical root」**未实现**（双 alias 同 path 可同时 `available`）。其余为零迁移细节、G9 双防线叠序注记、以及 G16 语料测法陷阱——均不架空 alias-only。  
**Verdict：`PASS_WITH_NOTE`**（核心命题未证伪；补 shadow-canonical 守卫 + 可选第二轮收口）。

---

## Files touched

none（只读对抗审；产物仅本文件）

---

## Acceptance verification（10/10 逐条）

### 1. G13 alias-only（第一条命）— **PASS**

**攻击面**：suffix hint、`citation_bases`、locator 二次解析、未声明 alias 回落、`subpaths`、`_resolve_in_root` 全部调用点。

**证据**：
- 端到端：声明+绑定 wiki（root 下真实存在 `kernel/facts.md`），review 只写 `` `kernel/

... [truncated, 520767 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 706913
- end_time: 2026-07-27T11:29:26.363Z
- log: see `T-069-output.log` for raw output
