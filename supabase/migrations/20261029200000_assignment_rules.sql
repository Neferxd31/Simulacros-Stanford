-- Una estudiante no puede tener dos veces asignado el mismo simulacro
create or replace function public.check_unique_exam_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student text;
begin
  if exists (
    select 1
    from public.session_students assigned
    join public.sessions assigned_session on assigned_session.id = assigned.session_id
    join public.sessions new_session on new_session.id = new.session_id
    where assigned.student_id = new.student_id
      and assigned.session_id <> new.session_id
      and assigned_session.exam_id = new_session.exam_id
  ) then
    select coalesce(full_name, email) into v_student from public.profiles where id = new.student_id;
    raise exception '% ya tiene este simulacro asignado', v_student;
  end if;
  return new;
end;
$$;

create trigger check_unique_exam_assignment
before insert or update on public.session_students
for each row
execute function public.check_unique_exam_assignment();

-- Deleting the auth user cascades to profile, assignments, attempts and answers
create or replace function public.delete_student(p_student_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo la docente puede eliminar estudiantes';
  end if;
  if not exists (select 1 from public.profiles where id = p_student_id and role = 'student') then
    raise exception 'Estudiante no encontrada';
  end if;

  delete from auth.users where id = p_student_id;
end;
$$;
