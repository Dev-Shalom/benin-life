import { useEffect, useRef, useState } from 'react';
import { Icon } from './Icon';

function label(seconds: number) {
  if (!Number.isFinite(seconds) || seconds < 0) return '0:00';
  return `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, '0')}`;
}

/** Private, download-button-free voice playback with an explicit playback-speed control. */
export function VoicePlayer({ src, mine = false, title = 'Voice message' }: { src: string; mine?: boolean; title?: string }) {
  const audio = useRef<HTMLAudioElement>(null);
  const [playing, setPlaying] = useState(false);
  const [duration, setDuration] = useState(0);
  const [position, setPosition] = useState(0);
  const [rate, setRate] = useState(1);

  useEffect(() => {
    const el = audio.current;
    if (!el) return;
    el.playbackRate = rate;
  }, [rate]);

  const toggle = async () => {
    const el = audio.current;
    if (!el) return;
    if (el.paused) {
      try { await el.play(); } catch { setPlaying(false); }
    } else el.pause();
  };

  return (
    <div className={`voice-player${mine ? ' is-mine' : ''}`} aria-label={title} onClick={(event) => event.stopPropagation()}>
      <audio ref={audio} src={src} preload="none" controlsList="nodownload noplaybackrate noremoteplayback"
        onContextMenu={(event) => event.preventDefault()}
        onLoadedMetadata={(event) => setDuration(Number.isFinite(event.currentTarget.duration) ? event.currentTarget.duration : 0)}
        onDurationChange={(event) => setDuration(Number.isFinite(event.currentTarget.duration) ? event.currentTarget.duration : 0)}
        onTimeUpdate={(event) => setPosition(event.currentTarget.currentTime)}
        onPlay={() => setPlaying(true)} onPause={() => setPlaying(false)} onEnded={() => { setPlaying(false); setPosition(0); }} />
      <button type="button" className="voice-player__play" onClick={() => void toggle()} aria-label={playing ? 'Pause voice message' : 'Play voice message'}>
        <Icon name={playing ? 'pause' : 'play'} size={17} />
      </button>
      <div className="voice-player__track">
        <input type="range" min={0} max={duration || 1} step={0.05} value={Math.min(position, duration || 1)}
          aria-label="Voice message position" onChange={(event) => {
            const next = Number(event.target.value);
            if (audio.current) audio.current.currentTime = next;
            setPosition(next);
          }} />
        <span>{label(position)} / {label(duration)}</span>
      </div>
      <select className="voice-player__speed" value={rate} aria-label="Playback speed" onChange={(event) => setRate(Number(event.target.value))}>
        {[0.75, 1, 1.25, 1.5, 2].map((speed) => <option key={speed} value={speed}>{speed}×</option>)}
      </select>
    </div>
  );
}
