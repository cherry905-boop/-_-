-- =====================================================================
-- 24_signup_issue_rpc.sql  —  [멀티테넌트 2단계: 가입·발급 RPC (center_id 서버 도출)]
-- 멱등(create or replace). 적용 순서: 19·21·22·23 이후.
--
-- 핵심: '가입'과 '코드 발급'을 SECURITY DEFINER RPC 로 옮기고, center_id 를 '항상 서버가' 도출한다.
--   · 학생/기업 가입 = 초대코드 → student_codes/company_codes 에서 center_id 도출(클라 center_id 미신뢰).
--   · 지원자 가입 = 슬러그를 center_id_for_slug 로 서버가 해석(클라 uuid 미신뢰).
--   · 코드 발급 = current_admin_center()(super 면 인자 허용)로 center_id 주입.
--
-- registrations 스키마는 운영 대시보드 관리(컬럼이 R01/R15 등으로 가변) → register_* 는 'p_row 의 키 중
--   실제 registrations 컬럼인 것만' 동적 insert 한다(없는 컬럼은 건너뛰고, id/created_at 등 기본값 보존).
--
-- 폴백: 프론트가 RPC 호출 전환 전(또는 RPC 미적용)에는 기존 직접 insert 경로가 그대로 동작(파일럿 동일).
-- =====================================================================

-- ── A. verify_* 에 center_id/center_slug 추가 (동일 시그니처 create or replace, PGRST203 안전) ──

