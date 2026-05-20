import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Pact = {
  id: string;
  title: string;
  core: "reactive" | "proactive";
  start_date: string;
  finish_date: string;
  status: string;
};

Deno.serve(async () => {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseURL || !serviceRoleKey) {
    return new Response("Missing Supabase environment", { status: 500 });
  }

  const supabase = createClient(supabaseURL, serviceRoleKey);
  const today = new Date().toISOString().slice(0, 10);

  const { data: pacts, error } = await supabase
    .from("pacts")
    .select("id,title,core,start_date,finish_date,status")
    .eq("status", "active")
    .lte("start_date", today)
    .gte("finish_date", today);

  if (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }

  const notifications = [];

  for (const pact of (pacts ?? []) as Pact[]) {
    const { data: participants } = await supabase
      .from("pact_participants")
      .select("user_id")
      .eq("pact_id", pact.id);

    for (const participant of participants ?? []) {
      if (pact.core === "reactive") {
        const { data: checkIn } = await supabase
          .from("check_ins")
          .select("id")
          .eq("pact_id", pact.id)
          .eq("user_id", participant.user_id)
          .eq("day", today)
          .maybeSingle();

        if (!checkIn) {
          notifications.push({
            user_id: participant.user_id,
            pact_id: pact.id,
            title: "Check-in still open",
            message: `${pact.title} needs your word today.`,
            scheduled_for: new Date().toISOString(),
          });
        }
      }
    }
  }

  if (notifications.length > 0) {
    await supabase.from("notifications").insert(notifications);
  }

  return Response.json({ evaluated: pacts?.length ?? 0, notifications: notifications.length });
});
