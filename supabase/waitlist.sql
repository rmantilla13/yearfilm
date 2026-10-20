-- Run once in the Supabase SQL editor for the yearfilm project.
create table if not exists waitlist (
  email       text primary key,
  source      text,
  created_at  timestamptz not null default now()
);

-- RLS on, zero policies: only the service key (server-side, in the API route) can touch it.
alter table waitlist enable row level security;
revoke all on waitlist from anon, authenticated;
