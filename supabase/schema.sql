create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.matches (
  match_id uuid primary key default gen_random_uuid(),
  join_code text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
  rules_version text not null,
  status text not null check (status in ('waiting_for_players', 'waiting_for_orders', 'resolving', 'resolved', 'finished')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  current_turn integer not null default 1,
  current_turn_status text not null default 'waiting_for_players' check (current_turn_status in ('waiting_for_players', 'waiting_for_orders', 'resolving', 'resolved', 'finished')),
  map_selection jsonb not null default '{}'::jsonb
);

create table if not exists public.match_players (
  match_id uuid not null references public.matches(match_id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  player_slot text not null check (player_slot in ('player1', 'player2')),
  display_name text not null default '',
  joined_at timestamptz not null default timezone('utc', now()),
  primary key (match_id, user_id),
  unique (match_id, player_slot)
);

create table if not exists public.turns (
  match_id uuid not null references public.matches(match_id) on delete cascade,
  turn_number integer not null,
  status text not null check (status in ('waiting_for_players', 'waiting_for_orders', 'resolving', 'resolved', 'finished')),
  snapshot_version integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  resolved_at timestamptz,
  primary key (match_id, turn_number)
);

create table if not exists public.turn_snapshots (
  match_id uuid not null,
  turn_number integer not null,
  snapshot_version integer not null,
  canonical_snapshot jsonb not null,
  player_views jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (match_id, turn_number, snapshot_version),
  foreign key (match_id, turn_number) references public.turns(match_id, turn_number) on delete cascade
);

create table if not exists public.turn_orders (
  match_id uuid not null,
  turn_number integer not null,
  player_slot text not null check (player_slot in ('player1', 'player2')),
  submitted_by uuid not null references auth.users(id) on delete cascade,
  snapshot_version integer not null,
  payload jsonb not null,
  submitted_at timestamptz not null default timezone('utc', now()),
  primary key (match_id, turn_number, player_slot),
  foreign key (match_id, turn_number) references public.turns(match_id, turn_number) on delete cascade
);

create table if not exists public.resolve_jobs (
  job_id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(match_id) on delete cascade,
  turn_number integer not null,
  job_type text not null check (job_type in ('seed_match', 'resolve_turn')),
  status text not null check (status in ('queued', 'processing', 'succeeded', 'failed')) default 'queued',
  snapshot_ref jsonb not null default '{}'::jsonb,
  orders_ref jsonb not null default '{}'::jsonb,
  last_error text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  started_at timestamptz,
  finished_at timestamptz,
  unique (match_id, turn_number, job_type)
);

alter table public.matches enable row level security;
alter table public.match_players enable row level security;
alter table public.turns enable row level security;
alter table public.turn_snapshots enable row level security;
alter table public.turn_orders enable row level security;
alter table public.resolve_jobs enable row level security;

drop policy if exists "matches_select_members" on public.matches;
create policy "matches_select_members"
on public.matches for select
using (
  exists (
    select 1 from public.match_players mp
    where mp.match_id = matches.match_id and mp.user_id = auth.uid()
  )
);

drop policy if exists "matches_insert_owner" on public.matches;
create policy "matches_insert_owner"
on public.matches for insert
with check (created_by = auth.uid());

drop policy if exists "match_players_select_members" on public.match_players;
create policy "match_players_select_members"
on public.match_players for select
using (
  exists (
    select 1 from public.match_players mp
    where mp.match_id = match_players.match_id and mp.user_id = auth.uid()
  )
);

drop policy if exists "match_players_insert_self" on public.match_players;
create policy "match_players_insert_self"
on public.match_players for insert
with check (user_id = auth.uid());

drop policy if exists "turns_select_members" on public.turns;
create policy "turns_select_members"
on public.turns for select
using (
  exists (
    select 1 from public.match_players mp
    where mp.match_id = turns.match_id and mp.user_id = auth.uid()
  )
);

drop policy if exists "turn_snapshots_select_members" on public.turn_snapshots;
create policy "turn_snapshots_select_members"
on public.turn_snapshots for select
using (
  exists (
    select 1 from public.match_players mp
    where mp.match_id = turn_snapshots.match_id and mp.user_id = auth.uid()
  )
);

drop policy if exists "turn_orders_select_own" on public.turn_orders;
create policy "turn_orders_select_own"
on public.turn_orders for select
using (submitted_by = auth.uid());

drop policy if exists "turn_orders_insert_own" on public.turn_orders;
create policy "turn_orders_insert_own"
on public.turn_orders for insert
with check (submitted_by = auth.uid());

drop policy if exists "resolve_jobs_select_members" on public.resolve_jobs;
create policy "resolve_jobs_select_members"
on public.resolve_jobs for select
using (
  exists (
    select 1 from public.match_players mp
    where mp.match_id = resolve_jobs.match_id and mp.user_id = auth.uid()
  )
);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at before update on public.profiles
for each row execute procedure public.touch_updated_at();

drop trigger if exists trg_matches_updated_at on public.matches;
create trigger trg_matches_updated_at before update on public.matches
for each row execute procedure public.touch_updated_at();

drop trigger if exists trg_turns_updated_at on public.turns;
create trigger trg_turns_updated_at before update on public.turns
for each row execute procedure public.touch_updated_at();

drop trigger if exists trg_resolve_jobs_updated_at on public.resolve_jobs;
create trigger trg_resolve_jobs_updated_at before update on public.resolve_jobs
for each row execute procedure public.touch_updated_at();

create or replace function public.claim_resolve_job(p_worker_name text default '')
returns table (
  job_id uuid,
  match_id uuid,
  turn_number integer,
  job_type text,
  snapshot_ref jsonb,
  orders_ref jsonb,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.resolve_jobs%rowtype;
begin
  select *
  into v_job
  from public.resolve_jobs
  where status = 'queued'
  order by created_at asc
  for update skip locked
  limit 1;

  if not found then
    return;
  end if;

  update public.resolve_jobs
  set
    status = 'processing',
    started_at = timezone('utc', now()),
    finished_at = null,
    last_error = ''
  where public.resolve_jobs.job_id = v_job.job_id;

  return query
  select
    v_job.job_id,
    v_job.match_id,
    v_job.turn_number,
    v_job.job_type,
    v_job.snapshot_ref,
    v_job.orders_ref,
    v_job.created_at;
end;
$$;

create or replace function public.fail_resolve_job(p_job_id uuid, p_error text default '')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.resolve_jobs
  set
    status = 'failed',
    last_error = left(coalesce(p_error, ''), 4000),
    finished_at = timezone('utc', now())
  where job_id = p_job_id;
end;
$$;

create or replace function public.complete_seed_match_job(
  p_job_id uuid,
  p_snapshot_version integer,
  p_canonical_snapshot jsonb,
  p_player_views jsonb default '{}'::jsonb,
  p_selected_map_index integer default -1,
  p_match_seed integer default -1,
  p_rules_version text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.resolve_jobs%rowtype;
  v_next_status text;
  v_player_count integer;
begin
  select *
  into v_job
  from public.resolve_jobs
  where job_id = p_job_id
  for update;

  if not found then
    raise exception 'resolve job not found: %', p_job_id;
  end if;

  if v_job.job_type <> 'seed_match' then
    raise exception 'resolve job % is not seed_match', p_job_id;
  end if;

  if v_job.status <> 'processing' then
    raise exception 'resolve job % is not processing', p_job_id;
  end if;

  select count(*)
  into v_player_count
  from public.match_players
  where match_id = v_job.match_id;

  v_next_status := case
    when v_player_count >= 2 then 'waiting_for_orders'
    else 'waiting_for_players'
  end;

  insert into public.turn_snapshots (
    match_id,
    turn_number,
    snapshot_version,
    canonical_snapshot,
    player_views
  )
  values (
    v_job.match_id,
    v_job.turn_number,
    p_snapshot_version,
    p_canonical_snapshot,
    coalesce(p_player_views, '{}'::jsonb)
  )
  on conflict (match_id, turn_number, snapshot_version) do update
  set
    canonical_snapshot = excluded.canonical_snapshot,
    player_views = excluded.player_views;

  update public.turns
  set
    status = v_next_status,
    snapshot_version = p_snapshot_version,
    resolved_at = null
  where match_id = v_job.match_id
    and turn_number = v_job.turn_number;

  update public.matches
  set
    status = v_next_status,
    current_turn = v_job.turn_number,
    current_turn_status = v_next_status,
    rules_version = coalesce(p_rules_version, rules_version),
    map_selection = jsonb_set(
      jsonb_set(
        coalesce(map_selection, '{}'::jsonb),
        '{selected_map_index}',
        to_jsonb(p_selected_map_index),
        true
      ),
      '{match_seed}',
      to_jsonb(p_match_seed),
      true
    )
  where match_id = v_job.match_id;

  update public.resolve_jobs
  set
    status = 'succeeded',
    snapshot_ref = jsonb_build_object(
      'turn_number', v_job.turn_number,
      'snapshot_version', p_snapshot_version
    ),
    finished_at = timezone('utc', now()),
    last_error = ''
  where job_id = p_job_id;
end;
$$;

create or replace function public.complete_resolve_turn_job(
  p_job_id uuid,
  p_next_turn_number integer,
  p_snapshot_version integer,
  p_canonical_snapshot jsonb,
  p_player_views jsonb default '{}'::jsonb,
  p_game_over boolean default false,
  p_winner_id text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.resolve_jobs%rowtype;
  v_next_status text;
begin
  select *
  into v_job
  from public.resolve_jobs
  where job_id = p_job_id
  for update;

  if not found then
    raise exception 'resolve job not found: %', p_job_id;
  end if;

  if v_job.job_type <> 'resolve_turn' then
    raise exception 'resolve job % is not resolve_turn', p_job_id;
  end if;

  if v_job.status <> 'processing' then
    raise exception 'resolve job % is not processing', p_job_id;
  end if;

  v_next_status := case
    when coalesce(p_game_over, false) then 'finished'
    else 'waiting_for_orders'
  end;

  insert into public.turns (
    match_id,
    turn_number,
    status,
    snapshot_version,
    resolved_at
  )
  values (
    v_job.match_id,
    p_next_turn_number,
    v_next_status,
    p_snapshot_version,
    case when coalesce(p_game_over, false) then timezone('utc', now()) else null end
  )
  on conflict (match_id, turn_number) do update
  set
    status = excluded.status,
    snapshot_version = excluded.snapshot_version,
    resolved_at = excluded.resolved_at;

  insert into public.turn_snapshots (
    match_id,
    turn_number,
    snapshot_version,
    canonical_snapshot,
    player_views
  )
  values (
    v_job.match_id,
    p_next_turn_number,
    p_snapshot_version,
    p_canonical_snapshot,
    coalesce(p_player_views, '{}'::jsonb)
  )
  on conflict (match_id, turn_number, snapshot_version) do update
  set
    canonical_snapshot = excluded.canonical_snapshot,
    player_views = excluded.player_views;

  update public.turns
  set
    status = 'resolved',
    resolved_at = timezone('utc', now())
  where match_id = v_job.match_id
    and turn_number = v_job.turn_number;

  update public.matches
  set
    status = v_next_status,
    current_turn = p_next_turn_number,
    current_turn_status = v_next_status
  where match_id = v_job.match_id;

  update public.resolve_jobs
  set
    status = 'succeeded',
    snapshot_ref = jsonb_build_object(
      'turn_number', p_next_turn_number,
      'snapshot_version', p_snapshot_version,
      'winner_id', coalesce(p_winner_id, '')
    ),
    finished_at = timezone('utc', now()),
    last_error = ''
  where job_id = p_job_id;
end;
$$;
