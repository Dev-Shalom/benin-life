# Billboards, ad payments, approval and owner phone alerts (H3)

Digital billboards stand at ten busy spots on the 3D city map. Players buy ad time with real money (Paystack). The owner approves each ad first. Rejected ads are refunded automatically, and the owner's phone gets a notification for everything that needs attention.

| Piece | Files |
|---|---|
| Database (tables, RPCs, storage bucket, Tokunbo Lot fix, car dealer check) | `supabase/migrations/20261012000500_billboards.sql` |
| Tests | `supabase/tests/billboards_test.sql` (13 groups) |
| Payment check (top-ups + ads) | `supabase/functions/_shared/paystack.ts`, `paystack-verify`, `paystack-webhook` |
| Refunds | `supabase/functions/billboard-refund` |
| Phone notifications | `supabase/functions/admin-push`, `_shared/push.ts` (VAPID + encryption, WebCrypto only), `_shared/notify.ts`, `public/sw.js`, `src/lib/push.ts` |
| Client logic (no three.js) | `src/lib/billboards.ts` |
| 3D boards | `src/art/city3d/engine/boards.ts`, wired in `engine/CityScene.tsx` (filter chip, pills, tap) |
| Board sheet + booking form | `src/screens/game/BillboardSheet.tsx`, `src/styles/billboards.css` |
| Phone app | `src/screens/game/phone/BillboardsApp.tsx` (Boards / My ads) |
| Admin | `src/admin/Ads.tsx` (sidebar **Ads**), Content → **Billboards** (prices), nav badge + chime in `AdminApp.tsx` |

## How it works for players
1. **Map → 📺 Billboards chip.** Every board gets a dark pill showing how many ads are on air. The boards are also visible in 3D without the chip. Tap a board, or its pill, to open the board sheet.
2. **Board sheet.** It shows:
   - a red **ON AIR** pill and "N ads take turns, 15 s each";
   - a swipe carousel of the live ads, with the one on screen right now marked;
   - under each ad, **Visit <domain>** and "until Thu, 10 Dec", plus **Report**;
   - **+ Add your ad to this board** and a footnote with the 7-day price.
3. **Visit** first shows **"You are leaving Benin Life"** (the domain, plus a reminder never to share passwords). The link opens in a new tab with `rel="noopener noreferrer"`. Each player's tap counts once per hour.
4. **Add your ad:**
   - Pick an image in the big 2:1 picker. The browser resizes it to fit 1200×600 and compresses it to WebP (JPEG as a fallback) under 1.4 MB.
   - Enter a **https://** link. The client and server run the same check.
   - Pick 1, 3 or 7 days. The card shows "Today → <date> · rotates with N other ads · ₦price".
   - Tap **Pay** (the button reads "Add an image" until an image is chosen).
   - The footnote covers secure payment and the rules: scams, adult content, coins or tokens, selling accounts and pretending to be Benin Life are removed without a refund.
5. **Phone → Billboards** has two tabs:
   - **Boards:** every board, what's on air now and the prices.
   - **My ads:** status (Waiting for payment, In review, On air · N days left, Ended, Not approved + reason, Taken down, refund state), views, taps and tap rate.
6. Players get an in-game alert (toast + Alerts) when the ad is paid, approved, rejected (with the reason), taken down, refunded or ended.

## Rotation (everyone sees the same ad)
- `billboard_list()` returns each board's live ads in a fixed order: started first, then by id. It returns at most `billboards.max_ads` ads per board, and only ads with `starts_at <= now < ends_at`.
- The ad on air is `floor(serverNow / (rotate_seconds × 1000)) mod N`. `serverNow` is corrected for the device's clock skew, so every phone shows the same ad.
- A board with no ads cycles four **house ads**, drawn on a canvas so they need no image files: "Top up, get up to +75%", "Benin Boutique", "Tonight in Benin" and "Your ad fit dey here". In the sheet their buttons open the Wallet, the Boutique, or the booking form.
- **3D cost:**
  - Every pole and frame is one merged mesh (1 draw call). Each board's screen is one more draw call (+10 in total, which keeps the map well under the ~60 budget).
  - Each screen shader holds two 512×256 textures and cross-fades between them in 0.9 s, with a slight LED dip. Each rotation swaps one texture.
  - Real images load only for boards near the camera, at most about 3 textures per board. Far boards show a house ad.
  - A timer wakes the idle canvas at each ad change, so it works with reduced motion too.
- **Views:** when a board near the camera starts showing a player's ad, the client counts one view. Views are sent in batches (`billboard_track`): at most one batch per player every 50 s and at most 10 views per ad per batch.

