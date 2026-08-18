-- =====================================================================
-- 42_attendance_monthly.sql — [학생 홈 '내 출석 진도' 카드]
-- 멱등(create or replace / if not exists). 적용 순서: 19·21 이후(centers·admin_users·헬퍼 필요).
--
--  · attendance_monthly = 학생별 월 예정/실적 시수(노션 「OJT 월별 — 학생」 미러, 관리자가 갱신).
--  · PII·개인 성적 취급: anon 정책 없음(직접 조회 전면 차단) → rls-check MUST_BE_BLOCKED 등록 필수.
--  · 학생 조회는 my_attendance(초대코드) SECURITY DEFINER 만 — 코드로 본인 확인, '자기 행만' 반환.
--  · 쓰기는 bulk_upsert_attendance(관리자 전용, center 서버 주입)만. 클라 center_id 미신뢰.
--  · 프론트 폴백: RPC/테이블 미적용이면 index.html 카드가 조용히 미표시(회귀 0).
-- =====================================================================

create table if not exists public.attendance_monthly (
  id            uuid primary key default gen_random_uuid(),
  center_id     uuid not null references public.centers(id),
  name          text not null,
  month         date not null,             -- 해당 월 1일
  planned_hours numeric,                   -- 예정 시수(훈련과정시간표)
  actual_hours  numeric,                   -- 실적 시수(비콘). null = 집계 전
  note          text,
  updated_at    timestamptz not null default now()
);

-- 센터 + 정규화 이름 + 월 유일 (동명이인은 파일럿 범위 밖 — 발생 시 학번 키 승격)
create unique index if not exists attendance_monthly_uniq
  on public.attendance_monthly (center_id, (replace(trim(name), ' ', '')), month);

alter table public.attendance_monthly enable row level security;

-- 관리자만 직접 접근(센터 스코프). to public + 헬퍼 패턴(publishable 키에서 to authenticated 미동작 전례).
drop policy if exists "attendance admin all" on public.attendance_monthly;
create policy "attendance admin all" on public.attendance_monthly
  for all to public
  using (is_super_admin() or center_id = current_admin_center())
  with check (is_super_admin() or center_id = current_admin_center());

revoke all on public.attendance_monthly from anon;
grant select, insert, update, delete on public.attendance_monthly to authenticated;

-- ── 학생 조회 RPC — 초대코드로 본인 확인 후 자기 행만 ──
create or replace function public.my_attendance(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare sc record; ip text; rows jsonb;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  begin
    perform check_verify_rate('attn:' || ip);
  exception when undefined_function then null;  -- rate limit 미적용 DB에서도 조회는 동작
  end;
  select * into sc from student_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')) and active;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'month', to_char(a.month, 'YYYY-MM'),
           'planned', a.planned_hours,
           'actual', a.actual_hours,
           'updated_at', a.updated_at) order by a.month), '[]'::jsonb)
    into rows
    from attendance_monthly a
   where a.center_id = sc.center_id
     and replace(trim(a.name), ' ', '') = replace(trim(sc.name), ' ', '');
  return jsonb_build_object('ok', true, 'rows', rows);
end $$;
grant execute on function public.my_attendance(text) to anon, authenticated;

-- ── 관리자 일괄 upsert RPC — rows: [{name, month:'YYYY-MM', planned, actual, note}] ──
create or replace function public.bulk_upsert_attendance(p_rows jsonb, p_center uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_center uuid; r jsonb; v_name text; v_month date; existing uuid; n_ins int := 0; n_upd int := 0; n_skip int := 0;
begin
  if not exists (select 1 from admin_users au where au.user_id = auth.uid()) then
    raise exception 'not_admin';
  end if;
  if is_super_admin() then v_center := coalesce(p_center, current_admin_center());
  else v_center := current_admin_center();  -- center_admin 은 클라값 무시(강제)
  end if;
  if v_center is null then raise exception 'no_center'; end if;

  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_name := trim(coalesce(r->>'name', ''));
    if v_name = '' or coalesce(r->>'month', '') !~ '^\d{4}-\d{2}$' then n_skip := n_skip + 1; continue; end if;
    v_month := to_date((r->>'month') || '-01', 'YYYY-MM-DD');
    select id into existing from attendance_monthly a
     where a.center_id = v_center and a.month = v_month
       and replace(trim(a.name), ' ', '') = replace(v_name, ' ', '');
    if found then
      update attendance_monthly
         set planned_hours = nullif(r->>'planned', '')::numeric,
             actual_hours  = nullif(r->>'actual', '')::numeric,
             note = r->>'note', updated_at = now()
       where id = existing;
      n_upd := n_upd + 1;
    else
      insert into attendance_monthly (center_id, name, month, planned_hours, actual_hours, note)
      values (v_center, v_name, v_month,
              nullif(r->>'planned', '')::numeric, nullif(r->>'actual', '')::numeric, r->>'note');
      n_ins := n_ins + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'inserted', n_ins, 'updated', n_upd, 'skipped', n_skip);
end $$;
grant execute on function public.bulk_upsert_attendance(jsonb, uuid) to authenticated;

-- 검증 쿼리 (적용 후):
--   set local role anon; select count(*) from attendance_monthly;      -- → permission denied 여야 정상
--   select my_attendance('실제코드');                                    -- → ok:true + 본인 rows
--   select my_attendance('WRONGCODE');                                  -- → ok:false
