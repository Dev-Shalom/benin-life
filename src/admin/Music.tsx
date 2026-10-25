// /admin/music (M1, docs/MUSIC.md): the club music library, playlists, and which playlist plays where.
//   Tracks     pick many MP3 / M4A / OGG files (button or drag-drop, phone or PC): each is measured in the browser,
//              uploaded to the public club-music bucket and listed with an editable title, artist, preview and delete.
//   Playlists  create, add / reorder / remove tracks, shuffle on or off, "default for clubs with no playlist".
//   Places     one playlist per club and (optionally) per event. A LIVE event's playlist beats the club's.
// Every change goes through admin-only RPCs (audited). Saving a playlist restarts its radio clock for everyone.
import { useEffect, useMemo, useRef, useState, type DragEvent } from 'react';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton, Toggle } from './parts';
import { useLoad } from './util';
import {
  ACCEPT, fmtDuration, isAudioFile, measureDuration, musicApi, probeCors, removeFromBucket, titleFromFilename, uploadTrack,
  type MusicOverview, type MusicPlaylist, type MusicTrack,
} from './musicApi';

type Tab = 'tracks' | 'playlists' | 'places';
const TABS: { id: Tab; label: string }[] = [
  { id: 'tracks', label: 'Tracks' },
  { id: 'playlists', label: 'Playlists' },
  { id: 'places', label: 'Clubs & events' },
];

/** A playlist dropdown (used here and in Content → Clubs). */
export function PlaylistSelect({ value, playlists, onChange, disabled, label, emptyLabel = 'Default (synth groove)' }: {
  value: string | null; playlists: MusicPlaylist[]; onChange: (id: string | null) => void; disabled?: boolean; label: string; emptyLabel?: string;
}) {
  return (
    <select className="adm-input adm-music-select" aria-label={label} disabled={disabled} value={value ?? ''}
      onChange={(e) => onChange(e.target.value || null)}>
      <option value="">{emptyLabel}</option>
      {playlists.map((p) => <option key={p.id} value={p.id}>{p.name}{p.playable ? '' : ' (not playable yet)'}</option>)}
    </select>
  );
}

