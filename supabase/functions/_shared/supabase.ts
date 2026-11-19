// 공통: 서버 권한 Supabase 클라이언트와 요청한 사용자 확인
import { createClient, type SupabaseClient, type User } from 'npm:@supabase/supabase-js@2';
import { HttpError } from './http.ts';

// 서버 전용 키는 Supabase 가 Edge Function 환경변수로 자동으로 넣어 줍니다.
function serverKey(): string {
  const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacy) return legacy;
  // 새 API 키 방식 프로젝트: SUPABASE_SECRET_KEYS = {"default": "sb_secret_..."}
  const keys = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (keys) {
    try {
      const parsed = JSON.parse(keys) as Record<string, string>;
      const key = parsed['default'] ?? Object.values(parsed)[0];
      if (key) return key;
    } catch {
      // 형식이 다르면 아래 오류로
    }
  }
  throw new Error('서버 키(SUPABASE_SERVICE_ROLE_KEY)를 찾지 못했어요');
}

export function adminClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  if (!url) throw new Error('SUPABASE_URL 환경변수가 없어요');
  return createClient(url, serverKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

// 앱이 보낸 로그인 토큰(Authorization: Bearer ...)으로 요청한 사람을 확인합니다.
export async function requireUser(req: Request, admin: SupabaseClient): Promise<User> {
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  if (!token) throw new HttpError(401, '로그인이 필요해요', 'unauthorized');
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, '로그인이 필요해요', 'unauthorized');
  return data.user;
}
