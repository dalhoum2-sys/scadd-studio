// SCADD Partner Studio — "studio-ai" Edge Function (single file, no imports; paste into Supabase → Edge Functions → editor).
// Turns a user's request into structured design content. The Claude API key lives only in this function's secrets
// (ANTHROPIC_API_KEY); users never see it. Attempts are counted in the database: ai_claim (as the user, checks project
// rights and limits) before the call, ai_finish (as the service role) after it, so failed calls are not counted.
const env = (k: string, d = "") => Deno.env.get(k) ?? d;
const CORS = {
  "Access-Control-Allow-Origin": env("ALLOWED_ORIGIN", "*"),
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function rpc(fn: string, args: unknown, token?: string) {
  const key = token ? env("SUPABASE_ANON_KEY") : env("SUPABASE_SERVICE_ROLE_KEY");
  const r = await fetch(`${env("SUPABASE_URL")}/rest/v1/rpc/${fn}`, {
    method: "POST", headers: { apikey: key, Authorization: `Bearer ${token ?? key}`, "Content-Type": "application/json" }, body: JSON.stringify(args),
  });
  const t = await r.text(); const data = t ? JSON.parse(t) : null;
  if (!r.ok) throw Object.assign(new Error(data?.message ?? `rpc ${fn} ${r.status}`), { status: r.status === 401 ? 401 : 403 });
  return data;
}

const SYSTEM = `You write social-media content for SCADD (المركز العلمي للتوحّد والاضطرابات النمائية — Scientific Center for Autism and Developmental Disorders) and its training institute (معهد سكاد للتعليم والتدريب السريري), co-branded with a partner organisation. The output fills a design template; the platform draws both logos itself.

Write in Modern Standard Arabic: formal, institutional, clear, warm but never promotional hype. Evidence-informed and objective.
Hard rules:
- Never say autism is cured or disappears; no "شفاء", "علاج نهائي", "نضمن", "100%". Prefer "تدخّل قائم على الأدلة", "تحسّن في المهارات".
- Person-first, respectful language: "الأطفال ذوو التوحّد", never "مرضى التوحّد" or "معاناة".
- Never invent facts: dates, prices, phone numbers, links, numbers of seats, accreditation, statistics, names, sources. Use only what the request or the context provides. If something important is missing, leave the field empty and say so in notes.
- Scientific or awareness claims need a source; put a source only if the user gave one, otherwise leave it empty and flag it in notes.
- Text on the design must be short: title ≤ 9 words, eyebrow ≤ 3 words, text ≤ 30 words, up to 5 detail rows (label ≤ 3 words), CTA ≤ 6 words. Put longer explanation in the caption.
- Caption = the opening of the post (not the on-image text). Lead with the key message in the first line. Length by platform: Instagram ~125 characters visible before "more" (max 2200), Facebook ~125 visible, LinkedIn ~210 visible (max 3000, more professional tone). Promotional posts: short; awareness/educational posts: can be longer and structured.
- Hashtags: at most 5, relevant, Arabic where natural, without the # sign in the array.
- Carousel: only when the user asks for slides/carousel or the format is a LinkedIn document; 3–8 slides; each slide = a short heading line, newline, 1–2 sentences. For myth/fact content write "خرافة: …" then a new line "حقيقة: …".
- Choose layout from the given layouts and theme from scadd | partner | light. Use layout "stat" only when there is a real number; "photo" only if has_photo is true.
- Choose format only if format_picked is false and the request names a platform or shape; otherwise keep the current format.
- In revise mode: apply only the requested changes and keep everything else exactly as in "current".
Always answer by calling the fill_design tool. notes: one or two short Arabic sentences on assumptions made or information the user should add.`;

const TOOL = {
  name: "fill_design",
  description: "Return the content for the design fields.",
  input_schema: {
    type: "object",
    properties: {
      kind: { type: "string", description: "نوع المحتوى بكلمة أو كلمتين" },
      eyebrow: { type: "string" }, title: { type: "string" }, text: { type: "string" },
      details: { type: "array", maxItems: 5, items: { type: "object", properties: { label: { type: "string" }, value: { type: "string" } }, required: ["value"] } },
      stat: { type: ["object", "null"], properties: { num: { type: "string" }, label: { type: "string" } } },
      cta: { type: "string" }, contact: { type: "string" }, source: { type: "string" },
      slides: { type: "array", maxItems: 8, items: { type: "string" } },
      multi: { type: "boolean" },
      caption: { type: "string" }, hashtags: { type: "array", maxItems: 5, items: { type: "string" } },
      layout: { type: "string", enum: ["classic", "bold", "split", "photo", "stat", "card"] },
      theme: { type: "string", enum: ["scadd", "partner", "light"] },
      format: { type: "string" },
      notes: { type: "string" },
    },
    required: ["kind", "title", "caption", "layout", "theme", "notes"],
  },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed" }, 405);
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ ok: false, error: "Not signed in" }, 401);
  let body: any; try { body = await req.json(); } catch { return json({ ok: false, error: "Invalid JSON" }, 400); }
  const { design_id, project_id, mode, prompt, context } = body ?? {};
  if (!UUID.test(design_id ?? "") || !UUID.test(project_id ?? "")) return json({ ok: false, error: "Invalid design or project" }, 400);
  if (!["generate", "revise"].includes(mode)) return json({ ok: false, error: "Invalid mode" }, 400);
  if (typeof prompt !== "string" || prompt.trim().length < 10 || prompt.length > 3000) return json({ ok: false, error: "Prompt must be 10–3000 characters" }, 400);
  const ctx = JSON.stringify(context ?? {}); if (ctx.length > 30000) return json({ ok: false, error: "Context too large" }, 413);
  const key = env("ANTHROPIC_API_KEY");
  if (!key) return json({ ok: false, code: "not_configured", error: "not_configured" }, 503);

  let claim: any;
  try { claim = await rpc("ai_claim", { p_design: design_id, p_project: project_id, p_kind: mode, p_prompt: prompt }, token); }
  catch (e) { return json({ ok: false, error: (e as Error).message }, (e as any).status ?? 403); }

  const kind = claim.kind ?? mode;
  const user = `Mode: ${kind}\nContext (JSON):\n${ctx}\n\n${kind === "generate" ? "Request" : "Requested changes"} from the user (Arabic):\n<<<\n${prompt}\n>>>`;
  try {
    const r = await fetch(env("ANTHROPIC_BASE_URL", "https://api.anthropic.com") + "/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: env("AI_MODEL", "claude-sonnet-5-5"), max_tokens: 2500, system: SYSTEM, tools: [TOOL], tool_choice: { type: "tool", name: "fill_design" }, messages: [{ role: "user", content: user }] }),
      signal: AbortSignal.timeout(110_000),
    });
    const data = await r.json().catch(() => null);
    if (!r.ok) throw new Error(data?.error?.message ?? `model ${r.status}`);
    const block = (data?.content ?? []).find((b: any) => b.type === "tool_use" && b.name === "fill_design");
    if (!block?.input) throw new Error("no structured result");
    await rpc("ai_finish", { p_id: claim.id, p_ok: true, p_in: data?.usage?.input_tokens ?? null, p_out: data?.usage?.output_tokens ?? null });
    return json({ ok: true, result: block.input, used: claim.used, limit: claim.limit, remaining: claim.remaining });
  } catch (e) {
    await rpc("ai_finish", { p_id: claim.id, p_ok: false }).catch(() => {});
    console.error("studio-ai failed:", (e as Error).message);
    return json({ ok: false, error: "generation_failed: " + (e as Error).message }, 502);
  }
});
