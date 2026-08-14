rounds/0014 —— 本地持久化文件的形状（重启验收时实读）

落点：AGENT_SHELL_STATE_DIR 覆盖到 scratchpad（默认为
~/Library/Application Support/dev.test-harnessloop.agent-shell/sessions.json）。
验收刻意用环境变量隔离，未写入用户的 Application Support。

正常形状（2 个会话时，实读内容）：

{
  "version": 1,
  "sessions": [
    {
      "createdAt": "2026-08-11T07:30:27Z",
      "handle": {
        "billing": { "tokenRef": "TODO-sg4-no-newapi-token-minted" },
        "createdAt": "2026-08-11T07:30:27Z",
        "kernel": "openclaw",
        "kernelSessionId": "838df057-d05a-4fb2-ad0f-5781dec0f894",
        "sessionId": "693459D3-02D4-48AF-8B56-9CBE30ACEC80"
      },
      "kernelKey": "agent:main:dashboard:6cc1b04c-b1cc-4b83-ba6f-37722438e3ac",
      "title": "会话 1"
    },
    {
      "createdAt": "2026-08-11T07:31:23Z",
      "handle": {
        "billing": { "tokenRef": "TODO-sg4-no-newapi-token-minted" },
        "createdAt": "2026-08-11T07:31:23Z",
        "kernel": "openclaw",
        "kernelSessionId": "03b36182-a82d-4600-8f82-ae7ecb2932de",
        "sessionId": "297BF1C8-180F-44E4-8425-73F870BE008C"
      },
      "kernelKey": "agent:main:dashboard:59dd711c-8d55-4a43-b3a6-49bd3b061829",
      "title": "会话 2"
    }
  ]
}

三个要点：

1. kernelKey 存的是 openclaw 的 key（形如 agent:main:dashboard:<uuid>），
   与同一条记录里的 handle.kernelSessionId 明确不是同一个值。
   —— rounds/0013 在这里踩过坑：用 kernelSessionId 去查 history 会查到一个不存在的会话。
   本轮持久化把两者都存下来且不混用，是对那次教训的直接回应。

2. 不含任何凭证。billing.tokenRef 是既有占位串（TODO-sg4-no-newapi-token-minted），
   endpoint 与 token 仍只走环境变量。本仓是 PUBLIC 仓，凭证不得进 tracked 文件。

3. 破坏性反证用的坏内容见同目录 sessions-json-CORRUPTED.txt（59 字节非法 JSON）。
   壳读到它以后：未崩溃、回到空列表、连接正常、可继续新建会话
   （见 ../shots/r14-corrupt.png）。
