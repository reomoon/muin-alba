// 카카오 로컬 API
// REST 키는 앱에 넣지 않고 Edge Function 비밀값 KAKAO_REST_API_KEY 로만 씁니다.

export interface Region {
  code: string; // 행정동 코드 10자리
  name: string; // 예: 서울특별시 강남구 역삼1동
  dong: string; // 예: 역삼1동
  sigungu: string; // 예: 서울특별시 강남구
}

interface Coord2RegionDoc {
  region_type: string; // 'B' 법정동, 'H' 행정동
  code: string;
  address_name: string;
  region_1depth_name: string;
  region_2depth_name: string;
  region_3depth_name: string;
}

function kakaoKey(): string {
  const key = Deno.env.get('KAKAO_REST_API_KEY');
  if (!key) throw new Error('KAKAO_REST_API_KEY 비밀값이 설정되지 않았어요');
  return key;
}

// 좌표 → 행정동
export async function coordToRegion(lat: number, lng: number): Promise<Region | null> {
  const url = new URL('https://dapi.kakao.com/v2/local/geo/coord2regioncode.json');
  url.searchParams.set('x', String(lng));
  url.searchParams.set('y', String(lat));

  const res = await fetch(url, { headers: { Authorization: `KakaoAK ${kakaoKey()}` } });
  if (!res.ok) {
    throw new Error(`카카오 로컬 API 오류 ${res.status}: ${await res.text()}`);
  }

  const body = (await res.json()) as { documents?: Coord2RegionDoc[] };
  const h = body.documents?.find((d) => d.region_type === 'H');
  if (!h) return null;

  return {
    code: h.code,
    name: h.address_name,
    dong: h.region_3depth_name,
    sigungu: `${h.region_1depth_name} ${h.region_2depth_name}`.trim(),
  };
}
