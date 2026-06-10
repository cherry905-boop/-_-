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
firebase.messaging();
