// Sim sheet (R4): Profile / Needs / Goals / Skills / People / Career / Settings.
// Career is live since V1-3 (shared UI in src/panels/careers/CareerUI.tsx). Skills, people, wishes,
// perks and feelings arrive later; their tabs preview the layout.
// The Profile turntable is the only live 3D view while this sheet is open: Game suspends the 3D home.
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
import { useChat } from '../../state/chat';
import { useGame } from '../../state/game';
import { useUi, type SimTab } from '../../state/ui';
import { Button, EmptyState, Sheet, Switch, Tabs, toast } from '../../ui';
import LookPanel from '../creator/LookPanel';
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

const SKILLS = [
  { id: 'cooking', name: 'Cooking', emoji: '🍳' },
  { id: 'charisma', name: 'Charisma', emoji: '😎' },
  { id: 'fitness', name: 'Fitness', emoji: '💪' },
  { id: 'coding', name: 'Coding', emoji: '💻' },
  { id: 'music', name: 'Music', emoji: '🎶' },
  { id: 'hustle', name: 'Hustle', emoji: '💼' },
  { id: 'dance', name: 'Dance', emoji: '💃' },
  { id: 'comedy', name: 'Comedy', emoji: '🎭' },
  { id: 'bronze', name: 'Bronze casting', emoji: '🗿' },
];

const PERKS = [
  { name: 'Big Belly', emoji: '🍲', text: 'Hunger drops 25% slower.' },
  { name: 'Tank Bladder', emoji: '🚽', text: 'Bladder drops 30% slower.' },
  { name: 'Morning Person', emoji: '🌅', text: 'Energy drops 25% slower.' },
  { name: 'Life of the Party', emoji: '🎉', text: 'Fun drops 25% slower.' },
];

const CAREERS = ['💻 Tech', '🏧 PoS & Fintech', '🛒 Trade', '🛺 Transport', '🩺 Health', '🎓 Education'];

