// stripe-webhook: Stripe tells us a payment or refund happened; we record it in the app.
// Turn OFF "Verify JWT" for this function (Stripe can't sign in). Secrets: STRIPE_WEBHOOK_SECRET
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

async function verify(body: string, header: string, secret: string) {
  const parts = Object.fromEntries(header.split(',').map(p => p.split('=') as [string, string]));
  const t = parts['t']; const sigs = header.split(',').filter(p => p.startsWith('v1=')).map(p => p.slice(3));
  if (!t || !sigs.length || Math.abs(Date.now() / 1000 - Number(t)) > 600) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${t}.${body}`));
  const hex = [...new Uint8Array(mac)].map(b => b.toString(16).padStart(2, '0')).join('');
  return sigs.includes(hex);
}

Deno.serve(async (req) => {
  const body = await req.text();
  const ok = await verify(body, req.headers.get('stripe-signature') || '', Deno.env.get('STRIPE_WEBHOOK_SECRET') || '');
  if (!ok) return new Response('Bad signature', { status: 400 });
  const ev = JSON.parse(body);
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  if (ev.type === 'checkout.session.completed' && ev.data.object.payment_status === 'paid') {
    const s = ev.data.object; const m = s.metadata || {}; const amount = s.amount_total / 100;
    if (m.kind === 'tickets') {
      await db.from('ticket_reservations').update({ status: 'paid', paid_at: new Date().toISOString(), stripe_session: s.id }).eq('id', Number(m.reservation_id)).neq('status', 'paid');
    } else if (m.kind === 'booking') {
      await db.from('payments').upsert({ booking_id: Number(m.booking_id), user_id: m.user_id, amount, kind: m.part === 'deposit' ? 'deposit' : 'balance',
        method: 'online', paid_on: new Date().toISOString().slice(0, 10), note: 'Paid online (Stripe)', stripe_ref: s.payment_intent || s.id, taken_by: null }, { onConflict: 'stripe_ref', ignoreDuplicates: true });
    }
  }
  if (ev.type === 'charge.refunded') {
    const c = ev.data.object; const m = c.metadata || {}; const refunded = c.amount_refunded / 100;
    if (m.kind === 'booking' && refunded > 0) {
      await db.from('payments').upsert({ booking_id: Number(m.booking_id), user_id: m.user_id, amount: refunded, kind: 'refund', method: 'online',
        paid_on: new Date().toISOString().slice(0, 10), note: 'Refunded online (Stripe)', stripe_ref: 'refund-' + c.payment_intent, taken_by: null }, { onConflict: 'stripe_ref' });
    }
    if (m.kind === 'tickets') await db.from('ticket_reservations').update({ status: 'cancelled', note: 'Refunded online' }).eq('id', Number(m.reservation_id));
  }
  return new Response('ok');
});
