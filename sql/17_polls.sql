-- 17. 사안별 투표 — 대상 타게팅(공지와 동일 custom JSON), 기기당 1표, 결과는 집계만 노출
create table if not exists public.polls (
  id             uuid primary key default gen_random_uuid(),
  question       text not null,
  description    text,
  options        jsonb not null,               -- ["보기1","보기2",...] (보기 인덱스=응답값, 발행 후 순서 변경 금지)
  target_scope   text not null default 'all',  -- 'all' | 'custom'
  target_value   text,
  multi          boolean not null default false,
  results_public boolean not null default false,
  open           boolean not null default true,
  close_at       timestamptz,
  created_at     timestamptz not null default now()
);
alter table public.polls enable row level security;
drop policy if exists "anyone read polls" on public.polls;
create policy "anyone read polls" on public.polls for select to public using (true);  -- PII 없음, 마감 후 결과 열람용
drop policy if exists "admin write polls" on public.polls;
create policy "admin write polls" on public.polls
  for all to public using (auth.uid() is not null) with check (auth.uid() is not null);

create table if not exists public.poll_votes (
  id         uuid primary key default gen_random_uuid(),
  poll_id    uuid not null references public.polls(id) on delete cascade,
  choices    jsonb not null,   -- ["0"] 또는 ["0","2"] (보기 인덱스 문자열 — 설문 패턴과 동일)
  device_id  text,
  created_at timestamptz not null default now(),
  unique (poll_id, device_id)
);
alter table public.poll_votes enable row level security;
-- 서버측 투표 게이트: 열려 있고 마감 전인 투표에만 insert 허용 (클라이언트 토글만으로는 불충분)
drop policy if exists "anyone vote open polls" on public.poll_votes;
create policy "anyone vote open polls" on public.poll_votes for insert to public
  with check (exists (select 1 from public.polls p
    where p.id = poll_id and p.open and (p.close_at is null or now() < p.close_at)));
drop policy if exists "admin read votes" on public.poll_votes;
create policy "admin read votes" on public.poll_votes for select to public using (auth.uid() is not null);
drop policy if exists "admin delete votes" on public.poll_votes;
create policy "admin delete votes" on public.poll_votes for delete to public using (auth.uid() is not null);

-- 결과는 집계값만 — results_public이거나 관리자면 보기별 counts, 아니면 total만
create or replace function public.poll_results(p_poll uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pl record; cnts jsonb; tot bigint;
begin
  select * into pl from polls where id = p_poll;
  if not found then return null; end if;
  select count(*) into tot from poll_votes where poll_id = p_poll;
  if not pl.results_public and auth.uid() is null then
    return jsonb_build_object('total', tot, 'counts', null);
  end if;
  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into cnts from (
    select v.value as k, count(*) as n
    from poll_votes pv, jsonb_array_elements_text(pv.choices) v
    where pv.poll_id = p_poll group by v.value) s;
  return jsonb_build_object('total', tot, 'counts', cnts);
end $$;
grant execute on function public.poll_results(uuid) to anon, authenticated;
