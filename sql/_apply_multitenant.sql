-- ================================================================
-- _apply_multitenant.sql — 멀티테넌트 + 코드리뷰 15건 수정 통합본 (19~32)
-- Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run.
-- 모든 구문 idempotent(재실행 안전). 번호순으로 이미 합쳐져 있음.
-- ⚠️ 이후 후속(대시보드 전용): admin_students() RPC 에 센터 스코프 추가(아래 32 파일 주석 참조).
-- ================================================================


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/19_multitenant_core.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- =====================================================================
-- 19_multitenant_core.sql  —  [P3/P5 backbone] 멀티테넌트 핵심 스키마
-- 멱등(idempotent): 여러 번 실행해도 안전. 기존 데이터는 전부 명지대(mju)로 백필.
-- 적용 순서: 01~18 이후 → 19 → 20(storage) → 21(RLS 재작성).
-- ⚠️ 이 마이그레이션은 '추가'만 한다(컬럼/테이블/헬퍼). 갓모드 정책 제거는 21에서.
-- =====================================================================

-- ── 1) 센터 레지스트리 (config.js 의 센터별 값을 DB로) ──
create table if not exists public.centers (
  id                        uuid primary key default gen_random_uuid(),
  slug                      text unique not null check (slug ~ '^[a-z0-9-]{1,40}$'),
  name                      text not null,
  region                    text,
  app_title                 text,
  privacy_officer           text,
  privacy_officer_contact   text,
  privacy_effective_date    text,
  privacy_retention         text,
  privacy_retention_applicant text,
  privacy_transfer          text,
  push_kick_url             text,           -- 센터별 푸시 발송기(P7에서 조직계정으로)
  active                    boolean not null default true,
  created_at                timestamptz not null default now()
);

-- 명지대(파일럿) 센터 시드 — config.js 현재값과 일치 (멱등)
insert into public.centers (slug, name, region, app_title, privacy_officer, privacy_officer_contact,
  privacy_effective_date, privacy_retention, privacy_retention_applicant, privacy_transfer)
values ('mju', '일학습병행 공동훈련센터', '명지대', '일학습병행 앱',
  '권순천 (일학습병행운영팀)', '전화 031-324-1228 / 이메일 cherry905@mju.ac.kr',
  '2026. 6. 11.', '훈련 종료 후 3년', '해당 학년도 모집 종료 후 6개월',
  'Supabase Inc.(미국), Google LLC(미국)')
on conflict (slug) do nothing;

-- centers 는 공개 표시 정보(센터명·처리방침 문구) → anon 읽기 허용(rls-check PUBLIC_OK).
alter table public.centers enable row level security;
drop policy if exists "centers public read" on public.centers;
create policy "centers public read" on public.centers for select to public using (active);

-- ── 2) 관리자↔센터↔역할 매핑 (P5에서 RLS가 이걸로 권한 강제) ──
create table if not exists public.admin_users (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  center_id  uuid references public.centers(id) on delete restrict,
  role       text not null default 'center_admin' check (role in ('super_admin','center_admin')),
  created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;
-- admin_users 자체는 PII 매핑 → anon 차단(정책 미부여). 관리자 본인 행만 읽기 허용:
drop policy if exists "admin reads own mapping" on public.admin_users;
create policy "admin reads own mapping" on public.admin_users
  for select to public using (user_id = auth.uid());

-- ── 3) 권한 헬퍼 (RLS/RPC 공용). SECURITY DEFINER 로 매핑 조회 ──
create or replace function public.current_admin_center()
returns uuid language sql stable security definer set search_path = public as $$
  select center_id from public.admin_users where user_id = auth.uid();
$$;
create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.admin_users where user_id = auth.uid() and role = 'super_admin');
$$;
create or replace function public.center_id_for_slug(p_slug text)
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.centers where slug = lower(p_slug);
$$;
grant execute on function public.current_admin_center(), public.is_super_admin(), public.center_id_for_slug(text) to anon, authenticated;

-- ── 4) 기존 전 테이블에 center_id 추가 + 명지대로 백필 ──
-- 존재하는 테이블에만 적용(to_regclass 체크)하므로 누락 테이블이 있어도 안전.
do $mt$
declare
  t    text;
  mju  uuid;
  tbls text[] := array[
    'registrations','push_tokens','push_logs','student_codes','company_codes',
    'company_contacts','company_info','company_stages','company_survey_responses',
    'job_postings','qna_posts','success_cases','surveys','survey_answers',
    'polls','poll_votes','verify_attempts','notices','library','calendar_events',
    'consultations','consultation_messages','notice_recipients','unverified_signups'
  ];
begin
  select id into mju from public.centers where slug = 'mju';
  foreach t in array tbls loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I add column if not exists center_id uuid references public.centers(id)', t);
      execute format('update public.%I set center_id = $1 where center_id is null', t) using mju;
      execute format('create index if not exists %I on public.%I (center_id)', t || '_center_idx', t);
    end if;
  end loop;
end
$mt$;

