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
