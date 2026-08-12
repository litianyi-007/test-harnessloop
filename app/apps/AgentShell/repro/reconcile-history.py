#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""reconcile-history.py -- RAE-0001 条件③(b)(c) 取证脚本。

比对两个来源的 assistant 消息集合，证明"受控会话内没有丢消息"：

  A. wire trace（本地 JSONL，逐行事件记录，已录好，无需改任何代码）
     取每一行里 producedEvents[] 含 wireType == "evt.message.delta" 的帧，
     用 wireFrame.payload.message.role == "assistant" 过滤，
     键取 (wireFrame.payload.messageId, wireFrame.payload.messageSeq)。

  B. 权威 history 快照（HTTP GET {base}/sessions/{sessionKey}/history?limit=N，
     跟着响应里的 nextCursor 持续翻页直到 hasMore 为 false；或本地 --history-file
     离线快照，同一 JSON 形状：{"messages": [...], "hasMore": bool, "nextCursor"?: str}）
     取 role == "assistant" 的消息，键取 (msg.__openclaw.id, msg.__openclaw.seq)。

断言（两条都要，缺一不可）：
  1. wire ⊆ history        —— wire 侧每个 (id, seq) 都能在 history 里找到
  2. history ⊆ wire（反向） —— history 的 assistant 消息在 wire 侧全部出现
     （这一条就是条件③(b)"受控会话内无缺失"的直接取证）

--drop-one：在同一次执行内先验证未删减数据的 baseline 是绿的，再从 wire 侧集合删掉一条
assistant 消息重跑对账，最后断言新增的差集精确等于被删的那一个 key——用于证明断言②确实
有牙齿（条件③(c) 破坏性反证）。删除前会原样打印被删记录（id、seq、文本前 60 字符）——
没打印出被删的内容，这次反证不算数。

2026-08-11 加固（异构对抗评审 codex 只读实证发现 5 条"假绿"路径后的修复）：
  1. **去重不再掩盖基数丢失**：history 侧同一 (id, seq) 出现 >=2 次时，以前会被直接覆盖、
     只留最后一条，两向断言只看 key 集合看不出这里丢过东西。现在 history 侧的重复 key
     直接判失败并把每次出现的文本都打印出来。wire 侧的同键重复不受影响——那是流式增量的
     正常语义（同一条逻辑消息被拆成多个 delta 帧、后写覆盖合成最终文本），继续折叠为 1
     条，不计入异常。
  2. **解析异常 / 缺 metadata 不再 fail-open**：JSON 解析失败、JSON 顶层非对象、wire 侧缺
     messageId/messageSeq、history 侧缺 __openclaw.id/seq——这些以前只统计不参与 PASS
     判定，现在计数非零就直接判失败。role 过滤（非 assistant）在**history 侧**仍然是
     正常语义、继续忽略，报告里会把被过滤条数与角色分布显式列出来。（**wire 侧**当时也
     被一并放行，二轮评审发现这其实是假绿，已在下方"二轮加固"第 6 条单独收紧——wire 侧
     与 history 侧的 role 规则并不对称，不能套用同一条。）
  3. **新增 --expect-min-assistant N（默认 1）**：wire/history 两侧的 assistant 计数任一
     低于 N 就判失败，堵住"两个空集直接 PASS"的漏洞。（首轮曾允许显式传 0 关闭这条校验；
     二轮评审认定这个开关本身就是漏洞，已在下方"二轮加固"第 8 条收紧为拒绝 0。）
  4. **history 分页读全**：在线模式现在会跟着响应里的 nextCursor 持续请求，直到 hasMore
     为 false 才认为读到了完整 history；离线 --history-file 快照也会检查其中的 hasMore
     字段——hasMore 为 true（或缺失/不是合法布尔值）一律硬失败，不只是警告，因为离线快照
     没有办法继续翻页，不能假装对完了账。这是五条里最重要的一条：如果 wire 侧丢失的正好
     是 history 首页分页截断掉的旧消息，两侧会同时"缺失"、两条断言都会通过。
  5. **--drop-one 现在是单次执行内的三步流程**：(a) 先用同一份数据跑一次 baseline，
     baseline 必须完全干净（不干净就报"无法反证：baseline 本身是红的"，以新退出码 4
     失败，不再顺着旧逻辑误报"断言②捕获了删除"）；(b) 再删一条；(c) 断言删除后新增的
     差集精确等于被删的那一个 key，而不是"随便非空就算数"。同一次执行内完成，避免在线
     模式先后两次请求可能读到两个不同 history 快照的问题。

