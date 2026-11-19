// =====================================================================
// 회원 탈퇴 (2단계, Google Play 계정 삭제 정책)
//   POST /functions/v1/delete-account   (앱 로그인 토큰 필요, 본문 없음)
//   1) prepare_account_deletion: 근무 중 매칭 종료·공고 재모집, 지울 매장 사진 목록
//   2) Storage 에서 그 사진들을 삭제
//   3) 로그인 계정 삭제 → 프로필·매장 등은 외래키 규칙대로 함께 정리
//      (위치정보 확인자료는 법정 보관 기간 동안 남깁니다)
//   응답: { ok: true }
// =====================================================================
import { HttpError, json, serve } from '../_shared/http.ts';
import { adminClient, requireUser } from '../_shared/supabase.ts';

serve(async (req) => {
  if (req.method !== 'POST') throw new HttpError(405, 'POST 요청만 받아요', 'method_not_allowed');

  const admin = adminClient();
  const user = await requireUser(req, admin);

  const { data: paths, error } = await admin.rpc('prepare_account_deletion', { p_user_id: user.id });
  if (error) throw new Error(`prepare_account_deletion 실패: ${error.message}`);

  const byBucket = new Map<string, string[]>();
  for (const p of (paths ?? []) as { bucket_id: string; name: string }[]) {
    const list = byBucket.get(p.bucket_id) ?? [];
    list.push(p.name);
    byBucket.set(p.bucket_id, list);
  }
  for (const [bucket, names] of byBucket) {
    for (let i = 0; i < names.length; i += 100) {
      const { error: removeError } = await admin.storage.from(bucket).remove(names.slice(i, i + 100));
      if (removeError) throw new Error(`사진 삭제 실패(${bucket}): ${removeError.message}`);
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) throw new Error(`계정 삭제 실패: ${deleteError.message}`);

  return json({ ok: true });
});
