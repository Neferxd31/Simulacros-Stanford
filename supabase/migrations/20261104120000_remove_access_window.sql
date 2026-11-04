-- Sin hora límite para iniciar: la estudiante inicia en cualquier momento desde la hora de la sesión.
-- La docente puede habilitar a una estudiante antes de esa hora
alter table public.session_students add column enabled_at timestamptz;

create or replace function public.available_at(assignment public.session_students)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select least(sessions.starts_at, coalesce(assignment.enabled_at, sessions.starts_at))
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
  if public.available_at(assignment) > now() then
    raise exception 'La sesión aún no está disponible';
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

-- Uses the server clock so enabling does not depend on the teacher's computer
create or replace function public.enable_access(p_session_id uuid, p_student_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo la docente puede habilitar pruebas';
  end if;

  update public.session_students
  set enabled_at = now()
  where session_id = p_session_id and student_id = p_student_id;
end;
$$;

drop function public.reopen_access(uuid, uuid);
drop function public.access_ends_at(public.session_students);
alter table public.session_students drop column access_until;