2026-08-11 二轮加固（同一异构对抗评审 codex 只读、复验第一轮修复后又实证发现 2 条残留
"假绿"，均附可复现反例）：
  6. **wire 侧 role 缺失/非法不再当"非 assistant，正常忽略"静默放过**：
     `EventMapping.swift:149-177`（`mapOpenclawSessionMessageToKernelEvents`）是 wire 侧
     唯一产出 evt.message.delta 的地方，函数一开头就用 `message.role == "assistant"`
     （精确字符串匹配）把非 assistant 的 session.message 短路掉、不产出任何 D2 事件——换句
     话说，一条已经在 producedEvents[] 里出现了 evt.message.delta 的 wire 记录，其
     wireFrame.payload.message.role 只可能是 "assistant"，缺失/非字符串/其他取值都与
     "它确实产出了 evt.message.delta" 这个既成事实自相矛盾。以前脚本把这类记录一律当
     "正常非 assistant 流量"忽略，异常计数不动，是假绿；现在计入新的 wire 侧异常
     bad_role_delta_lines，参与 PASS 判定。**history 侧不受影响**：history 侧的
     role != assistant（例如 user 消息）依然是正常语义——两侧规则本来就不对称，这条
     只收紧 wire 侧。
  7. **id/seq 从"非 None 即可"改成严格类型校验**：Python 里 `True == 1` 且
     `hash(True) == hash(1)`，旧的 normalize_seq 对 bool 直接原样放行，导致 wire 侧一个
     非法的 JSON boolean seq 能在 (id, seq) 元组比较/哈希时跟 history 侧合法的整数 seq
     冒充成同一个 key 从而被判定"匹配"；float 还会被 `int(v)` 静默截断，掩盖类型不一致。
     现在 seq 必须是真正的 int（`isinstance(v, int) and not isinstance(v, bool)`，显式
     排除 bool）、拒绝 float/str/其他类型；id 必须是非空 str。不满足则计入该侧原有的
     metadata 异常统计（wire 侧 malformed_candidate_lines / history 侧
     malformed_metadata_messages），不再进入 recs——原 normalize_seq 的"尽量转成 int"
     容错路径已整体移除，改为 is_valid_id() / is_valid_seq() 两个不做任何类型强转的
     纯校验函数。
  8. **--expect-min-assistant 不再接受 0**：0 曾是显式关闭"两个空集直接 PASS"下限校验的
     后门。作为 RAE 专用取证工具，这条下限存在的意义就是防止"其实什么都没检查、却报
     PASS"，允许一个开关把它关掉等于把同一个漏洞换个入口留在原地。现在下限最小值收紧
     为 1，传 0 或负数在参数校验阶段直接判用法错误（退出码 2），没有可以绕过的开关。

退出码：
  0  PASS —— 正常模式，全部断言/校验都成立
  1  FAIL —— 正常模式下不成立；或 --drop-one 模式下按预期精确变红（自证断言有效：
     baseline 干净、删除后差集精确等于被删的键——这正是 --drop-one 模式"成功"的表现）
  2  用法/环境错误 —— 参数缺失、trace/history 文件读取失败、HTTP 请求失败、history 响应
     形状不对、分页读不全（含离线快照 hasMore 非 false、在线翻页出现重复 cursor 或缺
     nextCursor）等，在能跑对账之前就出的错
  3  --drop-one 完整性失败 —— 删了一条消息，对账却仍然是全绿；或差集不精确等于被删的那
     个 key（说明这次反证不精确、方法本身不可信）。脚本会明确打印具体是哪一种
  4  --drop-one 基线不干净 —— 同一次执行内，删除前的 baseline 本身就没通过全部校验
     （断言①②、history 侧重复 key、双方异常计数、assistant 数量下限任一不满足），无法
     在脏 baseline 上做破坏性反证，脚本会打印"无法反证：baseline 本身是红的"

用法示例：
  # 在线：对着真实 gateway 取 history（自动翻页直到 hasMore=false）
  reconcile-history.py --trace wire-trace.jsonl --base http://127.0.0.1:PORT --session-key agent:main:dashboard:xxx

  # 离线：用存档快照代替 HTTP（也可用于把某次线上 history 存档留证；快照必须自带 hasMore=false）
  reconcile-history.py --trace wire-trace.jsonl --history-file history-snapshot.json

  # 破坏性反证
  reconcile-history.py --trace wire-trace.jsonl --history-file history-snapshot.json --drop-one

  # 调整 assistant 数量下限（默认且最小值 1；0 与负数会被拒绝，见"二轮加固"第 8 条）
  reconcile-history.py --trace wire-trace.jsonl --history-file history-snapshot.json --expect-min-assistant 3

token 只从环境变量 OPENCLAW_GATEWAY_TOKEN 读取（--token 可覆盖，但命令行参数会留痕在
shell history / `ps`，能用环境变量就不要用这个）。脚本任何时候都不打印 token 本身，
包括出错时。

只用标准库，不引入任何第三方依赖；本机 python3 基线是 3.9（见 L1-REPRO.md 前置表），
本脚本按 3.9 语法边界编写。
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from typing import Any, Dict, List, Optional, Tuple

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_USAGE_ERROR = 2
EXIT_DROP_ONE_INTEGRITY_FAILURE = 3
EXIT_DROP_ONE_BASELINE_DIRTY = 4

Key = Tuple[str, Any]

DEFAULT_EXPECT_MIN_ASSISTANT = 1
# Sanity bound so a server-side pagination bug (cursor never advancing, or
# hasMore stuck true) can't spin the client forever.
MAX_HISTORY_PAGES = 10000


class ReconcileError(Exception):
    """Fatal error surfaced before/outside the actual set comparison."""


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------

def dig(obj: Any, *path: str) -> Any:
    """Safely walk a chain of dict keys; returns None as soon as something isn't a dict."""
    cur = obj
    for p in path:
        if isinstance(cur, dict):
            cur = cur.get(p)
        else:
            return None
    return cur


