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
