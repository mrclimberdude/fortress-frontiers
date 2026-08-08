import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createClient } from "@supabase/supabase-js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const workerRoot = path.resolve(__dirname, "..");
await loadEnvFile(path.join(workerRoot, ".env"));
const repoRoot = path.resolve(workerRoot, "..", "..");

const SUPABASE_URL = process.env.SUPABASE_URL ?? "";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
const GODOT_BIN = process.env.GODOT_BIN ?? "godot";
const PROJECT_ROOT = process.env.GAME_PROJECT_ROOT ?? repoRoot;
const WORKER_NAME = process.env.WORKER_NAME ?? `${os.hostname()}:${process.pid}`;
const POLL_INTERVAL_MS = Number.parseInt(process.env.POLL_INTERVAL_MS ?? "5000", 10);
const GODOT_TIMEOUT_MS = Number.parseInt(process.env.GODOT_TIMEOUT_MS ?? "120000", 10);
const MODE = process.argv.includes("--once") ? "once" : (process.env.WORKER_MODE ?? "loop");

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.");
}

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

async function loadEnvFile(envPath) {
  try {
    const raw = await fs.readFile(envPath, "utf8");
    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) {
        continue;
      }
      const separator = trimmed.indexOf("=");
      if (separator <= 0) {
        continue;
      }
      const key = trimmed.slice(0, separator).trim();
      let value = trimmed.slice(separator + 1).trim();
      if (
        value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))
      ) {
        value = value.slice(1, -1);
      }
      if (!(key in process.env)) {
        process.env[key] = value;
      }
    }
  } catch (error) {
    if (error?.code !== "ENOENT") {
      throw error;
    }
  }
}

async function main() {
  if (MODE === "once") {
    const result = await processNextJob();
    if (!result.processed) {
      console.log("No queued resolve jobs.");
      return;
    }
    if (!result.ok) {
      process.exitCode = 1;
    }
    return;
  }

  while (true) {
    const result = await processNextJob();
    if (!result.processed) {
      await sleep(POLL_INTERVAL_MS);
    }
  }
}

async function processNextJob() {
  const job = await claimJob();
  if (!job) {
    return { processed: false, ok: true };
  }

  console.log(`[worker] claimed ${job.job_type} ${job.match_id} turn ${job.turn_number}`);
  try {
    if (job.job_type === "seed_match") {
      await handleSeedJob(job);
    } else if (job.job_type === "resolve_turn") {
      await handleResolveJob(job);
    } else {
      throw new Error(`Unsupported job type: ${job.job_type}`);
    }
    console.log(`[worker] completed ${job.job_type} ${job.match_id} turn ${job.turn_number}`);
    return { processed: true, ok: true };
  } catch (error) {
    const message = formatError(error);
    console.error(`[worker] failed ${job.job_type} ${job.match_id} turn ${job.turn_number}: ${message}`);
    await markJobFailed(job.job_id, message);
    return { processed: true, ok: false };
  }
}

async function claimJob() {
  const { data, error } = await admin.rpc("claim_resolve_job", { p_worker_name: WORKER_NAME });
  if (error) {
    throw new Error(`claim_resolve_job failed: ${error.message}`);
  }
  if (!Array.isArray(data) || data.length === 0) {
    return null;
  }
  return data[0];
}

async function handleSeedJob(job) {
  const { data: match, error: matchError } = await admin
    .from("matches")
    .select("match_id, current_turn, rules_version, map_selection")
    .eq("match_id", job.match_id)
    .single();
  if (matchError || !match) {
    throw new Error(matchError?.message ?? "seed match not found");
  }
  if (Number(match.current_turn) !== Number(job.turn_number)) {
    throw new Error(`seed job turn mismatch: current=${match.current_turn} job=${job.turn_number}`);
  }

  const { data: players, error: playersError } = await admin
    .from("match_players")
    .select("player_slot")
    .eq("match_id", job.match_id)
    .order("player_slot", { ascending: true });
  if (playersError) {
    throw new Error(playersError.message);
  }

  const mapSelection = asObject(match.map_selection);
  const allPlayerSlots = ["player1", "player2"];
  const payload = {
    job_type: "seed_match",
    match_id: job.match_id,
    turn_number: Number(job.turn_number),
    rules_version: String(match.rules_version ?? "async_v1"),
    player_slots: allPlayerSlots,
    local_player_id: "player1",
    map_selection: mapSelection,
    match_seed: Number(mapSelection.match_seed ?? -1),
  };

  const result = await runGodotWorker(payload);
  ensureWorkerOk(result);
  logSnapshotSummary("seed_match", result.snapshot);
  const snapshot = asObject(result.snapshot);
  const snapshotVersion = Number(snapshot.snapshot_version ?? 0);
  if (snapshotVersion <= 0) {
    throw new Error("seed worker returned invalid snapshot_version");
  }

  const { error: completeError } = await admin.rpc("complete_seed_match_job", {
    p_job_id: job.job_id,
    p_snapshot_version: snapshotVersion,
    p_canonical_snapshot: snapshot,
    p_player_views: asObject(result.player_views),
    p_selected_map_index: Number(result.selected_map_index ?? mapSelection.selected_map_index ?? -1),
    p_match_seed: Number(result.map_seed ?? mapSelection.match_seed ?? -1),
    p_rules_version: String(result.rules_version ?? match.rules_version ?? "async_v1"),
  });
  if (completeError) {
    throw new Error(`complete_seed_match_job failed: ${completeError.message}`);
  }
}

