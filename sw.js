/* sw.js — PWA 기본 서비스워커 (앱처럼 보이게 + 오프라인 최소 캐시)
 * 주의: 푸시 수신용 firebase-messaging-sw.js 는 다음 마일스톤에서 별도로 추가합니다.
 * 코드를 고친 뒤 반영이 안 되면 CACHE 버전 숫자를 올리세요(브라우저 캐시 갱신). */
const CACHE = 'ilhak-v15';
const ASSETS = ['./', './index.html', './install.html', './notice.html', './library.html', './calendar.html',
  './consult.html', './board.html', './survey.html', './company-survey.html', './faq.html', './privacy.html',
  './intro.html', './companies.html', './cases.html', './qna.html',
  './styles.css', './app.js', './config.js', './manifest.json', './assets/logo-mono-white.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).catch(()=>{}));
  self.skipWaiting();
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))));
  self.clients.claim();
});
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  // 네트워크 우선, 실패 시 캐시 (공지 등 최신 데이터가 중요하므로)
  e.respondWith(fetch(req).catch(() => caches.match(req)));
});
