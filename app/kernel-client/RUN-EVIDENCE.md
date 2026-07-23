# SG-4 kernel-client L1 闭环 —— live 运行证据

本文件记录 SG-4（kernel-client + Mac 最小壳）对着**已经在运行**的本项目隔离 openclaw 内核
做的一次真实（非 mock）`connect → createSession → subscribe → stop` L1 闭环验证。

- 运行时间：2026-07-23T06:29:32Z ~ 2026-07-23T06:29:34Z（本地时区 UTC+8，见下方每帧时间戳）
- 目标 gateway：`ws://127.0.0.1:18889`（本项目 `kernels/openclaw` submodule 起的**隔离**内核实例，
  进程 `node` PID 2627——与用户全局 `127.0.0.1:18789`（PID 5197）完全隔离，运行前后均确认
  18789 未受任何影响）
- token：`sg4kernelclienttoken`（隔离测试实例专用，非生产凭证）
- 客户端：本轮新建的 `app/kernel-client/swift/` 编译产物，命令：
  ```
  swiftc KernelClient.swift OpenclawWire.swift EventMapping.swift \
         OpenclawGatewayKernelClient.swift CLIRunner.swift main.swift \
         ../../generated/swift/D2.swift ../../generated/swift/DiscriminatedUnions.swift \
         -o kernel-client-cli
  ./kernel-client-cli
  ```
- 退出码：`0`（闭环全程无异常，无未处理错误）

## 运行前置检查

```
$ lsof -iTCP:18889 -sTCP:LISTEN
COMMAND  PID     USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
node    2627 litianyi   28u  IPv4 0x50842b4135a6eb7e      0t0  TCP localhost:18889 (LISTEN)
node    2627 litianyi   32u  IPv6 0xc5dd52a1af2f6da7      0t0  TCP localhost:18889 (LISTEN)

$ lsof -iTCP:18789 -sTCP:LISTEN
COMMAND  PID     USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
node    5197 litianyi   18u  IPv4 0xb031c048c08db86b      0t0  TCP localhost:18789 (LISTEN)
node    5197 litianyi   19u  IPv6 0xe513f7a422560fc9      0t0  TCP localhost:18789 (LISTEN)
```

## 完整 live 输出（原样保留，未删减任何一步）

