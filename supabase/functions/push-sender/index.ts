// =====================================================================
// push-sender — 공지 푸시 발송기 (Apps Script 대체, 2026-08-20)
// 미발송 공지(published & !pushed)를 읽어 FCM HTTP v1 로 발송.
//  · personal 스코프: notice_recipients → push_tokens(device_key) 매칭, 수신자별 제목·본문
//  · 그 외: push_tokens 전체에서 타겟 매칭(all/job/company/target/type/custom)
//  · 클릭 시 https://mju-ipp.github.io/mju/notice.html 열림(신규 주소)
//  · 무효 토큰(UNREGISTERED)은 자동 정리, push_logs 기록, pushed=true 마킹
//  · 호출: pg_cron 5분 폴링 + 관리자 발행 즉시 킥(GET/POST 모두 처리, 멱등)
//  · secret: FIREBASE_SERVICE_ACCOUNT (서비스 계정 JSON 전체)
// =====================================================================
import { createClient } from 'npm:@supabase/supabase-js@2'
import { importPKCS8, SignJWT } from 'npm:jose@5'

const APP_URL = 'https://mju-ipp.github.io/mju/notice.html'
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS' }
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } })

const normCo = (s: string) => (s || '').replace(/㈜|\(주\)|주식회사|\s/g, '')

function matches(scope: string, value: string | null, t: Record<string, unknown>): boolean {
  switch (scope) {
    case 'all': return true
    case 'job': return t.job_key === value
    case 'company': return normCo(String(t.company || '')) === normCo(String(value || ''))
    case 'target': return t.target_type === value
    case 'type': return t.type1 === value
    case 'custom': {
      try {
        const sel = JSON.parse(value || '{}')
        if (sel.targets?.includes(t.target_type)) return true
        if (sel.jobs?.includes(t.job_key)) return true
        if (sel.companies?.map(normCo).includes(normCo(String(t.company || '')))) return true
        if (sel.types?.includes(t.type1)) return true
        if (sel.managers?.length && t.manager && sel.managers.includes(String(t.manager).trim())) return true
      } catch (_) { /* 무시 */ }
      return false
    }
    default: return false
  }
}

async function fcmAccessToken(sa: { private_key: string; client_email: string; token_uri: string }) {
  const key = await importPKCS8(sa.private_key, 'RS256')
  const jwt = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email).setAudience(sa.token_uri)
    .setIssuedAt().setExpirationTime('1h').sign(key)
  const r = await fetch(sa.token_uri, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  })
  const d = await r.json()
  if (!d.access_token) throw new Error('oauth_failed: ' + JSON.stringify(d).slice(0, 200))
  return d.access_token as string
}

async function sendOne(access: string, project: string, token: string, title: string, body: string): Promise<'ok' | 'dead' | 'fail'> {
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`, {
    method: 'POST', headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: { token,
      notification: { title, body },
      webpush: { fcm_options: { link: APP_URL } } } }),
  })
  if (r.ok) return 'ok'
  const t = await r.text()
  return /UNREGISTERED|NOT_FOUND|INVALID_ARGUMENT/i.test(t) ? 'dead' : 'fail'
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  try {
    const saRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!saRaw) return json({ error: 'no_service_account' }, 500)
    const sa = JSON.parse(saRaw)

    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } })

    const { data: notices, error: ne } = await db.from('notices')
      .select('id,title,body,target_scope,target_value,center_id')
      .eq('published', true).eq('pushed', false).limit(10)
    if (ne) return json({ error: 'notices_read: ' + ne.message }, 500)
    if (!notices?.length) return json({ ok: true, processed: 0 })

    const { data: allTokens } = await db.from('push_tokens')
      .select('id,token,device_key,target_type,job_key,company,type1,manager')
    const access = await fcmAccessToken(sa)

    const results: unknown[] = []
    for (const n of notices) {
      let targets: { fcm: string; title: string; body: string; rowId: string }[] = []
      if (n.target_scope === 'personal') {
        const { data: recs } = await db.from('notice_recipients')
          .select('student_token,title,body').eq('notice_id', n.id)
        for (const rec of recs || []) {
          for (const t of allTokens || []) {
            if (t.device_key === rec.student_token && t.token)
              targets.push({ fcm: t.token, title: rec.title || n.title, body: rec.body || n.body, rowId: t.id })
          }
        }
      } else {
        for (const t of allTokens || []) {
          if (t.token && matches(n.target_scope || 'all', n.target_value, t))
            targets.push({ fcm: t.token, title: n.title, body: n.body, rowId: t.id })
        }
      }

      let ok = 0; const dead: string[] = []
      for (const tg of targets) {
        const r = await sendOne(access, sa.project_id, tg.fcm, tg.title, (tg.body || '').slice(0, 300))
        if (r === 'ok') ok++
        else if (r === 'dead') dead.push(tg.rowId)
      }
      if (dead.length) await db.from('push_tokens').delete().in('id', dead)

      await db.from('push_logs').insert({
        scope: n.target_scope || 'all', target: n.target_value || '전체',
        title: n.title, body: (n.body || '').slice(0, 200),
        recipient_count: targets.length, success_count: ok, center_id: n.center_id,
      })
      await db.from('notices').update({ pushed: true }).eq('id', n.id)
      results.push({ notice: n.title, recipients: targets.length, success: ok, cleaned: dead.length })
    }
    return json({ ok: true, processed: notices.length, results })
  } catch (e) {
    return json({ error: String(e).slice(0, 300) }, 500)
  }
})
