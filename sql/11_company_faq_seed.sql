-- 11. 기업담당자용 FAQ 시드 — qna_posts(audience='company')에 6건
-- 근거: 센터 운영 데이터(노션 할일·매뉴얼 안내)·2024 Q&A 상담사례집·2026 소개 브로슈어·만족도 설문 문항.
-- 재실행해도 안전: 동일 질문이 이미 있으면 건너뜀. 내용 수정은 관리자 화면(모집 탭 > FAQ)에서도 가능.

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'company', '행정·수당', '전담인력(기업현장교사·HRD담당자) 수당은 어떻게 신청하나요?', '매월 학습일지 작성이 완료된 분을 대상으로 수당을 신청해요.
신청 시기와 양식은 매월 공지로 안내드리니, 앱 알림을 켜두시면 놓치지 않아요.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '전담인력(기업현장교사·HRD담당자) 수당은 어떻게 신청하나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'company', '행정·수당', 'HRD-Net 출석 결과는 어디서 확인하나요?', '매월 HRD-Net에서 학습근로자의 출석 결과를 확인해주세요.
확인 방법은 센터가 배포한 매뉴얼(5~8쪽)에 정리돼 있어요. 매뉴얼이 없거나 막히는 부분이 있으면 1:1 상담으로 문의해주세요.', 'manual', true
where not exists (select 1 from public.qna_posts where question = 'HRD-Net 출석 결과는 어디서 확인하나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'company', '행정·수당', '외부평가 합격 시 지원금(240만원)은 어떻게 지급되나요?', '지원금 신청기간에 학습근로자가 기업에 재직 중이면 최대 240만원이 학습기업 통장으로 입금된 후 전달돼요.
학습근로자에게 전액·일부 지급, 훈련 운영비 활용 등 구체적인 방식은 기업 내부 기준으로 정합니다.
※ 금액·요건은 연도별로 변동될 수 있어요.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '외부평가 합격 시 지원금(240만원)은 어떻게 지급되나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'company', '훈련 운영', '기업현장교사 양성교육은 꼭 받아야 하나요?', '네, OJT 훈련을 진행하려면 기업현장교사 양성교육 이수가 필요해요.
기본과정(3급 1단계)은 온라인 18시간으로 이수할 수 있고, 이수 후 이수증을 센터로 보내주세요. 신청 방법·기한은 공지로 안내드립니다.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '기업현장교사 양성교육은 꼭 받아야 하나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'company', '훈련 운영', 'OJT 훈련시간에 제한이 있나요?', 'OJT는 1일 최대 6시간, 주 40시간 한도 내에서 운영해요.
OJT 기간 학습근로자에게는 월 최저임금 이상 급여를 지급하고 4대보험(고용·산재·건강·국민)이 적용됩니다.', 'manual', true
where not exists (select 1 from public.qna_posts where question = 'OJT 훈련시간에 제한이 있나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'company', '제도', '일학습병행 자격증은 어떤 효력이 있나요?', '학습근로자가 한국산업인력공단 외부평가에 합격하면 국가자격인 일학습병행 자격을 취득해요.
수준은 L2·L3 = 산업기사, L4·L5 = 기사 수준에 해당합니다. 채용·인사에서 어떻게 우대할지는 기업이 정할 수 있어요.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '일학습병행 자격증은 어떤 효력이 있나요?');
