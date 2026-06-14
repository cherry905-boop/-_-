-- =====================================================================
-- 23_codes_center_scope.sql  —  [멀티테넌트 1단계: 코드 테이블 센터 스코프]
-- 멱등. 적용 순서: 19·21·22 이후(center_id 컬럼·백필 존재 가정).
--
-- student_codes 의 '활성 코드 1인 1개' 유니크를 센터 스코프로 좁힌다.
--   기존: (name, phone) where active   — 전역. 동명+동번호가 두 센터에 동시에 활성 코드를 못 가졌다.
--   변경: (center_id, name, phone) where active — 센터별. 센터 간 동명이인 충돌 제거.
-- · code 는 전역 unique 유지 — 코드 하나가 한 학생을 전역에서 유일하게 가리켜야 2단계 verify 가
--   'code → center_id' 를 명확히 도출한다(센터 인지 RPC의 근거). 그래서 code 는 좁히지 않는다.
-- · student_codes 발급은 admin.html 에서 update/insert(존재확인 후) 방식이라 onConflict 미사용 →
--   이 인덱스 변경은 프론트와 결합이 없다(회귀 0).
--
-- ⚠️ 회사 키(company_codes/company_stages/company_info 의 `company text PK`)와 사업자번호 자연키 전환은
--    5단계(sql/27)로 통합한다. 근거(코드 실측):
--    (1) 사업자번호 컬럼이 아직 스키마에 없음(grep 0건) → 지금 (center_id,사업자번호) 키 불가.
--    (2) admin.html 의 company_codes/stages/info upsert 는 onConflict 미지정 = 기본 PK(company) 충돌에
--        의존(1932/1966/2005). company PK 를 지금 떼면 그 upsert 들이 깨진다 → 키 변경은 admin.html
--        upsert 변경(또는 bulk RPC 대체)과 한 묶음이어야 한다.
--    (3) 2번째 센터가 회사를 갖는 시점이 5단계(명단 일괄등록)라 그 전엔 센터 간 동명 충돌이 발생하지 않음.
--    → company 이름키로 갈았다가 다시 사업자번호로 가는 이중 작업·조기 결합을 피해 5단계서 일괄 처리.
-- =====================================================================

do $codes$
begin
  if to_regclass('public.student_codes') is not null
     and exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='student_codes' and column_name='center_id') then
    -- 전역 person-uniq 제거 → 센터 스코프로 재생성(멱등)
    drop index if exists public.student_codes_person_uniq;
    create unique index if not exists student_codes_person_uniq
      on public.student_codes (center_id, name, phone) where active;
  end if;
end
$codes$;
