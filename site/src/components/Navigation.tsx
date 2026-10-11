import { useEffect, useState } from 'react';

export const CHAPTERS = [
  ['hero', 'Intro'], ['problem', 'Problem'], ['idea', 'Idea'], ['signals', 'Signals'], ['demo', 'Demo'], ['teens', 'Teens'],
  ['rideshare', 'Rideshare'], ['research', 'Research'], ['trust', 'Trust'], ['landscape', 'Landscape'], ['roadmap', 'Roadmap'], ['close', 'Close'],
] as const;

const go = (id: string) => {
  const el = document.getElementById(id); if (!el) return;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  el.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
  history.replaceState(null, '', `#${id}`);
};

export function Navigation() {
  const [active, setActive] = useState(0);
  const [progress, setProgress] = useState(0);
  const [present, setPresent] = useState(false);

  useEffect(() => {
    const onScroll = () => {
      const h = document.documentElement;
      setProgress(Math.min(1, h.scrollTop / Math.max(1, h.scrollHeight - h.clientHeight)));
      const line = 120;
      let idx = 0;
      CHAPTERS.forEach(([id], i) => { const el = document.getElementById(id); if (el && el.getBoundingClientRect().top <= line) idx = i; });
      setActive(idx);
    };
    onScroll();
    const h0 = location.hash.slice(1); if (h0) requestAnimationFrame(() => document.getElementById(h0)?.scrollIntoView());
    addEventListener('scroll', onScroll, { passive: true });
    return () => removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => { document.body.classList.toggle('present', present); }, [present]);

  useEffect(() => {
    if (!present) return;
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement;
      if (t.closest('input, textarea, select, [role="tab"], [role="switch"]')) return;
      if (e.key === 'Escape') setPresent(false);
      else if (e.key === 'ArrowRight') { e.preventDefault(); go(CHAPTERS[Math.min(CHAPTERS.length - 1, active + 1)][0]); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); go(CHAPTERS[Math.max(0, active - 1)][0]); }
    };
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  }, [present, active]);

  return (
    <>
      <a className="skip" href="#main">Skip to content</a>
      <header className="topbar">
        <div className="progress" style={{ transform: `scaleX(${progress})` }} aria-hidden="true" />
        <a className="brand" href="#hero" onClick={(e) => { e.preventDefault(); go('hero'); }}>
          <span className="brand-mark" aria-hidden="true" />CURBSIDE
        </a>
        <nav aria-label="Chapters" className="chapters">
          <ol>
            {CHAPTERS.map(([id, label], i) => (
              <li key={id}><a href={`#${id}`} aria-current={i === active ? 'true' : undefined} onClick={(e) => { e.preventDefault(); go(id); }}>
                <span className="num">{String(i + 1).padStart(2, '0')}</span> {label}</a></li>
            ))}
          </ol>
        </nav>
        <button className="btn tonal small" aria-pressed={present} onClick={() => setPresent((p) => !p)}>
          {present ? 'Exit present' : 'Present'}
        </button>
      </header>
      {present && (
        <div className="present-bar" role="toolbar" aria-label="Presentation controls">
          <button className="icon-btn" aria-label="Previous chapter" disabled={active === 0} onClick={() => go(CHAPTERS[active - 1][0])}>‹</button>
          <span className="mono" aria-live="polite">{String(active + 1).padStart(2, '0')} / {CHAPTERS.length} · {CHAPTERS[active][1]}</span>
          <button className="icon-btn" aria-label="Next chapter" disabled={active === CHAPTERS.length - 1} onClick={() => go(CHAPTERS[active + 1][0])}>›</button>
          <button className="icon-btn" aria-label="Exit presentation mode (Escape)" onClick={() => setPresent(false)}>✕</button>
        </div>
      )}
    </>
  );
}
export { go as scrollToChapter };
