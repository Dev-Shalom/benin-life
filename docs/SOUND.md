# Sound

Everything is synthesized with WebAudio (no audio files). Code: `src/lib/sound.ts` (context, buses, SFX, ambience, settings, tab rules, place switching), `src/lib/music.ts` (the tracks, the stingers, voice accounting).

## How it works
- **One `AudioContext`**, created on the first tap (`ensureCtx`). Graph: sources -> `sfxBus` / `musicBus` / `ambBus` / per-place bus -> `master` gain -> **limiter** (`DynamicsCompressor`, -12 dB, ratio 12) -> speakers. `admin chime()` now uses this same context.
- **Buses**: SFX (`playCue`, `playCoin`, `playHype` stingers), music (city bed), ambience (noise + horns/crickets), and one **place bus** per soundtrack.
- **One soundtrack at a time**: `Game.tsx` computes a `PlaceSound` and calls `setSoundPlace`. Every change goes through `applyPlace` -> `stopPlace` first (clears the 100 ms timer, fades the old bus, disconnects it 2.5 s later), then builds a new `Engine` + `Track`. `dance` is the afrobeats loop at home.
- **Scheduler**: a 100 ms timer with ~0.3 s look-ahead for place tracks, 150 ms for the city bed. Both skip ahead (silently) if they fall behind instead of playing every missed note.
- **Settings**: Sound effects -> `sfxBus` (ramped to 0 when off), Music -> bed, ambience and place tracks (stopped), HUD mute -> `master` (ramped). Prefs persist in localStorage (`bl.prefs.v1`). Nothing plays before the first gesture, whatever the prefs say; the master/sfx gains are created from the saved prefs so there is no blip.
- **Tab rules**: a hidden tab suspends its context (and pauses the licensed club track). Two visible windows: the last one you tapped plays, the other yields (BroadcastChannel `bl-sound`) until you tap it.
- **Resume**: every tap (`pointerdown/up`, `touchend`, `click`, `keydown`) retries `resume()` if the context is not running (iOS "interrupted" after a call, lock screen, app switch). `statechange`, `visibilitychange`, `pageshow` and `focus` also re-apply.

## What was fixed
| Problem | Cause | Fix |
|---|---|---|
| Music burst/flood after a stall or lock | the city-bed scheduler had no catch-up guard (`while nextAt < now+0.5`); event tracks replayed up to 1 s of ticks | skip to the next bar line when >0.25 s behind; event tracks skip after 0.3 s |
| Music stopped/restarted on StrictMode or a quick remount | `Game` cleanup called `setSoundPlace(null)` immediately | `leaveGameSound()` is deferred 150 ms and cancelled by the next `setSoundScene/Place` |
| No sound after iOS interruption or after leaving the app | unlock listeners were removed after the first tap; iOS needs `touchend`/`click`, not only `pointerdown` | permanent gesture listeners that resume a non-running context; `statechange` re-applies; `audioSession.type='playback'` so the silent switch does not mute |
| Several AudioContexts | admin `chime()` created a new context per chime (iOS allows few) | uses the shared context (`playChime`) |
| Unbounded voices on hype/spray spam | every `playHype` spawned ~25 nodes with no limit | one-shot voice cap (64), stinger throttle (0.6 s), one cheer at a time, click throttle (40 ms) |
| Node/memory growth | sources never disconnected; each stinger/cheer copied a large noise buffer; each place change re-copied the sample banks | every source is disconnected on `ended`; buffers cached per context; engines/buses/drones and the city bed are disconnected after their fades |
| Clipping/volume spikes | no limiter; stingers + cheers + groove stack | master limiter |
| Clicks | `sfxBus.gain.value =` hard set; hype ducking jumped from 0 while the bus was still fading in; mute only affected new sounds | `setTargetAtTime` ramps; ducking starts from the current value; mute/SFX-off ramp the master/sfx gains so in-flight stingers are cut too |
| Stale duck / cheer state across places | `duckUntil` survived a place change, so the next club skipped its duck | reset in `stopPlace` |

## Keep my own music playing
Many players run Spotify, Audiomack, YouTube Music or their phone's music app while they play. Setting **Keep my own music playing** (Sim, Settings; `prefs.keepOwnMusic`, **ON by default for everybody**, stored in `bl.prefs.v1` next to Music / Sound effects / mute; old saved prefs just gain the key, their other choices are untouched) makes the game stay out of the way: "Your music from other apps keeps playing. The game stays quiet and does not pause it."

