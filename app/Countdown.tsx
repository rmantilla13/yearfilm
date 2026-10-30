'use client'

import { useEffect, useState } from 'react'

/** Days until this year's premiere (December 20), counted in the visitor's own time zone. */
function daysLeft(now = new Date()) {
  const premiere = new Date(now.getFullYear(), 11, 20)
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  return Math.round((premiere.getTime() - today.getTime()) / 86_400_000)
}

export function Countdown() {
  // Rendered on the client only, so a static page never shows a stale count.
  const [days, setDays] = useState<number | null>(null)
  useEffect(() => setDays(daysLeft()), [])

  if (days === null) return <span className="countdown">&nbsp;</span>
  const text =
    days > 1 ? `${days} days of filming left this year` : days === 1 ? 'Premiere is tomorrow night' : days === 0 ? 'Premiere is tonight' : 'This year’s films are out — next year’s starts in January'
  return <span className="countdown">{text}</span>
}