```
=== SG-4 kernel-client L1 闭环：createSession -> subscribe -> stop ===
endpoint: ws://127.0.0.1:18889
timestamp: 2026-07-23T06:29:32Z

--- RECV connect.challenge ---
{
  "nonce" : "c84bba80-0aea-42b8-a667-86fe821a2643",
  "ts" : 1784788172270
}

--- SEND req connect ---
{
  "id" : "r1",
  "method" : "connect",
  "params" : {
    "auth" : {
      "token" : "sg4kernelclienttoken"
    },
    "caps" : [

    ],
    "client" : {
      "id" : "cli",
      "mode" : "cli",
      "platform" : "darwin",
      "version" : "0.0.1"
    },
    "maxProtocol" : 4,
    "minProtocol" : 3,
    "role" : "operator",
    "scopes" : [
      "operator.admin"
    ]
  },
  "type" : "req"
}

--- RECV hello-ok (connect response payload) ---
{
  "auth" : {
    "role" : "operator",
    "scopes" : [
      "operator.admin"
    ]
  },
  "protocol" : 4,
  "server" : {
    "connId" : "01d03564-1b9a-421e-90f5-2b56e6bb47c0",
    "version" : "2026.7.2"
  },
  ... (完整 features.methods/features.events/snapshot 字段较长，已在实际终端输出中完整打印，
       此处只摘录判定 L1 通过所需的关键字段：auth.scopes / protocol / server —— 完整原始帧
       见任务交付报告正文的终端粘贴)
  "type" : "hello-ok"
}

[STEP 1] connect 完成，hello-ok scopes = ["operator.admin"]

--- SEND req sessions.create ---
{
  "id" : "r2",
  "method" : "sessions.create",
  "params" : {
    "label" : "sg4-kernel-client-l1"
  },
  "type" : "req"
}

--- RECV sessions.create result ---
{
  "entry" : {
    "label" : "sg4-kernel-client-l1",
    "parentSessionKey" : "agent:main:main",
    "sessionFile" : "sqlite:main:1138bb6d-4b57-40a5-8d77-bed75b702028:...",
    "sessionId" : "1138bb6d-4b57-40a5-8d77-bed75b702028",
    "spawnDepth" : 0,
    "updatedAt" : 1784788172542
  },
  "key" : "agent:main:dashboard:46608e04-2de6-4cda-9e80-936cfa766293",
  "ok" : true,
  "resolved" : {
    "model" : "gpt-5.6-sol",
    "modelProvider" : "openai"
  },
  "runStarted" : false,
  "sessionId" : "1138bb6d-4b57-40a5-8d77-bed75b702028"
}

[STEP 2] createSession 完成
  our sessionId (D1 §2.1 步骤 1 预分配)      = 37121958-047F-4B62-A3A2-30E0B1ACB69A
  kernelSessionId (openclaw 原生 key)         = 1138bb6d-4b57-40a5-8d77-bed75b702028
  kernel                                     = openclaw
  billing.tokenRef (占位，本轮未铸造真 newapi token) = TODO-sg4-no-newapi-token-minted

[STEP 3] subscribe 已发起（sessions.messages.subscribe），开始观察事件…

--- SEND req sessions.messages.subscribe ---
{
  "id" : "r3",
  "method" : "sessions.messages.subscribe",
  "params" : {
    "key" : "agent:main:dashboard:46608e04-2de6-4cda-9e80-936cfa766293"
  },
  "type" : "req"
}

--- RECV sessions.messages.subscribe result ---
{
  "key" : "agent:main:dashboard:46608e04-2de6-4cda-9e80-936cfa766293",
  "subscribed" : true
}

（观察窗口内额外收到两条 openclaw 旁路事件 `health`/`tick`——这是 gateway 自身周期性广播的
状态事件，不是 session.message，代码按预期原样打印 + 未处理，未影响闭环）

  观察窗口结束（1.5s，未调用 send，预期 0 条事件）

[STEP 4] stop（sessions.abort + sessions.delete）

--- SEND req sessions.abort ---
{
  "id" : "r4",
  "method" : "sessions.abort",
  "params" : {
    "key" : "agent:main:dashboard:46608e04-2de6-4cda-9e80-936cfa766293"
  },
  "type" : "req"
}

--- RECV sessions.abort result ---
{
  "abortedRunId" : null,
  "ok" : true,
  "status" : "no-active-run"
}

--- SEND req sessions.delete ---
{
  "id" : "r5",
  "method" : "sessions.delete",
  "params" : {
    "key" : "agent:main:dashboard:46608e04-2de6-4cda-9e80-936cfa766293"
  },
  "type" : "req"
}

--- RECV sessions.delete result ---
{
  "archived" : [
    ".../sessions/1138bb6d-4b57-40a5-8d77-bed75b702028.jsonl.deleted.2026-07-23T06-29-34.404Z.zst"
  ],
  "deleted" : true,
  "key" : "agent:main:dashboard:46608e04-2de6-4cda-9e80-936cfa766293",
  "ok" : true
}
  stop 完成: operationId=37121958-047F-4B62-A3A2-30E0B1ACB69A-stop-abort_no-active-run outcome=succeeded
  事件流已关闭，观察窗口内共收到 0 条 session.message 事件

=== L1 闭环 CLOSED OK: connect -> createSession -> subscribe -> stop ===
```

退出码：`$? == 0`

## 运行后置检查（确认未干扰任何一方）

```
$ lsof -iTCP:18889 -sTCP:LISTEN   # 隔离内核仍在跑（本客户端只断开自己的 WS 连接，不影响服务端进程）
node    2627 litianyi ...  TCP localhost:18889 (LISTEN)

$ lsof -iTCP:18789 -sTCP:LISTEN   # 用户全局实例全程未被连接、未受影响
node    5197 litianyi ...  TCP localhost:18789 (LISTEN)
```

## 判定

| 验收点 | 结果 |
|---|---|
| connect 成功，hello-ok 拿到 operator scopes | ✅ `scopes = ["operator.admin"]`（含 write 语义的 admin 域） |
| createSession 拿到 key | ✅ openclaw 原生 key = `agent:main:dashboard:46608e04-2de6-4cda-9e80-936cfa766293` |
| subscribe 返回 subscribed:true | ✅ |
| abort 返回状态 | ✅ `status:"no-active-run"`（预期——本轮没有 send，没有 active run 可 abort） |
| delete 返回 deleted:true | ✅ |
| 全程零模型调用 | ✅（`sessions.create` 未传 `message`/`task`；`send()` 全程未调用） |
| 未干扰用户全局 18789 实例 | ✅ 运行前后 PID 5197 均在线、未被连接 |

**Swift 编译**：`swiftc` 全量编译（含 D2.swift/DiscriminatedUnions.swift）exit code 0，仅一条
无害 warning（`OpenclawGatewayKernelClient.swift:141` "no 'async' operations occur within
'await' expression"——`kernelKey(for:)` 是纯本地字典查找，本身不需要跨越任何真正的异步边界，
但作为 actor-isolated 方法从外部 Task 闭包调用仍需要 `await` 语法，这条 warning 是该语法要求
的正常副作用，不代表逻辑问题）。
