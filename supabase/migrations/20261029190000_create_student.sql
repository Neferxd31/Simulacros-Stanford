-- The teacher creates student accounts that can sign in right away, without email verification.
-- Creating users through the Auth API needs the secret key, which never reaches the browser
create or replace function public.create_student(p_email text, p_password text, p_full_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
  v_full_name text := nullif(trim(p_full_name), '');
  v_id uuid := gen_random_uuid();
begin
  if not public.is_admin() then
    raise exception 'Solo la docente puede crear estudiantes';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'El correo no es válido';
  end if;
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'La contraseña debe tener al menos 8 caracteres';
  end if;
  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Ese correo ya está en uso';
  end if;

  -- Token columns must be '' instead of null: Supabase Auth fails to read null tokens
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"]}', jsonb_build_object('full_name', v_full_name), now(), now(),
    '', '', '', ''
  );
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (
    v_id::text, v_id,
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
    'email', now(), now(), now()
  );

  -- handle_new_user already created the profile as a student
  return v_id;
end;
$$;
