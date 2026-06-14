-- =====================================================================
-- 27_roster_master_schema.sql  —  [멀티테넌트 5단계(스키마 추가분): 사업자번호 자연키 토대]
-- 멱등. 적용 순서: 19·21·22·23·24·25·26 이후.
--
-- 목적: 명단/회사를 '사업자번호'로 묶는 토대를 '추가만' 한다(파괴적 변경 없음 → admin.html upsert 무회귀).
--   · companies/students 마스터에 center_id(+mju 백필) 추가(19 배열에서 누락됐던 것).
--   · companies·company_codes·company_stages·company_info 에 biz_no(사업자번호) 컬럼 추가.
--   · (center_id, biz_no) 부분 유니크 = 사업자번호가 채워진 행에 한해 센터 스코프 유일성.
--
-- ⚠️ 의도적으로 '아직 안 하는' 것:
--   (1) company_codes/stages/info 의 `company text PK` 드롭 → biz_no 키 전환은 '아직' 안 한다.
--       admin.html 의 company upsert(1932/1966/2005)가 기본 PK(company) 충돌에 의존하므로, PK 드롭은
--       프론트 upsert 전환(onConflict)·biz_no 데이터 적재가 끝난 뒤의 별도 micro-migration 으로.
--       그때까지 company PK 와 (center_id,biz_no) 부분유니크가 공존(추가 제약이라 무해).
--   (2) bulk_upsert_student_roster / bulk_upsert_companies RPC + admin.html CSV UI →
--       students/companies 마스터의 실제 컬럼 정의가 레포에 없어(대시보드 관리) 정확히 쓰려면 스키마가 필요.
--       사용자에게 두 마스터 스키마 덤프 요청 후 작성 예정(또는 register 식 동적 insert 로 보강).
-- =====================================================================

do $roster$
declare
  mju uuid;
  t   text;
  cid_tbls text[] := array['companies','students'];                       -- center_id 누락분(19 배열 밖)
  biz_tbls text[] := array['companies','company_codes','company_stages','company_info'];
begin
  select id into mju from public.centers where slug = 'mju';

  -- center_id 추가 + mju 백필 + 인덱스 (companies/students)
  foreach t in array cid_tbls loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I add column if not exists center_id uuid references public.centers(id)', t);
      execute format('update public.%I set center_id = $1 where center_id is null', t) using mju;
      execute format('create index if not exists %I on public.%I (center_id)', t || '_center_idx', t);
    end if;
  end loop;

  -- biz_no(사업자번호) 컬럼 추가 + (center_id, biz_no) 부분 유니크 (회사 계열 테이블)
  foreach t in array biz_tbls loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I add column if not exists biz_no text', t);
      -- 정규화 권장(숫자만)은 적재 RPC/UI 에서. 여기선 채워진 값에 한해 센터 유일성만 강제.
      execute format(
        'create unique index if not exists %I on public.%I (center_id, biz_no) where biz_no is not null',
        t || '_center_biz_uniq', t);
    end if;
  end loop;
end
$roster$;
