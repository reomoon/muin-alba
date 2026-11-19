// =====================================================================
// 동네 인증 (2단계)
//   POST /functions/v1/neighborhood
//   헤더: Authorization: Bearer <앱 로그인 토큰>  (supabase.functions.invoke 가 자동으로 붙임)
//   본문: { "lat": 37.5045, "lng": 127.0366, "confirm": false }
//     confirm = false → 이 위치의 동네만 알려 줌 ("역삼1동 맞나요?" 화면)
//     confirm = true  → 동네 인증 저장 (유효기간: app_config.neighborhood_valid_days)
//   응답: { region: { code, name, dong, sigungu }, verified_at?, expires_at? }
//   오류: { error: 사용자에게 보여 줄 문장, code: 'region_not_found' | 'out_of_korea' | ... }
// =====================================================================
import { HttpError, json, serve } from '../_shared/http.ts';
import { adminClient, requireUser } from '../_shared/supabase.ts';
import { coordToRegion } from '../_shared/kakao.ts';

serve(async (req) => {
  if (req.method !== 'POST') throw new HttpError(405, 'POST 요청만 받아요', 'method_not_allowed');

  const admin = adminClient();
  const user = await requireUser(req, admin);

  const body = await req.json().catch(() => ({}));
  const lat = Number(body?.lat);
  const lng = Number(body?.lng);
  const confirm = body?.confirm === true;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    throw new HttpError(400, '위치 값이 올바르지 않아요', 'bad_request');
  }

  const region = await coordToRegion(lat, lng);
  if (!region) throw new HttpError(422, '이 위치의 동네를 찾지 못했어요', 'region_not_found');

  if (!confirm) {
    // 위치를 받았으므로 확인자료를 남깁니다 (위치 자체는 저장하지 않음)
    const { error } = await admin.from('location_access_logs').insert({
      subject_user_id: user.id,
      action: 'collect',
      purpose: 'neighborhood_preview',
    });
    if (error) console.error('location_access_logs insert failed', error);
    return json({ region });
  }

  const { data, error } = await admin
    .rpc('save_neighborhood', {
      p_user_id: user.id,
      p_lat: lat,
      p_lng: lng,
      p_region_code: region.code,
      p_region_name: region.name,
    })
    .single();
  if (error) {
    if (error.hint === 'out_of_korea') throw new HttpError(422, error.message, 'out_of_korea');
    throw new Error(`save_neighborhood 실패: ${error.message}`);
  }

  const saved = data as { verified_at: string; expires_at: string };
  return json({ region, verified_at: saved.verified_at, expires_at: saved.expires_at });
});