-- (NOT NULL 강제는 21에서 — 모든 쓰기 경로가 center_id 를 채우도록 고친 뒤 적용)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/20_storage_isolation.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- =====================================================================
-- 20_storage_isolation.sql  —  [P2] 자료실(library 버킷) 센터 격리
-- 적용 순서: 19 이후. 라이브 적용 + 동작 확인 필요(로컬에서 검증 불가).
--
-- 배경: 학생은 '비로그인(anon)'이고 클라이언트가 보낸 center 는 신뢰하지 않는다.
--   따라서 공개 버킷(getPublicUrl)으로는 교차센터 차단이 불가능하다(URL만 알면 누구나 열람).
--   진짜 격리 = (a) 버킷 비공개 + (b) 센터별 경로(<slug>/lib/...) + (c) 서버측 서명 URL.
--   (a),(b)는 여기서. (c) anon 서명기는 초대코드로 센터 자격을 검증하는 Edge Function 으로
--   P7에서 완성한다(SQL 함수로는 storage 서명 토큰을 만들 수 없음).
-- =====================================================================

-- ── 1) 버킷을 비공개로 (공개 URL 차단) ──
update storage.buckets set public = false where id = 'library';

-- ── 2) 기존 정책 정리(있으면) ──
drop policy if exists "library admin all" on storage.objects;
drop policy if exists "library public read" on storage.objects;
drop policy if exists "library admin manage own center" on storage.objects;
-- ⚠️ sql/09 의 센터 무스코프 쓰기 정책(= bucket_id='library' AND auth.uid() IS NOT NULL)도 반드시 제거.
--    안 지우면 permissive OR 로 '로그인한 어떤 관리자든' 타 센터 폴더(<other>/lib/..)에 업로드·수정·삭제 가능
--    → 아래 '자기 센터 폴더만' 정책이 무효화된다(쓰기 격리 실패).
drop policy if exists "library admin insert" on storage.objects;
drop policy if exists "library admin update" on storage.objects;
drop policy if exists "library admin delete" on storage.objects;

-- ── 3) 관리자: 자기 센터 폴더(<slug>/...)만 업로드·수정·삭제 ──
--   객체 경로 첫 폴더 = 센터 슬러그. admin_users 의 센터 슬러그와 일치해야 함.
create policy "library admin manage own center" on storage.objects
  for all to authenticated
  using (
    bucket_id = 'library'
    and (
      public.is_super_admin()
      or (storage.foldername(name))[1] = (
        select c.slug from public.centers c where c.id = public.current_admin_center()
      )
    )
  )
  with check (
    bucket_id = 'library'
    and (
      public.is_super_admin()
      or (storage.foldername(name))[1] = (
        select c.slug from public.centers c where c.id = public.current_admin_center()
      )
    )
  );

-- ── 4) 학생(anon) 읽기: 직접 SELECT 정책을 주지 않는다 ──
--   anon 에게 library 객체 SELECT 를 열면 경로만 알면 교차센터 열람이 되므로 금지.
--   학생용 다운로드는 P7 의 Edge Function 서명기(초대코드/토큰으로 센터 자격 확인 후
--   createSignedUrl 발급)를 통해서만. 그 전까지 학생 자료 열람은 기존 공개 URL 행에 한해
--   동작하며(과도기), 신규 업로드는 비공개이므로 서명기 배포 후 노출된다.
--   (library.html 의 렌더를 '저장된 path → 서명 URL' 로 바꾸는 작업은 P7 서명기와 함께.)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/21_rls_center_scope.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/22_baseline_hardening.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- =====================================================================
-- 22_baseline_hardening.sql  —  [멀티테넌트 0단계: 토대 하드닝]
-- 멱등(idempotent). 적용 순서: 19·21 이후(centers·admin_users·헬퍼·center_id·센터스코프 RLS 존재 가정).
--
-- 목적: 멀티테넌트 단계(23~)를 쌓기 전에, 레포 sql/ 에 누락돼 있던 보안 토대를 '박제'한다.
--   registrations 의 anon INSERT 정책(=학생/지원자/기업 가입의 핵심 경로)이 레포에 없고
--   운영 대시보드에만 존재했다 → 가입 폴백 경로가 버전관리 밖이라 재구축/스테이징에서 깨질 수 있었다.
--
-- ⚠️ 남은 일(사용자): registrations 의 CREATE TABLE(컬럼 정의)·기존 정책 원본은 여전히 운영
--    대시보드에만 있다. 완전한 재구축 안전을 위해 운영 DB에서 스키마 덤프로 별도 캡처가 필요하다.
--    (이 파일의 정책은 permissive 라 운영의 기존 정책과 OR 로 합쳐져 무해하며, 기존 동작을 보존한다.)
-- =====================================================================

-- ── registrations: RLS 활성 + anon 가입(INSERT) 정책 박제 ──
-- · permissive 정책 → 운영에선 기존 anon insert 정책과 OR 로 합쳐져 무해(회귀 0), 재구축에선 가입 보장.
-- · SELECT 정책은 부여하지 않는다 → anon PII 차단 유지(rls-check MUST_BE_BLOCKED).
-- · 23단계: 가입을 register_with_code RPC(서버가 center_id 도출)로 전환.
-- · 28단계(NOT NULL 승격): with check 를 (center_id is not null) 로 조인다.
do $reg$
begin
  if to_regclass('public.registrations') is not null then
    execute 'alter table public.registrations enable row level security';
    drop policy if exists "registrations anon insert" on public.registrations;
    create policy "registrations anon insert" on public.registrations
      for insert to public with check (true);
  end if;
