// Sim sheet (R4): Profile / Needs / Goals / People / Career / Settings.
// Career is live since V1-3 (shared UI in src/panels/careers/CareerUI.tsx). L1 launch pass: the
// unfinished Skills tab, Perks and Feelings previews are hidden; Wishes are today's D1 daily goals.
// The Profile turntable is the only live 3D view while this sheet is open: Game suspends the 3D home.
import { CharmChips } from './Shrine';
import { YahooBadge } from './Yahoo';
import { useYahoo } from '../../state/yahoo';
import { useCrew } from '../../state/crew';
import { useShrine } from '../../state/shrine';
import { useLiveProfile } from '../../lib/live';
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AvatarPortrait, AvatarStage, migrateAvatar } from '../../art/avatar3d';
import { chatBlocked, chatUnblock } from '../../api/chat';
import { rpc, errorMessage } from '../../lib/api';
import { naira, titleCase } from '../../lib/format';
import { moodOf, needValue } from '../../lib/mood';
import { HUD_NEEDS, NEED_META, ORIGIN_UI, P, WEEKDAYS, originCopy, type NeedKey } from '../../lib/pidgin';
import { usePrefs } from '../../lib/prefs';
import type { AvatarConfig, BlockedPlayer, GameState } from '../../lib/types';
import { useCatalog } from '../../state/catalog';
import { useDaily } from '../../state/daily';
import { useChat } from '../../state/chat';
import { useGame } from '../../state/game';
import { useUi, type SimTab } from '../../state/ui';
import { Button, CrewTag, EmptyState, Logo, Sheet, Switch, Tabs, toast } from '../../ui';
import { SkillsTab } from './Skills';
import { CertificatesCard } from './School';
import LookPanel from '../creator/LookPanel';
import { startTour } from '../../onboarding/tourStore';
import { NotificationsSettings } from './NotificationsSettings';
import { JobCard, PerfBar, Promotion, ShiftStats } from '../../panels/careers/CareerUI';

const TABS: { id: SimTab; label: string }[] = [
  { id: 'profile', label: 'Profile' },
  { id: 'needs', label: 'Needs' },
  { id: 'goals', label: 'Goals' },
  { id: 'skills', label: 'Skills' },
  { id: 'people', label: 'People' },
  { id: 'career', label: 'Career' },
  { id: 'settings', label: 'Settings' },
];

const CAREERS = ['💻 Tech', '🏧 PoS & Fintech', '🛒 Trade', '🛺 Transport', '🩺 Health', '🎓 Education'];

function SheetHead({ state }: { state: GameState }) {
  const p = state.profile;
  const mood = moodOf(p);
  const tier = state.origin?.id ?? p.origin;
  const copy = tier ? originCopy(tier, state.origin?.name ?? tier, state.origin?.tagline ?? '') : null;
  const yahooRank = useYahoo((s) => s.status?.rank);
  const myCrew = useCrew((s) => s.status?.crew ?? null);
  return (
    <div className="sim-head">
      <span className="sim-head__face"><AvatarPortrait config={p.avatar} size={56} /></span>
      <div className="grow">
        <div className="sim-head__name"><CrewTag tag={myCrew?.tag} color={myCrew?.color} emblem={myCrew?.emblem} />{p.username}</div>
        <div className="sim-head__sub">
          <span aria-hidden>{mood.emoji}</span> {mood.label}
          {copy && <span className={`origin-pill origin-pill--${tier === 'nepo' ? 'nepo' : 'lapo'}`}>{copy.emoji} {copy.badge}</span>}
          <YahooBadge rank={yahooRank} />
        </div>
      </div>
    </div>
  );
}

