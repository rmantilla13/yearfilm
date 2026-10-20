-- SUPERSEDED (2026-10-20): media no longer goes to a server; see docs/storage-plan.md.
-- Kept as the sketch of the film's data model. Only `waitlist` (supabase/) is deployed.
-- yearfilm: data model sketch (Postgres / Supabase). See docs/data-model.md for the why.

create extension if not exists pgcrypto;

-- A family is the tenant. Everything below belongs to exactly one.
create table families (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,                      -- "The Garcias"
  created_at  timestamptz not null default now()
);

-- Who can sign in. NOT who is in the film - that is cast_members.
create table family_members (
  family_id   uuid not null references families on delete cascade,
  user_id     uuid not null,                      -- auth.users
  role        text not null check (role in ('producer', 'contributor', 'viewer')),
  invited_by  uuid,
  primary key (family_id, user_id)
);

-- Who appears on screen and in the credits. A baby has no login; a grandparent
-- with a login may never appear. Face clusters are attached here, with consent.
create table cast_members (
  id               uuid primary key default gen_random_uuid(),
  family_id        uuid not null references families on delete cascade,
  name             text not null,
  face_consent_at  timestamptz,                   -- BIPA-style explicit consent; null = no face matching
  credit_order     int
);

-- One film per family per year. The year is the product.
create table films (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null references families on delete cascade,
  year         int  not null,
  title        text,                              -- defaults to "<family> — <year>"
  premiere_at  timestamptz,                       -- the night it unlocks
  status       text not null default 'filming'
               check (status in ('filming', 'post_production', 'locked', 'premiered')),
  unique (family_id, year)
);

-- Raw uploads. Originals are kept; the proxy is what analysis and rendering read.
create table footage (
  id            uuid primary key default gen_random_uuid(),
  family_id     uuid not null references families on delete cascade,
  uploaded_by   uuid not null,
  original_path text not null,                    -- {family}/{year}/original/{id}.mov
  proxy_path    text,                             -- 1080p SDR CFR H.264
  captured_on   date not null,                    -- calendar date where it was filmed, never a UTC instant
  duration_s    real,
  width         int,
  height        int,
  has_audio     boolean,
  is_hdr        boolean,
  status        text not null default 'uploaded'
                check (status in ('uploaded', 'processing', 'analysed', 'failed')),
  created_at    timestamptz not null default now()
);
create index on footage (family_id, captured_on);

-- The weekly "what happened this week?" recording. Becomes narration.
create table voice_notes (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null references families on delete cascade,
  recorded_by  uuid not null,
  path         text not null,
  recorded_on  date not null,
  duration_s   real,
  transcript   text                               -- Whisper; feeds chapter titles
);

-- Analysis output: candidate cuts. Derived and regenerable - safe to delete and rerun.
create table moments (
  id          uuid primary key default gen_random_uuid(),
  footage_id  uuid not null references footage on delete cascade,
  kind        text not null check (kind in ('shot', 'scene')),
  start_s     real not null,
  dur_s       real not null,
  score       real not null,
  features    jsonb not null default '{}',        -- sharpness, motion, speech, laughter, embedding id...
  pinned      boolean not null default false,     -- a producer said "this one must be in it"
  hidden      boolean not null default false      -- ...or "never this one"
);
create index on moments (footage_id);

create table appearances (
  moment_id       uuid not null references moments on delete cascade,
  cast_member_id  uuid not null references cast_members on delete cascade,
  primary key (moment_id, cast_member_id)
);

-- Score cues. Licence terms travel with the track, because the trailer is shared
-- publicly and the film is not - a licence can cover one and not the other.
create table music_tracks (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid references families on delete cascade,   -- null = catalogue-wide
  source       text not null check (source in ('library', 'generated', 'upload')),
  provider     text,                              -- 'epidemic', 'elevenlabs', ...
  external_id  text,
  path         text not null,
  duration_s   real,
  tempo        real,
  beats        jsonb,                             -- seconds; from librosa
  downbeat     int,
  licence      jsonb not null default '{}'        -- {private: true, public_trailer: false, ...}
);

-- The edit. A cut is a versioned timeline (the same JSON the renderer follows).
-- Swapping a clip or a song writes a new version; nothing is re-analysed.
create table film_cuts (
  id           uuid primary key default gen_random_uuid(),
  film_id      uuid not null references films on delete cascade,
  version      int  not null,
  kind         text not null default 'feature' check (kind in ('feature', 'trailer', 'chapter')),
  timeline     jsonb not null,
  created_by   uuid,                              -- null = the planner made it
  render_path  text,
  rendered_at  timestamptz,
  locked_at    timestamptz,                       -- producer signed off; premiere plays this
  unique (film_id, kind, version)
);

-- Weekly shot-list prompts ("turn your phone sideways", "first snow?").
create table prompts (
  id        uuid primary key default gen_random_uuid(),
  week      int  check (week between 1 and 53),
  months    int[],                                -- seasonal prompts only fire in these months
  text      text not null
);

-- RLS sketch: one helper, every policy asks it.
create or replace function my_family_ids() returns setof uuid
  language sql stable security definer set search_path = public as $$
  select family_id from family_members where user_id = auth.uid()
$$;

alter table footage enable row level security;
create policy footage_read on footage for select using (family_id in (select my_family_ids()));
create policy footage_write on footage for insert with check (
  family_id in (select family_id from family_members
                where user_id = auth.uid() and role in ('producer', 'contributor'))
);
-- ...same shape for voice_notes, cast_members, films; moments/appearances via their footage;
-- film_cuts writable by producers only.
