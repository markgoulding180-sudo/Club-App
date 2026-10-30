# Club & Pub App: Features

**A members' app for social clubs and pubs, covering events, room hire, tickets, the staff rota and holidays in one place.**

Live example: **Ashford Railway Club** at https://club-app-zeta.vercel.app

It works in any phone, tablet or computer browser, and members can add it to their phone's home screen like an app. Nothing has to be installed from an app store.

---

## Three types of account

| Account | Who it's for | What they see |
|---|---|---|
| **Member** | Customers and club members | What's On, booking requests for the rooms, event tickets, and their own bookings and payments |
| **Staff** | Bar and door staff | Their shifts, the rota, holiday requests, and the days they're unavailable |
| **Admin** | Managers and committee | Everything: the bookings diary, rota, staff records, tickets and What's On |

Each person signs in with an email and password, and sees only what their account allows. Security is enforced by the database, not just by hiding buttons.

---

## Public front page (before sign-in)

- A full-width photo banner and the club's details: address, opening times, and a live **Open now / Closed** indicator.
- The next few events from What's On, so visitors can see what's coming up before they join.
- Sections for **About**, **What's On**, **The Club** (bar, sport, amenities), **Hall Hire**, **Membership** (tiers and prices), **Bowls** and **Find Us**, linked from a top menu.
- **Sign in** and **Register** sit on the page itself, with a short note on what members get.
- **Phone version:** a compact home screen with the banner and a swipeable info panel. Sign-in and registration open inside that panel.
- Fast to load on mobile data: optimised images and a single lightweight page.

---

## What's On

- Two tabs: **Club Events** (darts, pool, quiz, bingo, live music, karaoke, Deal or No Deal and so on) and **Live Sport Shown**.
- **Live Sport Shown** lists the full Premier League fixture list, grouped by day, with kick-off times.
- Each event card has a banner image chosen by its **category**, so a darts night shows the darts banner and a quiz shows the quiz banner.
- Ticketed events show member and non-member prices, and how many tickets are left.

---

## Tailored to each member

- On their first sign-in, members get a short **"Make the app yours"** screen. They pick the nights they enjoy (darts, quiz, bingo, live music, karaoke and so on), their football team and what they like to drink. They can also skip it.
- Their favourite kinds of night get a **★** on What's On, and a **★ For you** filter shows only those. Tapping ☆ on any event adds that kind of night to their favourites.
- Their team's matches are highlighted on Live Sport Shown.
- Home shows **Picked for you**, their next few favourite events, and a **My preferences** tile so they can change these any time.
- Drinks and likes are stored for tailored offers in future. Members can opt out with one tick box.

---

## Going, interested and friends

- Every event on What's On has **✓ Going** and **☆ Interested** buttons, with a count ("12 going · 5 interested"). The manager sees the counts too, which helps with staffing and stock.
- **Friends tab:** members add each other by **membership number** (from their membership card). The app shows the first name and surname initial so they know it's the right person, and the friend has to accept.
- When adding a friend they can pick the nights they both like (Bingo, Quiz…). Each friend card shows those, plus what the friend is going to.
- What's On shows when friends are going ("👥 Pat is going").
- **Message board:** friends can send each other short messages, shown as conversations with unread counts. Only accepted friends can message each other.
- **Membership register (admin):** the club's list of every member and their number, added one at a time or pasted in from a spreadsheet. An app account only counts as that member if the surname matches the register.

---

## Room hire bookings (members)

- A booking calendar for each room (for example the **Function Room**, up to 120 guests, and the **Lounge Bar**, up to 60).
- Afternoon, Evening and Full day sessions, with weekday and weekend prices shown up front.
- The calendar shows at a glance which days are free, part booked or full.
- Members choose the event type (birthday, wedding reception, christening, wake, meeting and others), the guest numbers and any notes.
- **18th birthdays** collect extra details: the name of the person turning 18, agreement to ID checks, and notes for the door team.
- Requests go to the admin to confirm. Members can follow their booking, deposit and balance under **My bookings**.

---

## Bookings diary (admin)

