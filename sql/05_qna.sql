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
