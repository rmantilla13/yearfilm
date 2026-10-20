-- Profiles, invite links, and week-limited contributors.

-- The name family members see. Optional: Sign in with Apple gives us no name.
create table profiles (
  user_id       uuid primary key references auth.users on delete cascade,
  display_name  text check (char_length(display_name) <= 60),
  updated_at    timestamptz not null default now()
);

-- A contributor can be limited to some weeks of one year's film ("send us your Thanksgiving
-- clips"). Null weeks = any week.
alter table family_members
  add column weeks int[] check (weeks is null or (cardinality(weeks) between 1 and 52 and 1 <= all(weeks) and 52 >= all(weeks))),
  add column weeks_year int;

-- A shareable link. Only a hash of the token is stored, so a database leak doesn't leak links.
-- Invites can carry contributor or viewer, never producer.
create table family_invites (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null references families on delete cascade,
  token_hash   text not null unique,
  role         text not null default 'contributor' check (role in ('contributor', 'viewer')),
  weeks        int[] check (weeks is null or (cardinality(weeks) between 1 and 52 and 1 <= all(weeks) and 52 >= all(weeks))),
  weeks_year   int,
  created_by   uuid references auth.users on delete set null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  revoked_at   timestamptz,
  uses         int not null default 0
);
create index on family_invites (family_id);

alter table profiles       enable row level security;
alter table family_invites enable row level security;

-- Members can see each other's names; everything else goes through the server.
create policy profiles_read on profiles for select to authenticated
  using (user_id = auth.uid() or user_id in (
    select user_id from family_members where family_id in (select my_family_ids())
  ));

revoke insert, update, delete on profiles, family_invites from anon, authenticated;
revoke all on profiles, family_invites from anon;
revoke select on family_invites from authenticated;
