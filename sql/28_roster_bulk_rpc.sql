-- =====================================================================
-- 28_roster_bulk_rpc.sql  —  [멀티테넌트 5단계(RPC): 명단 일괄등록]
-- 멱등(create or replace). 적용 순서: 27 이후(companies/students 의 center_id·biz_no 존재 가정).
-- ※ 롤번호: 5단계 스키마=27, RPC=28. 이후 6=sql/20(스토리지), 7=29(NOT NULL), 8=30(config).
--
-- center_admin/super 가 CSV·엑셀 명단을 일괄 적재. center_id 는 '항상 서버가' 주입(클라 미신뢰).
--   · super 는 p_center_id 명시 허용, center_admin 은 자기 센터 강제.
--   · p_rows 는 jsonb 배열(각 원소=한 행). 실제 컬럼과 교집합인 키만 동적 insert(가변 스키마·기본값 보존).
--   · 회사: companies.notion_id 가 NOT NULL(노션 동기화 키) → CSV 행엔 합성 notion_id('csv:센터:사업자')를
--     서버가 채운다. 중복 판정 = (center_id, biz_no) 우선, 없으면 (center_id, name). 재업로드 시 갱신.
--   · 학생: (center_id, student_no) 우선, 없으면 (center_id, name, phone). 이미 있으면 건너뜀(편집 보호).
-- =====================================================================

create or replace function public.bulk_upsert_companies(p_rows jsonb, p_center_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_center uuid; r jsonb; v_name text; v_biz text; v_row jsonb; cols text; n int := 0;
begin
  if not (is_super_admin() or current_admin_center() is not null) then raise exception 'not_admin'; end if;
  v_center := case when is_super_admin() then coalesce(p_center_id, current_admin_center())
                   else current_admin_center() end;
  if v_center is null then raise exception 'no_center'; end if;

  for r in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_name := nullif(btrim(coalesce(r->>'name', '')), '');
    v_biz  := nullif(regexp_replace(coalesce(r->>'biz_no', ''), '[^0-9]', '', 'g'), '');
    if v_name is null then continue; end if;

    -- 기존 행 갱신: biz_no 우선, 없으면 name (센터 스코프)
    if v_biz is not null then
      update public.companies set name = v_name, active = true, updated_at = now()
        where center_id = v_center and biz_no = v_biz;
    else
      update public.companies set active = true, updated_at = now()
        where center_id = v_center and name = v_name;
    end if;
    if found then n := n + 1; continue; end if;

    -- 신규: 서버가 center_id·active·notion_id(합성, NOT NULL 충족) 주입. CSV 키 중 실제 컬럼만.
    v_row := coalesce(r, '{}'::jsonb) - 'center_id'
             || jsonb_build_object('name', v_name, 'center_id', v_center, 'active', true);
    if v_biz is not null then v_row := v_row || jsonb_build_object('biz_no', v_biz); end if;
    if nullif(v_row->>'notion_id', '') is null then
      -- 합성 키: 사업자번호 우선, 없으면 정규화된 이름(md5 제거 → 서로 다른 이름끼리의 키 충돌 0). 동명 구분은 사업자번호로.
      v_row := v_row || jsonb_build_object('notion_id', 'csv:' || v_center::text || ':' || coalesce(v_biz, 'name:' || lower(btrim(v_name))));
    end if;

    select string_agg(quote_ident(k), ',') into cols
      from jsonb_object_keys(v_row) k
      where exists (select 1 from information_schema.columns c
                    where c.table_schema='public' and c.table_name='companies' and c.column_name = k);
    execute format('insert into public.companies (%s) select %s from jsonb_populate_record(null::public.companies, $1)', cols, cols) using v_row;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n);
end $$;
grant execute on function public.bulk_upsert_companies(jsonb, uuid) to authenticated;


create or replace function public.bulk_upsert_student_roster(p_rows jsonb, p_center_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_center uuid; r jsonb; v_name text; v_no text; v_phone text; v_row jsonb; cols text; n int := 0; v_exists boolean;
begin
  if not (is_super_admin() or current_admin_center() is not null) then raise exception 'not_admin'; end if;
  v_center := case when is_super_admin() then coalesce(p_center_id, current_admin_center())
                   else current_admin_center() end;
  if v_center is null then raise exception 'no_center'; end if;

  for r in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_name  := nullif(btrim(coalesce(r->>'name', '')), '');
    if v_name is null then continue; end if;
    v_no    := nullif(btrim(coalesce(r->>'student_no', '')), '');
    v_phone := nullif(regexp_replace(coalesce(r->>'phone', ''), '[^0-9]', '', 'g'), '');

    -- 이미 있으면 건너뜀(센터 스코프, 관리자 편집 보호): 학번 우선 → 이름+전화 → 이름
    if v_no is not null then
      select exists(select 1 from public.students where center_id = v_center and student_no = v_no) into v_exists;
    elsif v_phone is not null then
      select exists(select 1 from public.students where center_id = v_center and name = v_name and phone = v_phone) into v_exists;
    else
      select exists(select 1 from public.students where center_id = v_center and name = v_name) into v_exists;
    end if;
    if v_exists then continue; end if;

    -- 신규: center_id 서버 주입 + name_norm 채움. CSV 키 중 실제 컬럼만(job_keys 는 JSON 배열로 전달돼야 함).
    v_row := coalesce(r, '{}'::jsonb) - 'id' - 'center_id'
             || jsonb_build_object('name', v_name, 'center_id', v_center,
                  'name_norm', replace(lower(v_name), ' ', ''));
    if v_phone is not null then v_row := v_row || jsonb_build_object('phone', v_phone); end if;

    select string_agg(quote_ident(k), ',') into cols
      from jsonb_object_keys(v_row) k
      where exists (select 1 from information_schema.columns c
                    where c.table_schema='public' and c.table_name='students' and c.column_name = k);
    execute format('insert into public.students (%s) select %s from jsonb_populate_record(null::public.students, $1)', cols, cols) using v_row;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n);
end $$;
grant execute on function public.bulk_upsert_student_roster(jsonb, uuid) to authenticated;
