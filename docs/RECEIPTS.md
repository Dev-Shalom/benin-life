# Receipts (H2)

Big purchases give the player a paper receipt: it opens right after paying, and every receipt is kept in
**Phone → Bank → Receipts** (tap one to open it again).

Files: `supabase/migrations/20261012000400_sell_receipts.sql`, `supabase/tests/sell_receipts_test.sql`,
`src/state/receipts.ts`, `src/api/receipts.ts`, `src/screens/game/ReceiptSheet.tsx`, the Receipts tab in
`src/screens/game/phone/BankApp.tsx`.

## When a receipt is issued
- Any purchase of **receipts.min_amount** or more (default **₦500,000**; Settings → Shop). Switch: `receipts.enabled`.
- Hooked purchases (patched from their live definitions, so their results are unchanged apart from the extra key):

| RPC | kind | Seller on the receipt |
|---|---|---|
| `furniture_buy` | furniture | by tier: Oba Market Furniture Stalls (LAPO), Benin Home Store (Mid), Ring Road Interiors (Nepo), all made-up names |
| `shop_buy`, vehicle | car | the dealer's place name (the receipt meta carries the dealer tier) |
| `shop_buy`, other items | shop | the place name |
| `garage_build` | garage | Benin Builders & Sons (made-up) |
| `house_move` | house | "Landlord, <district>"; the item is "Move-in: <home> (N weeks rent)" |
| `wardrobe_buy` | boutique | the brand name (Benin Boutique for house items) |

## Data
- `receipts`: id (uuid), user_id, kind, item_name, amount, seller, ref (unique, `BL-YYYY-XXXXXX`, six letters/digits
  without look-alikes), meta (item id, from_bank / from_cash split, dealer tier ...), created_at (game time).
- RLS: the owner can read their own rows; nobody else (anon has no access at all). Clients have no insert,
  update or delete grants. Rows are written only by `bl_receipt_issue(uid, kind, item, amount, seller, meta)`, a
  private helper (revoked from anon/authenticated) that returns `{"receipt": {...}}` or `{}` so a purchase RPC can
  end with `return bl_receipt_issue(...) || jsonb_build_object(...)`.

## Client
- `src/lib/api.ts` passes every RPC result to `noteReceipt`, so any result with `receipt` opens the sheet. No purchase
  screen has to remember it.
- The sheet: store name, city, receipt number, date and time in WAT, type, item line, total, how it was paid (bank
  transfer and/or cash), a "Thank you for your patronage!" line, and a green **PAID** stamp. **All receipts** opens
  the Bank app on the Receipts tab.

## Adding a new purchase
Call `bl_receipt_issue` in the new RPC's return (see the patches in the migration for examples). Below the
threshold it does nothing.
