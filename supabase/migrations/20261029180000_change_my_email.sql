-- Supabase Auth only applies an email change after a confirmation email, and its default
-- mailer only delivers to the project's team: users change their login email here instead
create or replace function public.change_my_email(p_email text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'El correo no es válido';
  end if;
  if exists (select 1 from auth.users where email = v_email and id <> auth.uid()) then
    raise exception 'Ese correo ya está en uso';
  end if;

  update auth.users set email = v_email, updated_at = now() where id = auth.uid();
  update auth.identities
  set identity_data = identity_data || jsonb_build_object('email', v_email), updated_at = now()
  where user_id = auth.uid() and provider = 'email';
end;
$$;

-- Keep profiles.email in sync with any email change (this function or the dashboard)
create or replace function public.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set email = new.email where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_email_changed
after update of email on auth.users
for each row
when (old.email is distinct from new.email)
execute function public.handle_user_email_change();
