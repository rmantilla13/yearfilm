'use client'

import { useState } from 'react'
import { parseSignup } from '@/lib/waitlist'

type State = { kind: 'idle' } | { kind: 'sending' } | { kind: 'done' } | { kind: 'error'; message: string }

export function WaitlistForm({ cta = 'Join the waitlist' }: { cta?: string }) {
  const [state, setState] = useState<State>({ kind: 'idle' })

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const form = new FormData(e.currentTarget)
    const body = { email: String(form.get('email') ?? ''), website: String(form.get('website') ?? '') }
    const parsed = parseSignup(body)
    if (!parsed.ok) return setState({ kind: 'error', message: parsed.error })
    setState({ kind: 'sending' })
    try {
      const res = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) return setState({ kind: 'error', message: data.error ?? 'Something went wrong.' })
      setState({ kind: 'done' })
    } catch {
      setState({ kind: 'error', message: 'Couldn’t reach us. Check your connection and try again.' })
    }
  }

  if (state.kind === 'done') {
    return (
      <p className="note done" role="status">
        You’re on the list. We’ll write when filming opens — the best films start in January.
      </p>
    )
  }

  return (
    <form onSubmit={submit} noValidate>
      <div className="signup">
        <label className="hp" aria-hidden="true">
          Website <input name="website" tabIndex={-1} autoComplete="off" />
        </label>
        <input
          type="email"
          name="email"
          placeholder="you@family.com"
          autoComplete="email"
          aria-label="Email address"
          required
        />
        <button type="submit" disabled={state.kind === 'sending'}>
          {state.kind === 'sending' ? 'Joining…' : cta}
        </button>
      </div>
      <p className={`note${state.kind === 'error' ? ' error' : ''}`} role="status" aria-live="polite">
        {state.kind === 'error' ? state.message : 'One email when it’s ready. Nothing else.'}
      </p>
    </form>
  )
}
