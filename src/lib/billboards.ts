// H3 billboards (docs/BILLBOARDS.md): digital boards on the 3D map that rotate player ads.
// Server: 20261012000500_billboards.sql (billboard_list, billboard_ad_create, ...). Payments reuse Paystack
// (src/lib/payments.ts paystackCheckout) with references BLAD-…; the server marks the ad paid only after
// paystack-verify / the webhook checked the exact amount, then an admin approves it.
// No three.js here: the game chunk imports this cheaply; the 3D layer is src/art/city3d/engine/boards.ts.
import { create } from 'zustand';
import { errorMessage, rpc } from './api';
import { serverNow } from './clock';
import { paystackCheckout, paystackReady } from './payments';
import { supabase } from './supabase';

export interface BoardAd {
  id: string;
  image: string;
  link: string | null;
  ends_at: string;
  sponsor: boolean;
  mine: boolean;
}

export interface Board {
  id: string;
  name: string;
  area: string;
  kind: 'mega' | 'standard' | 'local';
  x: number;
  y: number;
  yaw: number;
  prices: Record<'1' | '3' | '7', number>;
  queued: number;
  ads: BoardAd[];
}

export interface BoardsData {
  enabled: boolean;
  buy_enabled: boolean;
  rotate_seconds: number;
  max_ads: number;
  now: string;
  boards: Board[];
}

export interface MyAd {
  id: string;
  board_id: string;
  board: string;
  area: string;
  image: string;
  link: string | null;
  days: number;
  price_kobo: number;
  paid_kobo: number | null;
  status: 'awaiting_payment' | 'pending_review' | 'live' | 'rejected' | 'removed' | 'expired' | 'cancelled';
  starts_at: string | null;
  ends_at: string | null;
  created_at: string;
  reject_reason: string | null;
  refund_status: 'none' | 'pending' | 'processing' | 'refunded' | 'refund_failed';
  views: number;
  taps: number;
  reference: string | null;
}

export const DURATIONS = [1, 3, 7] as const;
export type Duration = (typeof DURATIONS)[number];

/** Public URL of an uploaded ad (paths in the billboard-ads bucket); sponsor ads may hold a full https URL. */
export function adImageUrl(path: string): string {
  if (/^(https?:)?\/\//.test(path) || path.startsWith('/') || path.startsWith('data:')) return path;
  const base = String(import.meta.env.VITE_SUPABASE_URL ?? '').replace(/\/$/, '');
  return `${base}/storage/v1/object/public/billboard-ads/${path.split('/').map(encodeURIComponent).join('/')}`;
}

/** "https://www.shop.com.ng/x" -> "shop.com.ng" (what the Visit button says). */
export function domainOf(url: string | null | undefined): string {
  if (!url) return '';
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return '';
  }
}