export default function Music() {
  const [tab, setTab] = useState<Tab>('tracks');
  const data = useLoad(() => musicApi.overview());
  return (
    <div className="adm-page" data-testid="admin-music">
      <PageHead title="Music" sub="Upload songs, make playlists and pick what plays in each club. Everyone in a club hears the same moment, like a radio station." />
      <nav className="adm-catnav" aria-label="Music sections">
        {TABS.map((t) => (
          <button key={t.id} type="button" className={`adm-chip${tab === t.id ? ' is-on' : ''}`} onClick={() => setTab(t.id)}>{t.label}</button>
        ))}
      </nav>
      {data.error && <LoadError error={data.error} onRetry={() => void data.reload()} />}
      {!data.data && !data.error && <Skeleton rows={6} />}
      {data.data && tab === 'tracks' && <TracksTab d={data.data} reload={data.reload} />}
      {data.data && tab === 'playlists' && <PlaylistsTab d={data.data} reload={data.reload} />}
      {data.data && tab === 'places' && <PlacesTab d={data.data} reload={data.reload} />}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------- tracks
interface QItem { id: number; name: string; state: 'wait' | 'busy' | 'done' | 'error'; step: string; error?: string }

function TracksTab({ d, reload }: { d: MusicOverview; reload: () => Promise<void> }) {
  const [queue, setQueue] = useState<QItem[]>([]);
  const [over, setOver] = useState(false);
  const running = useRef(false);
  const seq = useRef(0);
  const preview = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState<string | null>(null);

  useEffect(() => () => { preview.current?.pause(); }, []);

  const patch = (id: number, p: Partial<QItem>) => setQueue((q) => q.map((x) => (x.id === id ? { ...x, ...p } : x)));

  const addFiles = async (files: File[]) => {
    const picked = files.filter(isAudioFile);
    const skipped = files.length - picked.length;
    if (skipped) toast(`${skipped} file${skipped === 1 ? ' is' : 's are'} not MP3 / M4A / OGG / WAV and were skipped.`, 'info');
    if (!picked.length || running.current) {
      if (running.current && picked.length) toast('Still uploading. Add the next files when this batch finishes.', 'info');
      return;
    }
    running.current = true;
    const items = picked.map((f) => ({ f, item: { id: ++seq.current, name: f.name, state: 'wait', step: 'Waiting' } as QItem }));
    setQueue(items.map((x) => x.item));
    let ok = 0;
    for (const { f, item } of items) {
      patch(item.id, { state: 'busy', step: 'Starting' });
      try {
        await uploadTrack(f, titleFromFilename(f.name), '', (step) => patch(item.id, { step }));
        patch(item.id, { state: 'done', step: 'Added' });
        ok++;
      } catch (e) {
        patch(item.id, { state: 'error', step: 'Failed', error: errorMessage(e) });
      }
    }
    running.current = false;
    if (ok) toast(`${ok} track${ok === 1 ? '' : 's'} added.`, 'good');
    await reload();
  };

  const onDrop = (e: DragEvent) => {
    e.preventDefault();
    setOver(false);
    void addFiles(Array.from(e.dataTransfer.files));
  };

  const togglePreview = (t: MusicTrack) => {
    if (playing === t.id) { preview.current?.pause(); setPlaying(null); return; }
    preview.current?.pause();
    const a = new Audio(t.url);
    preview.current = a;
    a.onended = () => setPlaying((p) => (p === t.id ? null : p));
    a.onerror = () => { toast('This track would not play. Is the file still there?', 'bad'); setPlaying(null); };
    void a.play().then(() => setPlaying(t.id)).catch(() => setPlaying(null));
  };

  return (
    <div className="adm-stack">
      <label className={`adm-card adm-drop${over ? ' is-over' : ''}`} data-testid="music-drop"
        onDragOver={(e) => { e.preventDefault(); setOver(true); }} onDragLeave={() => setOver(false)} onDrop={onDrop}>
        <input type="file" multiple accept={ACCEPT} data-testid="music-file" className="adm-drop__input"
          onChange={(e) => { const fs = Array.from(e.target.files ?? []); e.target.value = ''; void addFiles(fs); }} />
        <b>Tap to pick songs, or drop them here</b>
        <span className="adm-sub">MP3, M4A, OGG or WAV, up to 150 MB each (big files upload in pieces and continue if your network drops). You can pick many at once. Use music you have the rights to (see docs/MUSIC.md).</span>
      </label>

      {queue.length > 0 && (
        <div className="adm-card adm-rows" data-testid="music-queue">
          {queue.map((q) => (
            <div key={q.id} className="adm-row">
              <div className="adm-row__main adm-row__main--static">
                <span className="adm-row__title">{q.name}</span>
                <span className="adm-row__sub">{q.error ?? q.step}</span>
              </div>
              <Badge tone={q.state === 'done' ? 'green' : q.state === 'error' ? 'red' : q.state === 'busy' ? 'blue' : 'grey'}>
                {q.state === 'done' ? 'Added' : q.state === 'error' ? 'Failed' : q.state === 'busy' ? 'Working' : 'Waiting'}
              </Badge>
            </div>
          ))}
        </div>
      )}

      <LinkAdd reload={reload} />

      <div className="adm-card adm-rows" data-testid="music-tracks">
        {d.tracks.length === 0 && <p className="adm-sub adm-pad">No tracks yet. Add some above.</p>}
        {d.tracks.map((t) => (
          <TrackRow key={t.id} t={t} playing={playing === t.id} onPreview={() => togglePreview(t)}
            onChanged={reload} onDeleted={() => { if (playing === t.id) { preview.current?.pause(); setPlaying(null); } }} />
        ))}
      </div>
      {d.setting_url && (
        <p className="adm-sub adm-inline-hint">
          Settings → <b>music.club_track_url</b> is set. It stays as a fallback: clubs with no playable playlist loop that one file.
        </p>
      )}
    </div>
  );
}

function TrackRow({ t, playing, onPreview, onChanged, onDeleted }: {
  t: MusicTrack; playing: boolean; onPreview: () => void; onChanged: () => Promise<void>; onDeleted: () => void;
}) {
  const [title, setTitle] = useState(t.title);
  const [artist, setArtist] = useState(t.artist);
  const [busy, setBusy] = useState(false);
  useEffect(() => { setTitle(t.title); setArtist(t.artist); }, [t.title, t.artist]);
  const dirty = title.trim() !== t.title || artist.trim() !== t.artist;
  const needsMeasure = t.duration_ms <= 0 || !t.cors_ok;

  const save = async () => {
    if (!dirty || !title.trim()) { setTitle(t.title); return; }
    setBusy(true);
    try {
      await musicApi.trackUpdate(t.id, { title: title.trim(), artist: artist.trim() });
      toast('Saved.', 'good');
      await onChanged();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  const measure = async () => {
    setBusy(true);
    try {
      const [ms, cors] = await Promise.all([measureDuration(t.url), probeCors(t.url)]);
      if (ms < 1000) throw new Error('Could not read this track. Check the link still works.');
      const r = await musicApi.trackUpdate(t.id, { durationMs: ms, corsOk: cors });
      toast(cors ? `Measured ${fmtDuration(ms)}.${r.playlists_restarted ? ' Playlists restarted.' : ''}` : 'This host does not allow other sites to play it (CORS), so it cannot be used in a playlist. Upload the file instead.', cors ? 'good' : 'bad');
      await onChanged();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  const remove = async () => {
    try {
      const r = await musicApi.trackDelete(t.id);
      onDeleted();
      const gone = await removeFromBucket(r.storage_path);
      toast(r.message + (gone ? '' : ' (The file is still in storage; remove it from the Supabase dashboard if you want the space back.)'), gone ? 'good' : 'info');
      await onChanged();
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };

  return (
    <div className="adm-row adm-music-row" data-testid="music-track">
      <button type="button" className="adm-iconbtn" aria-label={playing ? `Stop ${t.title}` : `Preview ${t.title}`} onClick={onPreview}>
        {playing ? '■' : '▶'}
      </button>
      <div className="adm-music-row__main">
        <input className="adm-input" aria-label="Title" value={title} maxLength={120} disabled={busy}
          onChange={(e) => setTitle(e.target.value)} onBlur={() => void save()} onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }} />
        <input className="adm-input" aria-label="Artist (optional)" placeholder="Artist (optional)" value={artist} maxLength={120} disabled={busy}
          onChange={(e) => setArtist(e.target.value)} onBlur={() => void save()} onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }} />
        <div className="adm-badges">
          <Badge tone={t.duration_ms > 0 ? 'grey' : 'amber'}>{t.duration_ms > 0 ? fmtDuration(t.duration_ms) : 'Length unknown'}</Badge>
          <Badge tone="blue">{t.storage_path ? 'Uploaded' : 'Link'}</Badge>
          {t.used_in > 0 && <Badge tone="violet">In {t.used_in} playlist{t.used_in === 1 ? '' : 's'}</Badge>}
          {needsMeasure && <Badge tone="amber">{t.duration_ms <= 0 ? 'Needs measuring' : 'No CORS'}</Badge>}
        </div>
      </div>
      <div className="adm-music-row__acts">
        {needsMeasure && <Btn small onClick={() => void measure()} disabled={busy}>Measure</Btn>}
        <ConfirmButton small onConfirm={remove} disabled={busy} confirmText="Delete?">Delete</ConfirmButton>
      </div>
    </div>
  );
}

function LinkAdd({ reload }: { reload: () => Promise<void> }) {
  const [open, setOpen] = useState(false);
  const [url, setUrl] = useState('');
  const [title, setTitle] = useState('');
  const [artist, setArtist] = useState('');
  const [busy, setBusy] = useState(false);
  const add = async () => {
    const u = url.trim();
    if (!/^https:\/\/[^\s]+$/i.test(u)) { toast('Paste a full https:// link to an MP3 / M4A / OGG file.', 'bad'); return; }
    setBusy(true);
    try {
      if (!(await probeCors(u))) throw new Error('That host does not allow other websites to play its files (CORS). Download the song and upload it here instead.');
      const ms = await measureDuration(u);
      if (ms < 1000) throw new Error('Could not read that file. Is it a direct link to an audio file (not a web page)?');
      const name = decodeURIComponent(u.split('?')[0].split('/').pop() ?? '') || 'Track';
      await musicApi.trackAdd({ title: (title.trim() || titleFromFilename(name)).slice(0, 120), artist: artist.trim(), url: u, storagePath: null, durationMs: ms, size: null, corsOk: true });
      toast('Track added from the link.', 'good');
      setUrl(''); setTitle(''); setArtist('');
      await reload();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  if (!open) return <div><Btn small onClick={() => setOpen(true)}>Add by direct MP3 link instead</Btn></div>;
  return (
    <div className="adm-card adm-form">
      <label className="adm-field"><span className="adm-field__label">Direct link (https, ends in .mp3 / .m4a / .ogg)</span>
        <input className="adm-input" value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://example.com/song.mp3" inputMode="url" /></label>
      <div className="adm-music-two">
        <label className="adm-field"><span className="adm-field__label">Title (optional)</span>
          <input className="adm-input" value={title} maxLength={120} onChange={(e) => setTitle(e.target.value)} /></label>
        <label className="adm-field"><span className="adm-field__label">Artist (optional)</span>
          <input className="adm-input" value={artist} maxLength={120} onChange={(e) => setArtist(e.target.value)} /></label>
      </div>
      <p className="adm-field__help">The other site must allow playing its file from other websites (CORS). Spotify and YouTube links do not work. Uploading the file is more reliable.</p>
      <div className="adm-btnrow">
        <Btn tone="primary" onClick={() => void add()} disabled={busy || !url.trim()}>{busy ? 'Checking...' : 'Add track'}</Btn>
        <Btn tone="quiet" onClick={() => setOpen(false)} disabled={busy}>Cancel</Btn>
      </div>
    </div>
  );
}

// ------------------------------------------------------------------------------------------- playlists
interface Draft { id: string | null; name: string; shuffle: boolean; isDefault: boolean; ids: string[] }
const blank = (): Draft => ({ id: null, name: '', shuffle: false, isDefault: false, ids: [] });
const fromPl = (p: MusicPlaylist): Draft => ({ id: p.id, name: p.name, shuffle: p.shuffle, isDefault: p.is_default, ids: p.track_ids.slice() });

function PlaylistsTab({ d, reload }: { d: MusicOverview; reload: () => Promise<void> }) {
  const [draft, setDraft] = useState<Draft | null>(null);
  const [picking, setPicking] = useState(false);
  const [chosen, setChosen] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const byId = useMemo(() => new Map(d.tracks.map((t) => [t.id, t])), [d.tracks]);
  const saved = draft?.id ? d.playlists.find((p) => p.id === draft.id) : null;

  // keep the open draft in step with the server after a reload (a deleted playlist closes the editor)
  useEffect(() => {
    if (draft?.id && !d.playlists.some((p) => p.id === draft.id)) setDraft(null);
  }, [d.playlists, draft?.id]);

  const dirty = !!draft && (!saved || saved.name !== draft.name.trim() || saved.shuffle !== draft.shuffle || saved.is_default !== draft.isDefault
    || saved.track_ids.join() !== draft.ids.join());
  const total = draft ? draft.ids.reduce((s, id) => s + (byId.get(id)?.duration_ms ?? 0), 0) : 0;
  const unplayable = draft ? draft.ids.filter((id) => { const t = byId.get(id); return !t || t.duration_ms <= 0 || !t.cors_ok; }).length : 0;

  const move = (i: number, by: number) => setDraft((x) => {
    if (!x) return x;
    const j = i + by;
    if (j < 0 || j >= x.ids.length) return x;
    const ids = x.ids.slice();
    [ids[i], ids[j]] = [ids[j], ids[i]];
    return { ...x, ids };
  });

  const save = async () => {
    if (!draft) return;
    setBusy(true);
    try {
      const r = await musicApi.playlistSave(draft.id, draft.name.trim(), draft.shuffle, draft.ids, draft.isDefault);
      toast(r.restarted && draft.id ? 'Saved. The radio clock for this playlist restarted.' : 'Saved.', 'good');
      await reload();
      setDraft((x) => (x ? { ...x, id: r.id, name: x.name.trim() } : x));
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  const del = async () => {
    if (!draft?.id) return;
    try {
      const r = await musicApi.playlistDelete(draft.id);
      toast(r.message, 'good');
      setDraft(null);
      await reload();
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };

  const available = draft ? d.tracks.filter((t) => !draft.ids.includes(t.id)) : [];

  return (
    <div className="adm-music-split">
      <div className="adm-card adm-rows" data-testid="music-playlists">
        <div className="adm-pad"><Btn tone="primary" small onClick={() => { setDraft(blank()); setPicking(false); }}>New playlist</Btn></div>
        {d.playlists.length === 0 && <p className="adm-sub adm-pad">No playlists yet.</p>}
        {d.playlists.map((p) => (
          <button key={p.id} type="button" className={`adm-row adm-row--btn${draft?.id === p.id ? ' is-selected' : ''}`} onClick={() => { setDraft(fromPl(p)); setPicking(false); }}>
            <div className="adm-row__main adm-row__main--static">
              <span className="adm-row__title">{p.name} {p.is_default && <Badge tone="violet">Default</Badge>} {!p.playable && <Badge tone="amber">Not playable</Badge>}</span>
              <span className="adm-row__sub">{p.track_ids.length} track{p.track_ids.length === 1 ? '' : 's'} · {fmtDuration(p.total_ms)}{p.shuffle ? ' · shuffle' : ''}{p.clubs ? ` · ${p.clubs} club${p.clubs === 1 ? '' : 's'}` : ''}{p.events ? ` · ${p.events} event${p.events === 1 ? '' : 's'}` : ''}</span>
            </div>
          </button>
        ))}
      </div>

      {draft ? (
        <div className="adm-card adm-form" data-testid="music-editor">
          <label className="adm-field"><span className="adm-field__label">Playlist name</span>
            <input className="adm-input" aria-label="Playlist name" value={draft.name} maxLength={80} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="e.g. Friday amapiano" /></label>
          <div className="adm-field adm-field--row">
            <span><span className="adm-field__label">Shuffle</span><span className="adm-field__help"> A new random order every loop, the same for everyone.</span></span>
            <Toggle checked={draft.shuffle} label="Shuffle" onChange={(v) => setDraft({ ...draft, shuffle: v })} />
          </div>
          <div className="adm-field adm-field--row">
            <span><span className="adm-field__label">Default for clubs with no playlist</span><span className="adm-field__help"> Only one playlist can be the default.</span></span>
            <Toggle checked={draft.isDefault} label="Default playlist" onChange={(v) => setDraft({ ...draft, isDefault: v })} />
          </div>

          <div>
            <span className="adm-field__label">Tracks ({draft.ids.length}) · loop length {fmtDuration(total)}</span>
            {unplayable > 0 && <p className="adm-field__err">{unplayable} track{unplayable === 1 ? ' needs' : 's need'} measuring (Tracks tab). A playlist with those cannot play yet.</p>}
            <div className="adm-rows adm-music-plist" data-testid="music-playlist-tracks">
              {draft.ids.length === 0 && <p className="adm-sub adm-pad">Empty. Add tracks below.</p>}
              {draft.ids.map((id, i) => {
                const t = byId.get(id);
                return (
                  <div key={id} className="adm-row">
                    <span className="adm-music-n">{i + 1}</span>
                    <div className="adm-row__main adm-row__main--static">
                      <span className="adm-row__title">{t?.title ?? 'Deleted track'}</span>
                      <span className="adm-row__sub">{t?.artist ? `${t.artist} · ` : ''}{t ? fmtDuration(t.duration_ms) : ''}</span>
                    </div>
                    <button type="button" className="adm-iconbtn" aria-label={`Move ${t?.title ?? 'track'} up`} disabled={i === 0} onClick={() => move(i, -1)}>↑</button>
                    <button type="button" className="adm-iconbtn" aria-label={`Move ${t?.title ?? 'track'} down`} disabled={i === draft.ids.length - 1} onClick={() => move(i, 1)}>↓</button>
                    <button type="button" className="adm-iconbtn" aria-label={`Remove ${t?.title ?? 'track'}`} onClick={() => setDraft({ ...draft, ids: draft.ids.filter((x) => x !== id) })}>✕</button>
                  </div>
                );
              })}
            </div>
          </div>

          {picking ? (
            <div className="adm-card adm-music-pick" data-testid="music-picker">
              <span className="adm-field__label">Pick tracks to add</span>
              {available.length === 0 && <p className="adm-sub">Every track is already in this playlist. Upload more on the Tracks tab.</p>}
              {available.map((t) => (
                <label key={t.id} className="adm-check">
                  <input type="checkbox" checked={chosen.includes(t.id)} onChange={(e) => setChosen((c) => (e.target.checked ? [...c, t.id] : c.filter((x) => x !== t.id)))} />
                  <span>{t.title} <span className="adm-sub">{fmtDuration(t.duration_ms)}</span></span>
                </label>
              ))}
              <div className="adm-btnrow">
                <Btn tone="primary" small disabled={!chosen.length} onClick={() => { setDraft({ ...draft, ids: [...draft.ids, ...chosen] }); setChosen([]); setPicking(false); }}>Add {chosen.length || ''} selected</Btn>
                <Btn tone="quiet" small onClick={() => { setChosen([]); setPicking(false); }}>Cancel</Btn>
              </div>
            </div>
          ) : (
            <div><Btn small onClick={() => setPicking(true)}>Add tracks</Btn></div>
          )}

          <p className="adm-field__help">Saving a changed track list or shuffle restarts this playlist's radio clock: players in the club may hear a jump. Renaming does not.</p>
          <div className="adm-btnrow">
            <Btn tone="primary" onClick={() => void save()} disabled={busy || !dirty || !draft.name.trim()}>{busy ? 'Saving...' : draft.id ? 'Save playlist' : 'Create playlist'}</Btn>
            {draft.id && <ConfirmButton onConfirm={del} confirmText="Delete playlist?">Delete</ConfirmButton>}
          </div>
        </div>
      ) : (
        <div className="adm-card"><p className="adm-sub">Pick a playlist on the left, or make a new one.</p></div>
      )}
    </div>
  );
}

// ------------------------------------------------------------------------------------------- places
function PlacesTab({ d, reload }: { d: MusicOverview; reload: () => Promise<void> }) {
  const [busy, setBusy] = useState<string | null>(null);
  const assign = async (kind: 'club' | 'event', id: string, pl: string | null) => {
    setBusy(kind + id);
    try {
      const r = await musicApi.assign(kind, id, pl);
      toast(r.message, 'good');
      await reload();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };
  return (
    <div className="adm-stack">
      <div className="adm-card">
        <h2 className="adm-h2">Clubs</h2>
        <p className="adm-sub">What plays in each club. With no playlist a club uses the default playlist (if you set one), then the single file in Settings, then the game's own amapiano groove.</p>
      </div>
      <div className="adm-card adm-rows" data-testid="music-clubs">
        {d.clubs.map((c) => (
          <div key={c.id} className={`adm-row${c.active ? '' : ' is-off'}`}>
            <div className="adm-row__main adm-row__main--static">
              <span className="adm-row__title">{c.name} {!c.active && <Badge>Closed for now</Badge>}</span>
              <span className="adm-row__sub">{c.id}</span>
            </div>
            <PlaylistSelect label={`Playlist for ${c.name}`} value={c.playlist_id} playlists={d.playlists} disabled={busy === 'club' + c.id}
              onChange={(pl) => void assign('club', c.id, pl)} />
          </div>
        ))}
      </div>
      <div className="adm-card">
        <h2 className="adm-h2">Events</h2>
        <p className="adm-sub">Optional. While an event is LIVE at its club, its playlist plays instead of the club's. Events are made in Content → Events.</p>
      </div>
      <div className="adm-card adm-rows" data-testid="music-events">
        {d.events.length === 0 && <p className="adm-sub adm-pad">No events at clubs yet.</p>}
        {d.events.map((e) => (
          <div key={e.id} className={`adm-row${e.active ? '' : ' is-off'}`}>
            <div className="adm-row__main adm-row__main--static">
              <span className="adm-row__title">{e.icon} {e.title} {!e.active && <Badge>Off</Badge>}</span>
              <span className="adm-row__sub">{e.location_name} · {e.kind}</span>
            </div>
            <PlaylistSelect label={`Playlist for ${e.title}`} value={e.playlist_id} playlists={d.playlists} emptyLabel="Use the club's playlist" disabled={busy === 'event' + e.id}
              onChange={(pl) => void assign('event', e.id, pl)} />
          </div>
        ))}
      </div>
    </div>
  );
}