function SheetHead({ state }: { state: GameState }) {
  const p = state.profile;
  const mood = moodOf(p);
  const tier = state.origin?.id ?? p.origin;
  const copy = tier ? originCopy(tier, state.origin?.name ?? tier, state.origin?.tagline ?? '') : null;
  return (
    <div className="sim-head">
      <span className="sim-head__face"><AvatarPortrait config={p.avatar} size={56} /></span>
      <div className="grow">
        <div className="sim-head__name">{p.username}</div>
        <div className="sim-head__sub">
          <span aria-hidden>{mood.emoji}</span> {mood.label}
          {copy && <span className={`origin-pill origin-pill--${tier === 'nepo' ? 'nepo' : 'lapo'}`}>{copy.emoji} {copy.badge}</span>}
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

function ProfileTab({ state, onEditLook }: { state: GameState; onEditLook: () => void }) {
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
      <Button variant="ghost" block icon="user" onClick={onEditLook}>Edit look</Button>
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
            <div className="muted sim-home__sub">{bagCount > 0 ? (state.inventory ?? []).slice(0, 6).map((i) => i.icon || '📦').join(' ') : 'Buy food at markets and bukas, or order on ChopNow.'}</div>
          </div>
          <Button size="sm" variant="ghost" icon="bag" onClick={() => openPanel('inventory')}>Open</Button>
        </div>
      </section>
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
      <section className="sim-card">
        <h4 className="sim-card__title">Body</h4>
        <div className="need-rows">
          <NeedRow k="health" v={needValue(p, 'health')} />
          <NeedRow k="stress" v={needValue(p, 'stress')} />
        </div>
      </section>
      <section className="soon-card">
        <span className="soon-card__emoji" aria-hidden>💭</span>
        <div>
          <div className="soon-card__title">Feelings arrive soon</div>
          <div className="soon-card__text">Good nights out, fine homes and bad days will leave feelings that lift or sink your mood.</div>
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
            <div className="dream-hero__desc">{dream?.description ?? 'Older Sims can pick a lifetime dream in a coming update.'}</div>
          </div>
        </div>
        <div className="dream-hero__bar"><span style={{ width: '0%' }} /></div>
        <div className="dream-hero__pct">Progress tracking starts soon · 0%</div>
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
      <section>
        <div className="sim-section-head"><h4>Wishes</h4><span className="soon-pill">Coming soon</span></div>
        <div className="ghost-list">
          {[['🍲', 'Eat at a buka you have never tried'], ['⚽', 'Watch a match at the viewing centre'], ['🗿', 'Visit the bronze casters on Igun Street']].map(([e, t]) => (
            <div key={t} className="ghost-row"><span aria-hidden>{e}</span><span className="grow">{t}</span><span className="ghost-row__pts">+3 ✨</span></div>
          ))}
        </div>
      </section>
      <section>
        <div className="sim-section-head"><h4>Perks</h4><span className="soon-pill">Coming soon</span></div>
        <div className="perk-grid">
          {PERKS.map((k) => (
            <div key={k.name} className="perk-card">
              <span className="perk-card__emoji" aria-hidden>{k.emoji}</span>
              <div className="perk-card__name">{k.name}</div>
              <div className="perk-card__text">{k.text}</div>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}

function SkillsTab() {
  return (
    <div className="sim-tab stack">
      <p className="soon-banner"><span aria-hidden>📚</span> Skills start growing in the next update. Everyone begins at level 1.</p>
      {SKILLS.map((s) => (
        <div key={s.id} className="skill-row">
          <div className="skill-row__top"><span><span aria-hidden>{s.emoji}</span> {s.name}</span><span className="skill-row__lvl">Level 1</span></div>
          <div className="skill-row__segs" aria-label={`${s.name} level 1 of 10`}>
            {Array.from({ length: 10 }, (_, i) => <span key={i} className={i < 1 ? 'is-on' : undefined} />)}
          </div>
        </div>
      ))}
    </div>
  );
}

function PeopleTab() {
  return (
    <div className="sim-tab stack">
      <EmptyState icon="people" title="Nobody in your circle yet"
        body="Friends, neighbours, colleagues and rivals will show up here with how close you are. Relationships arrive in the next update." />
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
  const nav = useNavigate();
  return (
    <div className="sim-tab">
      <div className="settings-list">
        <Switch label="Sound effects" checked={prefs.sfx && !prefs.muted} onChange={(v) => prefs.set({ sfx: v, muted: v ? false : prefs.muted })} />
        <Switch label="Music" checked={prefs.music && !prefs.muted} onChange={(v) => prefs.set({ music: v, muted: v ? false : prefs.muted })} />
        <Switch label="Lite map for weak network" hint="A lighter 2D map that loads fast on slow or expensive data."
          checked={prefs.liteMap} onChange={(v) => prefs.set({ liteMap: v })} />
      </div>
      <h4 className="settings-head">Notifications</h4>
      <div className="settings-row is-disabled">
        <div>
          <div>Messages and alerts</div>
          <div className="muted settings-row__hint">Phone notifications are coming soon.</div>
        </div>
        <span className="soon-pill">Soon</span>
      </div>
      <h4 className="settings-head">Account</h4>
      <div className="settings-row">
        <div>
          <div>{session?.user.email ?? 'Signed in'}</div>
          <div className="muted settings-row__hint">Your login email</div>
        </div>
      </div>
      <div className="stack" style={{ marginTop: 16 }}>
        {state.profile.is_admin && (
          <Button variant="gold" icon="crown" block onClick={() => nav('/admin')}>Open admin panel</Button>
        )}
        <Button variant="ghost" icon="logout" block onClick={() => { setOverlay(null); void signOut(); }}>{P.logout}</Button>
      </div>
      <p className="hint settings-foot"><span className="age-badge">18+</span> {P.ageNote}</p>
    </div>
  );
}

export function SimSheet({ state }: { state: GameState }) {
  const overlay = useUi((s) => s.overlay);
  const tab = useUi((s) => s.simTab);
  const openSim = useUi((s) => s.openSim);
  const setOverlay = useUi((s) => s.setOverlay);
  const loadCatalog = useCatalog((s) => s.loadCatalog);
  const open = overlay === 'sim';

  useEffect(() => {
    if (open) void loadCatalog();
  }, [open, loadCatalog]);

  return (
    <Sheet open={open} onClose={() => setOverlay(null)} size="tall" className="sim-sheet"
      header={
        <div className="sim-sheet__head">
          <SheetHead state={state} />
          <Tabs value={tab} onChange={(t) => openSim(t as SimTab)} tabs={TABS} className="sim-tabs" />
        </div>
      }>
      {tab === 'profile' && <ProfileTab state={state} onEditLook={() => setOverlay('look')} />}
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
    <Sheet open={open} onClose={back} size="tall" className="look-sheet" title="Edit look" subtitle="Change anything. Save when you like it."
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
          <LookPanel avatar={draft} onAvatar={setDraft} />
        </div>
      )}
    </Sheet>
  );
}

