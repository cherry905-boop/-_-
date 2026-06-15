-- =====================================================================
-- 21_rls_center_scope.sql  —  [P5] 관리자 갓모드 제거 → 센터 스코프 RLS
-- 적용 순서: 19(센터/admin_users/center_id) 이후. 라이브 적용 + rls-check 통과 확인 필수.
--
-- 제거 대상(갓모드): `for all to authenticated using (true) with check (true)`
--   → 어떤 관리자든 전 센터 데이터 접근. 이를 센터 스코프 정책으로 교체:
--     super_admin = 전체 / center_admin = 자기 center_id 행만.
-- 프로젝트 전례: publishable 키에서 `to authenticated` 가 안 먹힘 →
--   정책은 `to public` + auth.uid() 기반 헬퍼(current_admin_center/is_super_admin) 조건.
--   anon(미로그인)은 두 헬퍼가 null/false 라 자동 차단(기존 anon 차단 유지).
--
-- ⚠️ 적용 전 점검(드라이런): 아래로 갓모드 정책 목록을 먼저 확인하라.
--   select schemaname, tablename, policyname, cmd, qual, with_check
--   from pg_policies where schemaname='public' and qual='true';
-- =====================================================================

do $rls$
declare
  t   text;
  pol record;
  tbls text[] := array[
    'registrations','push_tokens','push_logs','student_codes','company_codes',
    'company_contacts','company_info','company_stages','company_survey_responses',
    'job_postings','qna_posts','success_cases','surveys','survey_answers',
    'polls','poll_votes','notices','library','calendar_events',
    'consultations','consultation_messages','notice_recipients'
  ];
begin
  foreach t in array tbls loop
    if to_regclass('public.' || t) is null then continue; end if;

    -- RLS 활성(멱등). notices/library/calendar_events/consultations/consultation_messages/notice_recipients 는
    -- 레포에 create table 이 없는 대시보드 관리 테이블이라 'enable RLS' 박제가 sql 에 없었다. RLS 가 꺼져 있으면
    -- 아래 센터 스코프 정책이 무시되고 grant 만으로 전면 개방되므로 명시적으로 켠다(이미 켜져 있으면 no-op).
    execute format('alter table public.%I enable row level security', t);

    -- (a) 갓모드 정책 제거 — 아래 형태들:
    --   (1) cmd=ALL & USING=true (원조 갓모드: for all to ... using(true)).
    --   (2) USING/WITH CHECK = (auth.uid() IS NOT NULL) (= '로그인한 어떤 관리자든' = 센터 무스코프).
    --       레포 실제 관리자 정책 다수가 이 형태다: surveys/polls/company_info 의 ALL,
    --       company_contacts/survey_answers/poll_votes/company_survey_responses 의 SELECT·DELETE.
    --   (3) ★ bare-true(USING=true 또는 WITH CHECK=true) + roles 에 authenticated 포함 — cmd 무관(DELETE/SELECT/UPDATE/INSERT).
    --       sql/07 "admin delete"(= for delete to authenticated using(true), 즉 cmd=DELETE·qual='true'·with_check=NULL)가
    --       바로 이 형태다. (1)은 cmd=ALL 이라, (2)는 qual='true'≠'(auth.uid()...)'라 둘 다 비매칭 → 예전 루프에선 살아남아
    --       센터 스코프 정책과 permissive OR 되어 '아무 로그인 계정이나 타 센터 행 DELETE' 구멍이 됐다(교차센터 삭제).
    --   ⚠️ 보존: anon/공개읽기 bare-true 정책은 roles 가 {anon}/{public} 이라 (3)의 authenticated 가드로 제외된다
    --      (예: sql/17 "anyone read polls"=for select to public using(true), sql/16 "anyone submit esurvey"=for insert to public with check(true)).
    --      본인행 정책('(user_id = auth.uid())')·published/open 게이트 정책도 qual 형태가 달라 보존된다.
    for pol in
      select policyname from pg_policies
      where schemaname = 'public' and tablename = t
        and (
              (cmd = 'ALL' and qual = 'true')
           or (qual = 'true'      and roles @> array['authenticated']::name[])
           or (with_check = 'true' and roles @> array['authenticated']::name[])
           or qual = '(auth.uid() IS NOT NULL)'
           or with_check = '(auth.uid() IS NOT NULL)'
        )
    loop
      execute format('drop policy if exists %I on public.%I', pol.policyname, t);
    end loop;

    -- (b) 센터 스코프 관리자 정책 생성(멱등 위해 먼저 drop).
    execute format('drop policy if exists %I on public.%I', t || '_admin_center', t);
    execute format($f$
      create policy %I on public.%I
        for all to public
        using ( public.is_super_admin() or center_id = public.current_admin_center() )
        with check ( public.is_super_admin() or center_id = public.current_admin_center() )
    $f$, t || '_admin_center', t);
  end loop;
end
$rls$;

-- 주의: 위는 '관리자 쓰기/관리' 경로만 센터 스코프화한다.
-- 학생(anon) 공개 읽기 경로(예: notices/library/calendar/surveys/polls 의 published=true)는
-- 22(공개읽기 센터 스코프)에서 `center_id = <요청 센터>` 를 추가로 강제한다.
