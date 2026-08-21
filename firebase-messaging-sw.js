/* firebase-messaging-sw.js — ⚠️ 더 이상 등록하지 않는 파일 (2026-08-21부터 미사용)
 *
 * 이 파일과 sw.js 는 둘 다 scope 가 /mju/ 라서 하나의 등록 자리를 두고 서로를 밀어냈고,
 * install.html 이 app.js(→ sw.js 등록)를 import 하는 탓에 이 파일은 늘 waiting 으로 밀렸다.
 * push 이벤트는 active 워커로만 가는데 그게 push 핸들러 없는 sw.js 였고, 그래서 FCM 이
 * success 를 반환해도 배너가 뜨지 않았다. (앱을 완전히 닫아 클라이언트가 0 이 된 구간에는
 * 이 파일이 active 로 승격돼 잠깐 정상 동작했다 — 다음 앱 실행 때 sw.js 가 되찾아갔다.)
 * → 푸시 수신 로직은 sw.js 안으로 통합했다. 이 파일을 다시 등록하지 말 것.
 *
 * 파일 자체는 남겨둔다: 과거 이 스크립트로 등록된 기기가 남아 있을 경우
 * 브라우저의 SW 갱신 요청이 404 를 받아 등록이 해제되는 일을 막기 위함.
 */
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDCQj4zs_ebgM18GKotG1-7n-MVXVdHkqs',
  authDomain: 'mjuipp.firebaseapp.com',
  projectId: 'mjuipp',
  messagingSenderId: '13262157393',
  appId: '1:13262157393:web:45caa766392425a90eaa70'
});

// messaging 초기화 → notification 메시지는 SDK가 백그라운드에서 자동 표시(클릭 시 fcm_options.link 로 이동)
const messaging = firebase.messaging();

// 앱 아이콘 배지(홈 화면 숫자) +1 — 앱을 열면 app.js가 실제 안읽음 수로 다시 맞춤
function bumpBadge() {
  try {
    const open = indexedDB.open('ilhak-badge', 1);
    open.onupgradeneeded = () => { open.result.createObjectStore('kv'); };
    open.onsuccess = () => {
      try {
        const tx = open.result.transaction('kv', 'readwrite');
        const st = tx.objectStore('kv');
        const g = st.get('n');
        g.onsuccess = () => {
          const n = (typeof g.result === 'number' ? g.result : 0) + 1;
          st.put(n, 'n');
          if (navigator.setAppBadge) navigator.setAppBadge(n).catch(() => {});
        };
      } catch (_) {}
    };
  } catch (_) {}
}
// notification 페이로드는 SDK가 자동 표시하므로 여기선 배지만 올림(중복 표시 없음)
messaging.onBackgroundMessage(() => { bumpBadge(); });
