-- Live Scrimmage event timeline: passes, possession, goals, assists, substitutions, drops, blocks, and team changes.
-- Run this script in the Supabase SQL Editor. It is safe to rerun to update an existing timeline table.

-- Quick Pass state is stored with the active match so connected devices share possession and mode.
alter table public.scrimmage_matches
  add column if not exists quick_pass_state jsonb not null default '{"active": false}'::jsonb;

create table if not exists public.scrimmage_timeline_events (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.scrimmage_matches(id) on delete cascade,
  event_type text not null check (event_type in ('goal', 'substitution', 'drop', 'block', 'team_change', 'pass', 'possession')),
  team text not null check (team in ('A', 'B')),
  player_id uuid references public.players(id) on delete cascade,
  related_player_id uuid references public.players(id) on delete cascade,
  stat_event_id uuid unique,
  created_at timestamptz not null default now(),
  constraint scrimmage_timeline_related_player_check check (
    (event_type = 'goal' and (related_player_id is null or related_player_id <> player_id))
    or (event_type = 'substitution' and related_player_id is not null and related_player_id <> player_id)
    or (event_type = 'drop' and related_player_id is null)
    or (event_type = 'block' and related_player_id is not null and related_player_id <> player_id)
    or (event_type = 'pass' and related_player_id is not null and related_player_id <> player_id)
    or (event_type = 'possession' and related_player_id is null)
    or (event_type = 'team_change' and player_id is null and related_player_id is null)
  )
);

-- Update constraints when rerunning this setup on an existing timeline table.
alter table public.scrimmage_timeline_events
  alter column player_id drop not null;
alter table public.scrimmage_timeline_events
  drop constraint if exists scrimmage_timeline_events_event_type_check;
alter table public.scrimmage_timeline_events
  add constraint scrimmage_timeline_events_event_type_check
  check (event_type in ('goal', 'substitution', 'drop', 'block', 'team_change', 'pass', 'possession'));
alter table public.scrimmage_timeline_events
  drop constraint if exists scrimmage_timeline_related_player_check;
alter table public.scrimmage_timeline_events
  add constraint scrimmage_timeline_related_player_check check (
    (event_type = 'goal' and (related_player_id is null or related_player_id <> player_id))
    or (event_type = 'substitution' and related_player_id is not null and related_player_id <> player_id)
    or (event_type = 'drop' and related_player_id is null)
    or (event_type = 'block' and related_player_id is not null and related_player_id <> player_id)
    or (event_type = 'pass' and related_player_id is not null and related_player_id <> player_id)
    or (event_type = 'possession' and related_player_id is null)
    or (event_type = 'team_change' and player_id is null and related_player_id is null)
  );

create index if not exists scrimmage_timeline_match_created_idx
  on public.scrimmage_timeline_events (match_id, created_at desc);

alter table public.scrimmage_timeline_events enable row level security;

drop policy if exists "scrimmage timeline anon read" on public.scrimmage_timeline_events;
create policy "scrimmage timeline anon read"
  on public.scrimmage_timeline_events for select to anon using (true);
drop policy if exists "scrimmage timeline anon insert" on public.scrimmage_timeline_events;
create policy "scrimmage timeline anon insert"
  on public.scrimmage_timeline_events for insert to anon with check (true);
drop policy if exists "scrimmage timeline anon update" on public.scrimmage_timeline_events;
create policy "scrimmage timeline anon update"
  on public.scrimmage_timeline_events for update to anon using (true) with check (true);
drop policy if exists "scrimmage timeline anon delete" on public.scrimmage_timeline_events;
create policy "scrimmage timeline anon delete"
  on public.scrimmage_timeline_events for delete to anon using (true);

grant select, insert, update, delete on public.scrimmage_timeline_events to anon, authenticated;

do $$ begin
  alter publication supabase_realtime add table public.scrimmage_timeline_events;
exception
  when duplicate_object then null;
  when others then raise notice 'Realtime Scrimmage timeline publication: %', SQLERRM;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.scrimmage_matches;
exception
  when duplicate_object then null;
  when others then raise notice 'Realtime Scrimmage match state publication: %', SQLERRM;
end $$;
