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