async function handleResolveJob(job) {
  const { data: match, error: matchError } = await admin
    .from("matches")
    .select("match_id, current_turn")
    .eq("match_id", job.match_id)
    .single();
  if (matchError || !match) {
    throw new Error(matchError?.message ?? "resolve match not found");
  }
  if (Number(match.current_turn) !== Number(job.turn_number)) {
    throw new Error(`resolve job turn mismatch: current=${match.current_turn} job=${job.turn_number}`);
  }

  const snapshotVersion = Number(asObject(job.snapshot_ref).snapshot_version ?? 0);
  let snapshotQuery = admin
    .from("turn_snapshots")
    .select("canonical_snapshot, snapshot_version")
    .eq("match_id", job.match_id)
    .eq("turn_number", job.turn_number)
    .order("snapshot_version", { ascending: false })
    .limit(1);
  if (snapshotVersion > 0) {
    snapshotQuery = snapshotQuery.eq("snapshot_version", snapshotVersion);
  }
  const { data: snapshotRows, error: snapshotError } = await snapshotQuery;
  if (snapshotError) {
    throw new Error(snapshotError.message);
  }
  const snapshot = snapshotRows?.[0]?.canonical_snapshot;
  if (!snapshot) {
    throw new Error("canonical snapshot not found for resolve job");
  }

  const { data: orderRows, error: ordersError } = await admin
    .from("turn_orders")
    .select("payload, submitted_at")
    .eq("match_id", job.match_id)
    .eq("turn_number", job.turn_number)
    .order("submitted_at", { ascending: true });
  if (ordersError) {
    throw new Error(ordersError.message);
  }
  if (!orderRows || orderRows.length < 2) {
    throw new Error(`resolve job requires 2 submissions, found ${orderRows?.length ?? 0}`);
  }

  const payload = {
    job_type: "resolve_turn",
    snapshot,
    submissions: orderRows.map((row) => row.payload),
  };

  const result = await runGodotWorker(payload);
  ensureWorkerOk(result);
  logDebugSummary("resolve_turn before upkeep", result.debug_before_upkeep);
  logDebugSummary("resolve_turn after upkeep", result.debug_after_upkeep);
  logSnapshotSummary("resolve_turn", result.snapshot);
  const nextSnapshot = asObject(result.snapshot);
  const nextTurnNumber = Number(result.turn_number ?? nextSnapshot.turn_number ?? 0);
  const nextSnapshotVersion = Number(nextSnapshot.snapshot_version ?? 0);
  if (nextTurnNumber <= Number(job.turn_number) || nextSnapshotVersion <= 0) {
    throw new Error("resolve worker returned invalid next turn payload");
  }

  const { error: completeError } = await admin.rpc("complete_resolve_turn_job", {
    p_job_id: job.job_id,
    p_next_turn_number: nextTurnNumber,
    p_snapshot_version: nextSnapshotVersion,
    p_canonical_snapshot: nextSnapshot,
    p_player_views: asObject(result.player_views),
    p_game_over: Boolean(result.game_over),
    p_winner_id: String(result.winner_id ?? ""),
  });
  if (completeError) {
    throw new Error(`complete_resolve_turn_job failed: ${completeError.message}`);
  }
}

async function runGodotWorker(payload) {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "ff-async-worker-"));
  const inputPath = path.join(tempDir, `${randomUUID()}-input.json`);
  const outputPath = path.join(tempDir, `${randomUUID()}-output.json`);
  await fs.writeFile(inputPath, JSON.stringify(payload), "utf8");

  const args = [
    "--headless",
    "--path",
    PROJECT_ROOT,
    "res://scenes/async_worker_main.tscn",
    "--",
    inputPath,
    outputPath,
  ];

  try {
    console.log(`[worker] launching godot for ${payload.job_type} with timeout ${GODOT_TIMEOUT_MS}ms`);
    const { stdout, stderr } = await spawnAndWait(GODOT_BIN, args, GODOT_TIMEOUT_MS);
    if (stdout.trim() !== "") {
      console.log(`[worker] godot stdout\n${stdout.trimEnd()}`);
    }
    if (stderr.trim() !== "") {
      console.log(`[worker] godot stderr\n${stderr.trimEnd()}`);
    }
    const raw = await fs.readFile(outputPath, "utf8");
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(`godot worker failed: ${formatError(error)}`);
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
}

