-- =====================================================================
-- SCADD Partner Studio · media.scadd.jo · schema v2 (projects & memberships)
-- Run in Supabase → SQL Editor. Idempotent: safe to re-run.
--
-- Access model
--   Global role (profiles.global_role): owner | admin | null
--     owner  = platform owner / project director: everything, incl. granting admin
--     admin  = SCADD staff: all projects, users, approvals
--   Project role (project_members.role), per project:
--     manager  = runs the project: content, approvals, finance, members (except managers)
--     reviewer = approves or returns content
--     editor   = creates and edits content (partner team)
--     finance  = course finance only
--     viewer   = read-only: approved content and archive
-- =====================================================================
create extension if not exists pgcrypto;

-- ---------- tables ----------
create table if not exists public.partners (
  id          text primary key default replace(gen_random_uuid()::text, '-', ''),
  name        text not null check (length(name) between 1 and 120),
  name_en     text,
  color       text not null default '#9a2c4f' check (color ~ '^#[0-9a-fA-F]{6}$'),
  logo_url    text,
  created_at  timestamptz not null default now()
);

create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text,
  global_role text check (global_role in ('owner','admin')),
  partner_id  text references public.partners(id) on delete set null,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.projects (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (length(name) between 1 and 160),
  partner_id       text not null references public.partners(id),
  city             text,
  start_date       date,
  status           text not null default 'planning' check (status in ('planning','active','completed','archived')),
  approval_mode    text not null default 'scadd' check (approval_mode in ('scadd','project')),  -- who gives final approval on co-branded content
  course           jsonb not null default '{}'::jsonb,
  drive_folder_id  text,
  drive_folder_url text,
  created_by       uuid references auth.users(id) default auth.uid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists public.project_members (
  project_id   uuid not null references public.projects(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  role         text not null check (role in ('manager','reviewer','editor','finance','viewer')),
  drive_permission_id text,
  drive_status text not null default 'pending' check (drive_status in ('pending','granted','failed','not_applicable')),
  drive_error  text,
  added_by     uuid references auth.users(id) default auth.uid(),
  created_at   timestamptz not null default now(),
  primary key (project_id, user_id)
);

create table if not exists public.designs (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects(id) on delete cascade,
  partner_id  text references public.partners(id),
  template    text not null check (template in ('course','seats','fact','myth','trainer')),
  format      text not null check (format in ('post45','post34','carousel','story','fb')),
  theme       text not null default 'scadd' check (theme in ('scadd','partner','light')),
  status      text not null default 'draft' check (status in ('draft','pending','approved','returned')),
  version     integer not null default 1 check (version >= 1),
  rev         integer not null default 0,
  fields      jsonb not null default '{}'::jsonb,
  slides      jsonb not null default '[]'::jsonb,
  created_by  uuid references auth.users(id) default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id)
);

create table if not exists public.design_comments (
  id          uuid primary key default gen_random_uuid(),
  design_id   uuid not null references public.designs(id) on delete cascade,
  author_id   uuid not null references auth.users(id) default auth.uid(),
  author_name text not null,
  body        text not null check (length(body) between 1 and 2000),
  created_at  timestamptz not null default now()
);

create table if not exists public.archive_files (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid not null references public.projects(id) on delete cascade,
  design_id     uuid references public.designs(id) on delete set null,
  name          text not null,
  mime_type     text,
  size_bytes    bigint,
  drive_file_id text not null,
  web_view_link text,
  kind          text not null default 'upload' check (kind in ('upload','approved_export')),
  uploaded_by   uuid references auth.users(id),
  uploaded_by_name text,
  created_at    timestamptz not null default now()
);

create table if not exists public.activity_log (
  id          bigserial primary key,
  project_id  uuid references public.projects(id) on delete cascade,
  actor_id    uuid,
  actor_name  text,
  action      text not null,
  detail      jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create table if not exists public.drive_jobs (
  id            bigserial primary key,
  project_id    uuid not null,
  user_id       uuid not null,
  email         text,
  action        text not null check (action in ('grant','revoke')),
  role          text,
  permission_id text,
  status        text not null default 'queued' check (status in ('queued','done','failed')),
  attempts      integer not null default 0,
  last_error    text,
  created_at    timestamptz not null default now()
);

create table if not exists public.settings (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now()
);

alter table public.projects add column if not exists approval_mode text not null default 'scadd' check (approval_mode in ('scadd','project'));

create index if not exists members_user_idx     on public.project_members(user_id);
create index if not exists designs_project_idx  on public.designs(project_id, updated_at desc);
create index if not exists comments_design_idx  on public.design_comments(design_id, created_at);
create index if not exists archive_project_idx  on public.archive_files(project_id, created_at desc);
create index if not exists activity_project_idx on public.activity_log(project_id, created_at desc);
create index if not exists drive_jobs_status_idx on public.drive_jobs(status, id);

-- ---------- permission helpers ----------
-- auth.uid() is null only in trusted server contexts (SQL editor, service role).
create or replace function public.is_service() returns boolean language sql stable
  as $$ select auth.uid() is null $$;

create or replace function public.is_staff() returns boolean
  language sql stable security definer set search_path = public as $$
  select public.is_service() or exists (select 1 from public.profiles where id = auth.uid() and active and global_role in ('owner','admin')) $$;

create or replace function public.is_owner() returns boolean
  language sql stable security definer set search_path = public as $$
  select public.is_service() or exists (select 1 from public.profiles where id = auth.uid() and active and global_role = 'owner') $$;

create or replace function public.project_role(p uuid) returns text
  language sql stable security definer set search_path = public as $$
  select m.role from public.project_members m join public.profiles pr on pr.id = m.user_id
  where m.project_id = p and m.user_id = auth.uid() and pr.active $$;

create or replace function public.can_view(p uuid) returns boolean language sql stable as
  $$ select public.is_staff() or public.project_role(p) is not null $$;
create or replace function public.can_edit(p uuid) returns boolean language sql stable as
  $$ select public.is_staff() or public.project_role(p) in ('manager','reviewer','editor') $$;
create or replace function public.approval_mode(p uuid) returns text
  language sql stable security definer set search_path = public as $$ select approval_mode from public.projects where id = p $$;
create or replace function public.can_review(p uuid) returns boolean language sql stable as
  $$ select public.is_staff() or (public.approval_mode(p) = 'project' and public.project_role(p) in ('manager','reviewer')) $$;
create or replace function public.can_finance(p uuid) returns boolean language sql stable as
  $$ select public.is_staff() or public.project_role(p) in ('manager','finance') $$;
create or replace function public.can_manage(p uuid) returns boolean language sql stable as
  $$ select public.is_staff() or public.project_role(p) = 'manager' $$;

create or replace function public.shares_project(other uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.project_members a join public.project_members b on a.project_id = b.project_id
                 where a.user_id = auth.uid() and b.user_id = other) $$;

create or replace function public.actor_name() returns text
  language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(full_name, email) from public.profiles where id = auth.uid()), 'النظام') $$;