def is_valid_seq(v: Any) -> bool:
    """seq must be a genuine int -- no coercion.

    2026-08-11 second-round fix: the previous normalize_seq() let a JSON
    boolean through unchanged, which is a real hole because in Python
    `True == 1` and `hash(True) == hash(1)` -- so a (id, True) key from one
    source and a (id, 1) key from the other would silently collide in a
    dict/set and be treated as "matched", even though a JSON `true` on the
    wire and a JSON `1` in history are not the same value at all. A plain
    `isinstance(v, int)` check alone does NOT catch this, because bool is a
    subclass of int in Python -- the bool exclusion has to be explicit.
    Floats are rejected too (the old code's `int(v)` would silently
    floor-truncate e.g. 2.7 -> 2, which could just as easily mask a genuine
    type mismatch instead of a harmless representation difference), and so is
    any other type (str included -- no more "best-effort" parsing of numeric
    strings). This mirrors is_valid_id() below: both halves of a key must now
    pass a real type check, not just "is not None".
    """
    return isinstance(v, int) and not isinstance(v, bool)


def is_valid_id(v: Any) -> bool:
    """id must be a non-empty str -- no coercion from int or any other type
    (2026-08-11 second-round fix; see is_valid_seq() above for the matching
    seq-side rationale)."""
    return isinstance(v, str) and v != ""


def extract_assistant_text(message: Any) -> str:
    """Pull human-readable text out of a message object.

    Handles both shapes seen in this project's real data:
      - message.content is a plain string
      - message.content is a list of blocks like {"type": "text", "text": "..."}
        (thinking blocks and anything without type == "text" are ignored)
    Never raises; returns "" if nothing recognizable is found.
    """
    if not isinstance(message, dict):
        return ""
    content = message.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                text = block.get("text")
                if isinstance(text, str):
                    parts.append(text)
        return "".join(parts)
    return ""


def preview(text: Optional[str], n: int = 60) -> str:
    flat = (text or "").replace("\n", "\\n").replace("\r", "\\r")
    if len(flat) > n:
        return flat[:n] + "...[截断]"
    return flat


def fmt_key(key: Key) -> str:
    return "id=%r seq=%r" % (key[0], key[1])


def kv(label: str, value: Any) -> None:
    print("  %-38s: %s" % (label, value))


def sub(label: str, values: List[Any]) -> None:
    if values:
        print("      %-34s: %s" % (label, values))


def fatal(msg: str, code: int = EXIT_USAGE_ERROR) -> None:
    print("[FATAL] %s" % msg, file=sys.stderr)
    sys.exit(code)


# ---------------------------------------------------------------------------
# source A: wire trace (local JSONL)
# ---------------------------------------------------------------------------

def parse_wire_trace(path: str) -> Tuple[Dict[Key, str], Dict[str, Any]]:
    stats: Dict[str, Any] = {
        "total_lines": 0,
        "blank_lines": 0,
        "parse_error_lines": 0,
        "parse_error_line_numbers": [],
        "unexpected_shape_lines": 0,
        "unexpected_shape_line_numbers": [],
        "no_delta_lines": 0,
        "bad_role_delta_lines": 0,
        "bad_role_delta_line_numbers": [],
        "role_distribution": Counter(),
        "malformed_candidate_lines": 0,
        "malformed_line_numbers": [],
        "matched_frames": 0,
        "duplicate_keys": 0,
    }
    recs: Dict[Key, str] = {}

    with open(path, "r", encoding="utf-8") as fh:
        for lineno, raw_line in enumerate(fh, start=1):
            stats["total_lines"] += 1
            line = raw_line.strip()
            if not line:
                stats["blank_lines"] += 1
                continue

            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                # Anomaly, not benign noise: a line that isn't valid JSON at all
                # means the trace itself is suspect. Counted here and gated on
                # in main() -- see anomaly_count below.
                stats["parse_error_lines"] += 1
                stats["parse_error_line_numbers"].append(lineno)
                continue

            if not isinstance(obj, dict):
                stats["unexpected_shape_lines"] += 1
                stats["unexpected_shape_line_numbers"].append(lineno)
                continue

            produced = obj.get("producedEvents")
            has_delta = isinstance(produced, list) and any(
                isinstance(e, dict) and e.get("wireType") == "evt.message.delta"
                for e in produced
            )
            if not has_delta:
                stats["no_delta_lines"] += 1
                continue

            role = dig(obj, "wireFrame", "payload", "message", "role")
            stats["role_distribution"][str(role)] += 1
            if role != "assistant":
                # Anomaly, NOT benign filtering (2026-08-11 second-round fix):
                # EventMapping.swift:149-177 (mapOpenclawSessionMessageToKernelEvents)
                # is the ONLY place evt.message.delta is ever constructed, and it
                # short-circuits to "no events" unless message.role == "assistant"
                # (exact string match) BEFORE producing anything. So a wire line
                # whose producedEvents[] already contains evt.message.delta is only
                # consistent with wireFrame.payload.message.role being exactly
                # "assistant" -- missing/non-string/any-other-value role here
                # contradicts that already-observed fact and must fail closed.
                # This is NOT the same rule as the history side: history's
                # messages[] legitimately interleaves role == "user" entries
                # (see extract_history_records below, where role != assistant
                # stays normal semantics) -- the two sides are asymmetric on
                # purpose and must not share this check.
                stats["bad_role_delta_lines"] += 1
                stats["bad_role_delta_line_numbers"].append(lineno)
                continue

            message_id = dig(obj, "wireFrame", "payload", "messageId")
            message_seq = dig(obj, "wireFrame", "payload", "messageSeq")
            message_obj = dig(obj, "wireFrame", "payload", "message") or {}

            if not is_valid_id(message_id) or not is_valid_seq(message_seq):
                # Anomaly, fail-closed (2026-08-11 second-round fix): see
                # is_valid_id()/is_valid_seq() near the top of this file for
                # why "is not None" wasn't enough (bool/float/str type
                # confusion, e.g. JSON `true` aliasing integer `1`).
                stats["malformed_candidate_lines"] += 1
                stats["malformed_line_numbers"].append(lineno)
                continue

            key = (message_id, message_seq)
            if key in recs:
                stats["duplicate_keys"] += 1
            stats["matched_frames"] += 1
            # Later frames for the same key (streaming growth) presumably carry the
            # fuller content, so last-writer-wins. This collapse is intentional and
            # NOT an anomaly: one logical assistant message legitimately spans many
            # delta frames sharing the same (messageId, messageSeq) key on the wire.
            # Contrast with the history side (extract_history_records below), where
            # each entry is already a materialized, distinct message and a repeated
            # key has no such benign explanation.
            recs[key] = extract_assistant_text(message_obj)

    stats["anomaly_count"] = (
        stats["parse_error_lines"] + stats["unexpected_shape_lines"]
        + stats["bad_role_delta_lines"] + stats["malformed_candidate_lines"]
    )
    return recs, stats


