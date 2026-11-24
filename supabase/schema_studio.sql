-- SCADD Partner Studio — v3 studio migration (free content, new sizes, uploads, generator quota)
-- Run once in Supabase → SQL Editor after schema.sql and schema_accounts.sql. Safe to re-run.

-- 1) designs: free content model and the new platform sizes
alter table public.designs drop constraint if exists designs_template_check;
alter table public.designs add constraint designs_template_check check (template in ('free','course','seats','fact','myth','trainer'));
alter table public.designs drop constraint if exists designs_format_check;
alter table public.designs add constraint designs_format_check check (format in ('post45','post34','post11','story','carousel','fb','fb45','li11','li45','li','lidoc'));

-- 2) uploaded ready-made designs can be larger than photos
update storage.buckets set file_size_limit = 10485760, allowed_mime_types = array['image/png','image/jpeg','image/webp'] where id = 'photos';

-- 3) generator requests: one generation + three revisions per design, plus daily and monthly ceilings
create table if not exists public.ai_requests (
  id            uuid primary key default gen_random_uuid(),
  design_id     uuid not null,
  project_id    uuid not null references public.projects(id) on delete cascade,
  user_id       uuid not null references auth.users(id) default auth.uid(),
  kind          text not null check (kind in ('generate','revise')),
  prompt        text not null,
  status        text not null default 'pending' check (status in ('pending','done','failed')),
  input_tokens  integer,
  output_tokens integer,
  created_at    timestamptz not null default now(),
  finished_at   timestamptz
);
create index if not exists ai_requests_design_idx on public.ai_requests(design_id, created_at);
create index if not exists ai_requests_user_idx on public.ai_requests(user_id, created_at);
create index if not exists ai_requests_project_idx on public.ai_requests(project_id, created_at);
alter table public.ai_requests enable row level security;
drop policy if exists ai_requests_select on public.ai_requests;
create policy ai_requests_select on public.ai_requests for select to authenticated using (public.can_view(project_id));
-- no insert/update/delete policies: rows are written only by the functions below

insert into public.settings(key, value) values ('ai_limits', '{"per_design":4,"per_user_day":30,"per_project_month":400}'::jsonb)
  on conflict (key) do nothing;

create or replace function public.ai_limits() returns jsonb language sql stable security definer set search_path = public as
$$ select coalesce((select value from public.settings where key = 'ai_limits'), '{}'::jsonb) || '{}'::jsonb $$;

-- a request counts unless it failed, or stayed pending for more than 10 minutes (crashed call)
create or replace function public.ai_counts(r public.ai_requests) returns boolean language sql immutable as
$$ select r.status = 'done' or (r.status = 'pending' and r.created_at > now() - interval '10 minutes') $$;

create or replace function public.ai_status(p_design uuid) returns jsonb
  language plpgsql stable security definer set search_path = public as $$
declare lim int := coalesce((public.ai_limits()->>'per_design')::int, 4); used int; pid uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in' using errcode = '42501'; end if;
  select project_id into pid from public.designs where id = p_design;
  if pid is not null and not public.can_view(pid) then raise exception 'Not allowed' using errcode = '42501'; end if;
  select count(*) into used from public.ai_requests r where r.design_id = p_design and public.ai_counts(r);
  return jsonb_build_object('used', used, 'limit', lim, 'remaining', greatest(0, lim - used));
end $$;

create or replace function public.ai_claim(p_design uuid, p_project uuid, p_kind text, p_prompt text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare L jsonb := public.ai_limits(); lim int := coalesce((L->>'per_design')::int, 4);
        day_lim int := coalesce((L->>'per_user_day')::int, 30); mon_lim int := coalesce((L->>'per_project_month')::int, 400);
        used int; dpid uuid; rid uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in' using errcode = '42501'; end if;
  if not public.can_edit(p_project) then raise exception 'You cannot edit designs in this project' using errcode = '42501'; end if;
  if p_kind not in ('generate','revise') then raise exception 'Invalid request kind' using errcode = '22023'; end if;
  if p_prompt is null or length(trim(p_prompt)) < 10 or length(p_prompt) > 3000 then raise exception 'Prompt must be 10–3000 characters' using errcode = '22023'; end if;
  select project_id into dpid from public.designs where id = p_design;
  if dpid is not null and dpid <> p_project then raise exception 'Design belongs to another project' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('ai:' || p_design::text));
  select count(*) into used from public.ai_requests r where r.design_id = p_design and public.ai_counts(r);
  if used >= lim then raise exception 'limit: all attempts for this design are used' using errcode = 'P0001'; end if;
  if (select count(*) from public.ai_requests r where r.user_id = auth.uid() and r.created_at > now() - interval '1 day' and public.ai_counts(r)) >= day_lim then
    raise exception 'limit: daily ceiling reached for this user' using errcode = 'P0001'; end if;
  if (select count(*) from public.ai_requests r where r.project_id = p_project and r.created_at > date_trunc('month', now()) and public.ai_counts(r)) >= mon_lim then
    raise exception 'limit: monthly ceiling reached for this project' using errcode = 'P0001'; end if;
  insert into public.ai_requests(design_id, project_id, user_id, kind, prompt) values (p_design, p_project, auth.uid(), case when used = 0 then 'generate' else 'revise' end, p_prompt)
    returning id into rid;
  return jsonb_build_object('id', rid, 'used', used + 1, 'limit', lim, 'remaining', lim - used - 1, 'kind', case when used = 0 then 'generate' else 'revise' end);
end $$;

-- called only by the studio-ai Edge Function with the service role, so a user cannot mark a delivered result as failed
create or replace function public.ai_finish(p_id uuid, p_ok boolean, p_in int default null, p_out int default null) returns void
  language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then raise exception 'Not allowed' using errcode = '42501'; end if;
  update public.ai_requests set status = case when p_ok then 'done' else 'failed' end, input_tokens = p_in, output_tokens = p_out, finished_at = now()
   where id = p_id and status = 'pending';
end $$;

revoke all on function public.ai_status(uuid), public.ai_claim(uuid, uuid, text, text), public.ai_finish(uuid, boolean, int, int), public.ai_limits() from public, anon;
revoke all on function public.ai_finish(uuid, boolean, int, int) from authenticated;
grant execute on function public.ai_status(uuid), public.ai_claim(uuid, uuid, text, text) to authenticated;
grant execute on function public.ai_finish(uuid, boolean, int, int) to service_role;
