-- 12_company_contacts.sql — 노션 기업 DB의 담당자(우선 HRD담당자) 미러
-- 가입자 탭 '기업담당자' 세그먼트가 이 명단 기준으로 가입/미가입을 표시합니다.
-- 데이터는 notion-sync(Apps Script, service_role)가 채우고, 앱에서는 로그인한 관리자만 읽습니다.
-- 익명(anon) 접근은 전면 차단 — rls-check.html MUST_BE_BLOCKED에 포함.

create table if not exists public.company_contacts (
  id bigint generated always as identity primary key,
  notion_id text not null,            -- 노션 기업 페이지 id
  role text not null default 'hrd',   -- 'hrd' (추후 기업현장교사 확장 대비)
  company text not null,              -- 기업명 (노션 title)
  name text,
  phone text,
  email text,
  status text,                        -- 기업 상태(진행/발굴/종료)
  manager text,                       -- 담당직원(노션 기업 DB '담당자' select)
  updated_at timestamptz default now(),
  unique (notion_id, role)
);

alter table public.company_contacts enable row level security;

-- 이 프로젝트는 to authenticated 정책이 publishable 키에서 안 먹는 전례가 있어
-- to public + auth.uid() 조건 패턴을 사용 (anon은 auth.uid()가 null이라 차단됨)
drop policy if exists "logged in read contacts" on public.company_contacts;
create policy "logged in read contacts" on public.company_contacts
  for select to public using (auth.uid() is not null);
