-- =====================================================================
-- 37_public_read_model.sql
-- [데이터 원장 → 화면 분배] 공개 공지 read-model RPC (notices 수직 증명)
--   설계: docs/READ_MODEL.md §3~§5 (Tier 1). app.js noticeMatches/matchSel 규칙을 서버로 이식.
--
-- 적용 순서:
--   1) sql/19~36 적용 후 이 파일을 먼저 적용한다(추가형·멱등).
--   2) 프론트(notice.html·app.js 배지)가 public_notices 를 쓰는지 확인한다.
--   3) 검증(mju 회귀 0) 후 sql/38_tighten_targeted_select.sql 로 anon 직접 SELECT 를 target_scope='all' 로 조인다.
--      (순서 역전 시: 38 먼저 적용 + RPC 부재 → 폴백 직조회가 'all' 만 봐서 타게팅 공지가 사라짐)
-- =====================================================================

-- ── A. 회사명 표기차 흡수(normCo) — app.js:157 정확 포팅(클라 noticeMatches 와 패리티) ──
--   ⚠️ app.js normCo 는 lower() 를 안 한다(대소문자 보존). my_company_stage 의 lower 포함식과 다르며,
--      여기선 클라 동작 회귀 0 이 우선이라 app.js 와 동일하게 소문자화하지 않고 \s(전체 공백)까지 제거한다.
create or replace function public._norm_co(s text)
returns text
language sql
immutable
as $$
  select regexp_replace(coalesce(s, ''), '㈜|\(주\)|주식회사|\s', '', 'g')
$$;
revoke all on function public._norm_co(text) from public, anon, authenticated;

-- ── B. matchSel(sel, profile, withManagers) 서버 이식 — app.js:159 ──────
--   sel = 'custom' 공지의 target_value(JSON). profile = 클라 신고 프로필(권위 아님, 표시·매칭용).
create or replace function public._match_sel(sel jsonb, prof jsonb, with_managers boolean)
returns boolean
language sql
stable
as $$
  select coalesce(
    -- targets ∋ target_type
    (nullif(prof ->> 'target_type', '') is not null and sel -> 'targets' ? (prof ->> 'target_type'))
    -- jobs ∋ job_key
    or (nullif(prof ->> 'job_key', '') is not null and sel -> 'jobs' ? (prof ->> 'job_key'))
    -- jobs ∩ interest_jobs[] ≠ ∅ (지원자: 단일 job_key 대신 관심직무 배열 교집합)
    or (jsonb_typeof(sel -> 'jobs') = 'array' and jsonb_typeof(prof -> 'interest_jobs') = 'array'
        and exists (
          select 1 from jsonb_array_elements_text(prof -> 'interest_jobs') ij
           where sel -> 'jobs' ? ij
        ))
    -- companies(normCo) ∋ normCo(company)
    or (nullif(prof ->> 'company', '') is not null and jsonb_typeof(sel -> 'companies') = 'array'
        and exists (
          select 1 from jsonb_array_elements_text(sel -> 'companies') c
           where public._norm_co(c) = public._norm_co(prof ->> 'company')
        ))
    -- types ∋ type1
    or (nullif(prof ->> 'type1', '') is not null and sel -> 'types' ? (prof ->> 'type1'))
    -- managers ∋ trim(manager) (공지에서만 — withManagers)
    or (with_managers and nullif(btrim(prof ->> 'manager'), '') is not null
        and sel -> 'managers' ? btrim(prof ->> 'manager'))
  , false)
$$;
revoke all on function public._match_sel(jsonb, jsonb, boolean) from public, anon, authenticated;

-- target_value(text, JSON 문자열)를 안전 캐스트해 _match_sel 호출(잘못된 JSON → false, 클라 try/catch 동치)
create or replace function public._match_sel_text(p_text text, prof jsonb, with_managers boolean)
returns boolean
language plpgsql
stable
as $$
declare
  sel jsonb;
begin
  begin
    sel := nullif(p_text, '')::jsonb;
  exception when others then
    return false;
  end;
  if sel is null then
    return false;
  end if;
  return public._match_sel(sel, prof, with_managers);
end $$;
revoke all on function public._match_sel_text(text, jsonb, boolean) from public, anon, authenticated;

-- ── C. public_notices — noticeMatches(app.js:171) 서버판 + 렌더 컬럼만 반환 ──
--   센터 = request_center_id()(헤더 도출, 클라 미신뢰). 실패 시 빈 결과(fail-closed).
--   target_scope/target_value 는 반환하지 않음(over-fetch·노출 차단). 개인지정 공지는 my_personal_notices(토큰) 별도.
create or replace function public.public_notices(p_profile jsonb default '{}'::jsonb)
returns table(id uuid, title text, body text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_center uuid;
  prof jsonb := coalesce(p_profile, '{}'::jsonb);
begin
  v_center := public.request_center_id();
  if v_center is null then
    return;
  end if;
  return query
    select n.id, n.title, n.body, n.created_at
      from public.notices n
     where n.published = true
       and n.center_id = v_center
       and (
         case coalesce(n.target_scope, 'all')
           when 'all'     then true
           when 'job'     then nullif(prof ->> 'job_key', '')     is not null and prof ->> 'job_key'     = n.target_value
           when 'company' then nullif(prof ->> 'company', '')     is not null and public._norm_co(prof ->> 'company') = public._norm_co(n.target_value)
           when 'target'  then nullif(prof ->> 'target_type', '') is not null and prof ->> 'target_type' = n.target_value
           when 'type'    then nullif(prof ->> 'type1', '')       is not null and prof ->> 'type1'       = n.target_value
           when 'custom'  then public._match_sel_text(n.target_value, prof, true)
           else false
         end
       )
     order by n.created_at desc;
end $$;
grant execute on function public.public_notices(jsonb) to anon, authenticated;