end
$reg$;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/23_codes_center_scope.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/24_signup_issue_rpc.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- =====================================================================
-- 24_signup_issue_rpc.sql  —  [멀티테넌트 2단계: 가입·발급 RPC (center_id 서버 도출)]
-- 멱등(create or replace). 적용 순서: 19·21·22·23 이후.
--
-- 핵심: '가입'과 '코드 발급'을 SECURITY DEFINER RPC 로 옮기고, center_id 를 '항상 서버가' 도출한다.
--   · 학생/기업 가입 = 초대코드 → student_codes/company_codes 에서 center_id 도출(클라 center_id 미신뢰).
--   · 지원자 가입 = 슬러그를 center_id_for_slug 로 서버가 해석(클라 uuid 미신뢰).
--   · 코드 발급 = current_admin_center()(super 면 인자 허용)로 center_id 주입.
--
-- registrations 스키마는 운영 대시보드 관리(컬럼이 R01/R15 등으로 가변) → register_* 는 'p_row 의 키 중
--   실제 registrations 컬럼인 것만' 동적 insert 한다(없는 컬럼은 건너뛰고, id/created_at 등 기본값 보존).
--
-- 폴백: 프론트가 RPC 호출 전환 전(또는 RPC 미적용)에는 기존 직접 insert 경로가 그대로 동작(파일럿 동일).
-- =====================================================================

-- ── A. verify_* 에 center_id/center_slug 추가 (동일 시그니처 create or replace, PGRST203 안전) ──