function NeedRow({ k, v }: { k: NeedKey; v: number }) {
  const m = NEED_META[k];
  return (
    <div className="need-row">
      <span className="need-row__icon" style={{ background: `${m.color}1f` }} aria-hidden>{m.emoji}</span>
      <div className="grow">
        <div className="need-row__top">
          <span>{m.label}</span>
          <span className="need-row__val">{Math.round(v)}%</span>
        </div>
        <div className="need-row__track" role="meter" aria-label={m.label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(v)}>
          <span style={{ width: `${v}%`, background: m.color }} />
        </div>
      </div>
    </div>
  );
}

function TraitList({ ids }: { ids: string[] }) {
  const catalog = useCatalog((s) => s.catalog);
  if (!ids.length) return <p className="muted">No traits picked.</p>;
  return (
    <div className="trait-list">
      {ids.map((id) => {
        const t = catalog?.traits.find((x) => x.id === id);
        return (
          <div key={id} className="trait-row">
            <span className="trait-row__emoji" aria-hidden>{t?.emoji ?? '✨'}</span>
            <div>
              <div className="trait-row__name">{t?.name ?? titleCase(id)}</div>
              {t?.description && <div className="trait-row__desc">{t.description}</div>}
            </div>
          </div>
        );
      })}
    </div>
  );
}

/** B2: active charms (and Baba's curses) with time left; hidden when there are none. */
function SimCharms() {
  const charms = useShrine((s) => s.charms);
  if (!charms.length) return null;
  return (
    <section className="sim-card" data-testid="sim-charms">
      <h4 className="sim-card__title">Charms</h4>
      <CharmChips charms={charms} />
    </section>
  );
}

function ProfileTab({ state, onEditLook, onWardrobe }: { state: GameState; onEditLook: () => void; onWardrobe: () => void }) {
  const p = state.profile;
  const catalog = useCatalog((s) => s.catalog);
  const byId = useGame((s) => s.locationsById);
  const dream = catalog?.dreams.find((d) => d.id === p.dream);
  const home = catalog?.homes.find((h) => h.id === p.start_home);
  const homeLoc = byId[p.home_location_id];
  const rentDay = WEEKDAYS[catalog?.rent_weekday ?? 5];
  const openPhone = useUi((s) => s.openPhone);
  const openPanel = useUi((s) => s.openPanel);
  const bagCount = (state.inventory ?? []).reduce((n, i) => n + i.qty, 0);
  return (
    <div className="sim-tab stack">
      <div className="sim-stage">
        <AvatarStage config={p.avatar} className="sim-stage__canvas" />
      </div>
      <div className="sim-field">
        <span className="sim-field__val">@{p.username}</span>
        <span className="sim-field__label">Username</span>
      </div>
      <div className="row" style={{ gap: 8 }}>
        <Button variant="ghost" className="grow" icon="user" onClick={onEditLook}>Edit look</Button>
        <Button variant="ghost" className="grow" onClick={onWardrobe}><span aria-hidden>👗</span> Wardrobe</Button>
      </div>
      <section className="sim-card">
        <h4 className="sim-card__title">Home</h4>
        <div className="sim-home">
          <span className="sim-home__emoji" aria-hidden>{home?.emoji ?? '🏠'}</span>
          <div className="grow">
            <div className="sim-home__name">{home?.name ?? homeLoc?.name ?? 'Your place'}</div>
            <div className="muted sim-home__sub">
              {p.weekly_rent > 0 ? `Rent ${naira(p.weekly_rent)} a week, due every ${rentDay}` : 'No rent to pay'}
              {state.rent && !state.rent.enabled && p.weekly_rent > 0 ? ' (collection paused)' : ''}
            </div>
            {p.rent_owed > 0 && <div className="sim-home__owed">You owe {naira(p.rent_owed)} rent</div>}
          </div>
          <Button size="sm" variant={p.rent_owed > 0 ? 'green' : 'ghost'} onClick={() => openPhone('houses')}>
            {p.rent_owed > 0 ? 'Pay' : 'Rent'}
          </Button>
        </div>
      </section>
      <section className="sim-card">
        <h4 className="sim-card__title">Bag</h4>
        <div className="sim-home">
          <span className="sim-home__emoji" aria-hidden>🎒</span>
          <div className="grow">
            <div className="sim-home__name">{bagCount > 0 ? `${bagCount} ${bagCount === 1 ? 'thing' : 'things'}` : 'Empty'}</div>
            <div className="muted sim-home__sub">{bagCount > 0 ? (state.inventory ?? []).slice(0, 6).map((i) => i.icon || '📦').join(' ') : 'Buy food at markets and bukas, or order on Chowdeck.'}</div>
          </div>
          <Button size="sm" variant="ghost" icon="bag" onClick={() => openPanel('inventory')}>Open</Button>
        </div>
      </section>
      <SimCharms />
      <CertificatesCard />
      <section className="sim-card">
        <h4 className="sim-card__title">Dream</h4>
        {dream ? (
          <div className="sim-home">
            <span className="sim-home__emoji" aria-hidden>{dream.emoji}</span>
            <div className="grow">
              <div className="sim-home__name">{dream.name}</div>
              <div className="muted sim-home__sub">{dream.description}</div>
            </div>
          </div>
        ) : (
          <p className="muted">{p.dream ? titleCase(p.dream) : 'No dream picked yet.'}</p>
        )}
      </section>
      <section className="sim-card">
        <h4 className="sim-card__title">Traits</h4>
        <TraitList ids={p.traits ?? []} />
      </section>
    </div>
  );
}

