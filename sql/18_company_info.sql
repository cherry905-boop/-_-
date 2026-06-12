-- 18. 기업별 학습 정보(운영팀 입력) + 본인 기업 조회 RPC
-- ⚠️ 원칙: 학생에게는 담당자 '이름·직책'만 노출 — 전화·이메일은 절대 반환 금지(사용자 확정 결정).
-- ⚠️ 출퇴근·비콘은 '안내 정보만' — 앱은 출결을 기록·자동화하지 않음(부정훈련 점검 원칙).

create table if not exists public.company_info (
  company    text primary key,
  beacon     text,   -- 비콘 시간표 안내
  commute    text,   -- 출퇴근 안내
  schedule   text,   -- 훈련시간표
  extra      text,   -- 기타 안내
  updated_at timestamptz not null default now()
);
alter table public.company_info enable row level security;
drop policy if exists "admin all company_info" on public.company_info;
create policy "admin all company_info" on public.company_info
  for all to public using (auth.uid() is not null) with check (auth.uid() is not null);
-- anon 직접 조회 차단 — 본인 기업 조회는 아래 RPC만 (my_company_stage 전례, sql/04)

create or replace function public.my_company_info(p_company text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare norm_in text; ci record;
begin
  norm_in := replace(replace(replace(replace(lower(coalesce(p_company, '')), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '');
  if norm_in = '' then return null; end if;
  select * into ci from company_info
   where replace(replace(replace(replace(lower(company), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '') = norm_in
   limit 1;
  return jsonb_build_object(
    'company', coalesce(ci.company, p_company),
    'info', case when ci.company is null then null else
      jsonb_build_object('beacon', ci.beacon, 'commute', ci.commute, 'schedule', ci.schedule, 'extra', ci.extra, 'updated_at', ci.updated_at) end,
    'contacts', coalesce((
      select jsonb_agg(jsonb_build_object('role', cc.role, 'name', cc.name) order by cc.role)
      from company_contacts cc
      where coalesce(cc.status, '') <> '종료' and cc.name is not null and cc.name <> ''
        and replace(replace(replace(replace(lower(cc.company), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '') = norm_in
    ), '[]'::jsonb));
end $$;
grant execute on function public.my_company_info(text) to anon, authenticated;