# ---------------------------------------------------------------------------
# source B: authoritative history snapshot (HTTP, paginated; or local file)
# ---------------------------------------------------------------------------

def fetch_history_http(
    base: str, session_key: str, limit: int, cursor: Optional[str], token: str, timeout: float
) -> Tuple[Any, str]:
    """Fetch exactly one page. Returns (parsed_json, url) -- the url is returned
    (never the token, which only ever lives in the Authorization header) so
    callers can cite it in pagination/diagnostic messages."""
    base_clean = base.rstrip("/")
    key_seg = urllib.parse.quote(session_key, safe=":")
    params: Dict[str, Any] = {"limit": limit}
    if cursor is not None:
        params["cursor"] = cursor
    query = urllib.parse.urlencode(params)
    url = "%s/sessions/%s/history?%s" % (base_clean, key_seg, query)

    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", "Bearer %s" % token)
    req.add_header("Accept", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            status = resp.getcode()
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")[:500]
        except Exception:
            pass
        # NOTE: url intentionally excludes the token (it only ever lives in the
        # Authorization header, never in the URL), so it's safe to print.
        raise ReconcileError(
            "history HTTP 请求失败：HTTP %s %s | url=%s | body(截断500字符)=%r"
            % (e.code, e.reason, url, body)
        )
    except urllib.error.URLError as e:
        raise ReconcileError("history HTTP 请求失败：无法连接 %s（%s）" % (url, e.reason))
    except OSError as e:
        raise ReconcileError("history HTTP 请求失败：%s（url=%s）" % (e, url))

    try:
        return json.loads(raw.decode("utf-8")), url
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        raise ReconcileError("history 响应（HTTP %s）不是合法 JSON：%s" % (status, e))


def load_history_file(path: str) -> Any:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        raise ReconcileError("--history-file 不存在：%s" % path)
    except json.JSONDecodeError as e:
        raise ReconcileError("--history-file 不是合法 JSON（%s）：%s" % (path, e))


def _validate_history_page(page_obj: Any, page_no: int, source_desc: str) -> Tuple[List[Any], bool, Optional[str]]:
    """Validate one page's shape and completeness metadata.

    Returns (messages, has_more, next_cursor). Used for both the online (HTTP,
    one call per page) and offline (--history-file, always exactly one "page")
    sources so both go through the identical completeness gate: a page whose
    hasMore/nextCursor can't be trusted must never be silently treated as "the
    whole history" -- if wire happens to be missing exactly the messages that
    got left off this page, both assertions would otherwise pass by accident.
    """
    if not isinstance(page_obj, dict):
        raise ReconcileError(
            "history 响应顶层不是对象（%s，第 %d 页）：%s" % (source_desc, page_no, type(page_obj).__name__)
        )
    messages = page_obj.get("messages")
    if not isinstance(messages, list):
        raise ReconcileError(
            "history 响应缺少合法的 'messages' 数组（%s，第 %d 页），无法对账" % (source_desc, page_no)
        )
    has_more = page_obj.get("hasMore")
    if has_more is not True and has_more is not False:
        raise ReconcileError(
            "history 响应缺少合法的布尔 'hasMore' 字段（%s，第 %d 页，实际值=%r），"
            "无法判断是否已经读全整个 history，拒绝在无法确认完整性的数据上对账（硬失败，不只是警告）"
            % (source_desc, page_no, has_more)
        )
    next_cursor = page_obj.get("nextCursor")
    if has_more and (not isinstance(next_cursor, str) or not next_cursor):
        raise ReconcileError(
            "history 响应 hasMore=true 但缺少合法的 'nextCursor'（%s，第 %d 页），无法继续翻页——"
            "拒绝在不完整的数据上对账" % (source_desc, page_no)
        )
    return messages, bool(has_more), (next_cursor if has_more else None)


def resolve_offline_history(path: str) -> Tuple[List[Any], str]:
    """Offline snapshots are necessarily a single page. Apply the same
    completeness gate as the online path: hasMore must be explicitly false,
    or we refuse to reconcile against a knowingly-incomplete snapshot (there's
    no way to page further with just a static file)."""
    history_obj = load_history_file(path)
    messages, has_more, _next_cursor = _validate_history_page(history_obj, 1, "file:%s" % path)
    if has_more:
        raise ReconcileError(
            "--history-file 离线快照的 hasMore=true——快照本身不完整（还有更早的消息没包含在这份快照"
            "里），离线模式没法继续翻页，拒绝在残缺数据上对账（硬失败，不是警告）：%s" % path
        )
    return messages, "file:%s" % path


def resolve_online_history(
    base: str, session_key: str, limit: int, token: str, timeout: float
) -> Tuple[List[Any], str]:
    """Follow nextCursor and keep requesting pages until hasMore is false.
    A truncated first page must never be silently treated as the whole
    history: if the messages wire lost are exactly the ones a truncated page
    would have left off, both assertions would otherwise pass by accident."""
    all_messages: List[Any] = []
    seen_cursors = set()
    cursor: Optional[str] = None
    page_no = 0
    last_url = ""
    source_desc = "%s/sessions/%s/history" % (base.rstrip("/"), session_key)
    while True:
        page_no += 1
        if page_no > MAX_HISTORY_PAGES:
            raise ReconcileError(
                "history 翻页超过 %d 页仍未见 hasMore=false，判定分页失控（服务端缺陷或游标未推进），中止"
                % MAX_HISTORY_PAGES
            )
        page_obj, last_url = fetch_history_http(base, session_key, limit, cursor, token, timeout)
        messages, has_more, next_cursor = _validate_history_page(page_obj, page_no, source_desc)
        all_messages.extend(messages)
        if not has_more:
            break
        if next_cursor in seen_cursors:
            raise ReconcileError(
                "history 翻页出现重复的 nextCursor=%r（第 %d 页），游标没有推进，可能是服务端分页缺陷，"
                "拒绝继续翻页" % (next_cursor, page_no)
            )
        seen_cursors.add(next_cursor)
        cursor = next_cursor

    label = "%s?limit=%s（在线翻页 %d 页直到 hasMore=false；最后一页 url=%s）" % (
        source_desc, limit, page_no, last_url
    )
    return all_messages, label


def extract_history_records(messages: List[Any]) -> Tuple[Dict[Key, str], Dict[str, Any]]:
    """messages is already a validated, fully-paginated list (see resolve_*_history
    above) -- this function no longer needs to guard against "not a list"."""
    stats: Dict[str, Any] = {
        "total_messages": 0,
        "non_assistant_messages": 0,
        "role_distribution": Counter(),
        "non_dict_messages": 0,
        "non_dict_indices": [],
        "malformed_metadata_messages": 0,
        "malformed_metadata_indices": [],
        "duplicate_keys": 0,
    }
    recs: Dict[Key, str] = {}
    key_texts: Dict[Key, List[str]] = {}

    for idx, msg in enumerate(messages):
        stats["total_messages"] += 1
        if not isinstance(msg, dict):
            # Anomaly: history entries are supposed to already be materialized
            # message objects, not raw scalars/lists. Gated on in main().
            stats["non_dict_messages"] += 1
            stats["non_dict_indices"].append(idx)
            continue

        role = msg.get("role")
        stats["role_distribution"][str(role)] += 1
        if role != "assistant":
            # Normal semantics, not an anomaly (e.g. user turns interleaved in
            # the same history). Kept out of anomaly_count, but still visible
            # via role_distribution above.
            stats["non_assistant_messages"] += 1
            continue

        mid = dig(msg, "__openclaw", "id")
        mseq = dig(msg, "__openclaw", "seq")
        if not is_valid_id(mid) or not is_valid_seq(mseq):
            # Anomaly, fail-closed (2026-08-11 second-round fix): see
            # is_valid_id()/is_valid_seq() near the top of this file for why
            # "is not None" wasn't enough (bool/float/str type confusion --
            # a JSON boolean seq could otherwise alias an integer seq via
            # Python's True == 1).
            stats["malformed_metadata_messages"] += 1
            stats["malformed_metadata_indices"].append(idx)
            continue

        key = (mid, mseq)
        text = extract_assistant_text(msg)
        if key in recs:
            stats["duplicate_keys"] += 1
        # Unlike the wire side, a repeated (id, seq) here has no benign
        # explanation -- each entry in history's messages[] is supposed to be
        # one already-materialized, distinct message, not a streaming delta.
        # Overwriting silently (last-writer-wins) would hide the fact that two
        # DISTINCT history entries collapsed onto one key, which is exactly
        # the "history has 2, wire has 1, dict-collapse makes it look like a
        # match" false-green this script now refuses to allow -- see
        # duplicate_key_texts below, which main() turns into a hard failure.
        recs[key] = text
        key_texts.setdefault(key, []).append(text)

    stats["malformed_messages"] = stats["non_dict_messages"] + stats["malformed_metadata_messages"]
    stats["anomaly_count"] = stats["malformed_messages"]
    stats["duplicate_key_texts"] = {k: v for k, v in key_texts.items() if len(v) > 1}
    return recs, stats


# ---------------------------------------------------------------------------
# reconciliation verdict -- single source of truth for pass/fail, reused by
# normal mode and (unmodified) by both the --drop-one baseline check and the
# post-drop check, so "passed" means the exact same thing everywhere.
# ---------------------------------------------------------------------------

def evaluate_reconciliation(
    wire_recs: Dict[Key, str],
    history_recs: Dict[Key, str],
    history_duplicate_keys: List[Key],
    wire_anomaly_count: int,
    history_anomaly_count: int,
    expect_min_assistant: int,
) -> Dict[str, Any]:
    wire_only = sorted(set(wire_recs) - set(history_recs))
    history_only = sorted(set(history_recs) - set(wire_recs))
    wire_count = len(wire_recs)
    history_count = len(history_recs)
    passed = (
        not wire_only
        and not history_only
        and not history_duplicate_keys
        and wire_anomaly_count == 0
        and history_anomaly_count == 0
        and wire_count >= expect_min_assistant
        and history_count >= expect_min_assistant
    )
    return {
        "wire_only": wire_only,
        "history_only": history_only,
        "history_duplicate_keys": history_duplicate_keys,
        "wire_anomaly_count": wire_anomaly_count,
        "history_anomaly_count": history_anomaly_count,
        "wire_assistant_count": wire_count,
        "history_assistant_count": history_count,
        "expect_min_assistant": expect_min_assistant,
        "passed": passed,
    }


def print_parse_stats(
    wire_recs: Dict[Key, str], wire_stats: Dict[str, Any],
    history_recs: Dict[Key, str], history_stats: Dict[str, Any],
) -> None:
    print("--- wire 侧解析 ---")
    kv("总行数", wire_stats["total_lines"])
    kv("空行（跳过，非异常）", wire_stats["blank_lines"])
    kv("JSON 解析失败（异常，计入判定）", wire_stats["parse_error_lines"])
    sub("解析失败的行号", wire_stats["parse_error_line_numbers"])
    kv("JSON 顶层非对象（异常，计入判定）", wire_stats["unexpected_shape_lines"])
    sub("该类行号", wire_stats["unexpected_shape_line_numbers"])
    kv("无 evt.message.delta（忽略，非异常）", wire_stats["no_delta_lines"])
    kv("role 非 assistant 但已产出 delta（异常，计入判定，见二轮加固#6）", wire_stats["bad_role_delta_lines"])
    sub("该类行号", wire_stats["bad_role_delta_line_numbers"])
    kv("delta 帧 role 分布", dict(wire_stats["role_distribution"]))
    kv("缺失或类型不合法的 messageId/messageSeq（异常，计入判定）", wire_stats["malformed_candidate_lines"])
    sub("该类行号", wire_stats["malformed_line_numbers"])
    kv("匹配的 assistant delta 帧（去重前）", wire_stats["matched_frames"])
    kv("去重后 unique (id, seq)", len(wire_recs))
    kv("同键重复帧数（流式增量，正常语义，不计入判定）", wire_stats["duplicate_keys"])
    kv("wire 侧异常合计（解析失败+顶层非对象+role非assistant却有delta+缺/坏metadata）", wire_stats["anomaly_count"])
    print()

    print("--- history 侧解析 ---")
    kv("messages 总条数", history_stats["total_messages"])
    kv("role != assistant（忽略，正常语义）", history_stats["non_assistant_messages"])
    kv("消息 role 分布", dict(history_stats["role_distribution"]))
    kv("顶层非对象条目（异常，计入判定）", history_stats["non_dict_messages"])
    sub("该类索引", history_stats["non_dict_indices"])
    kv("缺失或类型不合法的 __openclaw.id/seq（异常，计入判定）", history_stats["malformed_metadata_messages"])
    sub("该类索引", history_stats["malformed_metadata_indices"])
    kv("history 侧异常合计（非对象+缺metadata）", history_stats["anomaly_count"])
    kv("去重后 unique (id, seq)", len(history_recs))
    kv(
        "同一 (id,seq) 出现>=2次的key数（异常，计入判定）",
        len(history_stats["duplicate_key_texts"]),
    )
    if history_stats["duplicate_key_texts"]:
        print("      history 侧同键重复明细（每条都原样列出，不做去重覆盖）：")
        for k in sorted(history_stats["duplicate_key_texts"]):
            texts = history_stats["duplicate_key_texts"][k]
            print("        %s  出现 %d 次" % (fmt_key(k), len(texts)))
            for i, t in enumerate(texts):
                print("          [%d] text[:60]=%r" % (i, preview(t)))
    print()


def print_verdict_detail(
    evald: Dict[str, Any], wire_recs: Dict[Key, str], history_recs: Dict[Key, str], label: str
) -> None:
    print("--- %s：assistant 数量下限校验（--expect-min-assistant %d） ---" % (label, evald["expect_min_assistant"]))
    kv("wire 侧 assistant 数", evald["wire_assistant_count"])
    kv("history 侧 assistant 数", evald["history_assistant_count"])
    if evald["wire_assistant_count"] < evald["expect_min_assistant"]:
        print("  [FAIL] wire 侧低于下限")
    if evald["history_assistant_count"] < evald["expect_min_assistant"]:
        print("  [FAIL] history 侧低于下限")
    print()

    print("--- %s：差集 ---" % label)
    kv("wire 有、history 没有的条数（断言① wire<=history 违反）", len(evald["wire_only"]))
    kv("history 有、wire 没有的条数（断言② history<=wire 违反 = 受控会话内有缺失）", len(evald["history_only"]))
    kv("history 侧同键重复 key 数（视为异常）", len(evald["history_duplicate_keys"]))
    kv("wire 侧异常计数（视为异常）", evald["wire_anomaly_count"])
    kv("history 侧异常计数（视为异常）", evald["history_anomaly_count"])
    print()

    if evald["wire_only"]:
        print("--- %s：断言① 违反明细：wire subset-of history 不成立 ---" % label)
        for k in evald["wire_only"]:
            print("  %s  text[:60]=%r" % (fmt_key(k), preview(wire_recs.get(k, ""))))
        print()

    if evald["history_only"]:
        print("--- %s：断言② 违反明细：history 的 assistant 消息未在 wire 侧全部出现 ---" % label)
        for k in evald["history_only"]:
            print("  %s  text[:60]=%r" % (fmt_key(k), preview(history_recs.get(k, ""))))
        print()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="reconcile-history.py",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--trace", required=True, metavar="PATH",
                   help="wire trace JSONL 文件路径（本地，已录好）")
    p.add_argument("--base", metavar="URL",
                   help="openclaw gateway 的 base URL，例如 http://127.0.0.1:PORT。"
                        "与 --session-key 搭配用于拉取 history（自动翻页直到 hasMore=false）；"
                        "给了 --history-file 则忽略。")
    p.add_argument("--session-key", metavar="KEY",
                   help="要对账的 session key，例如 agent:main:dashboard:xxxx。"
                        "走 HTTP 拉取 history 时必需。")
    p.add_argument("--limit", type=int, default=500, metavar="N",
                   help="history 请求的单页 limit（仅在走 HTTP 拉取时生效；默认 500）。"
                        "总数超过一页时会自动跟着 nextCursor 继续翻页，直到 hasMore=false。")
    p.add_argument("--drop-one", action="store_true",
                   help="破坏性反证：单次执行内先验证 baseline 干净，再从 wire 侧集合删掉一条"
                        "assistant 消息重跑对账，断言新增差集精确等于被删的那个 key。")
    p.add_argument("--history-file", metavar="PATH",
                   help='离线模式：直接读本地 JSON 文件代替 HTTP 请求，形状与 '
                        'GET .../history 的响应一致（{"messages": [...], "hasMore": bool, '
                        '"nextCursor"?: str}）。给了这个就不会发任何 HTTP 请求，也可用来把线上 '
                        'history 快照存档取证——快照必须自带 hasMore=false，否则视为残缺快照、硬失败。')
    p.add_argument("--token", metavar="TOKEN", default=None,
                   help="覆盖 OPENCLAW_GATEWAY_TOKEN 环境变量。默认从环境变量读；"
                        "命令行参数会留痕在 shell history / `ps`，能用环境变量就别用这个。")
    p.add_argument("--timeout", type=float, default=30.0, metavar="SECONDS",
                   help="HTTP 请求超时秒数（默认 30；仅在走 HTTP 拉取时生效）")
    p.add_argument("--expect-min-assistant", type=int, default=DEFAULT_EXPECT_MIN_ASSISTANT, metavar="N",
                   help="wire/history 两侧 assistant 消息数的下限（默认且最小值 1）；任一侧低于 N 就判"
                        "失败，堵住两个空集直接 PASS 的漏洞。0 与负数会被拒绝（2026-08-11 二轮加固："
                        "这条校验本身不允许关闭）。")
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_arg_parser().parse_args(argv)

    if not os.path.isfile(args.trace):
        fatal("--trace 文件不存在：%s" % args.trace)

    if args.expect_min_assistant < 1:
        fatal(
            "--expect-min-assistant 必须 >= 1（收到 %r）：0 会让「wire/history 两侧都是"
            "空集」直接判 PASS，对本工具的取证目的而言那是无意义的空对空验证；"
            "2026-08-11 二轮加固后这条下限不再允许被关闭（不存在可以绕过的开关）"
            % args.expect_min_assistant
        )

    # --- resolve history source（在线：跟着 nextCursor 翻页直到 hasMore=false；
    # 离线：单份快照，也必须自证 hasMore=false）------------------------------------
    if args.history_file:
        try:
            history_messages, history_source_label = resolve_offline_history(args.history_file)
        except ReconcileError as e:
            fatal(str(e))
            return EXIT_USAGE_ERROR  # unreachable; fatal() exits
    else:
        if not args.base or not args.session_key:
            fatal("必须提供 --history-file，或同时提供 --base 与 --session-key")
        token = args.token or os.environ.get("OPENCLAW_GATEWAY_TOKEN")
        if not token:
            fatal(
                "缺少鉴权 token：设置环境变量 OPENCLAW_GATEWAY_TOKEN，或传 --token"
                "（不推荐，会留痕在 shell history / ps）"
            )
        try:
            history_messages, history_source_label = resolve_online_history(
                args.base, args.session_key, args.limit, token, args.timeout
            )
        except ReconcileError as e:
            fatal(str(e))
            return EXIT_USAGE_ERROR  # unreachable; fatal() exits

    # --- parse both sides ---------------------------------------------------
    try:
        wire_recs, wire_stats = parse_wire_trace(args.trace)
    except OSError as e:
        fatal("读取 --trace 失败：%s" % e)
        return EXIT_USAGE_ERROR  # unreachable; fatal() exits

    history_recs, history_stats = extract_history_records(history_messages)
    history_duplicate_keys = sorted(history_stats["duplicate_key_texts"].keys())

    # --- report header -------------------------------------------------------
    print("=" * 70)
    print("RAE-0001 条件③(b)(c) 对账报告")
    print("=" * 70)
    print("wire trace   : %s" % args.trace)
    print("history 来源  : %s" % history_source_label)
    print("session key  : %s" % (args.session_key or "(未提供)"))
    print("drop-one     : %s" % ("开" if args.drop_one else "关"))
    print("expect-min-assistant: %d" % args.expect_min_assistant)
    print()

    print_parse_stats(wire_recs, wire_stats, history_recs, history_stats)

    if not args.drop_one:
        evald = evaluate_reconciliation(
            wire_recs, history_recs, history_duplicate_keys,
            wire_stats["anomaly_count"], history_stats["anomaly_count"],
            args.expect_min_assistant,
        )
        print_verdict_detail(evald, wire_recs, history_recs, "正常模式")
        print("=" * 70)
        if evald["passed"]:
            print("结果：PASS")
            print("=" * 70)
            return EXIT_PASS
        else:
            print("结果：FAIL")
            print("=" * 70)
            return EXIT_FAIL

    # --- --drop-one：单次执行内三步：(a) baseline 必须绿 -> (b) 删一条 -> (c) 断言
    # 新增差集精确等于被删的那个 key -------------------------------------------
    if not wire_recs:
        fatal("wire 侧没有任何 assistant 消息，无法 --drop-one（没有可删的记录）")

    baseline = evaluate_reconciliation(
        wire_recs, history_recs, history_duplicate_keys,
        wire_stats["anomaly_count"], history_stats["anomaly_count"],
        args.expect_min_assistant,
    )
    print_verdict_detail(baseline, wire_recs, history_recs, "[DROP-ONE] (a) baseline（删除前）")

    if not baseline["passed"]:
        print("=" * 70)
        print("结果：无法反证——baseline 本身是红的（细节见上面 baseline 差集/异常/下限明细）。")
        print("--drop-one 的前提是「删除前必须先是绿的」，否则删除后出现的差集没法证明是这次删除")
        print("造成的，也可能只是复述了删除前就已经存在的缺陷。拒绝在脏 baseline 上假装完成了")
        print("破坏性反证。")
        print("=" * 70)
        return EXIT_DROP_ONE_BASELINE_DIRTY

    # baseline 干净 == wire_keys 与 history_keys 作为集合完全相等，所以 wire_recs
    # 里随便取一个 key 一定也在 history_recs 里，不需要再算交集/处理"没有交集"的
    # 兜底分支。
    dropped_key = sorted(wire_recs.keys())[0]
    dropped_text = wire_recs[dropped_key]
    print("[DROP-ONE] (b) baseline 干净，开始删除。删除前原样打印被删记录（硬要求——没打印出来")
    print("这次反证不算数）：")
    print("  %s  text[:60]=%r" % (fmt_key(dropped_key), preview(dropped_text)))
    wire_recs_after = dict(wire_recs)
    del wire_recs_after[dropped_key]
    print()

    after = evaluate_reconciliation(
        wire_recs_after, history_recs, history_duplicate_keys,
        wire_stats["anomaly_count"], history_stats["anomaly_count"],
        args.expect_min_assistant,
    )
    print_verdict_detail(after, wire_recs_after, history_recs, "[DROP-ONE] (c) 删除后")

    print("=" * 70)
    exact_match = after["history_only"] == [dropped_key] and not after["wire_only"]
    if not after["history_only"] and not after["wire_only"]:
        print("结果：FAIL（不应该！）—— 删了一条消息，对账却仍然是全绿！")
        print("破坏性反证失效——断言不守门。")
        print("=" * 70)
        return EXIT_DROP_ONE_INTEGRITY_FAILURE
    elif exact_match:
        print("结果：FAIL（符合预期）—— [DROP-ONE 自证] baseline 干净，删除后新增的差集精确等于")
        print("被删的那一个 key（%s），断言②确实捕获了这次删除，且没有牵连别的 key。" % fmt_key(dropped_key))
        print("=" * 70)
        return EXIT_FAIL
    else:
        print("结果：FAIL，但不是精确匹配——删除后的差集不等于「只有被删的那个 key」：")
        print("  history_only = %s" % [fmt_key(k) for k in after["history_only"]])
        print("  wire_only    = %s" % [fmt_key(k) for k in after["wire_only"]])
        print("  期望的 history_only 应该精确等于 [%s]，wire_only 应该是空。" % fmt_key(dropped_key))
        print("说明这次破坏性反证不精确——差集里混进了跟这次删除无关的东西，反证方法本身不可信。")
        print("=" * 70)
        return EXIT_DROP_ONE_INTEGRITY_FAILURE


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except ReconcileError as e:
        print("[FATAL] %s" % e, file=sys.stderr)
        sys.exit(EXIT_USAGE_ERROR)
    except Exception as e:  # last-resort guard: never dump a raw traceback
        print("[FATAL] 未预期的异常：%s: %s" % (type(e).__name__, e), file=sys.stderr)
        sys.exit(EXIT_USAGE_ERROR)