create or replace function public.log_activity(p uuid, act text, det jsonb default '{}'::jsonb) returns void
  language sql security definer set search_path = public as $$
  insert into public.activity_log(project_id, actor_id, actor_name, action, detail) values (p, auth.uid(), public.actor_name(), act, det) $$;

-- ---------- triggers ----------
create or replace function public.handle_new_user() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, lower(new.email), coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- profiles: people edit their own name; staff manage accounts; only the owner grants owner/admin
create or replace function public.guard_profile() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if public.is_service() then return new; end if;
  if new.global_role is distinct from old.global_role and not public.is_owner() then
    raise exception 'Only the platform owner can change global roles' using errcode = '42501';
  end if;
  if (new.active is distinct from old.active or new.partner_id is distinct from old.partner_id or new.email is distinct from old.email)
     and not public.is_staff() then
    raise exception 'Only SCADD staff can change accounts' using errcode = '42501';
  end if;
  if old.id = auth.uid() and old.global_role = 'owner' and (new.active = false or new.global_role is distinct from 'owner') then
    raise exception 'The owner cannot demote or deactivate themselves' using errcode = '42501';
  end if;
  if old.global_role = 'owner' and old.id <> auth.uid() and (new.active = false or new.global_role is distinct from 'owner') then
    raise exception 'An owner account can only be changed by that owner or from the SQL editor' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update on public.profiles for each row execute function public.guard_profile();

-- projects: managers run details; finance edits the course block; editors may update enrolment counts only
create or replace function public.guard_project() returns trigger
  language plpgsql security definer set search_path = public as $$
