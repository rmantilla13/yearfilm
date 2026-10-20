import type { Metadata, Viewport } from 'next'
import { Fraunces, Inter } from 'next/font/google'
import './globals.css'

const display = Fraunces({ subsets: ['latin'], variable: '--font-display', axes: ['opsz', 'SOFT'] })
const body = Inter({ subsets: ['latin'], variable: '--font-body' })

export const metadata: Metadata = {
  metadataBase: new URL('https://yearfilm.com'),
  title: 'Yearfilm — the movie of your family’s year',
  description:
    'Film a little every week. On the holidays, sit down together and watch the movie of your year — cut, scored, and narrated in your own words.',
  openGraph: {
    title: 'Yearfilm',
    description: 'Film a little every week. Premiere the movie of your year on the holidays.',
    url: 'https://yearfilm.com',
    siteName: 'Yearfilm',
    type: 'website',
  },
}

export const viewport: Viewport = { themeColor: '#0d0b09', colorScheme: 'dark' }

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable}`}>
      <body>{children}</body>
    </html>
  )
}