## Prices (kobo in the `billboards` table; edit in Admin → Content → Billboards)
| Board | Where | 1 day | 3 days | 7 days |
|---|---|---|---|---|
| Ring Road mega screen | King's Square | ₦50,000 | ₦130,000 | ₦250,000 |
| Ramat Park mega screen | Ramat Park junction | ₦40,000 | ₦100,000 | ₦200,000 |
| Sapele Rd screen | by the Mall | ₦20,000 | ₦50,000 | ₦100,000 |
| Ugbowo screen | UNIBEN main gate | ₦20,000 | ₦50,000 | ₦100,000 |
| GRA nightlife screen | 360 Signature · Golden Tulip | ₦18,000 | ₦45,000 | ₦90,000 |
| Oba Market screen | Oba Market · Ring Road | ₦15,000 | ₦40,000 | ₦80,000 |
| Akpakpava Rd screen | Ikpoba bridge | ₦12,000 | ₦32,000 | ₦65,000 |
| Uselu Market screen | Ugbowo Rd | ₦6,000 | ₦15,000 | ₦30,000 |
| Airport Rd screen | GRA | ₦5,000 | ₦13,000 | ₦25,000 |
| New Benin screen | Mission Rd | ₦5,000 | ₦13,000 | ₦25,000 |

The board's position (`x`, `y` in map space), its turn (`yaw`, keep within ±0.3), its kind (mega / standard / local = screen size) and whether it is on (`active`) can all be edited in the same table.

**Settings → billboards:**
| Key | Default | What it does |
|---|---|---|
| `billboards.enabled` | on | Boards on the map and buying. Buying also needs `payments.enabled`. |
| `billboards.max_ads` | 50 | Most ads per board, live plus in review. New bookings and approvals are refused while a board is full. |
| `billboards.rotate_seconds` | 15 | Seconds each ad shows (5–120). |
| `billboards.max_active_per_player` | 3 | Ads one player can have in review or live (unpaid checkouts count for 1 hour). |
| `billboards.report_alert` | 1 | Notify admins at this many reports, then each time the count doubles. |

## Payment flow and security
1. The image goes to Storage bucket **`billboard-ads`**:
   - public read, 1.5 MB limit, jpeg/png/webp only;
   - players may upload only into their own folder `<uid>/file.ext`, with no subfolders;
   - an image used by a paid or live ad can't be deleted.
2. `billboard_ad_create(board, days, image_path, link)` checks the following:
   - billboards and payments are on, the player has a Sim and is not banned;
   - the days are 1, 3 or 7;
   - the link is https with a real domain and no `user@`;
   - the image is in the player's own folder and exists in storage;
   - the per-player limit, 10 tries per hour, and room on the board.

   It then inserts an `awaiting_payment` row with the **price taken from the board** and a reference `BLAD-<32 hex>`. It returns `{ad_id, reference, amount_kobo, email, currency}`.
3. Paystack Inline charges that reference. The metadata is `{purpose: 'billboard_ad', ad_id, board, days}`.
4. `paystack-verify` checks that the reference belongs to the signed-in player. `paystack-webhook` is the backup and checks the HMAC signature. Both then call Paystack `transaction/verify` (success, NGN, same reference, metadata `ad_id` if present) and then **`bl_billboard_paid`**, which only the service role can run:
   - **Same amount as the stored price →** `pending_review` (paid_at set), the admin notification "New ad to approve", and an alert to the player.
   - **Wrong amount →** `rejected` + refund due + an admin notification. The ad never goes on air.
   - **Already paid →** a no-op (idempotent). An unpaid row that was cancelled (closed checkout) still counts if the money arrives later.
5. The client never marks anything paid. Unpaid checkouts are cancelled after a day.
6. **Approve** (`admin_billboard_approve`) puts the ad on air from now until now + the paid days. **Reject** needs a reason, and refunds by default. **Remove** takes a live ad down at once, with no refund unless the admin ticks "refund". **Sponsor ad** (`admin_billboard_sponsor`) is free, can go on any board for any dates, and takes an image from the bucket or an https URL. Every action writes to `admin_audit` (`billboard_approve/reject/remove/refund/sponsor`, `push_subscribe`).
7. **Refunds** (`billboard-refund` Edge Function, called by the admin page right after Reject or Remove-with-refund, or with **Retry refund**):
   1. `admin_billboard_refund_start`, run with the admin's own JWT, checks the caller is an admin and that a refund is due, and writes the audit entry.
   2. `bl_billboard_refund_claim` moves the refund to `processing`, so two clicks can't refund twice.
   3. The function calls `POST https://api.paystack.co/refund {transaction: reference, amount}`.
   4. `bl_billboard_refund_result` records `refunded`, or `refund_failed` with Paystack's message. A failure also sends the admin notification "Refund failed". It appears under **Ads → Refunds** with **Retry refund**; or refund it in the Paystack dashboard.

