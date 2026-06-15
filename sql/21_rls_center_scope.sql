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

    -- (a) 갓모드 정책 제거 — 두 형태 모두:
    --   (1) cmd=ALL & USING=true (원조 갓모드)
    --   (2) USING/WITH CHECK = (auth.uid() IS NOT NULL) (= '로그인한 어떤 관리자든' = 센터 무스코프).
    --       이 형태가 레포의 실제 관리자 정책이다: surveys/polls/company_info 의 ALL,
    --       company_contacts/survey_answers/poll_votes/company_survey_responses 의 SELECT·DELETE.
    --       (1) 만 지우면 이들이 살아남아 permissive OR 로 센터 스코프 정책을 무효화한다 → cmd 무관 제거.
    --   ⚠️ anon/공개읽기 정책은 qual 형태가 달라(예: 'true'(SELECT), '(open = true OR auth.uid() IS NOT NULL)',
    --      '(published = true)') 매칭되지 않으므로 보존된다. 본인행 정책('(user_id = auth.uid())')도 보존.
    for pol in
      select policyname from pg_policies
      where schemaname = 'public' and tablename = t
        and (
              (cmd = 'ALL' and qual = 'true')
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
