// 공통: JSON 응답과 오류 처리

export class HttpError extends Error {
  constructor(public status: number, message: string, public code = 'error') {
    super(message);
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

// 핸들러를 감싸서 오류를 { error, code } JSON 으로 돌려줍니다.
// 앱은 code 로 분기하고 error 는 그대로 사용자에게 보여 줄 수 있습니다.
export function serve(handler: (req: Request) => Promise<Response>): void {
  Deno.serve(async (req) => {
    try {
      return await handler(req);
    } catch (e) {
      if (e instanceof HttpError) {
        return json({ error: e.message, code: e.code }, e.status);
      }
      console.error(e);
      return json({ error: '서버에서 문제가 생겼어요. 잠시 후 다시 시도해 주세요.', code: 'internal' }, 500);
    }
  });
}
