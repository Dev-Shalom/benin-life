# Friends, private messages and shared house visits

Real-player social features for Benin Life. Public place chat remains available through the existing Chat tab. These features have no admin dashboard controls or game-config switches.

## Player flows

- Search players by username, send a friend request, and accept, decline or cancel requests. Only accepted friends can start direct conversations or send house invitations.
- Friends can exchange private text messages and recorded voice notes in Phone → Messages. The app applies no character-count limit to text; service, browser, and database resource limits still apply. Voice duration is not capped by the app, though browser recording and Supabase storage limits still apply.
- A host can select several friends and send them house invitations together. Each player can have one active invitation per host; invitations expire after 24 hours.
- Accepting an invitation means the guest is knocking. The host gets an event naming the guest, and the guest stays outside until the host opens Phone → Messages and admits them.
- Admission is server-checked: the host must be at their own home and not travelling. Up to eight guests may be admitted at once. The guest is moved into that host's private home and sees the host's home type, owner furniture, and saved furniture placements. Leaving the visit restores the guest's own home and layout.
- Both host and guests see one another's live positions in the room; player movement is interpolated between updates. The host can select an owned movable furniture item and place or rotate it. Its saved placement is shared with visitors currently in the home. Guests can walk around and use home activities, but cannot edit the host's furniture.
- A House chat shortcut opens a room shared by the people at that private home. It supports text and recorded voice notes. Selecting another player in the house offers the available food and drink items from the player's bag; accepted offers transfer one item to the recipient.
- Private homes have separate location records. They are omitted from the public map and normal travel destinations; only their owner and a guest admitted by that owner can see the location record. An invitation alone does not grant entry.
- Players can block or unfriend a contact from the conversation. Existing public chat's block controls also prevent private messaging and visits.

## Server and client

- Migrations: `supabase/migrations/20261008000300_friends_messages_visits.sql`, `supabase/migrations/20261008000400_shared_house_and_voice_chat.sql`
- Database coverage: `supabase/tests/social_test.sql`
- RPC and private voice storage wrappers: `src/api/social.ts`
- Friends, requests, house invites, conversations, and recording UI: `src/screens/game/phone/SocialApp.tsx`
- Shared home presence, movement, editable furniture, offers, and home chat: `src/state/houseRoom.ts`, `src/screens/Game.tsx`, `src/art/home3d/engine/HomeScene.tsx`, `src/panels/ChatPanel.tsx`
- Custom private voice player: `src/ui/VoicePlayer.tsx`
- Add-friend actions in live People lists: `src/screens/game/SocialPlayerButton.tsx`
- Phone wiring and badges: `src/screens/game/Phone.tsx`

All writes use authenticated server functions. Friendship, message, home-invite, furniture-placement, and voice storage tables are protected by RLS. Direct messages are published to Supabase Realtime with participant and accepted-friend checks. Private home presence and broadcasts are authorized only for the owner and admitted guests at that home. Voice audio uses a private bucket and signed playback URLs; the custom player exposes playback-speed controls and no download control. This hides the download affordance, but media played in a browser cannot be made technically impossible to save using browser developer tools.

## Verification

Run the rollback-only database test against the local Supabase database:

```sh
bash scripts/sql-test.sh supabase/migrations/20261008000200_chat_new_sims_can_send.sql supabase/tests/fixtures/social_legacy_home.sql supabase/migrations/20261008000300_friends_messages_visits.sql supabase/migrations/20261008000400_shared_house_and_voice_chat.sql -- supabase/tests/social_test.sql
bash scripts/sql-test.sh supabase/migrations/20261008000200_chat_new_sims_can_send.sql supabase/tests/fixtures/social_legacy_home.sql supabase/migrations/20261008000300_friends_messages_visits.sql supabase/migrations/20261008000400_shared_house_and_voice_chat.sql -- supabase/tests/chat_test.sql
```

The client build and lint use `npm run build` and `npm run lint`.
