# Card payments (Stripe): setup

The app lets members pay **ticket reservations** and **room-hire deposits/balances** by card.
Members pay on Stripe's secure page; the money goes to the club's Stripe account; the app marks it paid automatically.

## 1. Run the SQL
Supabase → SQL Editor → run `update-online-payments.sql`.

## 2. Stripe account (the club's)
1. Create a free account at stripe.com (stay in **Test mode** to start).
2. Developers → API keys → copy the **Secret key** (`sk_test_…`). Keep it private. Never paste it into a chat or the app.

## 3. Create the two functions in Supabase
Supabase → Edge Functions → **Deploy a new function → Via editor**:
- Name **`create-checkout`**: paste `supabase/functions/create-checkout/index.ts`. Leave **Verify JWT ON**.
- Name **`stripe-webhook`**: paste `supabase/functions/stripe-webhook/index.ts`. Turn **Verify JWT OFF** (function settings).

## 4. Tell Stripe where to send "paid" messages
Stripe → Developers → **Webhooks → Add endpoint**
- URL: `https://tvflgseltbjnkxyfjlem.supabase.co/functions/v1/stripe-webhook`
- Events: `checkout.session.completed` and `charge.refunded`
- Copy the endpoint's **Signing secret** (`whsec_…`).

## 5. Add the secrets in Supabase
Supabase → Edge Functions → **Secrets** → add:
| Name | Value |
|---|---|
| `STRIPE_SECRET_KEY` | your `sk_test_…` key |
| `STRIPE_WEBHOOK_SECRET` | the `whsec_…` signing secret |
| `APP_URL` | `https://club-app-zeta.vercel.app` |

## 6. Test
Sign in as a member, reserve tickets → **Pay now by card**. Use test card `4242 4242 4242 4242`, any future date, any CVC.
You come back to My bookings; within a few seconds the tickets show **Paid**.
For room hire, the admin confirms a booking first; the member then sees **Pay deposit**. Payments show on the booking as "Online (card)".

## Going live
In Stripe switch to **Live mode**, make a live webhook (same URL and events) and replace both secrets with the live `sk_live_…` and live `whsec_…`.

## Refunds
Refund in the Stripe dashboard. Room-hire refunds are recorded on the booking automatically; refunded tickets are marked cancelled.