function NeedsTab({ state }: { state: GameState }) {
  const p = useLiveProfile(state.profile);
  return (
    <div className="sim-tab stack">
      <div className="need-rows">
        {HUD_NEEDS.map((k) => <NeedRow key={k} k={k} v={needValue(p, k)} />)}
      </div>
      <SimCharms />
      <section className="sim-card">
        <h4 className="sim-card__title">Body</h4>
        <div className="need-rows">
          <NeedRow k="health" v={needValue(p, 'health')} />
          <NeedRow k="stress" v={needValue(p, 'stress')} />
        </div>
      </section>
      <section className="sim-card">
        <h4 className="sim-card__title">Traits</h4>
        <TraitList ids={p.traits ?? []} />
      </section>
    </div>
  );
}

function GoalsTab({ state }: { state: GameState }) {
  const p = state.profile;
  const catalog = useCatalog((s) => s.catalog);
  const dream = catalog?.dreams.find((d) => d.id === p.dream);
  const tier = state.origin?.id ?? p.origin;
  const copy = tier ? originCopy(tier, state.origin?.name ?? tier, state.origin?.tagline ?? '') : null;
  return (
    <div className="sim-tab stack">
      <section className="dream-hero">
        <span className="dream-hero__eyebrow">Lifetime dream</span>
        <div className="dream-hero__row">
          <span className="dream-hero__emoji" aria-hidden>{dream?.emoji ?? '🌟'}</span>
          <div>
            <div className="dream-hero__name">{dream?.name ?? 'No dream yet'}</div>
            <div className="dream-hero__desc">{dream?.description ?? 'No dream picked for this life.'}</div>
          </div>
        </div>
      </section>
      {copy && (
        <section className="sim-card origin-card">
          <span className="origin-card__emoji" aria-hidden>{copy.emoji}</span>
          <div>
            <div className="origin-card__title">{copy.title.replace(/!$/, '')}</div>
            <div className="muted">{copy.line}</div>
            {state.origin?.allowance_daily ? (
              <div className="origin-card__perk">{ORIGIN_UI.allowance(naira(state.origin.allowance_daily))}</div>
            ) : (
              <div className="origin-card__perk">Self-made. Every naira you get, you earn 💪</div>
            )}
          </div>
        </section>
      )}
      <Wishes />
    </div>
  );
}

