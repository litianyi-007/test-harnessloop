import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { Response } from 'express';

/**
 * 把 Nest 默认异常响应统一整形为 openapi.yaml `Error` schema（{code, message, details?}）。
 *
 * 不臆造具体错误码——业务 code（如 `no_license`/`billing_query_subject_unresolved`）由各
 * service 在抛出时通过 `HttpException(response, status)` 的 `response.code` 显式指定；
 * 本 filter 只在业务未提供 `code` 时兜底生成一个可读的 slug（基于 HTTP 状态文案），
 * 不假装这是协议定义的机器可读错误码。
 */
@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  catch(exception: HttpException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const status = exception.getStatus();
    const body = exception.getResponse();

    if (typeof body === 'object' && body !== null && 'code' in body) {
      response.status(status).json(body);
      return;
    }

    const message =
      typeof body === 'string'
        ? body
        : ((body as { message?: string })?.message ?? exception.message);

    response.status(status).json({
      code: fallbackCode(status),
      message,
    });
  }
}

function fallbackCode(status: number): string {
  return (
    HttpStatus[status]?.toString().toLowerCase().replace(/_/g, '_') ??
    `http_${status}`
  );
}
