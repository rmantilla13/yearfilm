'use client'

import { useEffect, useRef, useState } from 'react'

// A year told in four beats beside a phone that's pinned while you scroll: the screen changes
// with the beat in view, and the year's grid fills in as you go. All illustration, no footage.

type Beat = { eyebrow: string; title: string; body: string }

const BEATS: Beat[] = [
  {
    eyebrow: 'Sunday evening',
    title: 'A nudge, with one shot to try.',
    body: 'Not “upload your videos” — a shot list. The first snow, someone’s face watching the candles, the walk there instead of the arrival. One idea a week, so the film has moments worth keeping.',
  },
  {
    eyebrow: 'Any day that week',
    title: 'Add a few clips. Say what happened.',
    body: 'Pick clips from your library and record twenty seconds: what happened this week? By December, those notes are the narration — the story told by the people who lived it.',
  },
  {
    eyebrow: 'All year',
    title: 'Watch the weeks light up.',
    body: 'Every filmed week glows. Already filmed half the year? Bring it all in at once — each clip goes to the week it was filmed, and duplicates are skipped.',
  },
  {
    eyebrow: 'Whenever you’re curious',
    title: 'A rough cut of your year, so far.',
    body: 'Cut right on your phone: chapters by season, vertical clips framed for the TV, your voice over the montage. A preview of premiere night, any night you like.',
  },
]

// The sample year the grid fills toward. Week 43 is "now".
const NOW = 43
const FILMED = [1, 2, 3, 5, 6, 7, 9, 10, 11, 14, 16, 18, 20, 21, 23, 25, 26, 28, 31, 32, 33, 35, 36, 38, 40, 41, 42, 43]
const TINTS = ['#6f9fd8', '#5fc4bd', '#8fd6ff', '#8f9de6', '#bfb0ff']

export function YearStory() {
  const [beat, setBeat] = useState(0)
  const [progress, setProgress] = useState(1)
  const section = useRef<HTMLElement>(null)
  const steps = useRef<(HTMLDivElement | null)[]>([])

  useEffect(() => {
    const still = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    // The beat whose text crosses the middle of the screen is the one the phone shows.
    const watch = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) setBeat(Number((e.target as HTMLElement).dataset.beat))
        }
      },
      { rootMargin: '-45% 0px -45% 0px' },
    )
    steps.current.forEach((s) => s && watch.observe(s))

    // How far through the story we are, for the grid filling in. Held full when motion is off.
    let frame = 0
    const measure = () => {
      frame = 0
      const el = section.current
      if (!el || still) return setProgress(1)
      const r = el.getBoundingClientRect()
      const span = r.height - window.innerHeight
      setProgress(Math.min(1, Math.max(0, -r.top / Math.max(span, 1))))
    }
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(measure)
    }
    measure()
    window.addEventListener('scroll', onScroll, { passive: true })
    window.addEventListener('resize', onScroll)
    return () => {
      watch.disconnect()
      cancelAnimationFrame(frame)
      window.removeEventListener('scroll', onScroll)
      window.removeEventListener('resize', onScroll)
    }
  }, [])

  // The grid starts filling on the third beat and is complete by the end of it.
  const lit = Math.round(FILMED.length * Math.min(1, Math.max(0, (progress - 0.35) / 0.35)))
  const scenes = [<Nudge key="0" />, <Week key="1" />, <Grid key="2" lit={lit} />, <RoughCut key="3" />]

  return (
    <section ref={section} className="story" id="how" aria-label="How a year of Yearfilm goes">
      <div className="story-stage" aria-hidden="true">
        <div className="phone">
          <div className="phone-screen">
            {scenes.map((scene, i) => (
              <Scene key={i} on={beat === i}>{scene}</Scene>
            ))}
          </div>
        </div>
        <ol className="story-dots">
          {BEATS.map((b, i) => (
            <li key={b.title} className={i === beat ? 'on' : undefined} />
          ))}
        </ol>
      </div>
      <div className="story-steps">
        {BEATS.map((b, i) => (
          <div
            key={b.title}
            className={`story-step${i === beat ? ' on' : ''}`}
            data-beat={i}
            ref={(el) => {
              steps.current[i] = el
            }}
          >
            {/* On narrow screens each beat brings its own phone instead of one pinned beside them. */}
            <div className="step-phone" aria-hidden="true">
              <div className="phone">
                <div className="phone-screen">
                  <Scene on>{scenes[i]}</Scene>
                </div>
              </div>
            </div>
            <p className="eyebrow">{b.eyebrow}</p>
            <h2>{b.title}</h2>
            <p className="sub">{b.body}</p>
          </div>
        ))}
      </div>
    </section>
  )
}

