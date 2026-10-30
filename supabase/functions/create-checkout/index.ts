// create-checkout: makes a Stripe Checkout page for a member's tickets or room-hire deposit/balance.
// The amount is always worked out here from the database, never taken from the phone.
// Secrets (Supabase → Edge Functions → Secrets): STRIPE_SECRET_KEY, APP_URL
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
const pence = (n: number) => Math.round(n * 100);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const STRIPE = Deno.env.get('STRIPE_SECRET_KEY'); const APP = Deno.env.get('APP_URL') || 'https://club-app-zeta.vercel.app';
    if (!STRIPE) return reply({ error: 'Card payments aren’t set up yet. Please pay at the bar.' }, 400);
    const url = Deno.env.get('SUPABASE_URL')!; const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const admin = createClient(url, service);
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user) return reply({ error: 'Please sign in first.' }, 401);

    const { kind, id, part } = await req.json();
    let amount = 0, name = '', meta: Record<string, string> = { kind, user_id: user.id };

    if (kind === 'tickets') {
      const { data: t } = await admin.from('ticket_reservations').select('id,user_id,total,status,member_qty,guest_qty,booking_id,bookings(event_type,booking_date)').eq('id', id).single();
      if (!t || t.user_id !== user.id) return reply({ error: 'Tickets not found.' }, 404);
      if (t.status !== 'reserved') return reply({ error: t.status === 'paid' ? 'These tickets are already paid.' : 'These tickets were cancelled.' }, 400);
      amount = Number(t.total); name = `Tickets: ${t.bookings?.event_type ?? 'Event'} (${t.bookings?.booking_date ?? ''}) x${t.member_qty + t.guest_qty}`;
      meta = { ...meta, reservation_id: String(t.id) };
    } else if (kind === 'booking') {
      const { data: b } = await admin.from('bookings').select('id,user_id,status,price,deposit_required,event_type,booking_date,room').eq('id', id).single();
      if (!b || b.user_id !== user.id) return reply({ error: 'Booking not found.' }, 404);
      if (b.status !== 'confirmed') return reply({ error: 'The club needs to confirm your booking before you can pay.' }, 400);
      const { data: ps } = await admin.from('payments').select('amount,kind').eq('booking_id', b.id);
      const paid = (ps || []).reduce((a, x) => a + (x.kind === 'refund' ? -1 : 1) * Number(x.amount), 0);
      const price = Number(b.price) || 0; const dep = Math.min(Number(b.deposit_required ?? 100), price || Number(b.deposit_required ?? 100));
      amount = part === 'deposit' ? Math.max(0, dep - paid) : Math.max(0, price - paid);
      name = `${part === 'deposit' ? 'Deposit' : 'Balance'}: ${b.room === 'hall' ? 'Function Room' : 'Lounge Bar'} hire, ${b.booking_date} (${b.event_type})`;
      meta = { ...meta, booking_id: String(b.id), part: part === 'deposit' ? 'deposit' : 'balance' };
    } else return reply({ error: 'Unknown payment.' }, 400);

    if (amount < 0.3) return reply({ error: 'Nothing to pay.' }, 400);

    const form = new URLSearchParams({
      mode: 'payment',
      success_url: `${APP}/?paid=1&s={CHECKOUT_SESSION_ID}`,
      cancel_url: `${APP}/?paid=0`,
      customer_email: user.email ?? '',
      'line_items[0][quantity]': '1',
      'line_items[0][price_data][currency]': 'gbp',
      'line_items[0][price_data][unit_amount]': String(pence(amount)),
      'line_items[0][price_data][product_data][name]': name.slice(0, 250),
    });
    for (const [k, v] of Object.entries(meta)) { form.append(`metadata[${k}]`, v); form.append(`payment_intent_data[metadata][${k}]`, v); }
    const r = await fetch('https://api.stripe.com/v1/checkout/sessions', { method: 'POST', headers: { Authorization: `Bearer ${STRIPE}`, 'Content-Type': 'application/x-www-form-urlencoded' }, body: form });
    const s = await r.json();
    if (!r.ok) return reply({ error: s?.error?.message || 'Stripe error' }, 400);
    return reply({ url: s.url });
  } catch (e) { return reply({ error: String(e?.message || e) }, 500); }
});