- One diary for everything: member hire, club events and sports nights. It can be filtered by **All / Members / Club / Sports** and viewed as a list or a calendar.
- **Club events and sports leagues** are added from a dropdown of event names. **"+ Add a new event"** adds a new name, and it stays in the list for next time.
- **Block bookings for any event**, in three ways:
  - **One date**
  - **Weekly block**: for example every Friday from September to April
  - **Pick dates**: tap any dates on a calendar and they're added to a list you can edit
- Clashes and closed days are skipped automatically and listed afterwards. A whole block can be cancelled or deleted in one go.
- **Payments:** record deposits, balances and refunds (cash, card or bank transfer), with a running total of what's been paid and what's still owed.
- **No-bookings days:** close a room for the afternoon, the evening or the whole day. Members can't book those times.
- Ticketed club events can have member and guest prices and a ticket limit.

---

## Card payments

- Members pay for **tickets** and **room-hire deposits and balances** by card, Apple Pay or Google Pay, on Stripe's secure page. The money goes straight to the club.
- The app marks it paid automatically, and the manager sees it on the booking as "Online (card)". Refunds made in Stripe are recorded too.
- Paying at the bar or door still works as before.

---

## Tickets

- Members reserve tickets for ticketed events, choosing how many member tickets and how many guest tickets.
- The number left updates live, and the event can't be oversold.
- Members can change or cancel their reservation before the event.
- The admin sees everyone who has reserved for each event and marks reservations as **paid** or **cancelled**.

---

## Staff rota

- **4-weekly rotas** that run Monday to Sunday and line up with the wage period. The admin builds the next rota in the last week of the current one, while it's still a **draft** that staff can't see. **Publish rota** then shows it to staff in one tap.
- **The rota works out what's needed by itself.** It knows when the club is open and what's booked, so it knows how many staff each shift needs. For example:
  - Lounge Bar: 1 whenever open
  - Function Room Bar: when the room is in use, and 2 for big parties
  - Door: every evening
- Week-by-week view. Gaps are highlighted in yellow, and each day shows a staff counter such as **"2/3 staff · 1 more needed"**.
- **Pick a name and it saves.** The list only offers people who can do that job, such as bar or door.
- **Regular shifts:** set the days each person normally works, for example Fri and Sat evenings on the Lounge Bar. **Fill from regular shifts** then puts everyone on for the whole 4-week rota in one tap. It skips anyone unavailable or on holiday, days the club is closed, and jobs that are already full, and lists what it skipped.
- **One shift a day per person.** Nobody can be put on two shifts on the same day. The database enforces this too, not just the screen.
- **Unavailable** and **On holiday** staff are greyed out in the lists, and each day shows who's unavailable.
- After each shift, the admin records how it went: **Worked, Late, Sick or Didn't turn up**.

---

## Can't work and cover

1. A staff member taps a shift they're on and gives a reason. **A reason is required.** Requests need at least **2 days' notice**, and each person can ask off up to **2 shifts per rota**. For anything later, they phone the manager.
2. They get a confirmation that the manager has been told. If plans change, they can **withdraw** the request until the manager has dealt with it.
3. On the rota, that person stays on the shift **in red, marked "Can't work"**, with their reason. A **Cover** dropdown sits underneath, and the shift also appears in a **Cover needed** list at the top of the rota.
4. The manager picks someone to cover. **That approves the request.** The manager can **decline** it instead.
5. The staff member sees **"✓ Approved by management"** or **"Declined"** in their account.

---

## Message the manager

- Staff tap **✉ Message the manager** and pick a topic: can't work a shift (no swaps available), feeling ill, problem at the club, abuse from a member or guest, complaint, or something else. Then they write up to 60 words.
- The manager sees **Messages from staff** on their Home screen and the Rota, can reply, and marks each one seen or done. Staff see the reply in **My messages**.

## Unplanned absence

- Swaps and holiday asked for before the rota comes out never count against anyone.
- If a staff member can't work and no one can swap, they message the manager about that shift. The manager decides: **Allow (goes on record as unplanned absence)**, **Allow (special circumstances, not on record)**, or **Decline**.
- The staff record and the Hours report count unplanned absences.

## Finding cover

- On any shift that needs someone, the manager taps **📣 Ask everyone to cover**. Everyone who could work it (right job, not already working, not unavailable) sees **Cover needed** with **Yes, I can work it** / **No, sorry**.
- The manager sees how many said yes and no, then picks from the people who said yes. The others are told automatically.

