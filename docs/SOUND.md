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

## Club radio (M1)
A club playlist from the admin (docs/MUSIC.md) plays as a server-clock radio: two `<audio>` elements -> `MediaElementSource` -> the club's place bus, on the same single context, so mute, the Music setting, the limiter and the hype ducking apply. Hidden or yielded tabs pause it, and `wake()` / `claimTab()` resync it to the club's current moment. With no playable playlist the old paths run unchanged (`music.club_track_url` single file, then the synth groove). `readBeat()` uses its silent clock while a file plays.

## Dev check
`window.__blSound.stats()` (DEV only) returns the live voice counters (`music`, `sfx`, peaks, `dropped`), `ctxCreated`, live `intervals`, `buses`, `engines`, `trackActive`, `state`. `scripts/sound-check.mjs` drives the real app with Playwright (travel x6, hide/show, a 4 s main-thread stall, an 80-call hype spam, Music off/on) and asserts one context, one soundtrack, bounded voices and no burst:

```
GFX=low node scripts/sound-check.mjs   # dev server on :5242; env BASE, PW, EMAIL, PASSWORD
```
