// Human wording for a set of film weeks: "for week 30", "for weeks 47–48 of 2026".

export function weeksLabel(weeks: number[] | null, year: number | null): string {
  if (!weeks || weeks.length === 0) return 'from any week of the year'
  const runs: string[] = []
  let start = weeks[0]
  let prev = weeks[0]
  for (const w of [...weeks.slice(1), Number.NaN]) {
    if (w === prev + 1) {
      prev = w
      continue
    }
    runs.push(start === prev ? `${start}` : `${start}–${prev}`)
    start = prev = w
  }
  const plural = weeks.length > 1 ? 'weeks' : 'week'
  return `from ${plural} ${runs.join(', ')}${year ? ` of ${year}` : ''}`
}
