-- ============================================================
-- Profiles keep the email so the teacher can identify students
-- ============================================================

alter table public.profiles add column email text;

update public.profiles
set email = users.email
from auth.users
where users.id = profiles.id;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

-- ============================================================
-- What the student may see right now
-- ============================================================

-- Partes visibles: la parte de Listening en curso, o toda la sección de Reading
create function public.visible_parts(attempt public.attempts)
returns setof smallint
language sql
stable
security definer
set search_path = ''
as $$
  select parts.part
  from public.exam_parts parts
  join public.sessions on sessions.exam_id = parts.exam_id
  where sessions.id = attempt.session_id
    and (
      (public.attempt_status(attempt) = 'listening' and parts.part = attempt.current_part)
      or (public.attempt_status(attempt) = 'reading' and parts.section = 'reading')
    );
$$;

create function public.can_read_exam_object(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.attempts
    join public.sessions on sessions.id = attempts.session_id
    join public.exam_parts parts on parts.exam_id = sessions.exam_id
    left join public.exam_pages pages on pages.exam_id = parts.exam_id and pages.part = parts.part
    where attempts.student_id = auth.uid()
      and parts.part in (select public.visible_parts(attempts))
      and (pages.image_path = object_name or parts.audio_path = object_name)
  );
$$;

-- The student signs URLs with her own session; storage checks this policy per file
create policy "student reads current part files" on storage.objects
  for select to authenticated
  using (bucket_id = 'exams' and public.can_read_exam_object(name));

-- ============================================================
-- Attempt flow (called with supabase.rpc). Server time is the only clock.
-- ============================================================

create function public.start_attempt(p_session_id uuid)
returns public.attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt public.attempts;
begin
  if not exists (
    select 1 from public.session_students
    where session_id = p_session_id and student_id = auth.uid()
  ) then
    raise exception 'No estás asignada a esta sesión';
  end if;
  if (select starts_at from public.sessions where id = p_session_id) > now() then
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

create function public.start_next_part(p_attempt_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt public.attempts;
  current_ends_at timestamptz;
  next_part public.exam_parts;
  last_listening_part smallint;
begin
  select * into attempt
  from public.attempts
  where id = p_attempt_id and student_id = auth.uid()
  for update;
  if not found then
    raise exception 'Intento no encontrado';
  end if;
  if public.attempt_status(attempt) not in ('pending', 'listening') then
    raise exception 'El Listening ya terminó';
  end if;

  select attempt.current_part_started_at + make_interval(secs => parts.audio_duration_s)
  into current_ends_at
  from public.exam_parts parts
  join public.sessions on sessions.exam_id = parts.exam_id
  where sessions.id = attempt.session_id and parts.part = attempt.current_part;
  if current_ends_at > now() then
    raise exception 'La parte actual aún no termina';
  end if;

  select parts.* into next_part
  from public.exam_parts parts
  join public.sessions on sessions.exam_id = parts.exam_id
  where sessions.id = attempt.session_id
    and parts.section = 'listening'
    and parts.part > coalesce(attempt.current_part, 0)
  order by parts.part
  limit 1;
  if not found then
    raise exception 'No hay más partes de Listening';
  end if;

  select max(parts.part) into last_listening_part
  from public.exam_parts parts
  join public.sessions on sessions.exam_id = parts.exam_id
  where sessions.id = attempt.session_id and parts.section = 'listening';

  update public.attempts
  set
    current_part = next_part.part,
    current_part_started_at = now(),
    -- Reading arranca solo cuando termina el último audio
    reading_started_at = case
      when next_part.part = last_listening_part then now() + make_interval(secs => next_part.audio_duration_s)
    end
  where id = p_attempt_id;
end;
$$;

create function public.save_answer(p_attempt_id uuid, p_question integer, p_option text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt public.attempts;
  question_part public.exam_parts;
begin
  select * into attempt
  from public.attempts
  where id = p_attempt_id and student_id = auth.uid();
  if not found then
    raise exception 'Intento no encontrado';
  end if;

  select parts.* into question_part
  from public.exam_parts parts
  join public.sessions on sessions.exam_id = parts.exam_id
  where sessions.id = attempt.session_id and p_question between parts.first_q and parts.last_q;
  -- Solo se responde la parte de Listening en curso o la sección de Reading
  if not found or question_part.part not in (select public.visible_parts(attempt)) then
    raise exception 'La pregunta % no está disponible', p_question;
  end if;
  if p_option not in ('A', 'B', 'C', 'D') or (question_part.choices_count = 3 and p_option = 'D') then
    raise exception 'Opción inválida para la pregunta %', p_question;
  end if;

  insert into public.answers (attempt_id, question_number, selected_option)
  values (p_attempt_id, p_question, p_option)
  on conflict (attempt_id, question_number)
  do update set selected_option = excluded.selected_option, saved_at = now();
end;
$$;

create function public.submit_attempt(p_attempt_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt public.attempts;
  current_status text;
begin
  select * into attempt
  from public.attempts
  where id = p_attempt_id and student_id = auth.uid()
  for update;
  if not found then
    raise exception 'Intento no encontrado';
  end if;

  current_status := public.attempt_status(attempt);
  if current_status = 'submitted' then
    return;
  end if;
  if current_status <> 'reading' then
    raise exception 'Solo se puede enviar durante Reading';
  end if;

  update public.attempts set submitted_at = now() where id = p_attempt_id;
end;
$$;

-- Everything the student screen needs. After submitting it returns only the status.
create function public.attempt_state(p_attempt_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  attempt public.attempts;
  current_status text;
  result json;
begin
  select * into attempt
  from public.attempts
  where id = p_attempt_id and student_id = auth.uid();
  if not found then
    raise exception 'Intento no encontrado';
  end if;

  current_status := public.attempt_status(attempt);
  if current_status = 'submitted' then
    return json_build_object('status', current_status);
  end if;

  select json_build_object(
    'status', current_status,
    'server_now', now(),
    'current_part', attempt.current_part,
    'current_part_started_at', attempt.current_part_started_at,
    'reading_started_at', attempt.reading_started_at,
    'reading_ends_at', attempt.reading_started_at + make_interval(mins => exams.reading_minutes),
    'audio_path', (
      select audio_path from public.exam_parts
      where exam_id = exams.id and part = attempt.current_part
    ),
    'parts', (
      select json_agg(json_build_object(
        'part', part,
        'section', section,
        'first_q', first_q,
        'last_q', last_q,
        'choices_count', choices_count,
        'audio_duration_s', audio_duration_s
      ) order by part)
      from public.exam_parts
      where exam_id = exams.id
    ),
    'pages', (
      select coalesce(json_agg(json_build_object(
        'page_order', page_order,
        'part', part,
        'first_q', first_q,
        'last_q', last_q,
        'image_path', image_path
      ) order by page_order), '[]')
      from public.exam_pages
      where exam_id = exams.id and part in (select public.visible_parts(attempt))
    ),
    'answers', (
      select coalesce(json_object_agg(question_number, selected_option), '{}')
      from public.answers
      where attempt_id = attempt.id
    )
  )
  into result
  from public.sessions
  join public.exams on exams.id = sessions.exam_id
  where sessions.id = attempt.session_id;
  return result;
end;
$$;
