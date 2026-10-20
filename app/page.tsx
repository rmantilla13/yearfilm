import Link from 'next/link'
import { MemoryPool } from './MemoryPool'
import { WaitlistForm } from './WaitlistForm'

// One frame per week, tinted by season within the pool's blues, so the strip reads as a year going by.
const SEASONS: [number, string, string][] = [
  [9, '#13243f', '#6f9fd8'],   // winter
  [22, '#0f3036', '#5fc4bd'],  // spring
  [35, '#123754', '#8fd6ff'],  // summer
  [48, '#1d2649', '#8f9de6'],  // fall
  [53, '#241d42', '#bfb0ff'],  // holidays
]
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

function tint(week: number) {
  const [, a, b] = SEASONS.find(([end]) => week < end) ?? SEASONS[SEASONS.length - 1]
  return `linear-gradient(135deg, ${a}, ${b})`
}

function frames() {
  return Array.from({ length: 52 }, (_, i) => {
    const week = i + 1
    const month = MONTHS[Math.min(11, Math.floor((i * 12) / 52))]
    return { week, label: `${month} · wk ${week}`, bg: tint(week) }
  })
}

// The mockups' sample year: filmed weeks glow in the grid, as in the app's Year screen.
const THIS_WEEK = 42
const FILMED = new Set([1, 2, 3, 5, 6, 7, 9, 10, 11, 14, 16, 18, 20, 21, 23, 25, 26, 28, 31, 32, 33, 35, 36, 38, 40, 41, 42])
const WEEK_CLIPS: [string, string][] = [['Mon 19', '0:12'], ['Wed 21', '0:31'], ['Sat 24', '0:08']]

const CHAPTERS = [
  ['00:00', 'Cold open', 'The year’s best moments, cut to the beat'],
  ['01:30', 'Winter', 'Snow days, your voice over the montage'],
  ['07:10', 'Spring', 'First steps, birthday candles, the garden'],
  ['13:40', 'Summer', 'The road trip, played with its own sound'],
  ['20:05', 'Fall', 'Back to school, Halloween, the long dinners'],
  ['26:20', 'The Holidays', 'Where this year’s film ends — and next year’s begins'],
  ['31:00', 'Credits', 'Starring everyone you love'],
]

