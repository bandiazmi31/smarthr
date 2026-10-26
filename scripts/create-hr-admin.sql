-- Creates the first Smart HR login. Run in the Supabase SQL editor (it needs the
-- auth schema, which the anon key cannot reach).
--
-- Edit the three values below, then run. Afterwards, change the password from the
-- Supabase dashboard or have the user reset it.
do $$
declare
  admin_email    text := 'hr.admin@example.com';
  admin_password text := 'change-me-before-running';
  admin_name     text := 'HR Administrator';
  admin_role     text := 'hr_manager';   -- hr_manager | hr_admin
  new_user_id    uuid := gen_random_uuid();
begin
  if exists (select 1 from auth.users where email = admin_email) then
    raise exception 'A user with email % already exists.', admin_email;
  end if;

  -- The token columns must be '' rather than NULL: the auth service scans them
  -- into non-nullable strings and a NULL makes every sign-in fail with
  -- "Database error querying schema".
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
    is_sso_user, is_anonymous,
    confirmation_token, recovery_token, email_change, email_change_token_new,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token
  ) values (
    '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated',
    admin_email, crypt(admin_password, gen_salt('bf')), now(),
    now(), now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    false, false,
    '', '', '', '', '', '', '', ''
  );

  -- GoTrue needs a matching identity row for password sign-in.
  insert into auth.identities (
    id, provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), new_user_id, new_user_id,
    jsonb_build_object(
      'sub', new_user_id::text, 'email', admin_email,
      'email_verified', true, 'phone_verified', false
    ),
    'email', now(), now(), now()
  );

  -- Without this row the account can authenticate but sees no employee data.
  insert into public.hr_profiles (id, full_name, role)
  values (new_user_id, admin_name, admin_role);

  raise notice 'Created HR account % (%).', admin_email, new_user_id;
end
$$;
