-- =====================================================================
-- 31_cohort.sql  —  [4 기수·졸업] registrations·students 에 cohort(기수/년도) 추가
-- 멱등·추가만. 적용 순서: 19(center_id) 이후.
--
-- 모델: cohort = 기수 라벨(예 '2026'). NULL = 기수 미지정 → 목록·타게팅에서 '전체'로 취급(현재 동작 = 폴백 안전).
--   · 졸업 처리 = 다음 기수 라벨로 넘어가고 옛 기수를 기본 필터에서 빼는 운영(데이터는 보존, 이력·통계).
--   · 관리자 cohort 수정은 registrations 의 센터스코프 RLS(sql/21) 가 허용하므로 client update 로 충분(새 RPC 불필요).
--   · 신규 학생은 수기추가 폼/CSV 의 '기수' 값으로 들어가고, bulk_upsert_student_roster 의 동적 insert 가 그대로 채운다.
-- =====================================================================

do $coh$
declare
  t    text;
  tbls text[] := array['registrations', 'students'];
begin
  foreach t in array tbls loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I add column if not exists cohort text', t);
      execute format('create index if not exists %I on public.%I (center_id, cohort)', t || '_cohort_idx', t);
    end if;
  end loop;
end
$coh$;