export default function Home() {
  const strip = frames()
  return (
    <>
      <div className="wrap">
        <nav className="nav">
          <Link href="/" className="mark">
            year<span>film</span>
          </Link>
          <a className="small" href="#how">
            How it works
          </a>
        </nav>

        <header className="hero">
          <MemoryPool />
          <div className="hero-copy">
            <p className="eyebrow">Premiering December 20</p>
            <h1>
              Your family’s year, made into <em>a film</em>.
            </h1>
            <p className="lede">
              Film a little every week. In December, sit down together and watch the movie of your
              year — cut, scored, and narrated in your own words.
            </p>
            <WaitlistForm />
          </div>
        </header>

        <div className="reel" aria-hidden="true">
          <div className="strip">
            {[...strip, ...strip].map((f, i) => (
              <div key={i} className="frame" style={{ background: f.bg }}>
                {f.label}
              </div>
            ))}
          </div>
        </div>

        <section id="how" className="split">
          <div className="copy">
            <p className="eyebrow">Every week</p>
            <h2>A shot to try, a few clips, twenty seconds of you.</h2>
            <p className="sub">
              Each week the app suggests one shot — a reaction, the walk there, one wide shot of
              where you are. Add the week’s clips, then say what happened. In December, those
              voice notes become the narration: the story told by the people who lived it.
            </p>
          </div>
          <div className="mock phone" aria-hidden="true">
            <p className="m-eyebrow">Week {THIS_WEEK} · Oct 15 – 21</p>
            <p className="m-title">This week</p>
            <div className="m-card m-prompt">
              <span className="m-eyebrow">Shot to try</span>
              <span className="m-serif">Film hands doing something: cooking, building, drawing.</span>
            </div>
            <p className="m-section">Clips <span>3</span></p>
            <div className="m-strip">
              {WEEK_CLIPS.map(([day, length], i) => (
                <div key={day} className="m-frame" style={{ background: tint(36 + i * 4) }}>
                  <span>{day}</span>
                  <span>{length}</span>
                </div>
              ))}
              <div className="m-frame m-add">+</div>
            </div>
            <div className="m-card m-voice">
              <span className="m-record" />
              <span>
                <strong>What happened this week?</strong>
                <small>Twenty seconds becomes the narration.</small>
              </span>
            </div>
          </div>
        </section>

        <section className="split flip">
          <div className="copy">
            <p className="eyebrow">Already filming</p>
            <h2>Bring the whole year in at once.</h2>
            <p className="sub">
              Pick a few hundred videos from your library. Each one is filed under the week it was
              filmed, read from the video itself, and anything you’ve already added is skipped.
              Watch them float into the pool and light up their weeks.
            </p>
          </div>
          <div className="mock year" aria-hidden="true">
            <p className="m-eyebrow">Premiere · December 20</p>
            <p className="m-title">2026</p>
            <p className="m-section">{FILMED.size} of {THIS_WEEK} weeks filmed</p>
            <div className="m-grid">
              {Array.from({ length: 52 }, (_, i) => i + 1).map((w) => (
                <span
                  key={w}
                  className={FILMED.has(w) ? 'on' : w > THIS_WEEK ? 'future' : undefined}
                  data-current={w === THIS_WEEK || undefined}
                >
                  {w}
                </span>
              ))}
            </div>
            <div className="m-card m-rough">
              <span className="m-fan">
                {[8, 20, 31, 38, 42].map((w, i) => (
                  <i key={w} style={{ background: tint(w), transform: `rotate(${(i - 2) * 8}deg) translateX(${(i - 2) * 6}px)` }} />
                ))}
              </span>
              <span>
                <span className="m-eyebrow">Rough cut</span>
                <span className="m-serif">Watch your year so far</span>
                <small>142 clips so far</small>
              </span>
              <span className="m-play">▶</span>
            </div>
          </div>
        </section>

        <section>
          <p className="eyebrow">Premiere night</p>
          <h2>Not a slideshow. A film.</h2>
          <p className="sub">
            Real chapters, real scenes with their own sound, and montages cut on the beat — the way
            a documentary is made. Watch a rough cut whenever you like; it’s cut right on your
            phone.
          </p>
          <ol className="chapters">
            {CHAPTERS.map(([t, n, d]) => (
              <li key={n}>
                <span className="t">{t}</span>
                <span className="n">{n}</span>
                <span className="d">{d}</span>
              </li>
            ))}
          </ol>
        </section>

        <section>
          <div className="features">
            <div className="feature">
              <h3>Made for the TV</h3>
              <p>Widescreen, steady volume, chapter by chapter. Vertical phone clips are framed for the big screen, not squeezed between black bars.</p>
            </div>
            <div className="feature">
              <h3>Scored to your year</h3>
              <p>Music chosen for each season, with every cut landing on the beat and the music dipping when someone speaks.</p>
            </div>
            <div className="feature">
              <h3>The whole family films</h3>
              <p>Grandparents, siblings, partners: anyone you invite can add their clips to this year’s film.</p>
            </div>
            <div className="feature">
              <h3>One night for everyone</h3>
              <p>Every family’s film unlocks on December 20, in time to watch together for the holidays.</p>
            </div>
          </div>
        </section>

        <section className="privacy">
          <div className="m-card privacy-card">
            <p className="eyebrow">Your footage stays yours</p>
            <h2>On your iPhone. In your iCloud. Nowhere else.</h2>
            <p className="sub">
              Your clips and voice notes live on your iPhone. If you turn on backup, or make the
              film with family, they go through your own iCloud — under your Apple ID, in your
              storage. Yearfilm runs no server that holds your videos, so there’s nothing of yours
              on ours to lose, sell, or leak.
            </p>
            <Link className="small-link" href="/privacy">Read the privacy policy</Link>
          </div>
        </section>

        <section className="closing">
          <span className="closing-mark" aria-hidden="true" />
          <h2>Next year’s film starts in January.</h2>
          <p className="sub">Join the waitlist and be ready to film from week one.</p>
          <WaitlistForm cta="Save my seat" />
        </section>
      </div>

      <footer>
        <div className="wrap row">
          <span>© {new Date().getFullYear()} Yearfilm</span>
          <nav>
            <Link href="/privacy">Privacy</Link>
            <Link href="/support">Support</Link>
          </nav>
        </div>
      </footer>
    </>
  )
}
