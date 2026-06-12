/* firebase-messaging-sw.js — FCM 푸시 수신용 서비스워커 (앱 루트에 위치, 파일명 고정)
 * 서비스워커는 config.js 를 못 읽으므로 firebaseConfig 를 여기에 직접 적습니다(공개값이라 OK).
 * getToken()이 이 파일을 /firebase-cloud-messaging-push-scope 범위로 자동 등록합니다(PWA sw.js와 충돌 없음).
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
