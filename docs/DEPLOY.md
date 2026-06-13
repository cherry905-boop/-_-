# docs/DEPLOY.md — 멀티테넌트 적용 체크리스트 (사람이 해야 하는 라이브 단계)

> 코드/마이그레이션은 레포에 준비됨. 아래는 **라이브 Supabase·계정·인프라**가 필요해
> 자동화할 수 없는(또는 해서는 안 되는) 단계. 순서대로 진행하고 각 단계 끝에 검증.

## 0. 사전: 서울 리전 프로젝트 (P4)
- [ ] 현재 Supabase 프로젝트는 **미국 리전**(`ummuyzqyanrearbzgqyp`). 개인정보 국외이전 리스크 제거를 위해 **서울(ap-northeast-2) 리전 프로젝트로 이전**.
  - 신규 서울 프로젝트 생성 → 스키마(`sql/ALL_IN_ONE.sql` + 01~21) 적용 → 데이터 마이그레이션 → `config.js`의 `SUPABASE_URL`/`ANON_KEY` 교체.
  - 이전 시 `privacy.html` 국외이전 문구(현재 'Supabase Inc.(미국)')도 갱신.

## 1. SQL 적용 순서
라이브 SQL 에디터에서 **순서대로**:
1. [ ] (기존) `01`~`18` + 기반 → 이미 적용돼 있으면 생략.
2. [ ] `sql/19_multitenant_core.sql` — centers/admin_users/center_id + 명지대 백필. (멱등)
3. [ ] `sql/20_storage_isolation.sql` — library 버킷 비공개 + 센터 경로 정책. **적용 후 기존 공개 URL 자료는 서명기(7번) 전까지 새 업로드분이 안 열릴 수 있음** — 운영 공지 후 적용.
4. [ ] `sql/21_rls_center_scope.sql` — **먼저 드라이런**(`select … from pg_policies where qual='true'`)으로 갓모드 목록 확인 → 적용 → 관리자 계정으로 교차센터 접근이 0건인지 확인.

## 2. 관리자 매핑 (P5)
- [ ] `admin_users`에 본인(super_admin) 등록: `insert into admin_users(user_id, center_id, role) values ('<auth uid>', (select id from centers where slug='mju'), 'super_admin');`
- [ ] 신규 센터의 center_admin 도 같은 방식으로(센터별 1명 이상).

## 3. 검증 (절대 규칙 #5)
- [ ] `rls-check.html` 실행 → `admin_users` 차단(PASS), `centers` 공개(의도된 노출), PII 전부 PASS.
- [ ] center_admin 계정으로 로그인 → 타 센터 데이터 0건 확인("A센터 사용자가 B센터 데이터 0건").

## 4. 스토리지 서명기 (P2 완성 = P7 의존)
- [ ] 학생(anon)은 비로그인이라 SQL 만으로 교차센터 차단 불가 → **Edge Function 서명기** 필요:
  초대코드/토큰으로 센터 자격 확인 → `createSignedUrl(<center>/lib/...)` 발급.
- [ ] 배포 후 `library.html` 렌더를 '저장된 path → 서명 URL 요청'으로 전환(코드 변경은 그때).

## 5. 인프라 소유 정상화 (P7)
- [ ] 푸시: 개인 Google 계정 Apps Script(`PUSH_KICK_URL`) → **조직 계정 + Supabase Edge Function 크론**.
- [ ] Firebase `mjuipp`(개인) → 조직 Firebase 프로젝트.
- [ ] 호스팅: 개인 GitHub Pages(`cherry905-boop/-_-`) → **조직 GitHub + 본인 명의 도메인**.
- [ ] 센터별 오리진(서브도메인/커스텀 도메인)으로 진짜 동시 다센터 분리(P1 한계 해소) + 센터별 정적 manifest.
- [ ] 최소 연속성: 문서/백업/비상 인계(버스팩터 대비).

## 6. 거버넌스 (P4)
- [ ] 센터별 처리방침·보호책임자(`privacy.html` 동적화는 P3에서 config→DB 후) + 위·수탁 계약.
- [ ] 공단/지원단에 사업비로 지불 가능 여부 등 회계·계약 주체 확인(코드 외).