-- A-1. 학생 코드+이름 (sql/02)
create or replace function public.verify_by_code(p_code text, p_name text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare sc record; ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('code:' || ip);
  select * into sc from student_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')) and active;
  if not found then
    return jsonb_build_object('matched', false, 'reason', 'code');
  end if;
  if replace(trim(coalesce(p_name, '')), ' ', '') <> replace(trim(sc.name), ' ', '') then
    return jsonb_build_object('matched', false, 'reason', 'name');
  end if;
  return (select verify_student(sc.name, sc.phone))::jsonb
         || jsonb_build_object('phone', sc.phone,
              'center_id', sc.center_id,
              'center_slug', (select slug from centers where id = sc.center_id));
end $$;
grant execute on function public.verify_by_code(text, text) to anon, authenticated;

-- A-2. 학생 코드 단독 (sql/09)
create or replace function public.verify_code_solo(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare sc record; ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('code:' || ip);
  select * into sc from student_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')) and active;
  if not found then
    return jsonb_build_object('matched', false, 'reason', 'code');
  end if;
  return (select verify_student(sc.name, sc.phone))::jsonb
         || jsonb_build_object('name', sc.name, 'phone', sc.phone,
              'center_id', sc.center_id,
              'center_slug', (select slug from centers where id = sc.center_id));
end $$;
grant execute on function public.verify_code_solo(text) to anon, authenticated;

-- A-3. 기업 코드 단독 (sql/13 의 HRD 자동채움 보존 + center 보강 + HRD 조회 센터 스코프)
create or replace function public.verify_company_code_solo(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c record; h record; ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('cocode:' || ip);
  select * into c from company_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')) and active;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  -- 노션 동기화 HRD담당자(없거나 12 미적용이어도 ok/company/center는 동작). center 스코프로 동명기업 혼선 차단.
  begin
    select name, phone into h from company_contacts
     where role = 'hrd' and company = c.company and coalesce(status, '') <> '종료'
       and center_id = c.center_id
     order by updated_at desc limit 1;
  -- undefined_table(테이블 없음)뿐 아니라 undefined_column(부분 마이그레이션: status/center_id 등 컬럼 부재)도
  -- 'HRD 자동채움 없음'으로 우아하게 강등한다. 안 그러면 기업 코드 검증 RPC 전체가 500 → 기업 가입 차단.
  exception when undefined_table or undefined_column then
    return jsonb_build_object('ok', true, 'company', c.company, 'hrd_name', null, 'hrd_phone', null,
              'center_id', c.center_id, 'center_slug', (select slug from centers where id = c.center_id));
  end;
  return jsonb_build_object('ok', true, 'company', c.company, 'hrd_name', h.name, 'hrd_phone', h.phone,
            'center_id', c.center_id, 'center_slug', (select slug from centers where id = c.center_id));
end $$;
grant execute on function public.verify_company_code_solo(text) to anon, authenticated;

-- ── B. 가입 RPC — center_id 를 서버가 도출해 주입 ──

-- 내부 도우미: registrations 컬럼과 교집합인 키만 동적 insert (없는 컬럼·기본값 보존)
create or replace function public._insert_registration(p_row jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare cols text;
begin
  select string_agg(quote_ident(k), ',') into cols
    from jsonb_object_keys(p_row) k
    where exists (select 1 from information_schema.columns c
                  where c.table_schema='public' and c.table_name='registrations' and c.column_name = k);
  if cols is null then raise exception 'no_columns'; end if;
  execute format(
    'insert into public.registrations (%s) select %s from jsonb_populate_record(null::public.registrations, $1)',
    cols, cols
  ) using p_row;
end $$;

-- B-1. 학생/기업: 초대코드 → center_id 서버 도출 후 가입
create or replace function public.register_with_code(p_code text, p_row jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_code text; v_center uuid; v_name text; v_phone text; v_row jsonb; ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('reg:' || ip);
  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));

  -- 학생 코드 우선 → center·명단(이름·전화), 없으면 기업 코드 → center
  select center_id, name, phone into v_center, v_name, v_phone
    from student_codes where code = v_code and active;
  if v_center is null then
    select center_id into v_center from company_codes where code = v_code and active;
  end if;
  if v_center is null then
    return jsonb_build_object('ok', false, 'reason', 'code');
  end if;

  -- center_id 는 서버가 강제(클라 값 무시). 학생이면 명단의 이름·전화를 권위값으로 덮어씀.
  v_row := coalesce(p_row, '{}'::jsonb) - 'center_id' || jsonb_build_object('center_id', v_center);
  if v_name is not null then
    v_row := v_row || jsonb_build_object('name', v_name, 'phone', v_phone);
  end if;

  perform _insert_registration(v_row);
  return jsonb_build_object('ok', true, 'center_id', v_center,
            'center_slug', (select slug from centers where id = v_center));
end $$;
grant execute on function public.register_with_code(text, jsonb) to anon, authenticated;

-- B-2. 지원자(코드 없음): 슬러그를 서버가 해석해 center_id 도출
create or replace function public.register_applicant(p_slug text, p_row jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_center uuid; v_row jsonb; ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('regapp:' || ip);

  -- 슬러그는 약한 힌트지만 center_id 는 서버가 해석(클라가 보낸 uuid 미신뢰). centers 미적용/오타면 NULL=폴백.
  v_center := center_id_for_slug(coalesce(nullif(p_slug, ''), 'mju'));
  v_row := coalesce(p_row, '{}'::jsonb) - 'center_id' || jsonb_build_object('target_type', 'applicant');
  if v_center is not null then
    v_row := v_row || jsonb_build_object('center_id', v_center);
  end if;

  perform _insert_registration(v_row);
  return jsonb_build_object('ok', true, 'center_id', v_center);
end $$;
grant execute on function public.register_applicant(text, jsonb) to anon, authenticated;

-- ── C. 코드 발급 RPC — center_id = current_admin_center() (super 면 인자 허용) ──

create or replace function public.issue_student_code(p_name text, p_phone text, p_center_id uuid default null)
returns text
language plpgsql security definer set search_path = public as $$
declare v_center uuid; v_code text;
begin
  if not (is_super_admin() or current_admin_center() is not null) then
    raise exception 'not_admin';
  end if;
  -- center_admin 은 자기 센터 강제(클라 인자 무시). super 만 p_center_id 허용.
  v_center := case when is_super_admin() then coalesce(p_center_id, current_admin_center())
                   else current_admin_center() end;
  if v_center is null then raise exception 'no_center'; end if;

  -- 같은 센터 동일인의 활성 코드가 있으면 재사용(센터 스코프 person-uniq, sql/23)
  select code into v_code from student_codes
   where center_id = v_center and name = p_name and phone = p_phone and active limit 1;
  if v_code is not null then return v_code; end if;

  v_code := gen_join_code();
  insert into student_codes (name, phone, code, center_id) values (p_name, p_phone, v_code, v_center);
  return v_code;
end $$;
grant execute on function public.issue_student_code(text, text, uuid) to authenticated;

create or replace function public.issue_company_code(p_company text, p_center_id uuid default null)
returns text
language plpgsql security definer set search_path = public as $$
declare v_center uuid; v_code text;
begin
  if not (is_super_admin() or current_admin_center() is not null) then
    raise exception 'not_admin';
  end if;
  v_center := case when is_super_admin() then coalesce(p_center_id, current_admin_center())
                   else current_admin_center() end;
  if v_center is null then raise exception 'no_center'; end if;

  -- ⚠️ company_codes 는 아직 `company text PK`(전역 unique, 센터 스코프 키는 5단계 사업자번호 전환).
  --    재사용은 '내 센터' 행으로 한정한다(이전엔 company 만으로 매칭·update → 타 센터의 동명기업 코드 행을
  --    내 센터로 가로채는 교차센터 손상이 있었다).
  select code into v_code from company_codes where company = p_company and center_id = v_center limit 1;
  if v_code is not null then
    update company_codes set active = true where company = p_company and center_id = v_center;
    return v_code;
  end if;

  -- 동명 회사가 '다른' 센터에 이미 있으면(전역 PK 충돌) 가로채지 말고 명시적으로 실패한다.
  -- (사업자번호 자연키 전환(5단계, sql/27) 전까지의 안전장치. 그 후엔 (center_id, biz_no) 로 충돌 없이 공존.)
  if exists (select 1 from company_codes where company = p_company and center_id is distinct from v_center) then
    raise exception 'company_name_taken_other_center';
  end if;

  v_code := gen_join_code();
  insert into company_codes (company, code, center_id) values (p_company, v_code, v_center);
  return v_code;
end $$;
grant execute on function public.issue_company_code(text, uuid) to authenticated;