declare r text;
begin
  new.updated_at := now();
  if public.is_staff() then return new; end if;
  r := public.project_role(old.id);
  if new.partner_id is distinct from old.partner_id or new.drive_folder_id is distinct from old.drive_folder_id or new.drive_folder_url is distinct from old.drive_folder_url
     or new.approval_mode is distinct from old.approval_mode then
    raise exception 'Only SCADD staff can change the partner, approval rule or archive folder' using errcode = '42501';
  end if;
  if r = 'manager' then return new; end if;
  if (new.name, new.city, new.start_date, new.status) is distinct from (old.name, old.city, old.start_date, old.status) then
    raise exception 'Only managers can change project details' using errcode = '42501';
  end if;
  if r = 'editor' and (new.course - 'trainees' - 'capacity') is distinct from (old.course - 'trainees' - 'capacity') then
    raise exception 'Editors can update enrolment only' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists projects_guard on public.projects;
create trigger projects_guard before update on public.projects for each row execute function public.guard_project();

create or replace function public.after_project() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then perform public.log_activity(new.id, 'project_created', jsonb_build_object('name', new.name));
  elsif new.status is distinct from old.status then perform public.log_activity(new.id, 'project_status', jsonb_build_object('from', old.status, 'to', new.status)); end if;
  return null;
end $$;
drop trigger if exists projects_after on public.projects;
create trigger projects_after after insert or update on public.projects for each row execute function public.after_project();

-- memberships: managers add/remove non-manager roles; Drive access follows through the job queue
create or replace function public.guard_member() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if public.is_staff() then return coalesce(new, old); end if;
  if tg_op <> 'INSERT' and old.role = 'manager' then raise exception 'Only SCADD staff can change a project manager' using errcode = '42501'; end if;
  if tg_op <> 'DELETE' and new.role = 'manager' then raise exception 'Only SCADD staff can appoint a project manager' using errcode = '42501'; end if;
  if tg_op <> 'DELETE' and new.role = 'reviewer' and public.approval_mode(new.project_id) <> 'project' then
    raise exception 'Reviewers are appointed by SCADD while approval stays with SCADD' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and (new.drive_permission_id, new.drive_status, new.drive_error) is distinct from (old.drive_permission_id, old.drive_status, old.drive_error) then
    raise exception 'Drive status is managed by the system' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists members_guard on public.project_members;
create trigger members_guard before insert or update or delete on public.project_members for each row execute function public.guard_member();

create or replace function public.after_member() returns trigger
  language plpgsql security definer set search_path = public as $$
declare em text;
begin
  if tg_op = 'DELETE' then
    select email into em from public.profiles where id = old.user_id;
    insert into public.drive_jobs(project_id, user_id, email, action, role, permission_id) values (old.project_id, old.user_id, em, 'revoke', old.role, old.drive_permission_id);
    perform public.log_activity(old.project_id, 'member_removed', jsonb_build_object('email', em, 'role', old.role));
    return null;
  end if;
  if tg_op = 'UPDATE' and new.role is not distinct from old.role then return null; end if;
  select email into em from public.profiles where id = new.user_id;
  insert into public.drive_jobs(project_id, user_id, email, action, role, permission_id)
  values (new.project_id, new.user_id, em, 'grant', new.role, case when tg_op = 'UPDATE' then old.drive_permission_id end);
  perform public.log_activity(new.project_id, case when tg_op = 'INSERT' then 'member_added' else 'member_role' end, jsonb_build_object('email', em, 'role', new.role));
  return null;
end $$;
drop trigger if exists members_after on public.project_members;
create trigger members_after after insert or update or delete on public.project_members for each row execute function public.after_member();

-- deactivating a person queues Drive revocation on every project; reactivating re-grants
create or replace function public.after_profile() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if new.active is distinct from old.active then
    insert into public.drive_jobs(project_id, user_id, email, action, role, permission_id)
    select m.project_id, m.user_id, new.email, case when new.active then 'grant' else 'revoke' end, m.role, m.drive_permission_id
    from public.project_members m where m.user_id = new.id;
    insert into public.activity_log(project_id, actor_id, actor_name, action, detail)
    values (null, auth.uid(), public.actor_name(), case when new.active then 'user_reactivated' else 'user_deactivated' end, jsonb_build_object('email', new.email));
  end if;
  if new.global_role is distinct from old.global_role then
    insert into public.activity_log(project_id, actor_id, actor_name, action, detail)
    values (null, auth.uid(), public.actor_name(), 'global_role', jsonb_build_object('email', new.email, 'role', new.global_role));
  end if;
  return null;
