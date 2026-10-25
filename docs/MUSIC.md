# Club music (M1)

The owner uploads songs, puts them in playlists, and picks a playlist for each club (and, if wanted, for each event). Everyone in a club hears the same song at the same second, like a radio station. Code: `src/lib/radio.ts` (the schedule maths), `src/lib/clubRadio.ts` (the audio), `src/lib/clubMusic.ts` (asks the server what plays), `src/admin/Music.tsx` (the admin page). Database: `supabase/migrations/20261017000500_club_music.sql`, tests in `supabase/tests/club_music_test.sql`.

## Upload songs (Admin > Music > Tracks)
1. Open `/admin/music` on a phone or PC.
2. Tap the big box (opens the file picker) or drop files on it. Pick **many files at once**: MP3, M4A, OGG (WAV also works), up to 150 MB each. Files over 6 MB upload in pieces (resumable) with a percent counter, and carry on if the network drops.
3. For each file the browser measures the length, uploads it to the public Storage bucket `club-music`, and adds it to the list. The title comes from the file name; the artist is empty.
4. In the list, edit the **title** and **artist** (optional) in place (it saves when you leave the box). Use the play button to preview. Delete removes the track from every playlist and deletes the file.
5. "Add by direct MP3 link instead" adds a track that lives on another website. The other site must allow other websites to play its file (CORS), and the page checks that for you. Spotify and YouTube links do **not** work (licensing and no way to play them in the game). Uploading the file is more reliable.

Only admins can write to the bucket (Storage policies check `profiles.is_admin`). Anyone can play the public files, which is how players hear them.

## Playlists (Admin > Music > Playlists)
- **New playlist**, give it a name, **Add tracks** (tick several), reorder with the up and down arrows, remove with the cross.
- **Shuffle**: on = a new random order each loop, the same random order for everybody. Off = the order you set.
- **Default for clubs with no playlist**: one playlist can be the default.
- **Save** is explicit. A saved change to the track list or the shuffle setting restarts that playlist's radio clock (players in the club may hear a jump). Renaming does not.
- A playlist is "playable" when it has tracks and every track has a measured length and works with the game's audio (CORS). Otherwise it shows "Not playable" and the club falls through to the next choice.

## Which playlist plays where (Admin > Music > Clubs & events, and the picker in Content > Clubs)
Order of choice for a club, checked live:
1. **A LIVE event at that club that has a playlist** (event times are real Benin time, same as the Events system).
2. **The club's own playlist.**
3. **The default playlist** (clubs only).
4. **Settings > `music.club_track_url`**, a single file looped as before (the old fallback).
5. **The game's own synthesized amapiano groove.**

Events: in Admin > Music > Clubs & events each event at a club has a picker ("Use the club's playlist" = none). When the event ends the club's playlist is back. The client asks the server again exactly when an event starts or ends, so the change is at the event boundary (give or take about 3 seconds).

If `music.club_track_url` was filled when this was deployed, the migration made a **Default** playlist from it. That track has no measured length yet, so it is not used as a radio and the old single-file setting keeps working. Press **Measure** on that track in the Tracks list (this also checks CORS). If the host passes, the Default playlist becomes playable and takes over for clubs with no playlist. If it fails CORS, upload the file instead.

## How the sync works
- The server stores, per playlist, an **anchor** (a timestamp). It changes only when the playlist is edited (track list, order, shuffle, a track's length, or a track deleted).
- Every client computes the same thing from the **server clock** (the game's existing `serverNow()` offset):
  `position = (now - anchor) mod (total playlist duration)`.
- With shuffle on, the order of each loop cycle is a seeded shuffle (seed = playlist id + cycle number, a small PRNG that is identical in every browser). With three or more tracks a cycle never opens with the track the last one ended on.
- So players who join at different times, or leave and come back, hear the same track at the same second. It loops forever.
- Playback: two `<audio>` elements (A and B). The next track is preloaded into the spare one about 25 seconds before the boundary. At the boundary the tracks swap with a short fade out and fade in (about 0.9 s each, a "dip" crossfade; the schedule stays exact). A 200 ms tick compares the element's position with the schedule and re-seeks if it drifts more than 0.4 s.
- When the tab comes back to the front (visibility, focus, pageshow, any tap) the radio resyncs to the club's current moment.
- The client asks `club_music_for(location)` when it enters a club, every 2 to 2.25 minutes (to pick up admin edits), when an event starts or ends, and when the tab becomes visible. The same answer never restarts the music.

## Sound rules that still hold (docs/SOUND.md)
- The radio goes through the **one AudioContext**: `<audio>` > `MediaElementSource` > deck gain > the club's place bus > master > limiter. So Mute, the Music setting, the master limiter and the hype ducking all apply. `crossOrigin='anonymous'` is set on the elements; the `club-music` bucket sends CORS headers (a track that can't be read with CORS is refused when added, because WebAudio would play it silently).
- A hidden tab pauses the radio (and suspends the context); two visible windows: the last one tapped plays. Nothing plays before the first tap. On iOS the two elements are unlocked from the first tap.
- `readBeat()` keeps the dancers moving with a silent clock at the default club BPM while a file plays.
- Dev only: `window.__blSound.radio()` returns the playlist, track, expected position and the element's real position; `stats().radioActive`.

## Music rights (please read)
Only play music you have the right to play in a public place. Good options:
- tracks you made or own;
- royalty-free or "no attribution needed" libraries, with a licence that allows commercial use in a game or app;
- AI-generated music from a service whose plan gives you a **commercial licence**, kept with the receipt;
- songs an artist has given you written permission to play (a message or an email is enough, keep it).

Do not upload ripped or streamed songs from Spotify, YouTube, Apple Music or the radio. If a rights holder complains, delete the track in Admin > Music and the file is gone from the bucket and the playlists. Keep a note of where each track came from.

## Limits and notes
- 150 MB per file (the bucket limit; see below), up to 200 tracks per playlist, track length between 1 second and 3 hours.
- Files are cached by the browser for a year (they are never overwritten; each upload has its own name).
- Data: music_tracks, music_playlists, music_playlist_tracks have RLS and no direct grants; players cannot read or write them. The only public read is the RPC `club_music_for(location)`. Every admin change is in the Audit log (`music_track_add`, `music_track_update`, `music_track_delete`, `music_playlist_create`, `music_playlist_edit`, `music_playlist_delete`, `music_assign`).
- Not covered yet: real iPhone testing of the radio (the code unlocks both elements from the first tap, as iOS needs), and a true overlapping crossfade (the fade is a short dip).

## 150 MB uploads: two limits must both allow it (20261028000300_club_music_150mb)
1. The **bucket** `club-music` limit (set to 150 MB by the migration, and the admin page checks 150 MB).
2. Supabase's **global upload limit**: Dashboard > Storage > Settings > "Upload file size limit". The free plan allows at most 50 MB; on a paid plan set it to at least 150 MB. This one cannot be changed from code. If a big upload fails with "bigger than its upload limit", this is the setting to raise.
Big files use the resumable (TUS) endpoint `https://<project>.storage.supabase.co/storage/v1/upload/resumable` in 6 MB pieces (`src/admin/musicApi.ts`).
