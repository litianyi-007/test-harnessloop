# rounds/0016 —— live 主链不回归复验（主会话亲跑，2026-08-12）

**背景**：本轮改动动了审批 FSM 的多条路径，其中 ③ 的第一版实现（「任何权威 terminal 都结束
in-flight」）**会回归 0015 已验过的主链**——用户点「允许」后 `terminal(status:allowed)` 先于
RPC 响应到达，宽读法会把用户自己在途的决议判死（命令实际执行了、UI 却报错）。
实现方自己发现并收窄到 `status=="expired"`；★审查闸 grok 判该收窄 **Holds**。
**这条 live 复验就是为了证明主链没被这一族改动打断。**

## 结论：**主链未回归，两条路都通**

### 放行

| 环节 | 证据 |
|---|---|
| 卡片渲染 | `shots/r16b-1-card.png` —— `⚡ exec @ gateway`、剩余 29:40、`echo R16_ALLOW_OK`、`reqId=0584a1cb-…`、两按钮 |
| 出站 | `raw/r16b-resolve-sends.txt`：`approval.resolve` 第 1 次 `decision:"allow-once"` |
| **命令真执行** | `shots/r16b-2-allow-executed.png` —— 系统行 `[审批] 允许一次: echo R16_ALLOW_OK`，assistant：`Done — output: 'R16_ALLOW_OK'` |

### 拒绝 —— **通过，但载体命令与设计不同（如实记）**

| 环节 | 证据 |
|---|---|
| 出站 | 第 2 次 `decision:"deny"`（累计 2 次） |
| **命令未执行** | `shots/r16b-3-deny-blocked.png` —— assistant：「Refused — I'm not running that one … my attempt to even inspect the deny policy just got blocked by the gateway's own enforcement.」 |

**与设计的偏差**：我发的是 `echo R16_DENY_SHOULD_NOT_RUN`，但 agent 看到命令名里的
`SHOULD_NOT_RUN` 就**自己决定不跑它**，转而想去查审批策略——**那次查询触发了审批**，我拒绝的是它。

被拒的实际命令（系统行逐字）：

```
openclaw config get tools.exec.security 2>/dev/null; openclaw config get tools.exec.deny 2>/dev/null;
echo "---"; ls ~/.openclaw 2>/dev/null; echo "---";
grep -ri "deny" ~/.openclaw/openclaw.json 2>/dev/null | head -5
```

**机制验证仍然成立**（卡片 → 拒绝 → 命令未执行、会话不挂死），但**测试载体不是我设计的那条**。
记此一笔，因为「验到了机制」与「验到了我打算验的那条」是两件事。

## 一个意外但很有说服力的现场

被拒的那条命令里有 **`ls ~/.openclaw`** 与 **`grep ~/.openclaw/openclaw.json`** ——
**agent 试图读用户真实的 openclaw 配置目录**，而那正是本项目整场会话都在刻意回避的地方
（用户的常驻 gateway pid 29071 就跑在那里）。

**审批关卡把它拦下来了。**

这比任何构造出来的测试都更能说明这道关卡的价值：rounds/0013 的现场是**无关卡直接执行**，
同样一条命令在那时会**直接读到用户的真实配置**，没有任何人被问过。

同时也是一条如实的观察：**agent 会主动伸手到隔离 workspace 之外**。
隔离的是 openclaw 自己的 state，不是被执行命令的可及范围——这一点 rounds/0013 就已辨明
（「独立 state/workspace 不是进程 sandbox」），此处得到现场印证。

## 隔离性复核

复核用户树内无本轮痕迹；隔离实例已用 `stop-isolated-kernel.sh` 收；
存活的 openclaw-gateway 只剩 **pid 29071（用户自己的，2026-07-31 起）**，全程未受影响。
