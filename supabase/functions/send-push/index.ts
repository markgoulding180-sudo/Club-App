// send-push: sends the club's phone notifications (Web Push). Free: no outside service or account needed.
// Called every minute by the database (pg_cron) when there is something to send.
// Turn OFF "Verify JWT" for this function. It checks its own key instead. No secrets to add.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

// ---- web push (RFC 8291 encryption + VAPID), using only built-in web crypto ----
// <webpush>
const te = new TextEncoder();
const b64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64u = (s) => { s = s.replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '='; return Uint8Array.from(atob(s), c => c.charCodeAt(0)); };
const cat = (...parts) => { const n = parts.reduce((a, p) => a + p.length, 0); const out = new Uint8Array(n); let o = 0; for (const p of parts){ out.set(p, o); o += p.length; } return out; };
async function hmac(key, data){ const k = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']); return new Uint8Array(await crypto.subtle.sign('HMAC', k, data)); }

async function makeVapidKeys(){
  const kp = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  return { publicKey: b64u(await crypto.subtle.exportKey('raw', kp.publicKey)), privateJwk: JSON.stringify(await crypto.subtle.exportKey('jwk', kp.privateKey)) };
}
async function vapidHeader(endpoint, vapid, subject){
  const aud = new URL(endpoint).origin;
  const header = b64u(te.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const claims = b64u(te.encode(JSON.stringify({ aud, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: subject })));
  const key = await crypto.subtle.importKey('jwk', JSON.parse(vapid.privateJwk), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, te.encode(`${header}.${claims}`));
  return `vapid t=${header}.${claims}.${b64u(sig)}, k=${vapid.publicKey}`;
}
async function encrypt(payload, p256dh, auth){
  const uaPublic = unb64u(p256dh), authSecret = unb64u(auth);
  const as = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const asPublic = new Uint8Array(await crypto.subtle.exportKey('raw', as.publicKey));
  const uaKey = await crypto.subtle.importKey('raw', uaPublic, { name: 'ECDH', namedCurve: 'P-256' }, true, []);
  const ecdh = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, as.privateKey, 256));
  const prkKey = await hmac(authSecret, ecdh);
  const ikm = await hmac(prkKey, cat(te.encode('WebPush: info\0'), uaPublic, asPublic, new Uint8Array([1])));
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const prk = await hmac(salt, ikm);
  const cek = (await hmac(prk, cat(te.encode('Content-Encoding: aes128gcm\0'), new Uint8Array([1])))).slice(0, 16);
  const nonce = (await hmac(prk, cat(te.encode('Content-Encoding: nonce\0'), new Uint8Array([1])))).slice(0, 12);
  const key = await crypto.subtle.importKey('raw', cek, { name: 'AES-GCM' }, false, ['encrypt']);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, key, cat(te.encode(payload), new Uint8Array([2]))));
  const rs = new Uint8Array([0, 0, 16, 0]); // record size 4096
  return cat(salt, rs, new Uint8Array([asPublic.length]), asPublic, ct);
}
async function sendPush(sub, message, vapid, subject){
  const body = await encrypt(JSON.stringify(message), sub.p256dh, sub.auth);
  const r = await fetch(sub.endpoint, { method: 'POST', body, headers: {
    'Content-Encoding': 'aes128gcm', 'Content-Type': 'application/octet-stream', TTL: '86400', Urgency: 'normal',
    Authorization: await vapidHeader(sub.endpoint, vapid, subject) } });
  return r.status;
}
// </webpush>

// Several notifications for the same phone at once become one summary
function combine(items){
  if (items.length === 1) return [items[0]];
  const byKind = {}; items.forEach(i => (byKind[i.kind] ||= []).push(i));
  const out = [];
  for (const [kind, list] of Object.entries(byKind)) {
    if (list.length <= 2) { out.push(...list); continue; }
    const label = { events: 'new events at the club', messages: 'new messages', reminders: 'events starting soon', bookings: 'booking updates', news: 'updates from the club' }[kind] || 'updates';
    out.push({ kind, title: `${list.length} ${label}`, body: list.map(i => i.title.replace(/^New at the club: /, '')).slice(0, 4).join(' · '), url: list[0].url });
  }
  return out;
}

Deno.serve(async (req) => {
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: cfgRows } = await db.from('push_config').select('key,value');
  const cfg = Object.fromEntries((cfgRows || []).map(r => [r.key, r.value]));
  if (!cfg.cron_key || req.headers.get('x-push-key') !== cfg.cron_key) return new Response('Not allowed', { status: 401 });

  // First run: make the club's notification keys
  if (!cfg.vapid_public || !cfg.vapid_private) {
    const k = await makeVapidKeys();
    await db.from('push_config').upsert([{ key: 'vapid_public', value: k.publicKey }, { key: 'vapid_private', value: k.privateJwk }]);
    cfg.vapid_public = k.publicKey; cfg.vapid_private = k.privateJwk;
  }
  const vapid = { publicKey: cfg.vapid_public, privateJwk: cfg.vapid_private };
  const subject = cfg.contact || 'mailto:markgoulding180@gmail.com';

  const { data: rows, error } = await db.rpc('push_take_batch');
  if (error) return new Response(error.message, { status: 500 });
  const byPhone = new Map();
  for (const r of rows || []) {
    if (!byPhone.has(r.endpoint)) byPhone.set(r.endpoint, { sub: r, items: [] });
    byPhone.get(r.endpoint).items.push({ kind: r.kind, title: r.title, body: r.body, url: r.url });
  }
  let sent = 0; const dead = [];
  await Promise.all([...byPhone.values()].map(async ({ sub, items }) => {
    for (const m of combine(items)) {
      try {
        const st = await sendPush(sub, { title: m.title, body: m.body, url: m.url || '/' }, vapid, subject);
        if (st === 404 || st === 410) { dead.push(sub.endpoint); break; }
        if (st < 300) sent++;
      } catch (_) { /* skip this phone this time */ }
    }
  }));
  if (dead.length) await db.rpc('push_drop_subs', { endpoints: dead });
  return Response.json({ phones: byPhone.size, sent, removed: dead.length });
});
