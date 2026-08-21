# Round Summary — goal 002 / rounds/0025

**0024 接上的 CI 门，本轮让它在 macos 上稳住。frame-replay 174/174、Swift 金标 13/0/0，Actions 绿。**

## 改了什么

三条测试的采样，产品实现一字未动。

- 两条 §9.3「stop 等待在途 interrupt」：去掉固定 60ms sleep，改成 5ms 轮询，一看到 `interrupt_in_progress` 且 stop 未报告就采样。
- FAIL2 第三方 send：真牙齿仍是 `sessions.send#2` 未 dispatch；`unknown session` 与 `session_locked` 都算没偷到锁（stop 先跑完 delete 是合法后续，不是偷锁）。

## 证据

本机 174/174。Actions [32503486999](https://github.com/litianyi-007/test-harnessloop/actions/runs/32503486999) ubuntu + macos 全绿，含 frame-replay 与 Swift 13/0/0。

## Cost

unavailable: no local transcript source — Grok 会话。
