# Friends, private messages and house visits

Real-player social features for Benin Life. Public place chat remains available through the existing Chat tab. These features have no admin dashboard controls or game-config switches.

## Player flows

- Search players by username, send a friend request, and accept, decline or cancel requests. Only accepted friends can start direct conversations or send house invitations.
- Friends can exchange private text messages and recorded voice notes in Phone → Messages. Text is capped at 2,000 characters. Voice recording has no in-game duration cap; the browser and the Supabase project's storage quota still apply.
- A host can select several friends and send them house invitations together. Each player can have one active invitation per host; invitations expire after 24 hours.
- Accepting an invitation means the guest is knocking. The host gets an event naming the guest, and the guest stays outside until the host opens Phone → Messages and admits them.
- Admission is server-checked: the host must be at their own home and not travelling. The guest is moved into that host's private home and temporarily uses its housing layout. Leaving the visit restores the guest's own home and layout.
- Private homes have separate location records. They are omitted from the public map and normal travel destinations; only their owner and a guest admitted by that owner can see the location record. An invitation alone does not grant entry.
- Players can block or unfriend a contact from the conversation. Existing public chat's block controls also prevent private messaging and visits.

## Server and client

- Migration: `supabase/migrations/20261008000300_friends_messages_visits.sql`
- Database coverage: `supabase/tests/social_test.sql`
- RPC and private voice storage wrappers: `src/api/social.ts`
- Friends, requests, house invites, conversations, and recording UI: `src/screens/game/phone/SocialApp.tsx`
- Add-friend actions in live People lists: `src/screens/game/SocialPlayerButton.tsx`
- Phone wiring and badges: `src/screens/game/Phone.tsx`

All writes use authenticated server functions. Friendship, message, home-invite and voice storage tables are private under RLS. Direct messages are published to Supabase Realtime with participant and accepted-friend checks. Voice audio uses a private bucket and signed playback URLs; clients cannot upload into another player's conversation or read audio unless they remain friends and unblocked.

## Verification

Run the rollback-only database test against the local Supabase database:

```sh
bash scripts/sql-test.sh supabase/migrations/20261008000200_chat_new_sims_can_send.sql supabase/tests/fixtures/social_legacy_home.sql supabase/migrations/20261008000300_friends_messages_visits.sql -- supabase/tests/social_test.sql
```

The client build and lint use `npm run build` and `npm run lint`.
