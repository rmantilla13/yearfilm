-- Accounts, families and uploaded media: the first slice of schema/schema.sql that ships.
--
-- Clients never write these tables directly. The web API (service role, server-side)
-- checks membership, issues Blob upload URLs and records what arrived. Clients may only
-- read their own family's rows.

create extension if not exists pgcrypto;

create table families (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_at  timestamptz not null default now()
);

create table family_members (
  family_id   uuid not null references families on delete cascade,
  user_id     uuid not null references auth.users on delete cascade,
  role        text not null check (role in ('producer', 'contributor', 'viewer')),
  invited_by  uuid references auth.users on delete set null,
  created_at  timestamptz not null default now(),
  primary key (family_id, user_id)
);
create index on family_members (user_id);

-- The id is the one the phone already gave the clip, so a retried upload lands on the same row.
create table footage (
  id             uuid primary key,
  family_id      uuid not null references families on delete cascade,
  uploaded_by    uuid references auth.users on delete set null,
  original_path  text not null unique,           -- {family}/{year}/original/{id}.{ext}
  proxy_path     text,
  captured_on    date not null,                  -- calendar day where it was filmed, never a UTC instant
  duration_s     real,
  byte_size      bigint,
  content_type   text,
  status         text not null default 'uploaded'
                 check (status in ('uploaded', 'processing', 'analysed', 'failed')),
  created_at     timestamptz not null default now()
);
create index on footage (family_id, captured_on);

create table voice_notes (
  id           uuid primary key,
  family_id    uuid not null references families on delete cascade,
  recorded_by  uuid references auth.users on delete set null,
  path         text not null unique,             -- {family}/{year}/notes/{id}.m4a
  recorded_on  date not null,
  duration_s   real,
  byte_size    bigint,
  transcript   text,
  created_at   timestamptz not null default now()
);
create index on voice_notes (family_id, recorded_on);

create or replace function my_family_ids() returns setof uuid
  language sql stable security definer set search_path = public as $$
  select family_id from family_members where user_id = auth.uid()
$$;
revoke all on function my_family_ids() from public;
grant execute on function my_family_ids() to authenticated;

alter table families       enable row level security;
alter table family_members enable row level security;
alter table footage        enable row level security;
alter table voice_notes    enable row level security;

-- Read-only for signed-in members; every write goes through the server.
create policy families_read on families for select to authenticated
  using (id in (select my_family_ids()));
create policy members_read on family_members for select to authenticated
  using (family_id in (select my_family_ids()));
create policy footage_read on footage for select to authenticated
  using (family_id in (select my_family_ids()));
create policy voice_notes_read on voice_notes for select to authenticated
  using (family_id in (select my_family_ids()));

revoke insert, update, delete on families, family_members, footage, voice_notes from anon, authenticated;
revoke all on families, family_members, footage, voice_notes from anon;

-- Supabase grants execute to anon by default; signed-out callers have no families to list.
revoke execute on function my_family_ids() from anon;