---

## Shift swaps (ask everyone)

Staff have their own **Swaps** page with two tabs: **My requests** (with a 4-step tracker: Asked everyone → Pick an offer → Manager approves → Done) and **Asked of me** (requests they can help with, and their answers).

1. A staff member who can't work a shift taps it and chooses **Ask everyone to swap**, with an optional message.
2. Everyone who could work that shift (right job, free that day) sees **"Dave needs a swap. Can you help?"**, with their own shifts that Dave could take in return. They tap one to offer it, or tap **No thanks**.
3. Dave sees the offers come in and **picks the one he wants**, first come first served. The other offers are closed automatically.
4. The manager sees **Swaps to approve** showing both people and both shifts, and taps **Approve**. The rota updates.

If no one can swap, the staff member can still tell the manager they can't work it, with a reason, at least 2 days ahead and up to 2 shifts per rota.

---

## Offer to work

- When a shift on the published rota still needs someone, staff who could do it see an **I can work this** button.
- The manager sees **Offers to work** at the top of the rota, and on the shift itself, with **Accept** and **No thanks**. Accepting puts them on the rota, and if they're covering someone who can't work, that request is approved too.
- Staff can withdraw an offer until it's answered, and they see the answer in their updates.

---

## Hours and wages

- An **Hours** report for each 4-week rota. Every shift counts as its set opening hours.
- One row per staff member: shifts, hours, late, sick, didn't turn up, can't work, holiday days, unavailable days, and holiday left for the year, with totals.
- While a rota is still running, it shows hours worked so far alongside the planned total.
- **Download for wages (CSV)** opens in Excel or Google Sheets.
- Staff see their own shifts and hours for the current rota.

---

## Holidays

- Each staff member gets **28 days a year** (Jan–Dec). Holiday is asked for **before the rota comes out**. Days already on a published rota are locked; for those, staff swap their shift instead. They ask for holiday by tapping the days on a calendar, which also shows the days they're working and the days with events on.
- The admin sees each request with useful context: how many shifts it affects, who else is off, and how many days that person has left.
- **Approve** takes them off any shifts on those days, and those shifts go to **Cover needed**. **Decline** shows as declined in their account.
- An approved holiday can be cancelled later, and they go back on any shifts that haven't been covered yet.

---

## Staff records (admin)

- A card for each staff member over the last 12 weeks: shifts worked, hours, late, sick, didn't turn up, can't work, and a **reliability %** badge.
- Their holiday totals: taken, booked, waiting and left.
- Add notes to their record, such as sick, late or a general note.
- Change their account type (Member, Staff or Admin) and what they can work (Bar, Door or both). If someone leaves, changing them back to Member takes them off all their future shifts, and those shifts show as needing someone.
- Set their **regular shifts**.

---

## Staff view

- **Home and My shifts** open with the essentials: shifts and hours on this rota, holiday days left, and a big **Next shift** card (for example "Lounge Bar · Evening 17:00–23:30 · in 2 days").
- An **updates** button appears only when something needs their attention, along with when the next rota is due out.
- **My diary:** one colour-coded calendar.

  | Colour | Means |
  |---|---|
  | Teal | Shift (Bar / Func / Door) |
  | Purple | Swap waiting |
  | Red | Can't work |
  | Green | Holiday |
  | Amber | Holiday asked |
  | Grey | Unavailable |

- **Tap any day** for one simple pop-up:
  - On a shift day: **Swap this shift** or **I can't work it**.
  - On a free day: **Mark me unavailable**, **Ask for holiday from this day**, or **I can work this** for any shift that day that still needs someone.
- **Coming up** lists their next shifts with a status label, then **My holiday** and **Swaps**.
- The full rota is read-only, so they can see who they're working with.

---

## Built to be easy to run

- **Your branding:** logo, photos, colours, rooms, prices and opening times.
- Hosted online, with updates going live in minutes and nothing for staff to install.
- A secure database with sign-in for every user. Members can never see staff records, and staff can't change the rota.
- Phone-first design, with large tap targets and in-page dropdowns that work the same on every phone.
- A demo mode, so you can try every screen before going live.

---

*Ask for a walkthrough of the Admin, Staff and Member views.*
