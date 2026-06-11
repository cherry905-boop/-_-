-- ================================================================
-- ALL_IN_ONE — 01~05 마이그레이션 통합본 (한 번에 실행용)
-- Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 각 구문은 idempotent라 재실행해도 안전합니다.
-- ================================================================

-- ━━━━━━━━━━ 01_applicant.sql ━━━━━━━━━━
-- 01. 지원자(매칭 전 재학생) 가입 허용
-- registrations.target_type 에 'applicant' 추가 + 관심직무(다중)·학과 컬럼

alter table public.registrations add column if not exists interest_jobs text[];
alter table public.registrations add column if not exists dept text;
alter table public.push_tokens  add column if not exists interest_jobs text[];

-- target_type CHECK 제약이 있으면 applicant 포함해 재생성 (없었다면 새로 추가)
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.registrations'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%target_type%'
  loop
    execute format('alter table public.registrations drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.registrations
  add constraint registrations_target_type_check
  check (target_type in ('student', 'company', 'applicant'));

-- 푸시 토큰 메타 갱신 (지원자→학생 전환 등 재등록 시 23505로 insert가 막히므로
-- 토큰 보유 = 본인 인증으로 간주하고 메타만 갱신하는 RPC)
create or replace function public.refresh_push_token(
  p_token text, p_target_type text, p_job_key text, p_company text,
  p_type1 text, p_manager text, p_device_key text, p_interest_jobs text[]
) returns void
language plpgsql security definer set search_path = public as $$
begin
  update push_tokens
     set target_type = p_target_type, job_key = p_job_key, company = p_company,
         type1 = p_type1, manager = p_manager, device_key = p_device_key,
         interest_jobs = p_interest_jobs, updated_at = now()
   where token = p_token;
end $$;
grant execute on function public.refresh_push_token(text, text, text, text, text, text, text, text[]) to anon, authenticated;

-- ━━━━━━━━━━ 02_codes.sql ━━━━━━━━━━
-- 02. 초대코드 가입 — 학생(개인 코드)·기업담당자(기업 코드)
-- 명단 원본 테이블은 건드리지 않는다. 코드는 별도 테이블에 두고,
-- verify_by_code 가 내부에서 기존 verify_student(name, phone)를 호출해 명단 행을 바인딩한다.

-- ── 학생 개인 코드 (관리자가 가입자표에서 발급, 합격 통보에 동봉) ──
create table if not exists public.student_codes (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  phone      text not null,
  code       text not null unique,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.student_codes enable row level security;
drop policy if exists "admin all" on public.student_codes;
create policy "admin all" on public.student_codes
  for all to authenticated using (true) with check (true);
-- anon 정책 없음 = anon 접근 전면 차단 (조회는 verify_by_code 함수만)
-- 한 학생에게 활성 코드는 1개만 (중복 발급 방지)
create unique index if not exists student_codes_person_uniq
  on public.student_codes (name, phone) where active;

-- ── 기업 코드 (지정완료 메일에 동봉) ──
create table if not exists public.company_codes (
  company    text primary key,
  code       text not null unique,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.company_codes enable row level security;
drop policy if exists "admin all" on public.company_codes;
create policy "admin all" on public.company_codes
  for all to authenticated using (true) with check (true);

-- ── 검증 시도 기록 (열거 공격 방지용 rate limit) ──
create table if not exists public.verify_attempts (
  key        text not null,
  created_at timestamptz not null default now()
);
create index if not exists verify_attempts_idx on public.verify_attempts (key, created_at);
alter table public.verify_attempts enable row level security;
-- 정책 없음: security definer 함수만 기록

-- 읽기 혼동 문자(O/0/I/1/L) 제외 8자 코드
create or replace function public.gen_join_code() returns text
language sql volatile as $$
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', (floor(random()*31)+1)::int, 1), '')
  from generate_series(1, 8)
$$;

create or replace function public.check_verify_rate(p_key text) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from verify_attempts where created_at < now() - interval '1 hour';
  select count(*) into n from verify_attempts
   where key = p_key and created_at > now() - interval '10 minutes';
  if n >= 30 then
    raise exception 'too_many_attempts: 잠시 후 다시 시도해주세요';
  end if;
  insert into verify_attempts (key) values (p_key);
end $$;

-- ── 학생: 코드 + 이름 → 명단 바인딩 ──
create or replace function public.verify_by_code(p_code text, p_name text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  sc record;
  ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('code:' || ip);

  select * into sc from student_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
     and active;
  if not found then
    return jsonb_build_object('matched', false, 'reason', 'code');
  end if;
  if replace(trim(coalesce(p_name, '')), ' ', '') <> replace(trim(sc.name), ' ', '') then
    return jsonb_build_object('matched', false, 'reason', 'name');
  end if;
  -- 기존 명단 검증 RPC 재사용 (반환 타입이 json이면 ::jsonb 캐스팅이 그대로 동작)
  -- + 명단의 정규 휴대폰을 함께 반환 (클라이언트가 입력 오타 대신 명단 번호를 저장하도록)
  return (select verify_student(sc.name, sc.phone))::jsonb
         || jsonb_build_object('phone', sc.phone);
end $$;
grant execute on function public.verify_by_code(text, text) to anon, authenticated;

-- ── 기업담당자: 기업명 + 코드 ──
create or replace function public.verify_company_code(p_company text, p_code text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  ok boolean;
  ip text;
  norm_in text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('cocode:' || ip);

  norm_in := replace(replace(replace(replace(lower(coalesce(p_company, '')), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '');
  select true into ok from company_codes
   where replace(replace(replace(replace(lower(company), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '') = norm_in
     and code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
     and active;
  return coalesce(ok, false);
end $$;
grant execute on function public.verify_company_code(text, text) to anon, authenticated;

-- ━━━━━━━━━━ 03_recruit.sql ━━━━━━━━━━
-- 03. 모집 콘텐츠 — 채용공고 + 선배 사례 (공개 페이지용)

create table if not exists public.job_postings (
  id         uuid primary key default gen_random_uuid(),
  company    text not null,
  job_key    text,                          -- 직무명 (jobs 테이블 어휘와 동일)
  title      text not null,                 -- 예: 2026 하반기 SW개발 학습근로자 모집
  region     text,                          -- 예: 용인 / 화성
  intro      text,                          -- 기업·포지션 한 줄 소개
  perks      text,                          -- 근무조건·우대 (선택)
  deadline   date,                          -- 마감일 (null = 상시)
  published  boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.job_postings enable row level security;
drop policy if exists "anon read published" on public.job_postings;
create policy "anon read published" on public.job_postings
  for select to anon using (published = true);
drop policy if exists "admin all" on public.job_postings;
create policy "admin all" on public.job_postings
  for all to authenticated using (true) with check (true);

create table if not exists public.success_cases (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,                 -- 예: 반도체장비 기구설계로 입사까지
  job_key    text,
  company    text,                          -- 표기용 (익명 가능: "반도체 장비社")
  body       text not null,                 -- 후기 본문 (익명화된 원고)
  published  boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.success_cases enable row level security;
drop policy if exists "anon read published" on public.success_cases;
create policy "anon read published" on public.success_cases
  for select to anon using (published = true);
drop policy if exists "admin all" on public.success_cases;
create policy "admin all" on public.success_cases
  for all to authenticated using (true) with check (true);

-- ━━━━━━━━━━ 04_stages.sql ━━━━━━━━━━
-- 04. 학습기업 진행단계 트래커 (B)
-- 단계 어휘는 config.js COMPANY_STAGES 와 동일: apply / audit / designate / training / mou / recruit / matched / running

create table if not exists public.company_stages (
  company    text primary key,
  stage_key  text not null default 'apply',
  memo       text,                          -- 담당자에게 보이는 안내 (예: 이수증 회신 마감 6/20)
  updated_at timestamptz not null default now()
);
alter table public.company_stages enable row level security;
drop policy if exists "admin all" on public.company_stages;
create policy "admin all" on public.company_stages
  for all to authenticated using (true) with check (true);
-- anon 직접 조회 차단 — 본인 기업 조회는 아래 RPC만

create or replace function public.my_company_stage(p_company text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cs record;
  norm_in text;
begin
  norm_in := replace(replace(replace(replace(lower(coalesce(p_company, '')), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '');
  select * into cs from company_stages
   where replace(replace(replace(replace(lower(company), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '') = norm_in;
  if not found then return null; end if;
  return jsonb_build_object('company', cs.company, 'stage_key', cs.stage_key, 'memo', cs.memo, 'updated_at', cs.updated_at);
end $$;
grant execute on function public.my_company_stage(text) to anon, authenticated;

-- ━━━━━━━━━━ 05_qna.sql ━━━━━━━━━━
-- 05. QnA 사례 게시판 (C) — 상담에서 익명화해 큐레이션

create table if not exists public.qna_posts (
  id         uuid primary key default gen_random_uuid(),
  audience   text not null default 'all'    -- applicant / student / company / all
             check (audience in ('applicant', 'student', 'company', 'all')),
  category   text,                          -- 예: 지원·면접 / 가입·알림 / 서류·마감 / 수당 / 학사
  question   text not null,
  answer     text not null,
  source     text default 'manual',         -- consult / board / manual
  published  boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.qna_posts enable row level security;
drop policy if exists "anon read published" on public.qna_posts;
create policy "anon read published" on public.qna_posts
  for select to anon using (published = true);
drop policy if exists "admin all" on public.qna_posts;
create policy "admin all" on public.qna_posts
  for all to authenticated using (true) with check (true);
