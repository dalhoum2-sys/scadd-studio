-- SCADD Partner Studio — v4 migration: finance restricted to the platform owner and SCADD's finance manager,
-- financial figures moved to their own table, video formats, larger uploads. Run once after schema_studio.sql. Safe to re-run.

-- 1) a SCADD-wide finance manager role
alter table public.profiles drop constraint if exists profiles_global_role_check;
alter table public.profiles add constraint profiles_global_role_check check (global_role in ('owner','admin','finance'));
create or replace function public.is_fin_global() returns boolean language sql stable security definer set search_path = public as
  $$ select exists (select 1 from public.profiles where id = auth.uid() and active and global_role = 'finance') $$;
-- finance is now: the owner (and service) or the finance manager — no project role and no other staff
create or replace function public.can_finance(p uuid) returns boolean language sql stable security definer set search_path = public as
  $$ select public.is_owner() or public.is_fin_global() $$;
create or replace function public.fin_keys() returns text[] language sql immutable as $$ select array['fee','staff','nights','hotel','travel','transport','supplies','roomRate','venueDays','hospRate','hospDays','reserveMode','reserveAmount','reservePct','trainerMode','trainerRate','trainerExtra','onlineCost','targetMargin'] $$;

-- 2) financial figures live in their own table, readable and writable only with finance rights
create table if not exists public.project_finance (
  project_id uuid primary key references public.projects(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  rev        integer not null default 1,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);
alter table public.project_finance enable row level security;
revoke all on public.project_finance from anon;
grant select, insert, update on public.project_finance to authenticated;
drop policy if exists finance_select on public.project_finance;
drop policy if exists finance_insert on public.project_finance;
drop policy if exists finance_update on public.project_finance;
create policy finance_select on public.project_finance for select to authenticated using (public.can_finance(project_id));
create policy finance_insert on public.project_finance for insert to authenticated with check (public.can_finance(project_id));
create policy finance_update on public.project_finance for update to authenticated using (public.can_finance(project_id)) with check (public.can_finance(project_id));
create or replace function public.touch_finance() returns trigger language plpgsql as $$
begin new.updated_at := now(); new.updated_by := coalesce(auth.uid(), new.updated_by); if tg_op = 'UPDATE' then new.rev := old.rev + 1; end if; return new; end $$;
drop trigger if exists finance_touch on public.project_finance;
create trigger finance_touch before insert or update on public.project_finance for each row execute function public.touch_finance();

-- move existing figures out of projects.course (visible to every project member) into project_finance
insert into public.project_finance(project_id, data)
  select id, (select coalesce(jsonb_object_agg(k, course->k), '{}'::jsonb) from unnest(public.fin_keys()) k where course ? k)
  from public.projects
  on conflict (project_id) do update set data = public.project_finance.data || excluded.data;
alter table public.projects disable trigger projects_guard;
update public.projects set course = course - public.fin_keys() where course ?| public.fin_keys();
alter table public.projects enable trigger projects_guard;

-- projects.course may never carry financial keys again (protects against older clients)
create or replace function public.guard_project() returns trigger
  language plpgsql security definer set search_path = public as $$
declare r text;
begin
  new.updated_at := now();
  new.course := coalesce(new.course, '{}'::jsonb) - public.fin_keys();
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
create or replace function public.strip_course_insert() returns trigger language plpgsql as $$
begin new.course := coalesce(new.course, '{}'::jsonb) - public.fin_keys(); return new; end $$;
drop trigger if exists projects_strip on public.projects;
create trigger projects_strip before insert on public.projects for each row execute function public.strip_course_insert();

-- the finance manager sees every project and partner (names, course details), nothing else
drop policy if exists projects_select_finance on public.projects;
create policy projects_select_finance on public.projects for select to authenticated using (public.is_fin_global());
drop policy if exists partners_select_finance on public.partners;
create policy partners_select_finance on public.partners for select to authenticated using (public.is_fin_global());

-- the owner can create the finance manager's account
create or replace function public.admin_create_user(
  p_login text, p_password text, p_full_name text default null, p_partner text default null,
  p_global_role text default null, p_project uuid default null, p_role text default null)
returns uuid language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  v_staff boolean := public.is_staff();
  v_email text := public.login_to_email(p_login);
  v_username text := case when position('@' in p_login) > 0 then null else lower(trim(p_login)) end;
  v_uid uuid;
  v_partner text := p_partner;
  v_mode text;
  v_existing boolean := false;
begin
  perform set_config('scadd.trusted', 'on', true);  -- lets guard_profile accept the profile fields this function sets after its own checks
  if auth.uid() is null and not public.is_service() then raise exception 'Sign in required' using errcode = '42501'; end if;
  if coalesce(trim(p_login), '') = '' then raise exception 'اسم المستخدم مطلوب' using errcode = '22023'; end if;
  if v_username is not null and v_username !~ '^[a-z0-9][a-z0-9._-]{2,39}$' then
    raise exception 'اسم المستخدم: من 3 إلى 40 حرفاً إنجليزياً أو رقماً أو . _ -' using errcode = '22023'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'بريد إلكتروني غير صالح' using errcode = '22023'; end if;
  if p_role is not null and p_role not in ('manager','reviewer','editor','finance','viewer') then raise exception 'دور غير معروف' using errcode = '22023'; end if;
  if p_global_role is not null and p_global_role not in ('admin','finance') then raise exception 'صلاحية عامة غير معروفة' using errcode = '22023'; end if;
  if p_global_role is not null and not public.is_owner() then raise exception 'Only the platform owner can change global roles' using errcode = '42501'; end if;

  if not v_staff then
    if p_project is null or p_role is null or not public.can_manage(p_project) then
      raise exception 'تحتاج إلى صلاحية إدارة المشروع' using errcode = '42501'; end if;
    select partner_id, approval_mode into v_partner, v_mode from public.projects where id = p_project;
    if p_role = 'manager' then raise exception 'Only SCADD staff can appoint a project manager' using errcode = '42501'; end if;
    if p_role = 'reviewer' and v_mode <> 'project' then raise exception 'Reviewers are appointed by SCADD while approval stays with SCADD' using errcode = '42501'; end if;
  end if;

  select id into v_uid from auth.users where lower(email) = v_email;
  if v_uid is not null then
    v_existing := true;
  else
    if length(coalesce(p_password, '')) < 8 then raise exception 'كلمة المرور الأولية 8 أحرف على الأقل' using errcode = '22023'; end if;
    v_uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_email, crypt(p_password, gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('full_name', coalesce(p_full_name, '')), now(), now(), '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_uid, v_uid::text, jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true), 'email', now(), now(), now());
    -- the on_auth_user_created trigger has created the profile
    update public.profiles set username = v_username, full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
      partner_id = v_partner, must_change_password = true where id = v_uid;
  end if;

  if p_global_role is not null then update public.profiles set global_role = p_global_role where id = v_uid; end if;
  if p_project is not null and p_role is not null then
    insert into public.project_members (project_id, user_id, role) values (p_project, v_uid, p_role)
    on conflict (project_id, user_id) do update set role = excluded.role;
  end if;
  insert into public.activity_log(project_id, actor_id, actor_name, action, detail)
  values (p_project, auth.uid(), public.actor_name(), case when v_existing then 'user_attached' else 'user_created' end,
          jsonb_build_object('email', coalesce(v_username, v_email), 'role', p_role));
  return v_uid;
end $$;

-- 3) video formats and larger uploads (Supabase free plan caps a single file at 50 MB)
alter table public.designs drop constraint if exists designs_format_check;
alter table public.designs add constraint designs_format_check check (format in ('post45','post34','post11','story','carousel','fb','fb45','li11','li45','li','lidoc',
  'igv916','igv45','igv11','fbv916','fbv45','fbv169','liv45','liv11','liv169'));
update storage.buckets set file_size_limit = 52428800, allowed_mime_types = array['image/png','image/jpeg','image/webp','video/mp4','video/quicktime','video/webm'] where id = 'photos';

revoke all on function public.is_fin_global() from public, anon;
grant execute on function public.is_fin_global(), public.can_finance(uuid) to authenticated;