-- A-1. 학생 코드+이름 (sql/02)
create or replace function public.verify_by_code(p_code text, p_name text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare sc record; ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('code:' || ip);
  select * into sc from student_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')) and active;
  if not found then
    return jsonb_build_object('matched', false, 'reason', 'code');
  end if;
  if replace(trim(coalesce(p_name, '')), ' ', '') <> replace(trim(sc.name), ' ', '') then
    return jsonb_build_object('matched', false, 'reason', 'name');
  end if;
  return (select verify_student(sc.name, sc.phone))::jsonb
         || jsonb_build_object('phone', sc.phone,
              'center_id', sc.center_id,
              'center_slug', (select slug from centers where id = sc.center_id));
end $$;
grant execute on function public.verify_by_code(text, text) to anon, authenticated;

-- A-2. 학생 코드 단독 (sql/09)
create or replace function public.verify_code_solo(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare sc record; ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('code:' || ip);
  select * into sc from student_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')) and active;
  if not found then
    return jsonb_build_object('matched', false, 'reason', 'code');
  end if;
  return (select verify_student(sc.name, sc.phone))::jsonb
         || jsonb_build_object('name', sc.name, 'phone', sc.phone,
              'center_id', sc.center_id,
              'center_slug', (select slug from centers where id = sc.center_id));
end $$;
grant execute on function public.verify_code_solo(text) to anon, authenticated;

-- A-3. 기업 코드 단독 (sql/13 의 HRD 자동채움 보존 + center 보강 + HRD 조회 센터 스코프)
create or replace function public.verify_company_code_solo(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c record; h record; ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('cocode:' || ip);
  select * into c from company_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')) and active;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  -- 노션 동기화 HRD담당자(없거나 12 미적용이어도 ok/company/center는 동작). center 스코프로 동명기업 혼선 차단.
  begin
    select name, phone into h from company_contacts
     where role = 'hrd' and company = c.company and coalesce(status, '') <> '종료'
       and center_id = c.center_id
     order by updated_at desc limit 1;
  -- undefined_table(테이블 없음)뿐 아니라 undefined_column(부분 마이그레이션: status/center_id 등 컬럼 부재)도
  -- 'HRD 자동채움 없음'으로 우아하게 강등한다. 안 그러면 기업 코드 검증 RPC 전체가 500 → 기업 가입 차단.
  exception when undefined_table or undefined_column then
    return jsonb_build_object('ok', true, 'company', c.company, 'hrd_name', null, 'hrd_phone', null,
              'center_id', c.center_id, 'center_slug', (select slug from centers where id = c.center_id));
  end;
  return jsonb_build_object('ok', true, 'company', c.company, 'hrd_name', h.name, 'hrd_phone', h.phone,
            'center_id', c.center_id, 'center_slug', (select slug from centers where id = c.center_id));
end $$;
grant execute on function public.verify_company_code_solo(text) to anon, authenticated;

-- ── B. 가입 RPC — center_id 를 서버가 도출해 주입 ──

-- 내부 도우미: registrations 컬럼과 교집합인 키만 동적 insert (없는 컬럼·기본값 보존)
create or replace function public._insert_registration(p_row jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare cols text;
begin
  select string_agg(quote_ident(k), ',') into cols
    from jsonb_object_keys(p_row) k
    where exists (select 1 from information_schema.columns c
                  where c.table_schema='public' and c.table_name='registrations' and c.column_name = k);
  if cols is null then raise exception 'no_columns'; end if;
  execute format(
    'insert into public.registrations (%s) select %s from jsonb_populate_record(null::public.registrations, $1)',
    cols, cols
  ) using p_row;
end $$;

-- B-1. 학생/기업: 초대코드 → center_id 서버 도출 후 가입
create or replace function public.register_with_code(p_code text, p_row jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_code text; v_center uuid; v_name text; v_phone text; v_row jsonb; ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('reg:' || ip);
  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));

  -- 학생 코드 우선 → center·명단(이름·전화), 없으면 기업 코드 → center
  select center_id, name, phone into v_center, v_name, v_phone
    from student_codes where code = v_code and active;
  if v_center is null then
    select center_id into v_center from company_codes where code = v_code and active;
  end if;
  if v_center is null then
    return jsonb_build_object('ok', false, 'reason', 'code');
  end if;

  -- center_id 는 서버가 강제(클라 값 무시). 학생이면 명단의 이름·전화를 권위값으로 덮어씀.
  v_row := coalesce(p_row, '{}'::jsonb) - 'center_id' || jsonb_build_object('center_id', v_center);
  if v_name is not null then
    v_row := v_row || jsonb_build_object('name', v_name, 'phone', v_phone);
  end if;

  perform _insert_registration(v_row);
  return jsonb_build_object('ok', true, 'center_id', v_center,
            'center_slug', (select slug from centers where id = v_center));
end $$;
grant execute on function public.register_with_code(text, jsonb) to anon, authenticated;

-- B-2. 지원자(코드 없음): 슬러그를 서버가 해석해 center_id 도출
create or replace function public.register_applicant(p_slug text, p_row jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_center uuid; v_row jsonb; ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('regapp:' || ip);

  -- 슬러그는 약한 힌트지만 center_id 는 서버가 해석(클라가 보낸 uuid 미신뢰). centers 미적용/오타면 NULL=폴백.
  v_center := center_id_for_slug(coalesce(nullif(p_slug, ''), 'mju'));
  v_row := coalesce(p_row, '{}'::jsonb) - 'center_id' || jsonb_build_object('target_type', 'applicant');
  if v_center is not null then
    v_row := v_row || jsonb_build_object('center_id', v_center);
  end if;

  perform _insert_registration(v_row);
  return jsonb_build_object('ok', true, 'center_id', v_center);
end $$;
grant execute on function public.register_applicant(text, jsonb) to anon, authenticated;

-- ── C. 코드 발급 RPC — center_id = current_admin_center() (super 면 인자 허용) ──

create or replace function public.issue_student_code(p_name text, p_phone text, p_center_id uuid default null)
returns text
language plpgsql security definer set search_path = public as $$
declare v_center uuid; v_code text;
begin
  if not (is_super_admin() or current_admin_center() is not null) then
    raise exception 'not_admin';
  end if;
  -- center_admin 은 자기 센터 강제(클라 인자 무시). super 만 p_center_id 허용.
  v_center := case when is_super_admin() then coalesce(p_center_id, current_admin_center())
                   else current_admin_center() end;
  if v_center is null then raise exception 'no_center'; end if;

  -- 같은 센터 동일인의 활성 코드가 있으면 재사용(센터 스코프 person-uniq, sql/23)
  select code into v_code from student_codes
   where center_id = v_center and name = p_name and phone = p_phone and active limit 1;
  if v_code is not null then return v_code; end if;

  v_code := gen_join_code();
  insert into student_codes (name, phone, code, center_id) values (p_name, p_phone, v_code, v_center);
  return v_code;
end $$;
grant execute on function public.issue_student_code(text, text, uuid) to authenticated;

create or replace function public.issue_company_code(p_company text, p_center_id uuid default null)
returns text
language plpgsql security definer set search_path = public as $$
declare v_center uuid; v_code text;
begin
  if not (is_super_admin() or current_admin_center() is not null) then
    raise exception 'not_admin';
  end if;
  v_center := case when is_super_admin() then coalesce(p_center_id, current_admin_center())
                   else current_admin_center() end;
  if v_center is null then raise exception 'no_center'; end if;

  -- ⚠️ company_codes 는 아직 `company text PK`(전역 unique, 센터 스코프 키는 5단계 사업자번호 전환).
  --    재사용은 '내 센터' 행으로 한정한다(이전엔 company 만으로 매칭·update → 타 센터의 동명기업 코드 행을
  --    내 센터로 가로채는 교차센터 손상이 있었다).
  select code into v_code from company_codes where company = p_company and center_id = v_center limit 1;
  if v_code is not null then
    update company_codes set active = true where company = p_company and center_id = v_center;
    return v_code;
  end if;

  -- 동명 회사가 '다른' 센터에 이미 있으면(전역 PK 충돌) 가로채지 말고 명시적으로 실패한다.
  -- (사업자번호 자연키 전환(5단계, sql/27) 전까지의 안전장치. 그 후엔 (center_id, biz_no) 로 충돌 없이 공존.)
  if exists (select 1 from company_codes where company = p_company and center_id is distinct from v_center) then
    raise exception 'company_name_taken_other_center';
  end if;

  v_code := gen_join_code();
  insert into company_codes (company, code, center_id) values (p_company, v_code, v_center);
  return v_code;
end $$;
grant execute on function public.issue_company_code(text, uuid) to authenticated;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/25_center_id_writes.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/26_center_provisioning.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- =====================================================================
-- 26_center_provisioning.sql  —  [멀티테넌트 4단계(SQL): 센터 개설·관리자 발급]
-- 멱등. 적용 순서: 19·21·22·23·24·25 이후.
-- 운영모델 A: super_admin 만 센터 생성·관리자 발급(슈퍼관리자 화면). center_admin 은 불가.
-- (프론트 = admin.html role-aware refresh + sec-centers 탭은 별도 하위단계.)
-- =====================================================================

-- ── A. admin_users 쓰기 정책 — super_admin 만 ──
-- 기존엔 "admin reads own mapping"(본인 행 select)만 있었음(19). 쓰기는 super 한정으로 연다.
do $au$
begin
  if to_regclass('public.admin_users') is not null then
    drop policy if exists "super manages admin_users" on public.admin_users;
    create policy "super manages admin_users" on public.admin_users
      for all to public
      using ( is_super_admin() )
      with check ( is_super_admin() );
  end if;
end $au$;
-- ("admin reads own mapping"(본인행 select)은 유지 — 로그인 직후 자기 role 조회·게이팅용.)

-- ── B. seed_center — 신규 센터 표준 콘텐츠 시딩(센터 스코프 멱등). 현재는 빈 센터로 시작. ──
-- 운영모델 B: 콘텐츠는 center_admin 이 대시보드로 직접 채운다 → 신규 센터는 빈 상태.
-- 공통 템플릿(일반 일학습병행 안내 등)을 넣고 싶으면 '여기'에 (center_id,...) 스코프 dedup 으로 추가:
--   insert into qna_posts (center_id, audience, category, question, answer, source, published)
--   select p_center_id, ... where not exists
--     (select 1 from qna_posts where center_id = p_center_id and question = '...');
-- ⚠️ mju 고유 시드(06/08/11)는 절대 복사 금지(명지대 전용 연락처·기업명 포함) — 0단계 보정과 일치.
create or replace function public.seed_center(p_center_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_center_id is null then return; end if;
  -- (현재 표준 템플릿 없음 → no-op. 신규 센터는 빈 상태로 시작.)
  return;
end $$;

-- ── C. create_center — super_admin 만. centers insert(멱등) + seed_center ──
create or replace function public.create_center(
  p_slug text, p_name text, p_region text default null, p_app_title text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not is_super_admin() then raise exception 'not_super_admin'; end if;
  if p_slug is null or lower(p_slug) !~ '^[a-z0-9-]{1,40}$' then
    raise exception 'invalid_slug: 소문자·숫자·하이픈 1~40자';
  end if;
  insert into public.centers (slug, name, region, app_title)
    values (lower(p_slug), p_name, p_region, p_app_title)
    on conflict (slug) do nothing
    returning id into v_id;
  if v_id is null then
    select id into v_id from public.centers where slug = lower(p_slug);   -- 이미 있으면 기존 id
  end if;
  perform seed_center(v_id);
  return v_id;
end $$;
grant execute on function public.create_center(text, text, text, text) to authenticated;

-- ── D. grant_admin — super_admin 만. 이메일 → auth.users → admin_users 매핑 upsert ──
-- ※ 대상 이메일로 Supabase Auth 계정이 먼저 있어야 한다(이메일 초대 후 첫 로그인). 없으면 에러.
-- ※ auth.users 조회 위해 SECURITY DEFINER(소유자 권한). search_path 에 auth 포함.
create or replace function public.grant_admin(
  p_email text, p_center_slug text, p_role text default 'center_admin'
) returns void
language plpgsql security definer set search_path = public, auth as $$
declare v_uid uuid; v_center uuid;
begin
  if not is_super_admin() then raise exception 'not_super_admin'; end if;
  if p_role not in ('super_admin','center_admin') then raise exception 'invalid_role'; end if;

  select id into v_uid from auth.users where lower(email) = lower(p_email) limit 1;
  if v_uid is null then
    raise exception 'user_not_found: 먼저 해당 이메일로 Supabase Auth 계정(초대)을 만들어야 합니다';
  end if;
  select id into v_center from public.centers where slug = lower(p_center_slug);
  if v_center is null then raise exception 'center_not_found'; end if;

  insert into public.admin_users (user_id, center_id, role)
    values (v_uid, v_center, p_role)
    on conflict (user_id) do update set center_id = excluded.center_id, role = excluded.role;
end $$;
grant execute on function public.grant_admin(text, text, text) to authenticated;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/27_roster_master_schema.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/28_roster_bulk_rpc.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- =====================================================================
-- 28_roster_bulk_rpc.sql  —  [멀티테넌트 5단계(RPC): 명단 일괄등록]
-- 멱등(create or replace). 적용 순서: 27 이후(companies/students 의 center_id·biz_no 존재 가정).
-- ※ 롤번호: 5단계 스키마=27, RPC=28. 이후 6=sql/20(스토리지), 7=29(NOT NULL), 8=30(config).
--
-- center_admin/super 가 CSV·엑셀 명단을 일괄 적재. center_id 는 '항상 서버가' 주입(클라 미신뢰).
--   · super 는 p_center_id 명시 허용, center_admin 은 자기 센터 강제.
--   · p_rows 는 jsonb 배열(각 원소=한 행). 실제 컬럼과 교집합인 키만 동적 insert(가변 스키마·기본값 보존).
--   · 회사: companies.notion_id 가 NOT NULL(노션 동기화 키) → CSV 행엔 합성 notion_id('csv:센터:사업자')를
--     서버가 채운다. 중복 판정 = (center_id, biz_no) 우선, 없으면 (center_id, name). 재업로드 시 갱신.
--   · 학생: (center_id, student_no) 우선, 없으면 (center_id, name, phone). 이미 있으면 건너뜀(편집 보호).
-- =====================================================================

create or replace function public.bulk_upsert_companies(p_rows jsonb, p_center_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_center uuid; r jsonb; v_name text; v_biz text; v_row jsonb; cols text; n int := 0;
begin
  if not (is_super_admin() or current_admin_center() is not null) then raise exception 'not_admin'; end if;
  v_center := case when is_super_admin() then coalesce(p_center_id, current_admin_center())
                   else current_admin_center() end;
  if v_center is null then raise exception 'no_center'; end if;

  for r in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_name := nullif(btrim(coalesce(r->>'name', '')), '');
    v_biz  := nullif(regexp_replace(coalesce(r->>'biz_no', ''), '[^0-9]', '', 'g'), '');
    if v_name is null then continue; end if;

    -- 기존 행 갱신: biz_no 우선, 없으면 name (센터 스코프)
    if v_biz is not null then
      update public.companies set name = v_name, active = true, updated_at = now()
        where center_id = v_center and biz_no = v_biz;
    else
      update public.companies set active = true, updated_at = now()
        where center_id = v_center and name = v_name;
    end if;
    if found then n := n + 1; continue; end if;

    -- 신규: 서버가 center_id·active·notion_id(합성, NOT NULL 충족) 주입. CSV 키 중 실제 컬럼만.
    v_row := coalesce(r, '{}'::jsonb) - 'center_id'
             || jsonb_build_object('name', v_name, 'center_id', v_center, 'active', true);
    if v_biz is not null then v_row := v_row || jsonb_build_object('biz_no', v_biz); end if;
    if nullif(v_row->>'notion_id', '') is null then
      -- 합성 키: 사업자번호 우선, 없으면 정규화된 이름(md5 제거 → 서로 다른 이름끼리의 키 충돌 0). 동명 구분은 사업자번호로.
      v_row := v_row || jsonb_build_object('notion_id', 'csv:' || v_center::text || ':' || coalesce(v_biz, 'name:' || lower(btrim(v_name))));
    end if;

    select string_agg(quote_ident(k), ',') into cols
      from jsonb_object_keys(v_row) k
      where exists (select 1 from information_schema.columns c
                    where c.table_schema='public' and c.table_name='companies' and c.column_name = k);
    execute format('insert into public.companies (%s) select %s from jsonb_populate_record(null::public.companies, $1)', cols, cols) using v_row;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n);
end $$;
grant execute on function public.bulk_upsert_companies(jsonb, uuid) to authenticated;


create or replace function public.bulk_upsert_student_roster(p_rows jsonb, p_center_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_center uuid; r jsonb; v_name text; v_no text; v_phone text; v_row jsonb; cols text; n int := 0; v_exists boolean;
begin
  if not (is_super_admin() or current_admin_center() is not null) then raise exception 'not_admin'; end if;
  v_center := case when is_super_admin() then coalesce(p_center_id, current_admin_center())
                   else current_admin_center() end;
  if v_center is null then raise exception 'no_center'; end if;

  for r in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_name  := nullif(btrim(coalesce(r->>'name', '')), '');
    if v_name is null then continue; end if;
    v_no    := nullif(btrim(coalesce(r->>'student_no', '')), '');
    v_phone := nullif(regexp_replace(coalesce(r->>'phone', ''), '[^0-9]', '', 'g'), '');

    -- 이미 있으면 건너뜀(센터 스코프, 관리자 편집 보호): 학번 우선 → 이름+전화 → 이름
    if v_no is not null then
      select exists(select 1 from public.students where center_id = v_center and student_no = v_no) into v_exists;
    elsif v_phone is not null then
      select exists(select 1 from public.students where center_id = v_center and name = v_name and phone = v_phone) into v_exists;
    else
      select exists(select 1 from public.students where center_id = v_center and name = v_name) into v_exists;
    end if;
    if v_exists then continue; end if;

    -- 신규: center_id 서버 주입 + name_norm 채움. CSV 키 중 실제 컬럼만(job_keys 는 JSON 배열로 전달돼야 함).
    v_row := coalesce(r, '{}'::jsonb) - 'id' - 'center_id'
             || jsonb_build_object('name', v_name, 'center_id', v_center,
                  'name_norm', replace(lower(v_name), ' ', ''));
    if v_phone is not null then v_row := v_row || jsonb_build_object('phone', v_phone); end if;

    select string_agg(quote_ident(k), ',') into cols
      from jsonb_object_keys(v_row) k
      where exists (select 1 from information_schema.columns c
                    where c.table_schema='public' and c.table_name='students' and c.column_name = k);
    execute format('insert into public.students (%s) select %s from jsonb_populate_record(null::public.students, $1)', cols, cols) using v_row;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n);
end $$;
grant execute on function public.bulk_upsert_student_roster(jsonb, uuid) to authenticated;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/29_center_vocab.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/30_company_contacts_in_app.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- =====================================================================
-- 30_company_contacts_in_app.sql  —  [③ 노션 졸업] 기업 CSV 로 담당자(company_contacts)까지 인앱 입력
-- 멱등(create or replace). 적용 순서: 27·28 이후(companies.biz_no, bulk RPC 존재 가정).
--
-- 배경: company_contacts(HRD 담당자)는 지금까지 노션 sync(Apps Script) 전용이라 인앱 입력 경로가 없었다
--   (admin.html 은 읽기만). → 명지대가 노션을 완전히 떼려면 담당자 입력 경로가 필요.
-- 이 마이그레이션: bulk_upsert_companies 가 같은 CSV 행의 담당자명·연락처·이메일로 company_contacts 도
--   함께 upsert 하도록 확장. verify_company_code_solo 가 이 담당자 정보를 기업 가입 자동채움에 사용하므로,
--   CSV 로 담당자를 채우면 노션 없이도 기업 가입 흐름이 그대로 동작한다.
-- ⚠️ company_contacts.notion_id 도 NOT NULL → 회사와 '같은' notion_id(기존 또는 합성 csv:센터:사업자)로 연결.
-- center_id 는 항상 서버가 주입(클라 미신뢰). company_contacts 는 rls-check MUST_BE_BLOCKED 유지(anon 차단).
-- =====================================================================

create or replace function public.bulk_upsert_companies(p_rows jsonb, p_center_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_center uuid; r jsonb;
  v_name text; v_biz text; v_status text; v_nid text;
  v_cname text; v_cphone text; v_cemail text;
  n int := 0; nc int := 0;
begin
  if not (is_super_admin() or current_admin_center() is not null) then raise exception 'not_admin'; end if;
  v_center := case when is_super_admin() then coalesce(p_center_id, current_admin_center())
                   else current_admin_center() end;
  if v_center is null then raise exception 'no_center'; end if;

  for r in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_name   := nullif(btrim(coalesce(r->>'name', '')), '');
    v_biz    := nullif(regexp_replace(coalesce(r->>'biz_no', ''), '[^0-9]', '', 'g'), '');
    v_status := nullif(btrim(coalesce(r->>'status', '')), '');
    v_cname  := nullif(btrim(coalesce(r->>'contact_name', '')), '');
    v_cphone := nullif(regexp_replace(coalesce(r->>'contact_phone', ''), '[^0-9]', '', 'g'), '');
    v_cemail := nullif(btrim(coalesce(r->>'contact_email', '')), '');
    if v_name is null then continue; end if;

    -- 회사 notion_id 도출: 기존 행 우선(센터 스코프, biz_no→name), 없으면 합성(회사·담당자 공유 키)
    v_nid := null;
    if v_biz is not null then
      select notion_id into v_nid from public.companies where center_id = v_center and biz_no = v_biz limit 1;
    end if;
    if v_nid is null then
      select notion_id into v_nid from public.companies where center_id = v_center and name = v_name limit 1;
    end if;
    if v_nid is null then
      -- 합성 키: 사업자번호 우선, 없으면 정규화된 이름(md5 제거 → 서로 다른 이름끼리의 키 충돌 0·사람이 읽을 수 있음).
      -- ⚠️ 사업자번호 없는 '서로 다른' 동명 회사는 같은 키로 묶인다(이름만으론 구분 불가). 구분하려면 CSV 에 사업자번호 기입.
      v_nid := 'csv:' || v_center::text || ':' || coalesce(v_biz, 'name:' || lower(btrim(v_name)));
    end if;

    -- 회사 upsert (notion_id 기준). status/biz_no 는 sql/27 추가분이라 부분 마이그레이션 DB 엔 없을 수 있다 →
    -- undefined_column 이면 핵심 컬럼만으로 강등 upsert(전체 RPC 가 'column does not exist' 로 500 나는 것 방지).
    begin
      update public.companies
         set name = v_name, active = true, updated_at = now(),
             biz_no = coalesce(v_biz, biz_no),
             status = coalesce(v_status, status)
       where center_id = v_center and notion_id = v_nid;
      if not found then
        insert into public.companies (notion_id, name, biz_no, status, center_id, active)
        values (v_nid, v_name, v_biz, v_status, v_center, true);
      end if;
    exception when undefined_column then
      update public.companies set name = v_name, active = true, updated_at = now()
       where center_id = v_center and notion_id = v_nid;
      if not found then
        insert into public.companies (notion_id, name, center_id, active)
        values (v_nid, v_name, v_center, true);
      end if;
    end;
    n := n + 1;

    -- 담당자(HRD) upsert — 회사와 같은 notion_id, role='hrd' (담당자 정보가 있을 때만). email/status 도 동일 강등.
    if v_cname is not null or v_cphone is not null or v_cemail is not null then
      begin
        update public.company_contacts
           set name = coalesce(v_cname, name), phone = coalesce(v_cphone, phone),
               email = coalesce(v_cemail, email), company = v_name,
               status = coalesce(v_status, status), updated_at = now()
         where center_id = v_center and notion_id = v_nid and role = 'hrd';
        if not found then
          insert into public.company_contacts (notion_id, role, company, name, phone, email, status, center_id)
          values (v_nid, 'hrd', v_name, v_cname, v_cphone, v_cemail, v_status, v_center);
        end if;
      exception when undefined_column then
        update public.company_contacts
           set name = coalesce(v_cname, name), phone = coalesce(v_cphone, phone),
               company = v_name, updated_at = now()
         where center_id = v_center and notion_id = v_nid and role = 'hrd';
        if not found then
          insert into public.company_contacts (notion_id, role, company, name, phone, center_id)
          values (v_nid, 'hrd', v_name, v_cname, v_cphone, v_center);
        end if;
      end;
      nc := nc + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'count', n, 'contacts', nc);
end $$;
grant execute on function public.bulk_upsert_companies(jsonb, uuid) to authenticated;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/31_cohort.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ▼▼▼ sql/32_master_center_scope.sql ▼▼▼
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- =====================================================================
-- 32_master_center_scope.sql  —  [리뷰 보강] companies/students 마스터 센터 스코프 RLS
-- 멱등. 적용 순서: 27(companies/students 에 center_id 추가) 이후. 라이브 적용 + rls-check 통과 확인.
--
-- 배경: companies/students 마스터는 sql/27 에서 center_id 를 받았지만, sql/21(센터 스코프 RLS)·
--   sql/25(center_id 주입 트리거) 의 테이블 배열에서 누락돼 '센터 스코프 정책이 없는' 상태였다.
--   → 두 번째 센터가 생기면 관리자가 타 센터의 회사·학생을 볼 수 있다(students 는 이름·전화=PII).
--
-- 이 파일이 하는 일(추가만):
--   · students : RLS 활성 + 센터 스코프 관리자 정책(super=전체 / center_admin=자기 센터). anon 차단 유지
--     (rls-check MUST_BE_BLOCKED). students 는 프론트가 직접 읽지 않으므로 anon 정책 불필요.
--   · companies: RLS 활성 + 센터 스코프 관리자 정책 + anon '활성 회사 읽기'(가입폼 드롭다운 보존).
--     companies 의 anon 읽기는 untrusted anon 특성상 센터로 못 좁힌다 → 회사'명'은 교차센터 노출(저민감).
--     화면 표시는 클라이언트가 center 로 필터(index.html/admin.html 드롭다운에 .eq('center_id') 추가).
--   · sql/21 과 동일한 갓모드 제거(qual='true' / 'auth.uid() IS NOT NULL') 도 두 테이블에 적용.
--
-- ⚠️⚠️ 남은 필수 작업(대시보드 전용 객체 — 레포 밖):
--   `admin_students()` 는 SECURITY DEFINER RPC(R15)라 RLS 를 '우회'한다(admin.html:1232 이 호출).
--   즉 이 파일의 students RLS 만으로는 그 RPC 경로가 안 좁혀진다. 대시보드에서 정의를 다음처럼 센터 스코프화할 것:
--     ... where is_super_admin() or center_id = current_admin_center()
--   (RPC 정의가 운영 대시보드에만 있어 레포에서 고칠 수 없음 — sql/22 의 dashboard-only 전례와 동일.)
-- =====================================================================

do $master$
declare
  t   text;
  pol record;
  tbls text[] := array['students', 'companies'];
begin
  foreach t in array tbls loop
    if to_regclass('public.' || t) is null then continue; end if;
    -- center_id 컬럼이 아직 없으면(=27 미적용) 스킵 = 회귀 0.
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = t and column_name = 'center_id') then
      continue;
    end if;

    execute format('alter table public.%I enable row level security', t);

    -- (a) 센터 무스코프 갓모드 정책 제거(sql/21 과 동일 기준). anon/공개읽기·본인행 정책은 qual 형태가 달라 보존.
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

    -- (b) 센터 스코프 관리자 정책(멱등).
    execute format('drop policy if exists %I on public.%I', t || '_admin_center', t);
    execute format($f$
      create policy %I on public.%I
        for all to public
        using ( public.is_super_admin() or center_id = public.current_admin_center() )
        with check ( public.is_super_admin() or center_id = public.current_admin_center() )
    $f$, t || '_admin_center', t);
  end loop;

  -- (c) companies 만: anon '활성 회사 읽기'(가입폼 드롭다운 보존). 멱등.
  if to_regclass('public.companies') is not null then
    drop policy if exists "companies anon read active" on public.companies;
    create policy "companies anon read active" on public.companies
      for select to public using ( active );
  end if;
end
$master$;
