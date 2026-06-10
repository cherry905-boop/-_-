/* =====================================================================
 *  config.js  —  이 파일 한 곳만 고치면 됩니다 (가장 자주 만지는 설정 파일)
 *  - 한글 깨짐 방지: 반드시 "UTF-8" 인코딩으로 저장하세요.
 *  - 따옴표(' ') 안의 값만 바꾸고, 콤마/중괄호는 건드리지 마세요.
 * ===================================================================== */

window.APP_CONFIG = {
  // ── 1) Supabase 연결값 (Supabase 대시보드 > Project Settings > API 에서 복사) ──
  //    아직 없으면 placeholder 그대로 두고, README_SETUP.md 2번 순서대로 만든 뒤 붙여넣으세요.
  SUPABASE_URL:      'https://ummuyzqyanrearbzgqyp.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_XzwIozsND6H-wTKmCQxGCQ_iM_aKhmx', // publishable(공개용) 키 — 노출돼도 안전

  // ── 2) 센터/앱 표시 정보 ──
  CENTER_NAME: '일학습병행 공동훈련센터',
  APP_TITLE:   '일학습병행 앱',

  // ── 3) 개인정보 처리방침 안내 (가입 동의 화면에 표시) ──
  PRIVACY_RETENTION: '훈련 종료 후 3년',          // 보유기간 (기관 규정에 맞게 수정)
  PRIVACY_TRANSFER:  'Supabase Inc.(미국), Google LLC(미국)', // 국외 이전받는 자
  // ⚠️ 학생 배포 전 반드시 실제값으로 — 개인정보보호법 게시의무(privacy.html에 표시됨):
  PRIVACY_OFFICER:         '○○○ (직책)',                          // 개인정보 보호책임자 성명·직책
  PRIVACY_OFFICER_CONTACT: '전화 000-0000-0000 / 이메일 ○○○@○○○',  // 보호책임자 연락처(열람·삭제·철회 창구)
  PRIVACY_EFFECTIVE_DATE:  '2026-○○-○○',                          // 처리방침 시행일
};

/* ── 4) 훈련 직무 (1차 분류축) ─ 노션 "2026 직무" 미러 ─────────────────
 *  출석부 양식 폴더(14직무)와 1:1. key=고정 식별자, label=학생에게 보이는 이름, dept=소속 학과(보조).
 *  ※ 스마트물류운영관리_L4 는 IPP포털 수강명단으로 운영여부 확인 후 추가.
 *  ※ '2,3유형'은 직무가 아니라 아래 TYPES(유형) 축으로 분류.
 */
window.JOBS = [
  { key: 'struct_l4',      label: '구조해석설계 (L4)',                 dept: '기계공학과' },
  { key: 'semieq_mech_l5', label: '반도체장비개발 · 기구설계 (L5)',     dept: '기계공학과' },
  { key: 'semidesign_l4',  label: '반도체설계 · 디지털설계 (L4)',       dept: '전자공학과' },
  { key: 'semieq_elec_l5', label: '반도체장비개발 · 전장설계 (L5)',     dept: '전자공학과' },
  { key: 'semieq_semi',    label: '반도체장비개발 · 전장설계',           dept: '반도체공학과' },
  { key: 'semimat_l4',     label: '반도체재료개발 (L4)',               dept: '신소재·화학공학과' },
  { key: 'chemanal_l5',    label: '화학물질분석 (L5)',                 dept: '화학나노학과' },
  { key: 'elec_design',    label: '전기설계',                         dept: '전기공학과' },
  { key: 'quality_l5',     label: '품질경영 (L5)',                     dept: '산업경영공학과' },
  { key: 'appdesign_l4',   label: '스마트앱디자인설계 · 게임 (L4)',     dept: '디지털콘텐츠디자인학과' },
  { key: 'sw_ict_l5',      label: 'SW개발 (L5) · 정보통신',            dept: '정보통신공학과' },
  { key: 'sw_cse_l5',      label: 'SW개발 (L5) · 컴퓨터',              dept: '컴퓨터공학과' },
  { key: 'biz_mkt',        label: '기획사무 · 마케팅',                 dept: '경영학과' },
  { key: 'biz_fin',        label: '재무회계',                         dept: '경영학과' },
];

/* ── 5) 학습기업 ─ 노션 "2026 기업 정보" 미러(초기 시드) ─────────────────
 *  ⚠️ 아래는 노션에서 가져온 일부 시드(25개)입니다. R2(노션 자동동기화)에서 전체 기업으로 자동 갱신됩니다.
 *  목록에 없으면 가입폼에서 '직접 입력'할 수 있습니다. 값(기업명)은 노션 기업명과 동일하게 유지하세요.
 */
window.COMPANIES = [
  '㈜덱스컨설팅','㈜나노엑스','프리시스','FTC코리아','㈜TPC로보틱스','대신환경기술',
  '아이디어스투실리콘','티엑스알로보틱스 마곡','피닉슨컨트롤스','(주)제이더블유시스템',
  '앰코테크놀로지코리아','한맥기술','엑시콘 천안','(주)프람트테크놀로지','더뷰티팩토리',
  '하이비젼시스템','주식회사 넥서스원','(주)시지바이오','아롬정보기술㈜(컴공)','엘케이셀텍',
  '아롬정보기술㈜(정보)','하나마이크론','주식회사 시지메드텍','멜콘','HDC랩스',
];

/* ── 6) 유형 ─ 노션 select 미러 ── */
window.TYPES = ['1유형', '2유형', '3유형'];   // 학습근로자 프로그램 유형
window.TYPE2 = ['산업형', '자율형'];          // (참고) 운영형태
window.MANAGERS = ['권순천', '김성훈', '차민정', '노혜정', '길은경'];  // 담당자 (타게팅용)
window.STATUSES = ['진행중', '휴학', '중도탈락', '수료'];              // 상태 (타게팅용)

/* ── 8) 푸시(FCM) 설정 ─ Firebase 콘솔에서 발급. 공개값이라 노출돼도 됨 ──
 *  Firebase 콘솔 → 프로젝트 설정 → '내 앱'(웹 </>) 에서 SDK 설정값 복사,
 *  → Cloud Messaging → '웹 푸시 인증서'에서 키 쌍 생성 후 공개키를 FCM_VAPID_KEY 에.
 */
window.FIREBASE_CONFIG = {
  apiKey:            'AIzaSyDCQj4zs_ebgM18GKotG1-7n-MVXVdHkqs',
  authDomain:        'mjuipp.firebaseapp.com',
  projectId:         'mjuipp',
  messagingSenderId: '13262157393',
  appId:             '1:13262157393:web:45caa766392425a90eaa70',
};
window.FCM_VAPID_KEY = 'BPwU6DR4mAus6qml5sw8A4kokXyuuJIB-V6HkCuvqeUTm-Xkqn9nOFS6APeY1dW6BSTyjkj6vR8cgICmUKkU7pg';

/* ── 7) 대상 구분 ── */
window.TARGET_TYPES = [
  { key: 'student',  label: '매칭학생 (재학생)' },
  { key: 'company',  label: '학습기업 담당자 (HRD담당자·기업현장교사)' },
];
