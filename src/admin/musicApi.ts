// M1 club music: admin RPC wrappers + browser-side helpers (duration, CORS probe, upload to the club-music bucket).
// Every RPC is admin-guarded server-side (supabase/migrations/20261017000500_club_music.sql); the bucket only
// accepts writes from admins (Storage policies).
import { rpc } from '../lib/api';
import { supabase } from '../lib/supabase';

export interface MusicTrack {
  id: string; title: string; artist: string; url: string; storage_path: string | null; duration_ms: number;
  size_bytes: number | null; cors_ok: boolean; created_at: string; used_in: number;
}
export interface MusicPlaylist {
  id: string; name: string; shuffle: boolean; is_default: boolean; anchor: string; playable: boolean; total_ms: number;
  track_ids: string[]; clubs: number; events: number;
}
export interface MusicClub { id: string; name: string; active: boolean; playlist_id: string | null }
export interface MusicEvent { id: string; title: string; icon: string; kind: string; active: boolean; location_id: string; location_name: string; playlist_id: string | null }
export interface MusicOverview { tracks: MusicTrack[]; playlists: MusicPlaylist[]; clubs: MusicClub[]; events: MusicEvent[]; setting_url: string | null }
type Msg = { message: string };

export const musicApi = {
  overview: () => rpc<MusicOverview>('admin_music_overview'),
  trackAdd: (t: { title: string; artist: string; url: string; storagePath: string | null; durationMs: number; size: number | null; corsOk: boolean }) =>
    rpc<MusicTrack>('admin_music_track_add', {
      p_title: t.title, p_artist: t.artist, p_url: t.url, p_storage_path: t.storagePath, p_duration_ms: t.durationMs, p_size: t.size, p_cors_ok: t.corsOk,
    }),
  trackUpdate: (id: string, patch: { title?: string; artist?: string; durationMs?: number; corsOk?: boolean }) =>
    rpc<MusicTrack & { playlists_restarted: number }>('admin_music_track_update', {
      p_id: id, p_title: patch.title ?? null, p_artist: patch.artist ?? null, p_duration_ms: patch.durationMs ?? null, p_cors_ok: patch.corsOk ?? null,
    }),
  trackDelete: (id: string) => rpc<Msg & { storage_path: string | null; playlists_restarted: number }>('admin_music_track_delete', { p_id: id }),
  playlistSave: (id: string | null, name: string, shuffle: boolean, tracks: string[], isDefault: boolean | null) =>
    rpc<{ id: string; restarted: boolean }>('admin_music_playlist_save', { p_id: id, p_name: name, p_shuffle: shuffle, p_tracks: tracks, p_default: isDefault }),
  playlistDelete: (id: string) => rpc<Msg>('admin_music_playlist_delete', { p_id: id }),
  assign: (kind: 'club' | 'event', id: string, playlist: string | null) => rpc<Msg>('admin_music_assign', { p_kind: kind, p_id: id, p_playlist: playlist }),
};

export const MAX_BYTES = 30 * 1024 * 1024;
export const AUDIO_EXT = ['mp3', 'm4a', 'ogg', 'oga', 'wav', 'aac', 'webm'];
export const ACCEPT = 'audio/mpeg,audio/mp4,audio/ogg,audio/x-m4a,audio/aac,audio/wav,.mp3,.m4a,.ogg,.oga,.wav,.aac';

const extOf = (name: string) => (name.split('.').pop() ?? '').toLowerCase();
export const isAudioFile = (f: File) => AUDIO_EXT.includes(extOf(f.name));

/** "my_song-final.mp3" -> "my song-final" (the artist is optional and typed by hand). */
export function titleFromFilename(name: string): string {
  const base = name.replace(/\.[A-Za-z0-9]{2,5}$/, '').replace(/[_]+/g, ' ').replace(/\s+/g, ' ').trim();
  return (base || 'Untitled').slice(0, 120);
}

