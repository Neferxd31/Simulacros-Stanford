-- La estudiante elige con qué sección empezar (Listening o Reading). Al terminar una
-- vuelve a la selección para hacer la otra; al terminar las dos, la prueba queda enviada.
-- reading_started_at pasa a ser el momento en que la estudiante entra a Reading.
alter table public.attempts add column reading_finished_at timestamptz;

-- Listening termina cuando acaba el audio de la última parte
create or replace function public.listening_done(attempt public.attempts)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.exam_parts parts
    join public.sessions on sessions.exam_id = parts.exam_id
    where sessions.id = attempt.session_id
      and parts.part = attempt.current_part
      and parts.part = (
        select max(listening.part) from public.exam_parts listening
        where listening.exam_id = parts.exam_id and listening.section = 'listening'
      )
      and now() >= attempt.current_part_started_at + make_interval(secs => parts.audio_duration_s)
  );
$$;

-- Reading termina con el botón "Terminar Reading" o al acabarse el tiempo
create or replace function public.reading_done(attempt public.attempts)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select attempt.reading_finished_at is not null
    or coalesce(now() >= attempt.reading_started_at + make_interval(mins => exams.reading_minutes), false)
  from public.sessions
  join public.exams on exams.id = sessions.exam_id
  where sessions.id = attempt.session_id;
$$;

-- pending: en la pantalla de selección de sección
create or replace function public.attempt_status(attempt public.attempts)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when attempt.submitted_at is not null then 'submitted'
    when public.listening_done(attempt) and public.reading_done(attempt) then 'submitted'
    when attempt.reading_started_at <= now() and not public.reading_done(attempt) then 'reading'
    when attempt.current_part is not null and not public.listening_done(attempt) then 'listening'
    else 'pending'
  end;
$$;

-- Same as before, without scheduling Reading after the last audio
create or replace function public.start_next_part(p_attempt_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt public.attempts;
  current_ends_at timestamptz;
  next_part public.exam_parts;
begin
  select * into attempt
  from public.attempts
  where id = p_attempt_id and student_id = auth.uid()
  for update;
  if not found then
    raise exception 'Intento no encontrado';
  end if;
  if public.attempt_status(attempt) not in ('pending', 'listening') then
    raise exception 'Termina primero la sección actual';
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
    raise exception 'El Listening ya terminó';
  end if;

  update public.attempts
  set current_part = next_part.part, current_part_started_at = now()
  where id = p_attempt_id;
end;
$$;

create or replace function public.start_reading(p_attempt_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt public.attempts;
begin
  select * into attempt
  from public.attempts
  where id = p_attempt_id and student_id = auth.uid()
  for update;
  if not found then
    raise exception 'Intento no encontrado';
  end if;
  if public.attempt_status(attempt) <> 'pending' then
    raise exception 'Termina primero la sección actual';
  end if;
  if attempt.reading_started_at is not null then
    raise exception 'El Reading ya terminó';
  end if;

  update public.attempts set reading_started_at = now() where id = p_attempt_id;
end;
$$;

create or replace function public.finish_reading(p_attempt_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt public.attempts;
begin
  select * into attempt
  from public.attempts
  where id = p_attempt_id and student_id = auth.uid()
  for update;
  if not found then
    raise exception 'Intento no encontrado';
  end if;
  if public.attempt_status(attempt) <> 'reading' then
    raise exception 'El Reading no está en curso';
  end if;

  update public.attempts set reading_finished_at = now() where id = p_attempt_id;
end;
$$;

-- Sending is automatic now: the attempt counts as submitted once both sections are done
drop function public.submit_attempt(uuid);

-- Same as before, plus which sections are already done
create or replace function public.attempt_state(p_attempt_id uuid)
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
    'listening_done', public.listening_done(attempt),
    'reading_done', public.reading_done(attempt),
    'current_part', attempt.current_part,
    'current_part_started_at', attempt.current_part_started_at,
    'reading_started_at', attempt.reading_started_at,
    'reading_minutes', exams.reading_minutes,
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