## Owner notifications (Web Push)
- **When:** an ad is paid and needs approval, an ad goes live, an ad is reported, an ad ends, a refund fails (and a wrong-amount payment needs a refund).
- **How it works:**
  1. The database writes each event into `admin_notifications`, which serves as the outbox and the inbox.
  2. The **`admin-push`** function claims unsent rows once (`for update skip locked`). It sends them, encrypted per RFC 8291 and signed with the VAPID key, to every admin's saved device in `push_subscriptions`, and deletes dead subscriptions (404/410). More than 3 at once arrive as one summary notification.
  3. It is called after a payment (verify/webhook), after a refund, after a report, after admin actions, every 30 s while the admin page is open, and by the map when `billboard_list` says something is waiting (at most once per 10 minutes per player). Finished ads are swept by `billboard_list`, `admin_billboard_queue` and `admin-push`.
- **Fallback:**
  - The **Ads** tab shows a red unread badge in the sidebar and tab bar. The tab title shows "(N) Benin Life admin", and a chime plays while the admin page is open.
  - The Ads page lists recent alerts with **Mark all read**.
  - This covers iPhones that haven't installed the app, blocked notifications, and browsers without push.
- **iPhone:** web push works only from the Home Screen app (iOS 16.4+). In Safari tap Share → **Add to Home Screen**, open Benin Life from there, go to `/admin/ads` and tap **Notify me**.

### Owner setup (one time)
1. **GitHub secret `VAPID_PRIVATE_KEY`** (repo → Settings → Secrets and variables → Actions): paste the private key the developer gave you. It is one line of 43 characters. **Never put it in the code or in Vercel.**
2. **GitHub secret `VAPID_SUBJECT`**: `mailto:code.devshalom@gmail.com`, or any email you read. Push services use it to contact you about problems.
3. Run **Actions → Supabase Edge Functions → Run workflow**. It also runs on every push to `main` that touches `supabase/functions/**`. It copies both secrets into Supabase and deploys `paystack-verify`, `paystack-webhook`, `admin-push` and `billboard-refund`.
4. The **public** key is already in the app (`src/lib/push.ts`, and `DEFAULT_VAPID_PUBLIC_KEY` in `_shared/push.ts`):
   `BLdPAJnlb5_3P_wOrtqveyTRo4flZj3qRxN13ga9KNSUNn4rAVMR5EpxANvF--aYhgIedHRrfYSd7EvfU02qssc`.
   If you ever make a new key pair, set `VITE_VAPID_PUBLIC_KEY` in Vercel and the `VAPID_PUBLIC_KEY` Supabase secret to the new public key, and `VAPID_PRIVATE_KEY` to the new private key.
5. On your phone: open `https://playbeninlife.app/admin/ads` (iPhone: from the Home Screen app), tap **Notify me**, allow notifications, then **Send a test**.
6. Payments must already work (docs/PAYMENTS.md: `PAYSTACK_SECRET_KEY` secret, public key in Vercel, `payments.enabled` on). Refunds use the same secret key. Paystack test mode refunds test payments.
7. The migration deploys with the normal database workflow, which pushes `supabase/migrations` to the hosted project.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/billboards_test.sql` covers:
- grants: helpers are private, service functions are for the service role only;
- create-ad validation and switches;
- no self-approval or skipping payment, and no direct writes;
- payment: exact amount only, idempotent, wrong amount leads to a refund, late payment after cancel still counts;
- approve, reject + refund claim/result/retry, remove with and without refund, sponsor, audit, events, notifications;
- the rotation list: live only, not expired or future, at most max_ads, stable order, plus the sweep;
- the per-player limit and a full board;
- report, tap, track and their throttles;
- RLS: others can't see unpaid or pending ads, the payment JSON is hidden;
- storage policies;
- push subscribe and the inbox outbox claim;
- Tokunbo Lot zones and the car dealer row check;
- Content → Billboards.

The push crypto was checked against the reference `http_ece` decrypt and a `jws` ES256 verify.

## Also in H3
- The ride-hailing phone app is now **Bolt**: green ⚡ tile (#34D186), green title and buttons, "Bolt ride-hail" copy.
- **Tokunbo Lot** shows only cars it sells. Its showroom zone is a "Tokunbo row" (used saloons, the "Muscle" Camry, a used Lexus SUV) under a shade cloth, and its own front lot holds a Kia Rio, a Bajaj Boxer and a bicycle. The luxury line-up (Urus, G 63, Cybertruck, GLE 63), the Escalade, the C300 and the new Camry are gone there, and so are their buy cards.
- **Admin → Content → Car dealers → Add** works through `admin_row_upsert` (an insert is audited as `row_insert`). New rows used to start with the id `new_dealer`, which failed with a raw foreign-key error. They now start empty, and a trigger explains the problem in plain words ("No place has the id …", "… needs a place of type car_dealer"). There is one dealer row per car-dealer place, so add the place first.
