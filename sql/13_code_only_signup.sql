-- 13_code_only_signup.sql — 초대코드 전용 가입 (참여학생·기업담당자 이름/휴대폰 입력 제거)
-- 학생은 verify_code_solo(09)가 이미 코드→명단정보를 반환하므로 변경 없음.
-- 기업은 코드→기업명만 반환하던 verify_company_code_solo를 확장:
--   company_contacts(12)에서 그 기업의 HRD담당자 이름·연락처를 함께 반환해
--   가입 시 이름·휴대폰을 자동으로 채운다 (가입자 탭 명단 매칭과도 일치).
-- 같은 시그니처의 create or replace — 오버로드가 생기지 않아 PGRST203 안전.

create or replace function public.verify_company_code_solo(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c record;
  h record;
  ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('cocode:' || ip);

  select * into c from company_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
     and active;
  if not found then
    return jsonb_build_object('ok', false);
  end if;

  -- 노션 동기화 HRD담당자 (없거나 12 미적용이어도 ok/company는 그대로 동작)
  -- 주의: 예외 시 h가 미할당 레코드라 h.name 접근이 에러 — 예외 분기에서 바로 반환해야 함
  begin
    select name, phone into h from company_contacts
     where role = 'hrd' and company = c.company and coalesce(status, '') <> '종료'
     order by updated_at desc limit 1;
  exception when undefined_table then
    return jsonb_build_object('ok', true, 'company', c.company,
                              'hrd_name', null, 'hrd_phone', null);
  end;

  return jsonb_build_object('ok', true, 'company', c.company,
                            'hrd_name', h.name, 'hrd_phone', h.phone);
end $$;
grant execute on function public.verify_company_code_solo(text) to anon, authenticated;