**ON**
- iOS Safari 16.4+: `navigator.audioSession.type = 'ambient'`, which mixes with other apps. Trade-off: an ambient session follows the **silent switch**, so the game's own sounds are muted when the ringer is on silent (normal iPhone behaviour). Older iOS has no audioSession API; the browser decides.
- No `<audio>` element is created, primed or started on the first tap (`primeRadioDecks` is skipped), and nothing starts the club radio or the single club track by itself. The two radio decks are released (paused, `src` removed, disconnected) whenever no club visit has opted in.
- Game music (home / city bed, ambience, place grooves, drones) stays off, whatever the Music switch says. Short sound effects still play through the shared AudioContext at about 55 % of the normal SFX level; the existing **Sound effects** switch (and the HUD mute) silence them. On Android Chrome, Web Audio output on its own does not request audio focus, so the other app keeps playing.
- **Club chip** (`src/screens/game/ClubMusicChip.tsx`): in a club or lounge with a playable playlist or club track, a small non-blocking chip says "Play the club music? This pauses your own music." with Play and a dismiss (x). One chip per club visit (remounted per place). Only the Play tap (`startClubRadio()`) starts the radio for that visit; during it the iOS session is `playback` (audible with the silent switch on and, as the chip says, it takes over from the other app). The chip then shows "Club music is on / Stop". Leaving the club (or Stop, or turning the setting off) resets the opt-in: the radio stops, the decks are released and the iOS session goes back to `ambient`. Hype ducking, `wake()` / `claimTab()` resync, tab yield and pause-while-hidden work as usual once the radio runs.
- Voice notes (`VoicePlayer`) are `preload="none"` and only play on the player's tap. Nothing else in the app starts a media element (the admin music preview is also tap-only).
- Switching the setting at runtime applies immediately: turning it **ON** stops game music, the radio and the club track, releases the decks and sets the session to `ambient`; turning it **OFF** restores the classic path (the decks are primed from that tap; music and radio resume).

**OFF**: exactly the old behaviour: `audioSession.type = 'playback'`, decks primed on the first tap, game music, club radio and club track start by themselves.

**Honest limits.** Browsers, not the game, decide audio focus. On Android Chrome any `HTMLMediaElement` that starts (the club radio after Play, a voice note, the admin preview) takes audio focus and pauses the other app's music; it does not hand focus back by itself, so the player may need to resume their app. Web Audio not taking focus on Android is Chrome's behaviour, not a guarantee. iOS below 16.4 has no `audioSession`. With ambient, the silent switch mutes game sound, and voice notes play in whatever session is active (so the silent switch mutes them on iPhone while the setting is on).

**Dev counter.** In dev builds only, `window.__blMediaStarts` counts every `HTMLMediaElement.play()` call (`window.__blMediaLog` lists the sources); `__blSound.stats()` also has `ownMode`, `clubOptIn`, `mediaStarts`.

**Manual test plan** (real phones; audio focus cannot be simulated headless)
1. Android Chrome, Spotify playing, setting ON (default): open Benin Life, tap around, travel, open a club. Spotify keeps playing; clicks and cues are faint. A chip appears in the club; dismiss it, nothing changes. Leave and re-enter: one new chip. Tap Play: Spotify pauses, the club music plays; Stop or leaving the club ends it (resume Spotify by hand).
2. iOS Safari, Apple Music playing, setting ON: same. With the ringer on silent the game's effects are muted (expected); Apple Music is unaffected. Play on the chip pauses Apple Music.
3. Both platforms, setting OFF (Sim, Settings): the game pauses the other app on the first tap and plays its music, as before. Toggle ON while the club radio plays: radio and music stop at once.
4. Voice note in a DM: its play button is the only start; the other app pauses then (Android) or mixes (iOS ambient).
5. HUD speaker muted, or Sound effects off: nothing from the game.

Automated: `scripts/sound-check.mjs` forces `keepOwnMusic=false` (it checks the classic path). The own-music path was checked with Playwright at 390x844 on a throwaway page that mounts the chip and settings switches: no `play()` after the first tap, no music timer, `audioSession` ambient, Play starts the radio, leaving stops it, runtime ON/OFF both ways.

## Club radio (M1)
With "Keep my own music playing" ON (default) it starts only from the club chip's Play tap (section above). A club playlist from the admin (docs/MUSIC.md) plays as a server-clock radio: two `<audio>` elements -> `MediaElementSource` -> the club's place bus, on the same single context, so mute, the Music setting, the limiter and the hype ducking apply. Hidden or yielded tabs pause it, and `wake()` / `claimTab()` resync it to the club's current moment. With no playable playlist the old paths run unchanged (`music.club_track_url` single file, then the synth groove). `readBeat()` uses its silent clock while a file plays.

## Dev check
`window.__blSound.stats()` (DEV only) returns the live voice counters (`music`, `sfx`, peaks, `dropped`), `ctxCreated`, live `intervals`, `buses`, `engines`, `trackActive`, `state`. `scripts/sound-check.mjs` drives the real app with Playwright (travel x6, hide/show, a 4 s main-thread stall, an 80-call hype spam, Music off/on) and asserts one context, one soundtrack, bounded voices and no burst:

```
GFX=low node scripts/sound-check.mjs   # dev server on :5242; env BASE, PW, EMAIL, PASSWORD
```
