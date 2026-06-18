-- =====================================================================
-- 39_center_vocab_seed_mju.sql
-- [원장 추종 P3] mju 타게팅 어휘(담당자·유형·운영형태·상태)를 centers.vocab 으로 시드
--   설계: docs/PLAN.md P3 / sql/29(vocab 컬럼). app.js applyCenterVocab() 가 이 값을 읽어
--   window.MANAGERS/TYPES/TYPE2/STATUSES 를 override → 모든 탭이 config.js 가 아닌 DB(원장)를 추종.
--
-- 범위: managers/types/type2/statuses 4키만(센터별로 다른 핵심 타게팅·편집 어휘).
--   company_stages·company_surveys·target_types 는 일학습병행 공통 스키마라 config.js 상수로 유지.
--   jobs·companies 는 별도 마스터 테이블이 원장(vocab 에 안 넣음).
--
-- 멱등: 이 4키를 mju 표준값으로 재설정(|| 병합 → 다른 키·다른 센터 vocab 은 보존). 규칙11(센터별 멱등) 준수.
--
-- ⚠️ 적용 순서(엄수, sql/37→38 과 동일 원리):
--   1) 이 파일을 라이브에 적용한다(mju vocab 채워짐).
--   2) 프론트가 DB vocab 을 읽는지 확인(admin 드롭다운이 동일값 렌더 = 회귀 0).
--   3) 그 다음에 config.js 의 TYPES/TYPE2/MANAGERS/STATUSES 정적값(폴백)을 제거한다.
--      (역전 시: 시드 전 vocab=null + config 제거 → admin 담당/유형/상태 드롭다운이 빈다.)
-- =====================================================================

do $$
declare
  mju uuid;
begin
  select id into mju from public.centers where slug = 'mju';
  if mju is null then
    return;   -- centers 미적용/행 없음 → no-op
  end if;
  update public.centers
     set vocab = coalesce(vocab, '{}'::jsonb) || jsonb_build_object(
       'managers', jsonb_build_array('권순천', '김성훈', '차민정', '노혜정', '길은경'),
       'types',    jsonb_build_array('1유형', '2유형', '3유형'),
       'type2',    jsonb_build_array('산업형', '자율형'),
       'statuses', jsonb_build_array('진행중', '휴학', '중도탈락', '수료')
     )
   where id = mju;
end $$;

-- 검증:
-- select vocab -> 'managers', vocab -> 'types', vocab -> 'type2', vocab -> 'statuses'
--   from public.centers where slug = 'mju';