const MIME: Record<string, string> = { mp3: 'audio/mpeg', m4a: 'audio/mp4', ogg: 'audio/ogg', oga: 'audio/ogg', wav: 'audio/wav', aac: 'audio/aac', webm: 'audio/webm' };
export const mimeOf = (f: File) => (f.type && f.type.startsWith('audio/') ? f.type : MIME[extOf(f.name)] ?? 'audio/mpeg');

export function fmtDuration(ms: number): string {
  if (!ms || ms < 0) return '-:--';
  const s = Math.round(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

/** Track length in ms, measured in this browser (audio element first, decodeAudioData for files that report no length). */
export async function measureDuration(src: File | string): Promise<number> {
  const url = typeof src === 'string' ? src : URL.createObjectURL(src);
  try {
    const viaElement = await new Promise<number>((resolve) => {
      const a = new Audio();
      a.preload = 'metadata';
      if (typeof src === 'string') a.crossOrigin = 'anonymous';
      const done = (v: number) => { a.removeAttribute('src'); a.load(); resolve(v); };
      const t = window.setTimeout(() => done(0), 15000);
      a.onloadedmetadata = () => { window.clearTimeout(t); done(Number.isFinite(a.duration) ? Math.round(a.duration * 1000) : 0); };
      a.onerror = () => { window.clearTimeout(t); done(0); };
      a.src = url;
    });
    if (viaElement > 0) return viaElement;
    // some files (streams, odd containers) report Infinity: decode it for the real length
    const buf = typeof src === 'string' ? await (await fetch(src)).arrayBuffer() : await src.arrayBuffer();
    const ctx = new OfflineAudioContext(1, 1, 44100);
    const audio = await ctx.decodeAudioData(buf);
    return Math.round(audio.duration * 1000);
  } catch {
    return 0;
  } finally {
    if (typeof src !== 'string') URL.revokeObjectURL(url);
  }
}

/** Can another site (the game) read this file? WebAudio routing needs CORS headers. */
export async function probeCors(url: string): Promise<boolean> {
  try {
    const r = await fetch(url, { mode: 'cors', headers: { Range: 'bytes=0-0' } });
    try { await r.body?.cancel(); } catch { /* ignore */ }
    return r.ok || r.status === 206;
  } catch {
    return false;
  }
}

export function publicUrl(path: string): string {
  return supabase.storage.from('club-music').getPublicUrl(path).data.publicUrl;
}

const safeId = () => (typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`);

/** Upload one file to the bucket and register it. Throws a plain-English Error. */
export async function uploadTrack(file: File, title: string, artist: string, onStep?: (s: string) => void): Promise<MusicTrack> {
  if (!isAudioFile(file)) throw new Error('Only MP3, M4A, OGG or WAV files.');
  if (file.size > MAX_BYTES) throw new Error(`Too big (${(file.size / 1048576).toFixed(1)} MB). The limit is 30 MB.`);
  onStep?.('Reading length');
  const durationMs = await measureDuration(file);
  if (durationMs < 1000) throw new Error('Could not read the length of this file. Is it a broken or unsupported file?');
  onStep?.('Uploading');
  const path = `${safeId()}.${extOf(file.name) === 'oga' ? 'ogg' : extOf(file.name)}`;
  const up = await supabase.storage.from('club-music').upload(path, file, { contentType: mimeOf(file), cacheControl: '31536000', upsert: false });
  if (up.error) throw new Error('Upload failed: ' + up.error.message);
  onStep?.('Saving');
  try {
    return await musicApi.trackAdd({ title, artist, url: publicUrl(path), storagePath: path, durationMs, size: file.size, corsOk: true });
  } catch (e) {
    void supabase.storage.from('club-music').remove([path]);
    throw e;
  }
}

export async function removeFromBucket(path: string | null): Promise<boolean> {
  if (!path) return true;
  const r = await supabase.storage.from('club-music').remove([path]);
  return !r.error;
}