function spawnAndWait(command, args, timeoutMs = 120000) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: PROJECT_ROOT,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    let finished = false;
    const timer = Number.isFinite(timeoutMs) && timeoutMs > 0
      ? setTimeout(() => {
          if (finished) {
            return;
          }
          child.kill("SIGKILL");
          const details = buildProcessErrorDetails(stdout, stderr);
          reject(new Error(`timed out after ${timeoutMs}ms${details}`));
        }, timeoutMs)
      : null;
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (error) => {
      finished = true;
      if (timer) {
        clearTimeout(timer);
      }
      reject(error);
    });
    child.on("close", (code) => {
      finished = true;
      if (timer) {
        clearTimeout(timer);
      }
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }
      const message = `exit code ${code}${buildProcessErrorDetails(stdout, stderr)}`;
      reject(new Error(message));
    });
  });
}

function buildProcessErrorDetails(stdout, stderr) {
  const stdoutText = stdout.trim();
  const stderrText = stderr.trim();
  let details = "";
  if (stderrText !== "") {
    details += `\nstderr:\n${stderrText}`;
  }
  if (stdoutText !== "") {
    details += `\nstdout:\n${stdoutText}`;
  }
  return details;
}

function logSnapshotSummary(label, snapshotPayload) {
  const snapshot = asObject(snapshotPayload);
  const state = decodeValue(snapshot.state);
  const units = Array.isArray(state.units) ? state.units : [];
  let baseCount = 0;
  let towerCount = 0;
  for (const rawUnit of units) {
    const unit = asObject(rawUnit);
    const unitType = String(unit.unit_type ?? "").trim().toLowerCase();
    if (unitType === "base") {
      baseCount += 1;
    } else if (unitType === "tower") {
      towerCount += 1;
    }
  }
  console.log(`[worker] ${label} snapshot summary`, {
    turn_number: Number(snapshot.turn_number ?? state.turn_number ?? -1),
    snapshot_version: Number(snapshot.snapshot_version ?? -1),
    active_players: Array.isArray(state.active_players) ? state.active_players : [],
    living_players: Array.isArray(state.living_players) ? state.living_players : [],
    player_gold: asObject(state.player_gold),
    player_income: asObject(state.player_income),
    unit_count: units.length,
    base_count: baseCount,
    tower_count: towerCount,
  });
}

function logDebugSummary(label, payload) {
  const data = asObject(payload);
  if (Object.keys(data).length === 0) {
    return;
  }
  console.log(`[worker] ${label}`, data);
}

async function markJobFailed(jobId, message) {
  const { error } = await admin.rpc("fail_resolve_job", {
    p_job_id: jobId,
    p_error: message,
  });
  if (error) {
    console.error(`[worker] fail_resolve_job error for ${jobId}: ${error.message}`);
  }
}

function ensureWorkerOk(result) {
  if (!result || result.ok !== true) {
    const reason = result && typeof result === "object" ? result.reason ?? "unknown_reason" : "missing_result";
    throw new Error(`worker returned failure: ${reason}`);
  }
}

function asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function decodeValue(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => decodeValue(entry));
  }
  if (!value || typeof value !== "object") {
    return value;
  }
  if (Array.isArray(value.__gd_vec2i) && value.__gd_vec2i.length >= 2) {
    return { x: Number(value.__gd_vec2i[0]), y: Number(value.__gd_vec2i[1]) };
  }
  if (Array.isArray(value.__gd_vec2) && value.__gd_vec2.length >= 2) {
    return { x: Number(value.__gd_vec2[0]), y: Number(value.__gd_vec2[1]) };
  }
  const out = {};
  for (const [rawKey, rawVal] of Object.entries(value)) {
    let key = rawKey;
    if (key.startsWith("s:")) {
      key = key.slice(2);
    } else if (key.startsWith("i:")) {
      key = String(Number(key.slice(2)));
    } else if (key.startsWith("v2i:")) {
      key = key.slice(4);
    }
    out[key] = decodeValue(rawVal);
  }
  return out;
}

function formatError(error) {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error ?? "unknown_error");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

await main();