/** L1: Wishes = today's three daily goals from the D1 daily reward + gem hunt (server status). */
function Wishes() {
  const reward = useDaily((s) => s.reward);
  const gems = useDaily((s) => s.gems);
  const load = useDaily((s) => s.load);
  const setSheet = useDaily((s) => s.setSheet);
  const setOverlay = useUi((s) => s.setOverlay);
  useEffect(() => {
    void load();
  }, [load]);
  const rows: { key: string; emoji: string; text: string; done: boolean; prize: string; sheet: 'reward' | 'gems' }[] = [];
  if (reward?.enabled) {
    const today = reward.steps.find((x) => x.state === 'today') ?? reward.next;
    rows.push({ key: 'reward', emoji: '🎁', text: reward.claimed ? "Today's daily reward collected" : "Collect today's daily reward",
      done: reward.claimed, prize: today ? (today.cash ? naira(today.cash) : today.label) : '', sheet: 'reward' });
  }
  if (gems?.enabled && gems.total > 0) {
    rows.push({ key: 'gem1', emoji: '💎', text: 'Find one hidden gem in the city', done: gems.found > 0, prize: naira(gems.prize), sheet: 'gems' });
    rows.push({ key: 'gemall', emoji: '🏆', text: `Find all ${gems.total} gems today (${gems.found}/${gems.total})`, done: gems.found >= gems.total,
      prize: naira(gems.all_bonus), sheet: 'gems' });
  }
  if (!rows.length) return null;
  const open = (sheet: 'reward' | 'gems') => {
    setOverlay(null);
    setSheet(sheet);
  };
  return (
    <section>
      <div className="sim-section-head"><h4>Today's wishes</h4><span className="muted" style={{ fontSize: 12 }}>New ones every day</span></div>
      <div className="ghost-list">
        {rows.map((r) => (
          <button key={r.key} type="button" className={`ghost-row wish-row${r.done ? ' is-done' : ''}`} onClick={() => open(r.sheet)}>
            <span aria-hidden>{r.done ? '✅' : r.emoji}</span>
            <span className="grow">{r.text}</span>
            {r.prize && !r.done && <span className="ghost-row__pts">+{r.prize}</span>}
          </button>
        ))}
      </div>
    </section>
  );
}

function PeopleTab() {
  return (
    <div className="sim-tab stack">
      <EmptyState icon="people" title="Nobody in your circle yet"
        body="Your friends and chats live in the Messages app on your phone. Players you block in chat show below." />
      <BlockedList />
    </div>
  );
}

