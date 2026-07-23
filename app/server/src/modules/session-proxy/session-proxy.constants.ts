/**
 * openclaw `sendSessionAffinityHeaders` 会话亲和头（sg6-openclaw-persession-patch-design.md
 * §5.1）——三者同值，同一个 sessionId，session-proxy 任取其一即可，`x-session-affinity`
 * 优先（语义最贴切，且是 openclaw 侧特意为"路由信号"新增的 header 名）。
 */
export const SESSION_AFFINITY_HEADER = 'x-session-affinity';
export const SESSION_ID_HEADER = 'session_id';
export const CLIENT_REQUEST_ID_HEADER = 'x-client-request-id';

/** 转发到 newapi 上游前必须剥离的入站 hop-by-hop / 鉴权头。 */
export const STRIPPED_REQUEST_HEADERS = new Set([
  'host',
  'connection',
  'content-length',
  'authorization', // 静态 openclaw→proxy key，转发时被替换为真实 newapi key，绝不透传原值
  'transfer-encoding',
  'upgrade',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
]);

/** 回传给 openclaw 前必须剥离的上游响应 hop-by-hop 头（由 undici/fetch 按新的传输方式重设）。 */
export const STRIPPED_RESPONSE_HEADERS = new Set([
  'content-length',
  'transfer-encoding',
  'connection',
  'keep-alive',
]);

/** session-proxy 控制器的挂载路径（随 main.ts 全局前缀，见 session-proxy.controller.ts 头注释）。 */
export const SESSION_PROXY_MOUNT_PATH = '/session-proxy';
