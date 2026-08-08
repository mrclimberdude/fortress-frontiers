import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

export const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export const handleCors = (req: Request): Response | null => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
};

export const getEnv = () => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return { supabaseUrl, anonKey, serviceRoleKey };
};

export const createUserClient = (req: Request) => {
  const { supabaseUrl, anonKey } = getEnv();
  const authHeader = req.headers.get("Authorization") ?? "";
  return createClient(supabaseUrl, anonKey, {
    global: {
      headers: {
        Authorization: authHeader,
      },
    },
  });
};

export const createAdminClient = () => {
  const { supabaseUrl, serviceRoleKey } = getEnv();
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
};

export const requireUser = async (req: Request) => {
  const client = createUserClient(req);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) {
    return { error: json({ error: "unauthorized" }, 401), client, user: null };
  }
  return { error: null, client, user: data.user };
};

export const getMembership = async (admin: ReturnType<typeof createAdminClient>, matchId: string, userId: string) => {
  const { data, error } = await admin
    .from("match_players")
    .select("match_id, user_id, player_slot, display_name")
    .eq("match_id", matchId)
    .eq("user_id", userId)
    .maybeSingle();
  return { data, error };
};
