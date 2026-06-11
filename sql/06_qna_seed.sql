-- 06. QnA 시드 — 2024 명지대 일학습병행 Q&A 상담사례집(공동훈련센터 발행) 기반
-- 출처: 사례집 2024.11 발행. 금액·일정은 연도별 변동 가능(본문에 단서 포함).
-- 재실행해도 안전: 동일 질문이 이미 있으면 건너뜀.

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'all', '참여신청', '학습근로자 참여 혜택은 무엇이 있나요?', '① 조기취업 — 근로자로 취업 후 교육훈련 기회 제공, 참여기간 동안 기업에서 임금 지급·4대 사회보험 가입·근로기준법 적용
② 학점 인정 — OFF-JT(3월~7월) 전공 12학점, OJT(8월~다음해 2월) 전공 15학점+일반교양 3학점
③ 하계계절학기 융합캡스톤디자인 프로젝트 수강 지원
④ 훈련비·장학금 — OJT 기간 월 최저임금 이상 급여, 훈련종료 후 사회진출 장학금 250만원, OFF-JT 지원금·현장적응 지원금 최대 320만원
⑤ 외부평가 합격 시 — 지원금 신청기간 기업 재직 시 최대 240만원(학습기업 통장으로 입금 후 전달, 기업마다 상이)
⑥ 교육훈련과정 수료 후 일반근로자 전환, 내부평가·외부평가 후 이수증·수료증 발급
※ 금액·내용은 연도별로 변동될 수 있어요 (2024년 사례집 기준)', 'manual', true
where not exists (select 1 from public.qna_posts where question = '학습근로자 참여 혜택은 무엇이 있나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'applicant', '참여신청', '학과별로 어떤 직무에 참여할 수 있나요?', '훈련 대상은 훈련종료 후 졸업이 가능한 참여학과 4학년 1학기 재학생이에요(졸업까지 2학기 남은 경우 가능, 졸업유예자 제외).
운영 직무(2025.8 기준, 변동 가능): SW개발·SW테스트(정보통신·컴퓨터공학), 구조해석설계(기계), 반도체장비개발(전자·기계), 반도체설계(전자·정보통신), 반도체재료개발(전자 등), 스마트앱디자인설계(디지털콘텐츠디자인), 품질경영(산업경영), 스마트물류운영관리(산업경영·경영·경영정보 등).
※ 학과별 직무 진입은 전담교수님과 상담 후 진행하세요.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '학과별로 어떤 직무에 참여할 수 있나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'applicant', '참여신청', '참여신청 등록은 어떻게 하나요?', 'IPP포털사이트(https://ipp.mju.ac.kr) 접속 → [일학습병행] - [일학습신청서]에서 참여신청서를 작성하세요.
· 개인정보 활용동의서 동의 후 저장, 작성 완료 후 반드시 [제출] 클릭
· 희망 직무를 반드시 선택하세요
· 자기소개서·이력서가 미완성이어도 신청서 제출이 가능해요
· 전담 교수님 상담 시 기업 선택이 가능합니다', 'manual', true
where not exists (select 1 from public.qna_posts where question = '참여신청 등록은 어떻게 하나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'applicant', '참여신청', '자소서·면접 컨설팅을 받을 수 있나요?', '네, 명지대학교 자연진로취업팀에서 지원받을 수 있어요.
· https://job.mju.ac.kr 접속 → [상담] 탭에서 진로취업상담·개인심리상담, [취업정보] 탭에서 자기소개서 교육·공유
· 왕초보 실전 모의면접 등 일정 확인·신청 가능
· 문의: 02-300-1579(인문) / 031-324-1554(자연)', 'manual', true
where not exists (select 1 from public.qna_posts where question = '자소서·면접 컨설팅을 받을 수 있나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'applicant', '참여신청', '면접·선발과 근로계약은 어떻게 진행되나요?', '· 기업마다 이력서 제출 시기는 다르지만 보통 11월~1월 사이에 최종 선발이 완료돼요. 이력서를 포털에 업로드하면 센터에서 제출을 지원합니다.
· 보통 1차 서류전형, 2차 면접전형이고 기업에 따라 역량(프로그램 테스트 등) 면접을 보기도 해요.
· 선발이 완료되면 담당 선생님이 2월 중 개별 연락드리고, (표준)훈련근로계약서 체결을 진행합니다.
· 계약서에는 일학습병행의 목표·방법, 기간, 일일 학습근로시간, 임금, 휴일·휴가, 근무 장소·업무가 포함돼요(법 제21조, 근로기준법 제17조 — 서면 교부 의무).', 'manual', true
where not exists (select 1 from public.qna_posts where question = '면접·선발과 근로계약은 어떻게 진행되나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OFF-JT', '고용·산재 보험은 어떻게 가입되나요?', '학습근로자는 훈련생인 동시에 근로기준법상 근로자 지위를 가져요(법 제3조 제3호). 훈련기간(3월~다음해 2월) 동안:
· OFF-JT 기간(3월~7월): 고용/산재 보험 필수 가입 (국민/건강보험은 근로계약서·협약서 증빙으로 납부 예외 신청 가능)
· OJT 기간(8월~2월): 고용/산재/국민/건강 4대보험 가입', 'manual', true
where not exists (select 1 from public.qna_posts where question = '고용·산재 보험은 어떻게 가입되나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OFF-JT', '아르바이트를 해도 되나요?', '네, 생계유지 등을 목적으로 학습기업 이외의 기업에 동시에 고용될 수 있어요.
근거: 일학습병행 운영규칙 제14조 — 재학생단계 학습근로자가 생계유지 등을 목적으로 다른 기업에 동시 고용되어 학습기업에서의 고용보험 피보험자격을 상실하는 경우는 예외로 인정됩니다.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '아르바이트를 해도 되나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OFF-JT', '4학년 1학기 수강신청은 어떻게 하나요?', '· 직무별 필수교과목 4과목 + 본인 필요 교과목을 수강신청하세요.
· 필수교과목 중 이미 수강한 과목이 있으면 청강 처리되고, 청강 교과목 시간에 다른 과목 수강신청은 불가해요.
· 2학기(OJT) 인정학점: 전공 15학점 + 일반교양 3학점, 총 18학점 (모든 훈련을 정상 이수한 경우)
· OJT 이후 졸업이 안 되는 일이 없도록 졸업 이수학점·필수교양을 반드시 미리 확인하세요.
· OJT(2학기) 기간 온라인 3학점 수강 불가(이월 학점 있는 경우 가능하나 비추천)
· 단과대별로 교학팀 수기입력이 있을 수 있으니 사전 OT에 꼭 참여해 공지를 확인하세요.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '4학년 1학기 수강신청은 어떻게 하나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OFF-JT', '직무별로 수강해야 하는 교과목은 무엇인가요?', '직무별 필수교과목은 4과목 12학점(180시간)이에요. 예시(2025.8 기준, 변동 가능):
· 구조해석설계: CAD, 캡스톤디자인1, FEM, 고체역학 (기계공학과)
· SW개발·SW테스트: 데이터베이스, 모바일/웹프로그래밍 또는 기계학습·시스템클라우드보안, 캡스톤디자인 (정보통신·컴퓨터공학과)
· 반도체설계: 전자회로, 반도체패키징, SoC설계, 반도체공정 (전자공학과)
· 품질경영: 품질관리, 프로젝트관리, 신뢰성공학, 마케팅애널리틱스 (산업경영공학과)
· 전 직무 공통: 직업기초능력(학기 중~7월, 24시간)
전체 표는 자료실의 학습안내서에서 확인하거나 센터로 문의하세요.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '직무별로 수강해야 하는 교과목은 무엇인가요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OFF-JT', '타과 필수교과목을 수강하면 전공으로 인정되나요?', '네. 이수해야 하는 NCS 기반자격별 필수교과목을 수강하면, 일학습병행에 참여하는 학습근로자에 한해 소속 학과의 전공으로 인정됩니다.
근거: 명지대 일학습병행 교과운영에 관한 내규 제6조 2항', 'manual', true
where not exists (select 1 from public.qna_posts where question = '타과 필수교과목을 수강하면 전공으로 인정되나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OFF-JT', '교과목 외에 훈련으로 진행하는 프로그램이 있나요?', '① 직업기초능력 — 전체 학습근로자 공통 필수, 3월~7월에 걸쳐 총 24시간 이수 (사전 OT에서 일정 공지)
② 반도체설계 특강 — 반도체설계 직무 참여자는 여름방학 특강 참여
③ 직무교육 — 기초 직무능력 배양·OJT 적응·외부평가 대비를 위해 직무별로 3~7월 진행
④ 기업방문데이 — OFF-JT 기간 중(6~7월) 소속 학습기업을 1회 방문해 소속감·적응력을 높여요', 'manual', true
where not exists (select 1 from public.qna_posts where question = '교과목 외에 훈련으로 진행하는 프로그램이 있나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OFF-JT', '고용24 가입은 어떻게 하나요?', '· www.work24.go.kr 접속 → 개인회원 가입 (기존 HRD-Net이 2024.8.28부터 고용24로 통합)
· 실명인증/본인인증: 나의정보 → 회원정보관리 → 실명인증/본인인증
· 공동인증서·금융인증서·간편인증으로 로그인 가능', 'manual', true
where not exists (select 1 from public.qna_posts where question = '고용24 가입은 어떻게 하나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OFF-JT', '학습활동서는 어떻게 작성하나요?', '고용24에서 작성해요: 마이 서비스 → 마이훈련 → 일학습병행제 → 학습활동서 작성
· 실제 훈련(수업)이 있는 날마다 작성
· 담당 선생님의 안내메일에 있는 ①학습활동서 작성 매뉴얼 ②학습안내서 ③수업일정을 참고
· 훈련시간표를 활용해 해당 월에 편성된 능력단위 내용을 작성하세요', 'manual', true
where not exists (select 1 from public.qna_posts where question = '학습활동서는 어떻게 작성하나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OFF-JT', '공학인증 포기가 가능한가요?', '네, 일학습병행에 참여하면 공학인증을 포기할 수 있어요(공학교육심화프로그램에 관한 내규 제4조).
일학습병행 참여 시 ''산학협력연계전공''을 신청할 수 있고, 연계전공을 이수하면 공학인증 포기가 가능합니다.
※ 인정 조건: OFF-JT 필수교과목 이수 + OJT 기간 9학점 이상 이수 + 제1전공 15학점 이상 이수
절차: ①기업 매칭(12~1월) → ②연계전공 신청(1월, 센터 행정실 이메일) → ③협조문 발송(2월 초) → ④공학인증 포기신청서 제출(2월 말, 공과대학)', 'manual', true
where not exists (select 1 from public.qna_posts where question = '공학인증 포기가 가능한가요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OFF-JT', '여름계절학기 융합캡스톤디자인은 무엇인가요?', '· 수강대상: 일학습병행 학습근로자 중 희망자
· 수업기간: 6월~7월 중 15일간 / 신청학점: 학사 규정에 따름
· 수업료 면제 (단, 일학습병행 중도탈락 시 이수학점 취소)
· 학과 관계없이 신청 가능하나 가급적 개설 학과 교과목 수강 권장
· 신청: IPP포털 → [일학습병행(학생)] → [계절학기 수강신청]', 'manual', true
where not exists (select 1 from public.qna_posts where question = '여름계절학기 융합캡스톤디자인은 무엇인가요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OFF-JT', '결석이 많은데 괜찮은가요?', '일학습병행은 전체 훈련시간의 80% 이상 출석하고, 필수능력단위 개수 기준 70% 이상 내부평가를 통과해야 이수자로 결정돼요.
OFF-JT 수업 결석이 많으면 능력단위별 훈련시간을 채우지 못할 가능성이 높아져 이수·수료에 어려움을 겪을 수 있어요.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '결석이 많은데 괜찮은가요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OJT', '기업 첫 출근 정보는 어떻게 알 수 있나요?', 'OFF-JT 기간 중(6~7월) 각 기업의 출퇴근 정보를 조사해 학습근로자에게 메일로 공유해드려요.
포함 내용: 훈련장소 주소, 첫 출근일, 출/퇴근 시간, 점심시간, 근태관리 방법, 복장, 통근버스, 기숙사 신청방법, 첫 출근일 담당자 연락처·지참서류 등', 'manual', true
where not exists (select 1 from public.qna_posts where question = '기업 첫 출근 정보는 어떻게 알 수 있나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OJT', '첫 출근일을 변경할 수 있나요?', '근로계약서에 일학습병행 기간과 근로 시간이 정해져 있어 첫 출근일 변경은 어려워요. 통상 8월 1일자로 전체 학습근로자가 OJT를 시작하며, 기업 전체 휴무 같은 특이사항이 있는 경우에만 변경될 수 있습니다.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '첫 출근일을 변경할 수 있나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OJT', '비콘 출결은 어떻게 하나요? 신호 오류가 나면요?', '■ 비콘 출결: HRD-Net 앱 설치 → 연차·출장 등을 제외한 근무일에 출결. 훈련은 1일 최대 6시간, 점심 1시간 포함 7시간 간격으로 입실·퇴실 태그. 비콘 출결을 하지 않으면 해당일 훈련시간이 인정되지 않아요(알람 설정 권장).
■ 신호 수신 오류 시: ①비콘 전원(배터리) 확인 ②주변 방해 요소(와이파이 등) 확인 ③출결 앱 삭제 후 재설치', 'manual', true
where not exists (select 1 from public.qna_posts where question = '비콘 출결은 어떻게 하나요? 신호 오류가 나면요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OJT', '훈련계획은 어떻게 이루어지나요?', '인정받은 훈련 시간표에 따라 훈련하고, 매월 초 기업현장교사와 함께 해당 월 훈련계획을 세워요.
· 훈련 정규시간에 불참하면 결석 처리
· 시간표 일정이 바뀌면 센터 전담자를 통해 HRD-Net에 변경 신고
· 출석·결석 관리는 1시간 단위
· 예비군·민방위·경조사 등 부득이한 경우 출석인정일수에 따라 출석 인정 가능 — 예측 가능한 일정은 미리 시간표에 반영하세요', 'manual', true
where not exists (select 1 from public.qna_posts where question = '훈련계획은 어떻게 이루어지나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OJT', '연차는 어떻게 쓰나요?', '연차는 근로기준법 제60조로 보장되는 유급휴가예요. OJT 기간에는 근로기간이 1년 미만이라 1개월 개근 시 1일의 월차가 생겨요.
연차(월차) 사용은 사내 규정에 따라 기업 인사팀에 문의 후 사용하세요.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '연차는 어떻게 쓰나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OJT', '경조사가 있으면 출석으로 인정되나요?', '일학습병행 운영규정(제10조·별표3)에 따른 출석인정 범위가 있어요. 주요 항목:
· 본인 결혼 5일 / 배우자 사망 5일 / 본인·배우자의 부모 사망 5일 / 조부모·외조부모·자녀 사망 2일 / 형제자매 사망 1일 / 배우자 출산 5일
· 예비군·민방위 훈련, 징병검사, 선거권 행사 등은 소요시간·일수만큼 인정
※ 기산일은 ''사유발생일'' 기준', 'manual', true
where not exists (select 1 from public.qna_posts where question = '경조사가 있으면 출석으로 인정되나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OJT', '야간이나 주말에도 훈련(근무)하나요?', '야간·휴일 도제식 현장교육훈련은 원칙적으로 금지돼요(법 제27조).
학습기업이 주말(토·일)을 휴일로 지정한 경우 주말 OJT는 불가하지만, 사업 특성상 주말 대신 평일을 휴일로 지정한 기업은 주말 OJT가 가능합니다(주말과 휴일은 다른 개념).', 'manual', true
where not exists (select 1 from public.qna_posts where question = '야간이나 주말에도 훈련(근무)하나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OJT', '하루에 OJT는 몇 시간까지 가능한가요?', '1일 OJT 최대 훈련시간은 6시간을 초과할 수 없어요. 점심시간은 훈련시간에 포함되지 않습니다.
※ 근무 시간은 근로계약서에 명시된 시간을 준수하세요.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '하루에 OJT는 몇 시간까지 가능한가요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OJT', 'OJT 중에 중도 포기하면 어떻게 되나요?', '· 학점: OFF-JT에서 이수한 필수교과목 중 소속 학과(부) 개설 과목은 전공으로, 그 외는 자유선택 학점으로 인정돼요.
· 지원금: 중도탈락 시 각종 지원금·장학금 수령이 불가합니다.', 'manual', true
where not exists (select 1 from public.qna_posts where question = 'OJT 중에 중도 포기하면 어떻게 되나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', 'OJT', '모니터링(초기·중간·종료)은 무엇인가요?', '공단·센터가 훈련이 잘 진행되는지 진단·컨설팅하는 절차예요. 재학생단계는 OJT 시작 기준으로 초기(시작 전 2주~2개월 이내), 진행, 종료(종료 3개월 전 또는 진도율 80%~) 단계로 실시합니다.
학습일지·학습활동서를 1개월 이상 작성하지 않으면 수시 모니터링 대상이 될 수 있으니 꾸준히 작성하세요. 종료 단계에서는 내부평가 이력·일반근로자 전환 준비 등을 점검해요.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '모니터링(초기·중간·종료)은 무엇인가요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', '외부평가', '외부평가는 무엇인가요?', '일학습병행과정 종목별 필수능력단위를 대상으로, 산업현장에서 필요한 지식·기술·태도를 국가가 평가해 역량을 인정하는 시험이에요(법 제30조, 시행령 제15조).
■ 응시요건: 전체 훈련시간 80% 이상 출석 + 필수능력단위 개수 기준 70% 이상 내부평가 통과
■ 응시기한: 최초 응시는 훈련 진도율 80% 시점부터 가능, 종료 후 1년 이내. 불합격 시 합격자 발표일로부터 1년 내 재응시(횟수 제한 없음)
■ 평가방법: 능력단위별 종합평가(지필+작업형+면접) — 필수능력단위 70% 이상 Pass 시 합격(능력단위별 60점 이상)', 'manual', true
where not exists (select 1 from public.qna_posts where question = '외부평가는 무엇인가요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', '외부평가', '외부평가 준비는 어떻게 해야 하나요?', '① NCS 홈페이지에서 직무별 필수능력단위 학습모듈 다운로드 후 학습
② CQ-Net(c.q-net.or.kr)에서 시험 일정·평가방법·수수료 확인, 홍보자료실→일학습병행 자료실의 공개 문제 활용
③ OFF-JT 기간 직무교육 참석 — 외부평가 개요부터 기출 공유까지
④ 센터가 매년 운영하는 외부전문가 초청 특강에서 노하우·작업평가(실기) 연습
⑤ 기업별 멘토링데이에서 멘토와 외부평가 스터디·준비 노하우 공유', 'manual', true
where not exists (select 1 from public.qna_posts where question = '외부평가 준비는 어떻게 해야 하나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', '외부평가', '외부평가는 언제 보고, 접수는 어떻게 하나요?', '· 일정: 연초 CQ-Net(c.q-net.or.kr)에 공고되는 연간 시행계획의 회차별 일정을 따라요.
· 대상자 신고: 센터에서 응시 여부를 확인해 신고기간 중 HRD-Net 대상자 신고 → 지역본부·지사에서 응시자격(이수 여부) 확인
· 원서접수: 최초 응시자는 센터에서 단체접수, 재응시자는 개별 접수', 'manual', true
where not exists (select 1 from public.qna_posts where question = '외부평가는 언제 보고, 접수는 어떻게 하나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', '외부평가', '합격증(자격증)은 어디서 출력하나요?', '외부평가 합격자 발표 후 CQ-Net에서 평가 결과를 개별 확인하고 자격증 발급을 신청해요.
· 신청: CQ-Net(c.q-net.or.kr) 또는 정부24 인터넷으로만 가능
· 출력: CQ-Net 홈 → 자격증확인서 → 확인서발급 → 발급신청 후 다운로드', 'manual', true
where not exists (select 1 from public.qna_posts where question = '합격증(자격증)은 어디서 출력하나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'student', '외부평가', '이수 후 중도탈락해도 외부평가에 응시할 수 있나요?', '네, 중도탈락했더라도 응시요건(출석 80% + 내부평가 70% 통과)을 충족하면 외부평가에 응시할 수 있어요.
외부평가 성과금은 합격하고 지원금 신청일 당시 학습기업에 재직 중인 경우 학습기업에 일괄 지급되며, 재응시자도 요건에 부합하면 지급 대상에 포함됩니다.', 'manual', true
where not exists (select 1 from public.qna_posts where question = '이수 후 중도탈락해도 외부평가에 응시할 수 있나요?');

insert into public.qna_posts (audience, category, question, answer, source, published)
select 'all', '지원금·장학금', '지원금·장학금은 얼마를 언제 받나요?', '모든 훈련을 정상 이수한 경우 기준(2024년 사례집, 연도별 변동 가능):
· 사회진출 장학금 250만원(50만원×OJT 5개월) — 훈련종료 후 2월 중순, 명지대학교 지급 (초과학기생 지급 불가)
· 현장적응지원금 120만원(10만원×12개월) — 명지대학교, 별도 안내
· OFF-JT 지원금 0~200만원 — 훈련종료 후 5월 이후, 고용노동부·한국산업인력공단 (훈련 성실도 반영, 외부평가 미응시 시 10% 차감)
· 외부평가 합격 — 합격 후 기업 재직 시 240만원(기업통장 지급 후 전달), 1회차 합격 시 센터에서 50만원 추가 지원', 'manual', true
where not exists (select 1 from public.qna_posts where question = '지원금·장학금은 얼마를 언제 받나요?');