end $$;
drop trigger if exists profiles_after on public.profiles;
create trigger profiles_after after update on public.profiles for each row execute function public.after_profile();

-- designs: only reviewers approve or return; edits to approved work reopen it as a new version
create or replace function public.guard_design() returns trigger
  language plpgsql security definer set search_path = public as $$
declare reviewer boolean := public.can_review(new.project_id);
begin
  select partner_id into new.partner_id from public.projects where id = new.project_id;
  if tg_op = 'INSERT' then
    if not reviewer and new.status not in ('draft','pending') then
      raise exception 'Only reviewers can create approved designs' using errcode = '42501';
    end if;
    new.created_by := coalesce(auth.uid(), new.created_by); new.updated_by := coalesce(auth.uid(), new.updated_by); new.rev := 0;
    return new;
  end if;
  if new.project_id <> old.project_id and not public.is_staff() then
    raise exception 'Project cannot be changed' using errcode = '42501';
  end if;
  if not reviewer and new.status in ('approved','returned') and new.status is distinct from old.status then
    raise exception 'Only reviewers can approve or return a design' using errcode = '42501';
  end if;
  if not reviewer and old.status in ('approved','returned') and new.status = old.status
     and (new.fields, new.slides, new.template, new.format, new.theme) is distinct from (old.fields, old.slides, old.template, old.format, old.theme) then
    new.status := 'draft';
  end if;
  if old.status = 'approved' and new.status <> 'approved'
     and (new.fields, new.slides, new.template, new.format, new.theme) is distinct from (old.fields, old.slides, old.template, old.format, old.theme)
     and new.version <= old.version then
    new.version := old.version + 1;
  end if;
  if new.version < old.version then new.version := old.version; end if;
  new.rev := old.rev + 1; new.updated_at := now(); new.updated_by := auth.uid();
  new.created_by := old.created_by; new.created_at := old.created_at;
  return new;
end $$;
drop trigger if exists designs_guard on public.designs;
create trigger designs_guard before insert or update on public.designs for each row execute function public.guard_design();

create or replace function public.after_design() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then perform public.log_activity(new.project_id, 'design_created', jsonb_build_object('design', new.id, 'title', new.fields->>'title'));
  elsif new.status is distinct from old.status then
    perform public.log_activity(new.project_id, 'design_' || new.status, jsonb_build_object('design', new.id, 'title', new.fields->>'title', 'version', new.version));
  end if;
  return null;
end $$;
drop trigger if exists designs_after on public.designs;
create trigger designs_after after insert or update on public.designs for each row execute function public.after_design();

-- ---------- row-level security ----------
alter table public.partners        enable row level security;
alter table public.profiles        enable row level security;
alter table public.projects        enable row level security;
alter table public.project_members enable row level security;
alter table public.designs         enable row level security;
alter table public.design_comments enable row level security;
alter table public.archive_files   enable row level security;
alter table public.activity_log    enable row level security;
alter table public.drive_jobs      enable row level security;
alter table public.settings        enable row level security;

do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

create policy partners_select on public.partners for select to authenticated using (
  public.is_staff()
  or id = (select partner_id from public.profiles where id = auth.uid())
  or exists (select 1 from public.projects p where p.partner_id = partners.id and public.project_role(p.id) is not null));
create policy partners_insert on public.partners for insert to authenticated with check (public.is_staff());
create policy partners_update on public.partners for update to authenticated
  using (public.is_staff() or exists (select 1 from public.projects p where p.partner_id = partners.id and public.project_role(p.id) in ('manager','editor')))
  with check (public.is_staff() or exists (select 1 from public.projects p where p.partner_id = partners.id and public.project_role(p.id) in ('manager','editor')));
create policy partners_delete on public.partners for delete to authenticated using (public.is_staff());

create policy profiles_select on public.profiles for select to authenticated using (id = auth.uid() or public.is_staff() or public.shares_project(id));
create policy profiles_update on public.profiles for update to authenticated using (id = auth.uid() or public.is_staff()) with check (id = auth.uid() or public.is_staff());

