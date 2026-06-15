-- =====================================================================
-- 30_company_contacts_in_app.sql  —  [③ 노션 졸업] 기업 CSV 로 담당자(company_contacts)까지 인앱 입력
-- 멱등(create or replace). 적용 순서: 27·28 이후(companies.biz_no, bulk RPC 존재 가정).
--
-- 배경: company_contacts(HRD 담당자)는 지금까지 노션 sync(Apps Script) 전용이라 인앱 입력 경로가 없었다
--   (admin.html 은 읽기만). → 명지대가 노션을 완전히 떼려면 담당자 입력 경로가 필요.
-- 이 마이그레이션: bulk_upsert_companies 가 같은 CSV 행의 담당자명·연락처·이메일로 company_contacts 도
--   함께 upsert 하도록 확장. verify_company_code_solo 가 이 담당자 정보를 기업 가입 자동채움에 사용하므로,
--   CSV 로 담당자를 채우면 노션 없이도 기업 가입 흐름이 그대로 동작한다.
-- ⚠️ company_contacts.notion_id 도 NOT NULL → 회사와 '같은' notion_id(기존 또는 합성 csv:센터:사업자)로 연결.
-- center_id 는 항상 서버가 주입(클라 미신뢰). company_contacts 는 rls-check MUST_BE_BLOCKED 유지(anon 차단).
-- =====================================================================

create or replace function public.bulk_upsert_companies(p_rows jsonb, p_center_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_center uuid; r jsonb;
  v_name text; v_biz text; v_status text; v_nid text;
  v_cname text; v_cphone text; v_cemail text;
  n int := 0; nc int := 0;
begin
  if not (is_super_admin() or current_admin_center() is not null) then raise exception 'not_admin'; end if;
  v_center := case when is_super_admin() then coalesce(p_center_id, current_admin_center())
                   else current_admin_center() end;
  if v_center is null then raise exception 'no_center'; end if;

  for r in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_name   := nullif(btrim(coalesce(r->>'name', '')), '');
    v_biz    := nullif(regexp_replace(coalesce(r->>'biz_no', ''), '[^0-9]', '', 'g'), '');
    v_status := nullif(btrim(coalesce(r->>'status', '')), '');
    v_cname  := nullif(btrim(coalesce(r->>'contact_name', '')), '');
    v_cphone := nullif(regexp_replace(coalesce(r->>'contact_phone', ''), '[^0-9]', '', 'g'), '');
    v_cemail := nullif(btrim(coalesce(r->>'contact_email', '')), '');
    if v_name is null then continue; end if;

    -- 회사 notion_id 도출: 기존 행 우선(센터 스코프, biz_no→name), 없으면 합성(회사·담당자 공유 키)
    v_nid := null;
    if v_biz is not null then
      select notion_id into v_nid from public.companies where center_id = v_center and biz_no = v_biz limit 1;
    end if;
    if v_nid is null then
      select notion_id into v_nid from public.companies where center_id = v_center and name = v_name limit 1;
    end if;
    if v_nid is null then
      -- 합성 키: 사업자번호 우선, 없으면 정규화된 이름(md5 제거 → 서로 다른 이름끼리의 키 충돌 0·사람이 읽을 수 있음).
      -- ⚠️ 사업자번호 없는 '서로 다른' 동명 회사는 같은 키로 묶인다(이름만으론 구분 불가). 구분하려면 CSV 에 사업자번호 기입.
      v_nid := 'csv:' || v_center::text || ':' || coalesce(v_biz, 'name:' || lower(btrim(v_name)));
    end if;

    -- 회사 upsert (notion_id 기준). status/biz_no 는 sql/27 추가분이라 부분 마이그레이션 DB 엔 없을 수 있다 →
    -- undefined_column 이면 핵심 컬럼만으로 강등 upsert(전체 RPC 가 'column does not exist' 로 500 나는 것 방지).
    begin
      update public.companies
         set name = v_name, active = true, updated_at = now(),
             biz_no = coalesce(v_biz, biz_no),
             status = coalesce(v_status, status)
       where center_id = v_center and notion_id = v_nid;
      if not found then
        insert into public.companies (notion_id, name, biz_no, status, center_id, active)
        values (v_nid, v_name, v_biz, v_status, v_center, true);
      end if;
    exception when undefined_column then
      update public.companies set name = v_name, active = true, updated_at = now()
       where center_id = v_center and notion_id = v_nid;
      if not found then
        insert into public.companies (notion_id, name, center_id, active)
        values (v_nid, v_name, v_center, true);
      end if;
    end;
    n := n + 1;

    -- 담당자(HRD) upsert — 회사와 같은 notion_id, role='hrd' (담당자 정보가 있을 때만). email/status 도 동일 강등.
    if v_cname is not null or v_cphone is not null or v_cemail is not null then
      begin
        update public.company_contacts
           set name = coalesce(v_cname, name), phone = coalesce(v_cphone, phone),
               email = coalesce(v_cemail, email), company = v_name,
               status = coalesce(v_status, status), updated_at = now()
         where center_id = v_center and notion_id = v_nid and role = 'hrd';
        if not found then
          insert into public.company_contacts (notion_id, role, company, name, phone, email, status, center_id)
          values (v_nid, 'hrd', v_name, v_cname, v_cphone, v_cemail, v_status, v_center);
        end if;
      exception when undefined_column then
        update public.company_contacts
           set name = coalesce(v_cname, name), phone = coalesce(v_cphone, phone),
               company = v_name, updated_at = now()
         where center_id = v_center and notion_id = v_nid and role = 'hrd';
        if not found then
          insert into public.company_contacts (notion_id, role, company, name, phone, center_id)
          values (v_nid, 'hrd', v_name, v_cname, v_cphone, v_center);
        end if;
      end;
      nc := nc + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'count', n, 'contacts', nc);
end $$;
grant execute on function public.bulk_upsert_companies(jsonb, uuid) to authenticated;
