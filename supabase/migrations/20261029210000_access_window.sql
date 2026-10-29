-- La estudiante tiene una hora desde el inicio de la sesión para iniciar la prueba.
-- Al rehabilitarla, la docente fija una hora nueva solo para esa estudiante
alter table public.session_students add column access_until timestamptz;

create or replace function public.access_ends_at(assignment public.session_students)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(assignment.access_until, sessions.starts_at + interval '1 hour')
  from public.sessions
  where sessions.id = assignment.session_id;
$$;

create or replace function public.start_attempt(p_session_id uuid)
returns public.attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment public.session_students;
  attempt public.attempts;
begin
  select * into assignment
  from public.session_students
  where session_id = p_session_id and student_id = auth.uid();
  if not found then
    raise exception 'No estás asignada a esta sesión';
  end if;

  -- Una prueba ya iniciada se retoma aunque haya pasado la hora de acceso
  select * into attempt
  from public.attempts
  where session_id = p_session_id and student_id = auth.uid();
  if found then
    return attempt;
  end if;

  if (select starts_at from public.sessions where id = p_session_id) > now() then
    raise exception 'La sesión aún no está disponible';
  end if;
  if now() > public.access_ends_at(assignment) then
    raise exception 'La hora para iniciar esta prueba ya pasó. Comunícate con tu docente.';
  end if;

  -- Un solo intento por sesión: volver a llamar devuelve el mismo
  insert into public.attempts (session_id, student_id)
  values (p_session_id, auth.uid())
  on conflict (session_id, student_id) do nothing;

  select * into attempt
  from public.attempts
  where session_id = p_session_id and student_id = auth.uid();
  return attempt;
end;
$$;

-- Uses the server clock so the new hour does not depend on the teacher's computer
create or replace function public.reopen_access(p_session_id uuid, p_student_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo la docente puede rehabilitar pruebas';
  end if;

  update public.session_students
  set access_until = now() + interval '1 hour'
  where session_id = p_session_id and student_id = p_student_id;
end;
$$;
