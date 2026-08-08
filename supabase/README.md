# Async Backend Notes

This directory contains the managed-backend scaffolding for the async multiplayer path.

## Pieces

- `schema.sql`
  - Core tables for matches, players, turns, snapshots, orders, and resolver jobs.
  - Row-level security is enabled so only match members can read match state and only the submitting player can read their raw order payloads.

- `functions/`
  - Thin Supabase Edge Functions for:
    - `create_match`
    - `join_match`
    - `list_matches`
    - `get_match_state`
    - `get_turn_snapshot`
    - `submit_orders`
    - `get_turn_result`

## Worker

The Edge Functions do not resolve turns directly. They enqueue `resolve_jobs` records.

Use the headless worker entrypoint in [scripts/async_turn_worker.gd](/C:/Users/mattb/Documents/fortress-frontiers/scripts/async_turn_worker.gd) plus the queue runner in [supabase/worker/src/index.mjs](/C:/Users/mattb/Documents/fortress-frontiers/supabase/worker/src/index.mjs) to:

1. Seed new matches from a `seed_match` job.
2. Resolve a submitted turn from a `resolve_turn` job.
3. Persist the canonical next snapshot plus per-player fog-filtered views back into `turn_snapshots`.

### Worker setup

1. Apply [schema.sql](/C:/Users/mattb/Documents/fortress-frontiers/supabase/schema.sql) to your Supabase project so the worker RPC helpers exist.
2. From `supabase/worker`, install dependencies with `npm install`.
3. Copy `.env.example` and provide:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `GODOT_BIN`
4. Run `npm run start` for a polling worker or `npm run start:once` to process a single queued job.

The worker claims jobs via `claim_resolve_job`, runs headless Godot, and finishes them through `complete_seed_match_job` or `complete_resolve_turn_job`.

## Bring-Up Checklist

1. Create a Supabase project.
2. Enable email/password auth for the project.
3. Decide whether email confirmation is required.
4. Apply [schema.sql](/C:/Users/mattb/Documents/fortress-frontiers/supabase/schema.sql).
5. Deploy the functions in [supabase/functions](/C:/Users/mattb/Documents/fortress-frontiers/supabase/functions).
6. Start the worker in [supabase/worker](/C:/Users/mattb/Documents/fortress-frontiers/supabase/worker).
7. In the game client, enter the Supabase URL and anon key in the async panel, then sign in.
8. Create a match as player 1, join it as player 2, and verify the worker processes both `seed_match` and `resolve_turn`.

## First Smoke Test

1. Player 1 signs up or signs in.
2. Player 1 creates a match.
3. Wait for the worker to write the initial snapshot for turn 1.
4. Player 2 signs up or signs in.
5. Player 2 joins using the match UUID or join code.
6. Both players open the match and confirm they receive a turn snapshot.
7. Player 1 submits orders and confirms the match stays pending.
8. Player 2 submits orders and confirms the worker advances the match to the next turn.

## Required Supabase Secrets

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