/** Same check as the server (bl_billboard_link_ok): https, a real domain, no user@ part. */
export function linkOk(url: string): boolean {
  const u = url.trim();
  if (u.length < 12 || u.length > 300 || u.includes('@')) return false;
  return /^https:\/\/[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,24}(:\d{2,5})?([/?#][^\s<>"'`\\]*)?$/.test(u);
}

/** Which ad of `n` is on air now. Wall clock (server-corrected), so every player sees the same one. */
export function slotNow(rotateSeconds: number, now = serverNow()): number {
  return Math.floor(now / (Math.max(5, rotateSeconds) * 1000));
}
export function adIndexNow(n: number, rotateSeconds: number, now = serverNow()): number {
  return n > 0 ? slotNow(rotateSeconds, now) % n : 0;
}

/* ------------------------------------------------------------------ */
/* House ads (shown when a board is empty): drawn on a canvas, no files */
/* ------------------------------------------------------------------ */
export interface HouseAd {
  id: 'topup' | 'boutique' | 'events' | 'yours';
  kicker: string;
  title: string;
  sub: string;
  cta: string;
  bg: [string, string];
  ink: string;
  accent: string;
  emoji: string;
}

export const HOUSE_ADS: HouseAd[] = [
  { id: 'topup', kicker: 'BENIN LIFE WALLET', title: 'Top up, get up to +75%', sub: 'Bigger packs, bigger bonus. Your bank smiles.', cta: 'Open Wallet', bg: ['#0fa968', '#05673f'], ink: '#ffffff', accent: '#ffd84a', emoji: '💸' },
  { id: 'boutique', kicker: 'BENIN BOUTIQUE', title: 'New drip just landed', sub: 'Owambe fits, Ring Road Atelier and more.', cta: 'Shop now', bg: ['#1f3c88', '#0d1c45'], ink: '#ffffff', accent: '#7fd3ff', emoji: '👗' },
  { id: 'events', kicker: 'TONIGHT IN BENIN', title: 'Who dey go out?', sub: 'Club nights, owambes and shows across the city.', cta: 'See events', bg: ['#7b2ff7', '#3a0ca3'], ink: '#ffffff', accent: '#ff9de2', emoji: '🎉' },
  { id: 'yours', kicker: 'BILLBOARD FOR RENT', title: 'Your ad fit dey here', sub: 'Phone → Billboards · from ₦5,000 a day', cta: 'Book this board', bg: ['#ffd23f', '#f59e0b'], ink: '#1b1b1f', accent: '#1b1b1f', emoji: '📣' },
];

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

/** Draw a house ad filling the canvas (2:1). */
export function drawHouseAd(ctx: CanvasRenderingContext2D, ad: HouseAd, w: number, h: number) {
  const g = ctx.createLinearGradient(0, 0, w, h);
  g.addColorStop(0, ad.bg[0]);
  g.addColorStop(1, ad.bg[1]);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
  // soft rings
  ctx.globalAlpha = 0.14;
  ctx.fillStyle = ad.accent;
  ctx.beginPath();
  ctx.arc(w * 0.86, h * 0.2, h * 0.55, 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(w * 0.08, h * 1.05, h * 0.42, 0, Math.PI * 2);
  ctx.fill();
  ctx.globalAlpha = 1;
  const u = h / 100;
  ctx.textBaseline = 'alphabetic';
  ctx.fillStyle = ad.accent;
  ctx.font = `800 ${7 * u}px system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`;
  ctx.fillText(ad.kicker, 8 * u, 20 * u);
  ctx.fillStyle = ad.ink;
  ctx.font = `900 ${17 * u}px system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`;
  const words = ad.title.split(' ');
  let line = '';
  let y = 43 * u;
  const maxW = w * 0.64;
  for (const word of words) {
    const t = line ? line + ' ' + word : word;
    if (ctx.measureText(t).width > maxW && line) {
      ctx.fillText(line, 8 * u, y);
      line = word;
      y += 18 * u;
    } else line = t;
  }
  ctx.fillText(line, 8 * u, y);
  ctx.globalAlpha = 0.86;
  ctx.font = `600 ${6.4 * u}px system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`;
  ctx.fillText(ad.sub, 8 * u, y + 13 * u, w * 0.66);
  ctx.globalAlpha = 1;
  // CTA pill
  ctx.font = `800 ${6.4 * u}px system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`;
  const cw = ctx.measureText(ad.cta).width + 12 * u;
  roundRect(ctx, 8 * u, 80 * u, cw, 12 * u, 6 * u);
  ctx.fillStyle = ad.accent;
  ctx.fill();
  ctx.fillStyle = ad.bg[1];
  ctx.fillText(ad.cta, 14 * u, 88.4 * u);
  // emoji art
  ctx.font = `${44 * u}px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji",sans-serif`;
  ctx.textAlign = 'center';
  ctx.fillText(ad.emoji, w - 34 * u, 66 * u);
  ctx.textAlign = 'left';
}

const houseUrls = new Map<string, string>();
/** A house ad as an image URL (data URL, cached) for the board sheet carousel. */
export function houseAdUrl(id: HouseAd['id'], w = 800): string {
  const key = `${id}:${w}`;
  const hit = houseUrls.get(key);
  if (hit) return hit;
  const ad = HOUSE_ADS.find((a) => a.id === id) ?? HOUSE_ADS[0];
  const c = document.createElement('canvas');
  c.width = w;
  c.height = w / 2;
  const ctx = c.getContext('2d');
  if (!ctx) return '';
  drawHouseAd(ctx, ad, c.width, c.height);
  const url = c.toDataURL('image/png');
  houseUrls.set(key, url);
  return url;
}

/* ------------------------------------------------------------------ */
/* Store                                                                */
/* ------------------------------------------------------------------ */
interface BoardsStore {
  data: BoardsData | null;
  loadedAt: number;
  loading: boolean;
  error: string | null;
  /** The board sheet (tap a board on the map, or Phone → Billboards). */
  sheet: { board: string; mode: 'view' | 'add' } | null;
  load(force?: boolean): Promise<BoardsData | null>;
  open(board: string, mode?: 'view' | 'add'): void;
  close(): void;
}

let inflight: Promise<BoardsData | null> | null = null;
let lastPoke = 0;

export const useBillboards = create<BoardsStore>((set, get) => ({
  data: null,
  loadedAt: 0,
  loading: false,
  error: null,
  sheet: null,
  load(force = false) {
    const s = get();
    if (!force && s.data && Date.now() - s.loadedAt < 120_000) return Promise.resolve(s.data);
    if (inflight) return inflight;
    set({ loading: true });
    inflight = rpc<BoardsData & { pending_push?: boolean }>('billboard_list')
      .then((d) => {
        set({ data: d, loadedAt: Date.now(), loading: false, error: null });
        if (d.pending_push && Date.now() - lastPoke > 600_000) {
          lastPoke = Date.now();
          pokeAdminPush();
        }
        return d as BoardsData;
      })
      .catch((e) => {
        set({ loading: false, error: errorMessage(e) });
        return get().data;
      })
      .finally(() => {
        inflight = null;
      });
    return inflight;
  },
  open(board, mode = 'view') {
    set({ sheet: { board, mode } });
    void get().load();
  },
  close() {
    set({ sheet: null });
  },
}));

/* ------------------------------------------------------------------ */
/* Counters + report                                                    */
/* ------------------------------------------------------------------ */
const pendingViews = new Map<string, number>();
let viewTimer: number | null = null;

/** The map saw this ad on a board on screen (batched, sent at most once a minute; the server caps it). */
export function noteAdView(adId: string) {
  if (!/^[0-9a-f-]{36}$/.test(adId)) return;
  pendingViews.set(adId, Math.min(10, (pendingViews.get(adId) ?? 0) + 1));
  if (viewTimer == null) {
    viewTimer = window.setTimeout(() => {
      viewTimer = null;
      const batch = Object.fromEntries(pendingViews);
      pendingViews.clear();
      if (Object.keys(batch).length) void rpc('billboard_track', { p_views: batch }).catch(() => {});
    }, 60_000);
  }
}

export function noteAdTap(adId: string) {
  void rpc('billboard_tap', { p_ad: adId }).catch(() => {});
}

/** Ask the server to push any queued admin notifications (it only sends what the database created). */
export function pokeAdminPush() {
  void supabase.functions.invoke('admin-push', { body: {} }).catch(() => {});
}

export async function reportAd(adId: string, reason: string): Promise<string> {
  const r = await rpc<{ reported: boolean; message: string }>('billboard_report', { p_ad: adId, p_reason: reason });
  if (r.reported) pokeAdminPush();
  return r.message;
}

export function loadMyAds(): Promise<MyAd[]> {
  return rpc<MyAd[]>('billboard_my_ads');
}

/* ------------------------------------------------------------------ */
/* Buying an ad                                                         */
/* ------------------------------------------------------------------ */
export const MAX_UPLOAD_BYTES = 1_500_000;

/** Resize to fit 1200×600 (keeps the shape) and compress to WebP (JPEG where WebP can't be made), under ~1.4 MB. */
export async function compressAdImage(file: File): Promise<{ blob: Blob; url: string; width: number; height: number; type: string }> {
  if (!/^image\/(jpeg|png|webp)$/.test(file.type)) throw new Error('Use a JPG, PNG or WebP image.');
  if (file.size > 15_000_000) throw new Error('That image is too big. Pick one under 15 MB.');
  const bmp = await createImageBitmap(file).catch(() => null);
  if (!bmp) throw new Error('That image could not be opened. Try another one.');
  const scale = Math.min(1, 1200 / bmp.width, 600 / bmp.height);
  const w = Math.max(1, Math.round(bmp.width * scale));
  const h = Math.max(1, Math.round(bmp.height * scale));
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const ctx = c.getContext('2d');
  if (!ctx) throw new Error('Your browser could not prepare the image.');
  ctx.drawImage(bmp, 0, 0, w, h);
  bmp.close?.();
  const toBlob = (type: string, q: number) => new Promise<Blob | null>((res) => c.toBlob(res, type, q));
  let type = 'image/webp';
  let q = 0.86;
  let blob = await toBlob(type, q);
  if (!blob || blob.type !== 'image/webp') {
    type = 'image/jpeg';
    blob = await toBlob(type, q);
  }
  while (blob && blob.size > MAX_UPLOAD_BYTES - 100_000 && q > 0.45) {
    q -= 0.1;
    blob = await toBlob(type, q);
  }
  if (!blob) throw new Error('Your browser could not prepare the image.');
  if (blob.size > MAX_UPLOAD_BYTES) throw new Error('That image is still too big after shrinking. Try a simpler one.');
  return { blob, url: URL.createObjectURL(blob), width: w, height: h, type };
}

export type BuyResult =
  | { status: 'paid'; message: string }
  | { status: 'pending'; message: string }
  | { status: 'cancelled' }
  | { status: 'error'; message: string };

/** Upload → create the ad (awaiting payment) → Paystack → server verify (ad becomes pending review). */
export async function buyAd(opts: { board: string; days: Duration; image: Blob; type: string; link: string; userId: string }): Promise<BuyResult> {
  if (!paystackReady()) return { status: 'error', message: 'Ad payments are paused right now. Check back later.' };
  const ext = opts.type === 'image/webp' ? 'webp' : opts.type === 'image/png' ? 'png' : 'jpg';
  const path = `${opts.userId}/${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
  const up = await supabase.storage.from('billboard-ads').upload(path, opts.image, { contentType: opts.type, cacheControl: '31536000', upsert: false });
  if (up.error) return { status: 'error', message: 'Upload failed. Check your connection and try again.' };
  let init: { ad_id: string; reference: string; amount_kobo: number; email: string; currency: string };
  try {
    init = await rpc('billboard_ad_create', { p_board: opts.board, p_days: opts.days, p_image_path: path, p_link: opts.link.trim() });
  } catch (e) {
    void supabase.storage.from('billboard-ads').remove([path]);
    return { status: 'error', message: errorMessage(e) };
  }
  const r = await paystackCheckout(init, { purpose: 'billboard_ad', ad_id: init.ad_id, board: opts.board, days: opts.days });
  if (r === 'cancelled') {
    await rpc('billboard_ad_cancel', { p_ad: init.ad_id }).catch(() => {});
    void supabase.storage.from('billboard-ads').remove([path]);
    return { status: 'cancelled' };
  }
  if ('error' in r) {
    await rpc('billboard_ad_cancel', { p_ad: init.ad_id }).catch(() => {});
    return { status: 'error', message: r.error };
  }
  if (r.ok) return { status: 'paid', message: 'Paid! Your ad goes live as soon as the Benin Life team checks it.' };
  return { status: 'pending', message: 'Payment received. It shows in My ads as soon as Paystack confirms it.' };
}

/** "₦250,000" from kobo. */
export const koboLabel = (k: number) => '₦' + Math.round(k / 100).toLocaleString('en-NG');

/** "Thu, 10 Dec" */
export function shortDate(iso: string | Date): string {
  const d = typeof iso === 'string' ? new Date(iso) : iso;
  return d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'Africa/Lagos' });
}

/** Whole days left (rounded up), 0 when over. */
export function daysLeft(iso: string | null): number {
  if (!iso) return 0;
  return Math.max(0, Math.ceil((new Date(iso).getTime() - serverNow()) / 86_400_000));
}
