-- =====================================================================
-- 25_center_id_writes.sql  —  [멀티테넌트 3단계: 관리자 쓰기 center_id 자동 주입]
-- 멱등. 적용 순서: 19·21·22·23·24 이후.
--
-- 목적: 관리자가 콘텐츠를 INSERT 할 때 center_id 를 '서버가' 채운다(클라 미신뢰).
--   · center_admin: 클라가 보낸 center_id 를 '무조건 무시'하고 current_admin_center() 로 강제(coalesce 아님).
--   · super_admin: 명시 center_id 는 honor(다센터 운영), 없으면 자기 홈 센터.
-- 그리고 registrations 관리자 정책의 '전센터 OR 구멍'(sql/14)을 센터 스코프로 교체하고,
-- unverified_signups(도움요청) 의 anon insert 박제 + 관리자 읽기 센터 스코프를 더한다.
--
-- ⚠️ 트리거는 '관리자가 쓰는 콘텐츠 테이블'에만 부착한다. registrations·poll_votes·survey_answers·
--    company_survey_responses·consultations·consultation_messages·push_tokens·notice_recipients·
--    unverified_signups 같은 anon/학생/시스템 쓰기 테이블에 붙이면, 비관리자 insert 때 current_admin_center()
--    가 null 이라 center_id 를 null 로 덮어써 가입·투표·응답을 깨뜨린다.
--    · registrations → 24단계 register_* RPC 가 center 주입(처리됨).
--    · poll_votes/survey_answers/company_survey_responses 등 학생·기업 응답 → 부모(poll/survey)의 center 로
--      도출하는 별도 트리거가 필요(미구현, 다음 보강 대상). push_tokens → 토큰등록 RPC 센터화(미구현).
--    현재 단일테넌트(mju)에선 이들 신규행 center_id=NULL 이고 super_admin 엔 보임(무사고), 2번째 센터 전에 보강.
-- =====================================================================

-- ── A. center_id 자동 주입 트리거 함수 ──
create or replace function public._set_center_id_on_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_center uuid;
begin
  if is_super_admin() then
    NEW.center_id := coalesce(NEW.center_id, current_admin_center());      -- super: 명시값 honor
  else
    v_center := current_admin_center();
    if v_center is not null then
      NEW.center_id := v_center;                                          -- center_admin: 클라값 무시·강제
    end if;
    -- 비관리자(anon/student) 도달 시엔 NEW.center_id 를 건드리지 않음(이 트리거는 관리자 전용 테이블 전용)
  end if;
  return NEW;
end $$;

-- ── B. 관리자-쓰기 콘텐츠 테이블에 BEFORE INSERT 트리거 부착 ──
do $trg$
declare
  t text;
  tbls text[] := array[
    'student_codes','company_codes','company_contacts','company_info','company_stages',
    'job_postings','qna_posts','success_cases','surveys','polls',
    'notices','library','calendar_events'
  ];
begin
  foreach t in array tbls loop
    if to_regclass('public.' || t) is not null
       and exists (select 1 from information_schema.columns c
                   where c.table_schema='public' and c.table_name=t and c.column_name='center_id') then
      execute format('drop trigger if exists set_center_id on public.%I', t);
      execute format(
        'create trigger set_center_id before insert on public.%I
           for each row execute function public._set_center_id_on_write()', t);
    end if;
  end loop;
end
$trg$;

-- ── C. registrations 관리자 정책의 '전센터 OR 구멍'(sql/14) 센터 스코프로 교체 ──
-- 기존: using (auth.uid() is not null) = 로그인한 어떤 관리자든 전 센터 가입자 열람/삭제.
do $reg$
begin
  if to_regclass('public.registrations') is not null then
    drop policy if exists "admin read registrations" on public.registrations;
    create policy "admin read registrations" on public.registrations
      for select to public using ( is_super_admin() or center_id = current_admin_center() );
    drop policy if exists "admin delete registrations" on public.registrations;
    create policy "admin delete registrations" on public.registrations
      for delete to public using ( is_super_admin() or center_id = current_admin_center() );
  end if;
end
$reg$;

-- ── D. unverified_signups(가입도움 요청): anon insert 박제 + 관리자 읽기 센터 스코프 ──
-- index.html 의 help-send 가 anon 으로 insert(이름·전화·구분·사유). 정책이 레포에 없었음 → 박제.
do $us$
begin
  if to_regclass('public.unverified_signups') is not null then
    execute 'alter table public.unverified_signups enable row level security';
    -- 도움요청 anon insert 유지(permissive). SELECT 정책은 없음 → anon 차단(rls-check MUST_BE_BLOCKED).
    drop policy if exists "unverified anon insert" on public.unverified_signups;
    create policy "unverified anon insert" on public.unverified_signups
      for insert to public with check (true);
    -- 관리자 읽기/관리 센터 스코프(sql/21 패턴; 19 의 center_id 백필 대상이나 21 배열에서 누락됐던 것 보강).
    drop policy if exists "unverified_signups_admin_center" on public.unverified_signups;
    create policy "unverified_signups_admin_center" on public.unverified_signups
      for all to public
      using ( is_super_admin() or center_id = current_admin_center() )
      with check ( is_super_admin() or center_id = current_admin_center() );
    -- NOTE: help-send 는 center_id 미설정 → 도움요청은 현재 super_admin 에게만 보임(center_admin 은 null≠자기센터).
    --       슬러그→center 도출 RPC 로 바인딩하는 보강은 추후(드물고 super 가 운영 주체라 무사고).
  end if;
end
$us$;
