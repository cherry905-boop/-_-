-- 16. 행사별 설문 — 관리자가 문항을 직접 만들고(questions jsonb), 응답은 익명(기기당 1회)
-- 문항 스키마는 config.js COMPANY_SURVEYS와 동일: [{key,type:'single'|'multi',label,options[],score[],etc}]
-- 발행 후 문항 수정은 UI에서 금지(보기 순서=응답 인덱스 드리프트 방지).

create table if not exists public.surveys (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  description  text,
  target_scope text not null default 'all',   -- 'all' | 'custom' (buildPicker serial JSON)
  target_value text,
  questions    jsonb not null,
  open         boolean not null default true,
  created_at   timestamptz not null default now()
);
alter table public.surveys enable row level security;
drop policy if exists "anyone read open surveys" on public.surveys;
create policy "anyone read open surveys" on public.surveys
  for select to public using (open = true or auth.uid() is not null);
drop policy if exists "admin write surveys" on public.surveys;
create policy "admin write surveys" on public.surveys
  for all to public using (auth.uid() is not null) with check (auth.uid() is not null);

create table if not exists public.survey_answers (
  id         uuid primary key default gen_random_uuid(),
  survey_id  uuid not null references public.surveys(id) on delete cascade,
  answers    jsonb not null,
  comment    text,
  job_key    text,            -- 프로필에서 복사(직무별 집계용)
  device_id  text,
  created_at timestamptz not null default now(),
  constraint esurvey_answers_shape check (jsonb_typeof(answers) = 'object' and pg_column_size(answers) < 20000)
);
create unique index if not exists esurvey_one_vote on public.survey_answers (survey_id, device_id);
alter table public.survey_answers enable row level security;
drop policy if exists "anyone submit esurvey" on public.survey_answers;
create policy "anyone submit esurvey" on public.survey_answers for insert to public with check (true);
drop policy if exists "admin read esurvey" on public.survey_answers;
create policy "admin read esurvey" on public.survey_answers for select to public using (auth.uid() is not null);
drop policy if exists "admin delete esurvey" on public.survey_answers;
create policy "admin delete esurvey" on public.survey_answers for delete to public using (auth.uid() is not null);
