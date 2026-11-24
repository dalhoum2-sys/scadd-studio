-- =====================================================================
-- SCADD Partner Studio · accounts managed by SCADD (no emails needed)
-- Run AFTER schema.sql. Idempotent.
--   admin_create_user  : SCADD staff (or a project manager, for their project) creates a login with an initial password
--   admin_set_password : reset a member's password (they must change it at next sign-in)
--   admin_set_active   : suspend / reactivate an account (blocks sign-in at the auth level too)
-- Logins without "@" become <username>@team.scadd.jo internally; no email is ever sent to that address.
-- =====================================================================
create extension if not exists pgcrypto;

alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists must_change_password boolean not null default false;
create unique index if not exists profiles_username_key on public.profiles (lower(username)) where username is not null;

create or replace function public.login_to_email(p_login text) returns text language sql immutable as $$
  select case when position('@' in p_login) > 0 then lower(trim(p_login)) else lower(trim(p_login)) || '@team.scadd.jo' end $$;

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
  if p_global_role is not null and p_global_role <> 'admin' then raise exception 'صلاحية عامة غير معروفة' using errcode = '22023'; end if;
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

create or replace function public.admin_set_password(p_user uuid, p_password text)
returns void language plpgsql security definer set search_path = public, extensions, auth as $$
declare v_target public.profiles; v_ok boolean;
begin
  select * into v_target from public.profiles where id = p_user;
  if v_target.id is null then raise exception 'المستخدم غير موجود' using errcode = '22023'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'كلمة المرور 8 أحرف على الأقل' using errcode = '22023'; end if;
  v_ok := public.is_staff();
  if v_target.global_role = 'owner' and p_user <> auth.uid() and not public.is_service() then v_ok := false; end if;
  if not v_ok then  -- a project manager may reset members of their project (not managers, not staff)
    v_ok := v_target.global_role is null and exists (
      select 1 from public.project_members m where m.user_id = p_user and m.role <> 'manager' and public.can_manage(m.project_id));
  end if;
  if not v_ok then raise exception 'لا تملك صلاحية إعادة تعيين كلمة مرور هذا المستخدم' using errcode = '42501'; end if;
  perform set_config('scadd.trusted', 'on', true);
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() where id = p_user;
  update public.profiles set must_change_password = (p_user <> coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)) where id = p_user;
  insert into public.activity_log(project_id, actor_id, actor_name, action, detail)
  values (null, auth.uid(), public.actor_name(), 'password_reset', jsonb_build_object('email', coalesce(v_target.username, v_target.email)));
end $$;

create or replace function public.admin_set_active(p_user uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_staff() then raise exception 'لموظفي سكاد فقط' using errcode = '42501'; end if;
  if p_user = auth.uid() then raise exception 'لا يمكنك إيقاف حسابك' using errcode = '22023'; end if;
  update public.profiles set active = p_active where id = p_user;   -- guard_profile enforces owner protections
  update auth.users set banned_until = case when p_active then null else 'infinity'::timestamptz end where id = p_user;
end $$;

-- people may clear their own "must change password" flag after choosing a new password
create or replace function public.password_changed() returns void language sql security definer set search_path = public as $$
  update public.profiles set must_change_password = false where id = auth.uid() $$;

revoke all on function public.admin_create_user(text, text, text, text, text, uuid, text) from public, anon;
revoke all on function public.admin_set_password(uuid, text) from public, anon;
revoke all on function public.admin_set_active(uuid, boolean) from public, anon;
revoke all on function public.password_changed() from public, anon;
grant execute on function public.admin_create_user(text, text, text, text, text, uuid, text) to authenticated;
grant execute on function public.admin_set_password(uuid, text) to authenticated;
grant execute on function public.admin_set_active(uuid, boolean) to authenticated;
grant execute on function public.password_changed() to authenticated;
grant execute on function public.login_to_email(text) to anon, authenticated;

-- guard_profile: also trust profile changes made inside the account functions above (they check permissions first)
create or replace function public.guard_profile() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if public.is_service() then return new; end if;
  if new.global_role is distinct from old.global_role and not public.is_owner() then
    raise exception 'Only the platform owner can change global roles' using errcode = '42501';
  end if;
  if current_setting('scadd.trusted', true) = 'on' then return new; end if;
  if (new.active is distinct from old.active or new.partner_id is distinct from old.partner_id or new.email is distinct from old.email
      or new.username is distinct from old.username) and not public.is_staff() then
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