create policy projects_select on public.projects for select to authenticated using (public.can_view(id));
create policy projects_insert on public.projects for insert to authenticated with check (public.is_staff());
create policy projects_update on public.projects for update to authenticated
  using (public.can_manage(id) or public.can_finance(id) or public.project_role(id) = 'editor')
  with check (public.can_manage(id) or public.can_finance(id) or public.project_role(id) = 'editor');
create policy projects_delete on public.projects for delete to authenticated using (public.is_owner());

create policy members_select on public.project_members for select to authenticated using (public.can_view(project_id));
create policy members_insert on public.project_members for insert to authenticated with check (public.can_manage(project_id));
create policy members_update on public.project_members for update to authenticated using (public.can_manage(project_id)) with check (public.can_manage(project_id));
create policy members_delete on public.project_members for delete to authenticated using (public.can_manage(project_id));

create policy designs_select on public.designs for select to authenticated using (
  public.can_edit(project_id) or (public.project_role(project_id) = 'viewer' and status = 'approved'));
create policy designs_insert on public.designs for insert to authenticated with check (public.can_edit(project_id));
create policy designs_update on public.designs for update to authenticated using (public.can_edit(project_id)) with check (public.can_edit(project_id));
create policy designs_delete on public.designs for delete to authenticated using (public.can_review(project_id) or (public.can_edit(project_id) and status = 'draft'));

create policy comments_select on public.design_comments for select to authenticated using (exists (select 1 from public.designs d where d.id = design_id));
create policy comments_insert on public.design_comments for insert to authenticated
  with check (author_id = auth.uid() and exists (select 1 from public.designs d where d.id = design_id and public.can_edit(d.project_id)));

create policy archive_select on public.archive_files for select to authenticated using (public.can_view(project_id));
create policy activity_select on public.activity_log for select to authenticated using (public.is_staff() or (project_id is not null and public.can_manage(project_id)));
create policy drive_jobs_select on public.drive_jobs for select to authenticated using (public.is_staff());
create policy settings_select on public.settings for select to authenticated using (true);
create policy settings_write on public.settings for all to authenticated using (public.is_staff()) with check (public.is_staff());

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.partners, public.profiles, public.projects, public.project_members, public.designs, public.design_comments, public.settings to authenticated;
grant select on public.archive_files, public.activity_log, public.drive_jobs to authenticated;
grant usage, select on all sequences in schema public to authenticated;
revoke all on all tables in schema public from anon;

-- ---------- storage ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('brand', 'brand', true, 3145728, array['image/png','image/jpeg','image/svg+xml','image/webp']),
       ('photos', 'photos', false, 5242880, array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists brand_select on storage.objects;
drop policy if exists brand_write on storage.objects;
drop policy if exists brand_update on storage.objects;
drop policy if exists photos_rw on storage.objects;
drop policy if exists photos_select on storage.objects;
drop policy if exists photos_insert on storage.objects;
create policy brand_select on storage.objects for select to authenticated using (bucket_id = 'brand');
create policy brand_write on storage.objects for insert to authenticated with check (bucket_id = 'brand' and (public.is_staff()
  or ((storage.foldername(name))[1] = 'partners' and exists (select 1 from public.projects p where p.partner_id = (storage.foldername(name))[2] and public.project_role(p.id) in ('manager','editor')))));
create policy photos_select on storage.objects for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$' and public.can_view(((storage.foldername(name))[1])::uuid));
create policy photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$' and public.can_edit(((storage.foldername(name))[1])::uuid));

-- ---------- starting data ----------
insert into public.partners (id, name, name_en, color) values ('cure', 'بيت العلاج', 'Cure House', '#9a2c4f') on conflict (id) do nothing;
insert into public.projects (name, partner_id, city, start_date, status, course)
select 'تدريب بغداد — بيت العلاج', 'cure', 'بغداد', '2027-01-10', 'active',
  '{"title":"دورة تحليل السلوك التطبيقي للعاملين مع الأطفال ذوي التوحّد","capacity":25,"trainees":15,"fee":500,"days":11,"staff":1,"nights":11,"hotel":100,"travel":400,"transport":200,"supplies":5,"roomRate":null,"venueDays":null,"hospRate":null,"hospDays":null,"reserveMode":0,"reserveAmount":300,"reservePct":10}'::jsonb
where not exists (select 1 from public.projects);

-- After you sign in once with your SCADD email, make yourself the owner (run here, in the SQL editor):
--   update public.profiles set global_role = 'owner' where email = 'mohammad@scadd.jo';