/** V1-6: players you blocked in chat, with Unblock. */
function BlockedList() {
  const [rows, setRows] = useState<BlockedPlayer[] | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    chatBlocked()
      .then((r) => alive && setRows(r ?? []))
      .catch(() => alive && setRows([]));
    return () => {
      alive = false;
    };
  }, []);
  const unblock = async (b: BlockedPlayer) => {
    setBusy(b.id);
    try {
      const r = await chatUnblock(b.id);
      toast(r.message, 'good');
      setRows((x) => (x ?? []).filter((y) => y.id !== b.id));
      void useChat.getState().reload();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };
  return (
    <section className="sim-card">
      <h4 className="sim-card__title">Blocked in chat</h4>
      {!rows ? (
        <div className="panel-skel"><span /></div>
      ) : rows.length === 0 ? (
        <p className="muted" style={{ fontSize: 13 }}>Nobody. To block someone, tap their message in a chat.</p>
      ) : (
        <div className="blocked-list">
          {rows.map((b) => (
            <div key={b.id} className="blocked-row">
              <span className="blocked-row__face">{b.avatar && <AvatarPortrait config={migrateAvatar(b.avatar)} size={36} />}</span>
              <b className="grow">@{b.username}</b>
              <Button size="sm" variant="ghost" loading={busy === b.id} onClick={() => void unblock(b)}>Unblock</Button>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

function CareerTab({ state }: { state: GameState }) {
  const openPhone = useUi((s) => s.openPhone);
  const career = state.career;
  const job = career?.job ?? null;
  if (!job) {
    return (
      <div className="sim-tab stack">
        <section className="sim-card career-card">
          <span className="career-card__emoji" aria-hidden>🧳</span>
          <div>
            <div className="muted">No job yet</div>
            <div className="career-card__title">Job hunting</div>
            <div className="muted">Pick a track in the Jobs app and climb from the bottom. Every shift pays.</div>
          </div>
        </section>
        <Button variant="green" block icon="bag" onClick={() => openPhone('jobs')}>Find a job</Button>
        <div className="chip-row">
          {CAREERS.map((c) => <span key={c} className="chip">{c}</span>)}
        </div>
        {career?.degree && <p className="muted" style={{ fontSize: 13 }}>🎓 You have a UNIBEN degree. Senior Tech and Health roles are open to you.</p>}
      </div>
    );
  }
  return (
    <div className="sim-tab stack">
      <JobCard job={job} />
      <PerfBar perf={job.perf_now} />
      <Promotion job={job} />
      <ShiftStats job={job} />
      <p className="muted career-where">
        <span aria-hidden>📍</span> Work at {job.locations.map((l) => l.name).join(' · ')}
        {career?.degree ? ' · 🎓 Degree' : ''}
      </p>
      <Button variant="ghost" block icon="bag" onClick={() => openPhone('jobs')}>Open the Jobs app</Button>
    </div>
  );
}

function SettingsTab({ state }: { state: GameState }) {
  const prefs = usePrefs();
  const session = useGame((s) => s.session);
  const signOut = useGame((s) => s.signOut);
  const setOverlay = useUi((s) => s.setOverlay);
  const openPhone = useUi((s) => s.openPhone);
  const nav = useNavigate();
  return (
    <div className="sim-tab">
      <div className="settings-list">
        <Switch label="Sound effects" checked={prefs.sfx && !prefs.muted} onChange={(v) => prefs.set({ sfx: v, muted: v ? false : prefs.muted })} />
        <Switch label="Music" checked={prefs.music && !prefs.muted} onChange={(v) => prefs.set({ music: v, muted: v ? false : prefs.muted })} />
        <Switch label="Lite map for weak network" hint="A lighter 2D map that loads fast on slow or expensive data."
          checked={prefs.liteMap} onChange={(v) => prefs.set({ liteMap: v })} />
        <div className="settings-row">
          <div>
            <div>Graphics</div>
            <div className="muted settings-row__hint">Low is lighter on older phones: no fog or light pools, less clutter.</div>
          </div>
          <div className="seg" role="radiogroup" aria-label="Graphics">
            {(['auto', 'low', 'high'] as const).map((g) => (
              <button key={g} type="button" role="radio" aria-checked={prefs.graphics === g}
                className={`seg__btn${prefs.graphics === g ? ' is-on' : ''}`} onClick={() => prefs.set({ graphics: g })}>
                {g === 'auto' ? 'Auto' : g === 'low' ? 'Low' : 'High'}
              </button>
            ))}
          </div>
        </div>
      </div>
      <NotificationsSettings />
      <h4 className="settings-head">Account</h4>
      <div className="settings-row">
        <div>
          <div>{session?.user.email ?? 'Signed in'}</div>
          <div className="muted settings-row__hint">Your login email</div>
        </div>
      </div>
      <div className="stack" style={{ marginTop: 16 }}>
        <Button variant="ghost" block data-tour="replay-tour" onClick={() => { setOverlay(null); startTour(); }}>🧭 Replay the tour</Button>
        <Button variant="ghost" block onClick={() => openPhone('help')}>🛟 Help and guides</Button>
        <Button variant="ghost" block onClick={() => openPhone('feedback')}>💡 Send feedback or report a bug</Button>
        {state.profile.is_admin && (
          <Button variant="gold" icon="crown" block onClick={() => nav('/admin')}>Open admin panel</Button>
        )}
        <Button variant="ghost" icon="logout" block onClick={() => { setOverlay(null); void signOut(); }}>{P.logout}</Button>
      </div>
      <div className="settings-brand"><Logo variant="full" size={44} /></div>
      <p className="hint settings-foot"><span className="age-badge">18+</span> {P.ageNote}</p>
      <p className="hint settings-legal">
        <span className="beta-badge">Beta</span>
        <a href="/terms" target="_blank" rel="noopener">Terms of Service</a>
        <span aria-hidden>·</span>
        <a href="/privacy" target="_blank" rel="noopener">Privacy Policy</a>
      </p>
    </div>
  );
}

export function SimSheet({ state }: { state: GameState }) {
  const overlay = useUi((s) => s.overlay);
  const rawTab = useUi((s) => s.simTab);
  const openSim = useUi((s) => s.openSim);
  const setOverlay = useUi((s) => s.setOverlay);
  const loadCatalog = useCatalog((s) => s.loadCatalog);
  const open = overlay === 'sim';
  const tab = TABS.some((t) => t.id === rawTab) ? rawTab : 'profile';

  useEffect(() => {
    if (open) void loadCatalog();
  }, [open, loadCatalog]);

  return (
    <Sheet open={open} onClose={() => setOverlay(null)} size="tall" className="sim-sheet"
      header={
        <div className="sim-sheet__head">
          <SheetHead state={state} />
          <Tabs value={tab} onChange={(t) => openSim(t as SimTab)} tabs={TABS} className="sim-tabs" tourPrefix="sim-tab" />
        </div>
      }>
      {tab === 'profile' && <ProfileTab state={state} onEditLook={() => setOverlay('look')} onWardrobe={() => setOverlay('boutique')} />}
      {tab === 'needs' && <NeedsTab state={state} />}
      {tab === 'goals' && <GoalsTab state={state} />}
      {tab === 'skills' && <SkillsTab />}
      {tab === 'people' && <PeopleTab />}
      {tab === 'career' && <CareerTab state={state} />}
      {tab === 'settings' && <SettingsTab state={state} />}
    </Sheet>
  );
}

/** "Edit look": the creator's look editor on a live turntable; saves with update_avatar. */
export function LookSheet({ state }: { state: GameState }) {
  const overlay = useUi((s) => s.overlay);
  const openSim = useUi((s) => s.openSim);
  const refresh = useGame((s) => s.refresh);
  const open = overlay === 'look';
  const [draft, setDraft] = useState<AvatarConfig>(state.profile.avatar);
  const [wasOpen, setWasOpen] = useState(open);
  const [saving, setSaving] = useState(false);
  if (open !== wasOpen) {
    setWasOpen(open);
    if (open) setDraft(state.profile.avatar);
  }
  const dirty = JSON.stringify(draft) !== JSON.stringify(state.profile.avatar);
  const back = () => openSim('profile');

  const save = async () => {
    setSaving(true);
    try {
      const r = await rpc<{ message: string }>('update_avatar', { p_avatar: { ...draft, gender: draft.gender } });
      toast(r.message, 'good');
      await refresh();
      back();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Sheet open={open} onClose={back} size="tall" className="look-sheet" title="Edit look" subtitle="Hair, face and body. Clothes are in the Benin Boutique."
      footer={
        <div className="row" style={{ gap: 8 }}>
          <Button variant="ghost" onClick={back}>Cancel</Button>
          <Button variant="green" block loading={saving} disabled={!dirty} onClick={() => void save()}>
            {dirty ? 'Save look' : 'No changes yet'}
          </Button>
        </div>
      }>
      {open && (
        <div className="look-sheet__body">
          <div className="look-sheet__stage">
            <AvatarStage config={draft} className="look-sheet__canvas" />
          </div>
          <LookPanel avatar={draft} onAvatar={setDraft} identityOnly />
        </div>
      )}
    </Sheet>
  );
}