function Scene({ on, children }: { on: boolean; children: React.ReactNode }) {
  return <div className={`scene${on ? ' on' : ''}`}>{children}</div>
}

function Nudge() {
  return (
    <div className="s-nudge">
      <p className="s-clock">6:00</p>
      <p className="s-date">Sunday, October 25</p>
      <div className="s-banner">
        <span className="s-app" />
        <span>
          <strong>Week {NOW} of your film</strong>
          <span>Add this week’s clips. Shot to try: film the walk there, not just the arrival.</span>
        </span>
      </div>
    </div>
  )
}

function Week() {
  return (
    <div className="s-week">
      <p className="m-eyebrow">Week {NOW} · Oct 22 – 28</p>
      <p className="m-title">This week</p>
      <div className="m-card m-prompt">
        <span className="m-eyebrow">Shot to try</span>
        <span className="m-serif">Film the walk there, not just the arrival.</span>
      </div>
      <p className="m-section">Clips <span>3</span></p>
      <div className="m-strip">
        {[['Thu 22', '0:12'], ['Sat 24', '0:31'], ['Sun 25', '0:08']].map(([day, len], i) => (
          <div key={day} className="m-frame" style={{ background: `linear-gradient(135deg, #1d2649, ${TINTS[(i + 2) % 5]})` }}>
            <span>{day}</span>
            <span>{len}</span>
          </div>
        ))}
      </div>
      <div className="m-card m-voice">
        <span className="m-record recording" />
        <span>
          <strong>0:14 of 1:00</strong>
          <span className="wave">
            {Array.from({ length: 18 }, (_, i) => <i key={i} style={{ animationDelay: `${(i % 6) * 0.12}s` }} />)}
          </span>
        </span>
      </div>
    </div>
  )
}

function Grid({ lit }: { lit: number }) {
  const on = new Set(FILMED.slice(0, lit))
  return (
    <div className="s-grid">
      <p className="m-eyebrow">Premiere · December 20</p>
      <p className="m-title">2026</p>
      <p className="m-section">{on.size} of {NOW} weeks filmed</p>
      <div className="m-grid">
        {Array.from({ length: 52 }, (_, i) => i + 1).map((w) => (
          <span key={w} className={on.has(w) ? 'on' : w > NOW ? 'future' : undefined} data-current={w === NOW || undefined}>
            {w}
          </span>
        ))}
      </div>
    </div>
  )
}

function RoughCut() {
  return (
    <div className="s-rough">
      <div className="s-player">
        <span className="s-title-card">
          <small>The Garcias</small>
          2026
        </span>
        <span className="s-bar"><i /></span>
      </div>
      <p className="m-section">Chapters</p>
      <ol className="s-chapters">
        {['Cold open', 'Winter', 'Spring', 'Summer', 'Fall'].map((c, i) => (
          <li key={c} className={i === 1 ? 'on' : undefined}>{c}</li>
        ))}
      </ol>
      <div className="m-card m-rough">
        <span className="m-fan">
          {TINTS.map((t, i) => (
            <i key={t} style={{ background: `linear-gradient(135deg, #13243f, ${t})`, transform: `rotate(${(i - 2) * 8}deg) translateX(${(i - 2) * 6}px)` }} />
          ))}
        </span>
        <span>
          <span className="m-eyebrow">Rough cut</span>
          <span className="m-serif">Your year so far</span>
          <small>148 clips · 28 weeks</small>
        </span>
      </div>
    </div>
  )
}
