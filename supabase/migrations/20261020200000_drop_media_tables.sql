-- Footage and voice notes now stay on the phone, backed up and shared through the user's own
-- iCloud (docs/storage-plan.md). Yearfilm's database keeps only the waitlist.
-- All of these were empty when dropped.
drop table if exists family_invites;
drop table if exists profiles;
drop table if exists voice_notes;
drop table if exists footage;
drop table if exists family_members;
drop table if exists families;
drop function if exists my_family_ids();
