-- Fallback account provisioning for the Phase 2 staff portal.
--
-- Normally staff activate themselves at /mobile/register and a trigger links the
-- new auth user to their employee record by email. Use this script only when that
-- is not possible -- e.g. "Confirm email" is on with no SMTP configured, or staff
-- have no mailbox. It inserts the auth user directly; the same trigger still runs,
-- so the link happens exactly as it would on self sign-up.
--
-- Run in the Supabase SQL editor (it needs the auth schema). Set the password,
-- then have each person change it.
do $$
declare
  target record;
  new_id uuid;
  initial_password text := 'change-me-before-running';
begin
  for target in
    select email, full_name
    from public.employees
    where is_active
      and portal_enabled
      and email is not null
      and user_id is null
  loop
    if exists (select 1 from auth.users where email = target.email) then
      raise notice 'Skipping %: an auth user already exists.', target.email;
      continue;
    end if;

    new_id := gen_random_uuid();

    -- The token columns must be '' rather than NULL, or every sign-in fails with
    -- "Database error querying schema". See scripts/create-hr-admin.sql.
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
      is_sso_user, is_anonymous,
      confirmation_token, recovery_token, email_change, email_change_token_new,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000', new_id, 'authenticated', 'authenticated',
      target.email, crypt(initial_password, gen_salt('bf')), now(),
      now(), now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
      false, false, '', '', '', '', '', '', '', ''
    );

    insert into auth.identities (
      id, provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), new_id, new_id,
      jsonb_build_object(
        'sub', new_id::text, 'email', target.email,
        'email_verified', true, 'phone_verified', false
      ),
      'email', now(), now(), now()
    );

    raise notice 'Created portal login for % (%).', target.full_name, target.email;
  end loop;
end
$$;

-- Confirm the trigger linked each new account to its employee record.
select e.employee_id, e.full_name, e.email, e.role, e.user_id is not null as linked
from public.employees e
where e.portal_enabled
order by e.employee_id;
