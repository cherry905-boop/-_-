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
