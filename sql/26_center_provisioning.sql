-- =====================================================================
-- 26_center_provisioning.sql  —  [멀티테넌트 4단계(SQL): 센터 개설·관리자 발급]
-- 멱등. 적용 순서: 19·21·22·23·24·25 이후.
-- 운영모델 A: super_admin 만 센터 생성·관리자 발급(슈퍼관리자 화면). center_admin 은 불가.
-- (프론트 = admin.html role-aware refresh + sec-centers 탭은 별도 하위단계.)
-- =====================================================================

-- ── A. admin_users 쓰기 정책 — super_admin 만 ──
-- 기존엔 "admin reads own mapping"(본인 행 select)만 있었음(19). 쓰기는 super 한정으로 연다.
do $au$
begin
  if to_regclass('public.admin_users') is not null then
    drop policy if exists "super manages admin_users" on public.admin_users;
    create policy "super manages admin_users" on public.admin_users
      for all to public
      using ( is_super_admin() )
      with check ( is_super_admin() );
  end if;
end $au$;
-- ("admin reads own mapping"(본인행 select)은 유지 — 로그인 직후 자기 role 조회·게이팅용.)

-- ── B. seed_center — 신규 센터 표준 콘텐츠 시딩(센터 스코프 멱등). 현재는 빈 센터로 시작. ──
-- 운영모델 B: 콘텐츠는 center_admin 이 대시보드로 직접 채운다 → 신규 센터는 빈 상태.
-- 공통 템플릿(일반 일학습병행 안내 등)을 넣고 싶으면 '여기'에 (center_id,...) 스코프 dedup 으로 추가:
--   insert into qna_posts (center_id, audience, category, question, answer, source, published)
--   select p_center_id, ... where not exists
--     (select 1 from qna_posts where center_id = p_center_id and question = '...');
-- ⚠️ mju 고유 시드(06/08/11)는 절대 복사 금지(명지대 전용 연락처·기업명 포함) — 0단계 보정과 일치.
create or replace function public.seed_center(p_center_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_center_id is null then return; end if;
  -- (현재 표준 템플릿 없음 → no-op. 신규 센터는 빈 상태로 시작.)
  return;
end $$;

-- ── C. create_center — super_admin 만. centers insert(멱등) + seed_center ──
create or replace function public.create_center(
  p_slug text, p_name text, p_region text default null, p_app_title text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not is_super_admin() then raise exception 'not_super_admin'; end if;
  if p_slug is null or lower(p_slug) !~ '^[a-z0-9-]{1,40}$' then
    raise exception 'invalid_slug: 소문자·숫자·하이픈 1~40자';
  end if;
  insert into public.centers (slug, name, region, app_title)
    values (lower(p_slug), p_name, p_region, p_app_title)
    on conflict (slug) do nothing
    returning id into v_id;
  if v_id is null then
    select id into v_id from public.centers where slug = lower(p_slug);   -- 이미 있으면 기존 id
  end if;
  perform seed_center(v_id);
  return v_id;
end $$;
grant execute on function public.create_center(text, text, text, text) to authenticated;

-- ── D. grant_admin — super_admin 만. 이메일 → auth.users → admin_users 매핑 upsert ──
-- ※ 대상 이메일로 Supabase Auth 계정이 먼저 있어야 한다(이메일 초대 후 첫 로그인). 없으면 에러.
-- ※ auth.users 조회 위해 SECURITY DEFINER(소유자 권한). search_path 에 auth 포함.
create or replace function public.grant_admin(
  p_email text, p_center_slug text, p_role text default 'center_admin'
) returns void
language plpgsql security definer set search_path = public, auth as $$
declare v_uid uuid; v_center uuid;
begin
  if not is_super_admin() then raise exception 'not_super_admin'; end if;
  if p_role not in ('super_admin','center_admin') then raise exception 'invalid_role'; end if;

  select id into v_uid from auth.users where lower(email) = lower(p_email) limit 1;
  if v_uid is null then
    raise exception 'user_not_found: 먼저 해당 이메일로 Supabase Auth 계정(초대)을 만들어야 합니다';
  end if;
  select id into v_center from public.centers where slug = lower(p_center_slug);
  if v_center is null then raise exception 'center_not_found'; end if;

  insert into public.admin_users (user_id, center_id, role)
    values (v_uid, v_center, p_role)
    on conflict (user_id) do update set center_id = excluded.center_id, role = excluded.role;
end $$;
grant execute on function public.grant_admin(text, text, text) to authenticated;
