# Phone notifications: setup (free, about 5 minutes)

Notifications use Web Push, which is built into phones and browsers. No account, no secret keys, no cost.

## 1. Create the send-push function in Supabase
1. Supabase → your Club-APP project → **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Name it exactly **`send-push`**.
3. Delete the sample code and paste everything from
   https://raw.githubusercontent.com/markgoulding180-sudo/Club-App/main/supabase/functions/send-push/index.ts
4. Click **Deploy function**.
5. Open the function's **Details** (or settings) and turn **Enforce JWT verification / Verify JWT** **OFF**, then save.
   (The database calls it with its own key, and the function checks that key itself.)

## 2. Run the SQL
SQL Editor → paste and run
https://raw.githubusercontent.com/markgoulding180-sudo/Club-App/main/add-push-notifications.sql

It switches on two built-in Supabase extensions (pg_cron to run every minute, pg_net to call the function), adds the tables, and the triggers that create notifications.

## 3. Check it after a minute
```sql
select key from public.push_config order by key;   -- should list contact, cron_key, vapid_private, vapid_public
```
If `vapid_public` doesn't appear after 2 minutes, check Edge Functions → send-push → Logs (Verify JWT must be off).

## What sends a notification
| When | Who gets it |
|---|---|
| A new club event or What's On item is added (not league nights or football) | Members |
| 1 hour before an event starts | Members who said Going/Interested, or who picked that kind of night in their preferences |
| The newsletter is published | Members and staff |
| A notice is sent | Whoever the notice is for |
| A message on the message board | The person it's to |
| A member's room booking is confirmed | That member |

Several at once to the same phone are combined into one (e.g. "13 new events at the club"). Members choose which kinds they get on the Notifications page.

## Members turning it on
- **Android:** Home → "Turn on notifications" → Allow.
- **iPhone (iOS 16.4 or later):** first add the app to the Home Screen (Safari → Share → Add to Home Screen), open it from there, then turn on notifications. The app shows these steps.

## Turning it all off
```sql
select cron.unschedule('club-push');
```
