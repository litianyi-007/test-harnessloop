/**
 * openclaw `sendSessionAffinityHeaders` 会话亲和头（sg6-openclaw-persession-patch-design.md
 * §5.1）——三者同值，同一个 sessionId，session-proxy 任取其一即可，`x-session-affinity`
 * 优先（语义最贴切，且是 openclaw 侧特意为"路由信号"新增的 header 名）。
 */
export const SESSION_AFFINITY_HEADER = 'x-session-affinity';
export const SESSION_ID_HEADER = 'session_id';
export const CLIENT_REQUEST_ID_HEADER = 'x-client-request-id';

/**
 * 转发到 newapi 上游前必须剥离的入站 hop-by-hop / 鉴权头。
 *
 * 除标准 hop-by-hop 头外，还包含 D3 自己的内部路由/归因头
 * （`SESSION_AFFINITY_HEADER`/`SESSION_ID_HEADER`/`CLIENT_REQUEST_ID_HEADER`）——
 * 这三者是 openclaw → D3-proxy 的会话路由信号，归因语义只应止于 D3，不应转发给
 * newapi（T-042 对抗审 P1 finding，场景 A：曾经历原样透传导致 sessionId 泄露给
 * 上游）。`proxy-connection` 是 `connection` 的非标准历史别名，部分老客户端/代理
 * 仍会发送，一并剥离（T-042 次要项）。
 */
export const STRIPPED_REQUEST_HEADERS = new Set([
  'host',
  'connection',
  'proxy-connection',
  'content-length',
  'authorization', // 静态 openclaw→proxy key，转发时被替换为真实 newapi key，绝不透传原值
  'transfer-encoding',
  'upgrade',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  SESSION_AFFINITY_HEADER,
  SESSION_ID_HEADER,
  CLIENT_REQUEST_ID_HEADER,
]);

/** 回传给 openclaw 前必须剥离的上游响应 hop-by-hop 头（由 undici/fetch 按新的传输方式重设）。 */
export const STRIPPED_RESPONSE_HEADERS = new Set([
  'content-length',
  'transfer-encoding',
  'connection',
  'keep-alive',
]);

/**
 * 允许代理到 newapi 上游的下游路径 allowlist（T-042 对抗审 P1 finding，场景 B：
 * 无 allowlist + 字符串拼接 path 可经 `..` 逃逸 `/v1` 打到 newapi 的
 * Management 路径）。
 *
 * 依据 sg6-openclaw-persession-patch-design.md §5.1：openclaw 侧把 D3-proxy 注册为
 * `"api": "openai-completions"` provider，`createClient()` 用官方 `openai` SDK
 * （`packages/ai/src/providers/openai-completions.ts:656-710`）发起请求；该 patch
 * 引用的调用路径是 `streamOpenAICompletions()`（同文件 :163-166），只对应 chat
 * completions 一种请求形态。设计文档未提及这条 `sendSessionAffinityHeaders` 通道
 * 会触达 legacy `completions` 或 `embeddings` 端点，本仓库也拿不到 openclaw 源码
 * 做二次确认——按 brief 要求"不确定就从严"，allowlist 目前只放行 `chat/completions`
 * 一条。后续若确认 openclaw 侧还会用同一 provider 发 `embeddings`/legacy
 * `completions`，在此追加即可。
 */
export const ALLOWED_UPSTREAM_PATHS = new Set<string>(['chat/completions']);
