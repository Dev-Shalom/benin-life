import { useEffect, useState } from 'react';
import { storylineChoose, storylineCurrent, type StorylineState } from '../../../api/storylines';
import { errorMessage } from '../../../lib/api';
import { useGame } from '../../../state/game';
import { Button, EmptyState, toast } from '../../../ui';

export default function StoriesApp() {
  const refresh = useGame((s) => s.refresh);
  const [story, setStory] = useState<StorylineState | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const load = () => storylineCurrent().then((s) => { setStory(s); setError(''); }).catch((e) => setError(errorMessage(e)));
  useEffect(() => { void load(); }, []);
  const choose = async (id: string) => {
    setBusy(true);
    try { const r = await storylineChoose(id); setStory(r.story); toast(r.message, 'good'); await refresh(); }
    catch (e) { toast(errorMessage(e), 'bad'); void load(); }
    finally { setBusy(false); }
  };
  return <div className="phone-app__body stories-app">
    <p className="phone-app__lead">One Benin Life community story each week. Your choice can affect your Sim’s needs and reputation.</p>
    {error && <p className="error-text">{error}</p>}
    {!story && !error && <div className="panel-skel"><span /><span /></div>}
    {story && !story.enabled && <EmptyState icon="sparkle" title="Stories are paused" body="Check back for next week’s story." />}
    {story?.episode && <article className="story-card">
      <span className="story-card__eyebrow">THIS WEEK · {story.week_start}</span>
      <h3>{story.episode.title}</h3><p>{story.episode.summary}</p>
      {story.choice ? <div className="story-card__result"><b>Your choice</b><p>{story.choice.result.reply}</p></div>
        : <div className="story-card__choices">{story.episode.choices.map((c) => <Button key={c.id} block variant="green" disabled={busy} onClick={() => void choose(c.id)}>{c.label}</Button>)}</div>}
      <small>Story scenes are fictional and for gameplay. They are not legal advice or a statement of current law.</small>
    </article>}
  </div>;
}
