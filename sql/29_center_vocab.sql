-- =====================================================================
-- 29_center_vocab.sql  —  [백본 이후 ②b: 센터별 어휘 DB화 토대]
-- 멱등·추가만. centers 에 vocab jsonb 컬럼 추가. 기존 동작 변화 0(아무도 아직 안 읽음/mju=null).
--
-- vocab = 센터별 정적 어휘(config.js 의 JOBS/MANAGERS/TYPES/TYPE2/STATUSES/COMPANY_STAGES/COMPANY_SURVEYS)를
--   센터별 DB값으로. mju 는 vocab=null 유지 → app.js 가 config.js 정적값으로 폴백(파일럿 동일).
--   신규 센터는 vocab 을 채우면 그 센터 직무·담당·유형이 타게팅 드롭다운·가입폼에 반영된다.
-- 구조 예:
--   {"jobs":[{"key":"...","label":"...","dept":"..."}], "managers":["..."], "types":["..."],
--    "type2":["..."], "statuses":["..."], "company_stages":[...], "company_surveys":{...}}
-- (companies 는 별도 — companies 마스터 테이블에서 센터스코프로 이미 조회. vocab 에 안 넣음.)
-- =====================================================================

alter table public.centers add column if not exists vocab jsonb;
