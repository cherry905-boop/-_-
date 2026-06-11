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
