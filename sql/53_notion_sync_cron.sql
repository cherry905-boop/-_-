-- =====================================================================
-- 53_notion_sync_cron.sql — 노션 출석 동기화 자동화 (적용 완료: 2026-08-21)
--
-- 왜 만들었나
--   비콘 입실 알림은 평일 09:00 에 돌면서 attendance_monthly 의 시수를 푸시 본문에
--   그대로 박아 보낸다. 그런데 노션 동기화는 관리자가 아침에 손으로 버튼을 눌러야
--   돌았고(그날은 09:02), 알림이 동기화보다 2분 먼저 나가는 바람에 이틀 묵은 값이
--   발송됐다 — 실제 30시간인 학생에게 "24시간"이라고 나갔다.
--   → 동기화를 08:45 로 자동화해서 알림보다 항상 먼저 끝나게 한다.
--
-- 키를 사람이 만지지 않는 이유
--   cron 이 엣지 함수를 부르려면 인증이 필요한데, service_role 키를 cron.job.command
--   문자열에 박으면 DB 를 보는 누구에게나 노출된다. 그래서 전용 공유키를 Vault 안에서
--   무작위로 만들고, cron 은 그 값을 서브쿼리로 읽어 헤더로만 흘린다. 명령문에도,
--   채팅에도, 파일에도 키 값은 남지 않는다.
-- =====================================================================

-- 1) cron 전용 공유키를 Vault 에 생성(이미 있으면 유지)
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'cron_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'cron_key',
      'pg_cron -> edge function 호출용 공유키 (sql/53)'
    );
  end if;
end $$;

-- 2) 엣지 함수가 헤더로 받은 키를 대조하는 창구. service_role 만 호출 가능.
create or replace function public.verify_cron_key(p_key text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'vault'
as $$
  select coalesce(
    (select decrypted_secret from vault.decrypted_secrets where name = 'cron_key' limit 1) = nullif(p_key, ''),
    false);
$$;

revoke all on function public.verify_cron_key(text) from public, anon, authenticated;
grant execute on function public.verify_cron_key(text) to service_role;

-- 3) 출석 upsert 를 service_role 로도 호출 가능하게 (center 를 명시할 때만).
--    관리자 경로(admin_users 검사 → center 주입)의 판정 순서와 의미는 그대로 둔다.
create or replace function public.bulk_upsert_attendance(p_rows jsonb, p_center uuid default null::uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_center uuid; r jsonb; v_name text; v_month date; existing uuid; n_ins int := 0; n_upd int := 0; n_skip int := 0;
begin
  if auth.role() = 'service_role' then
    -- cron 경로: 어느 센터인지 스스로 알 수 없으므로 반드시 명시받는다.
    if p_center is null then raise exception 'center_required'; end if;
    v_center := p_center;
  else
    if not exists (select 1 from admin_users au where au.user_id = auth.uid()) then
      raise exception 'not_admin';
    end if;
    if is_super_admin() then v_center := coalesce(p_center, current_admin_center());
    else v_center := current_admin_center();
    end if;
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
end $function$;

-- 4) 평일 08:45 KST(= 23:45 UTC 전날, 일~목) 자동 동기화.
--    같은 날 09:00 beacon-in-daily 보다 15분 먼저 끝난다.
select cron.schedule(
  'notion-sync-daily',
  '45 23 * * 0-4',
  $job$
  select net.http_post(
    url := 'https://ggitgqijycvnhhraxzgn.supabase.co/functions/v1/sync-attendance',
    body := jsonb_build_object('slug','mju'),
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-cron-key', (select decrypted_secret from vault.decrypted_secrets where name='cron_key')),
    timeout_milliseconds := 60000);
  $job$
);

-- 확인용
-- select jobname, schedule, active from cron.job order by jobname;
-- select id, status_code, content from net._http_response order by id desc limit 3;
