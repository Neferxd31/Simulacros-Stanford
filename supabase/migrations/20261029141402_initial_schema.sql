-- ============================================================
-- Tables
-- ============================================================

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  role text not null default 'student' check (role in ('admin', 'student')),
  full_name text
);

create table public.exams (
  id text primary key,
  title text not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'archived')),
  reading_minutes smallint not null default 75 check (reading_minutes > 0),
  created_at timestamptz not null default now()
);

create table public.exam_parts (
  exam_id text not null references public.exams on delete cascade,
  part smallint not null check (part between 1 and 7),
  section text not null check (section in ('listening', 'reading')),
  first_q smallint not null,
  last_q smallint not null,
  choices_count smallint not null check (choices_count in (3, 4)),
  audio_path text,
  audio_duration_s integer,
  primary key (exam_id, part),
  check (first_q between 1 and last_q),
  -- Cada parte de Listening necesita su audio para calcular cuándo termina
  check (section = 'reading' or (audio_path is not null and audio_duration_s > 0))
);

create table public.exam_pages (
  exam_id text not null,
  page_order smallint not null check (page_order > 0),
  part smallint not null,
  image_path text not null,
  first_q smallint,
  last_q smallint,
  primary key (exam_id, page_order),
  foreign key (exam_id, part) references public.exam_parts on delete cascade,
  check (first_q <= last_q)
);

create table public.answer_key (
  exam_id text not null references public.exams on delete cascade,
  question_number smallint not null check (question_number between 1 and 200),
  correct_option char(1) not null check (correct_option in ('A', 'B', 'C', 'D')),
  primary key (exam_id, question_number)
);

create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  exam_id text not null references public.exams,
  starts_at timestamptz not null,
  created_by uuid not null default auth.uid() references public.profiles,
  created_at timestamptz not null default now()
);

create table public.session_students (
  session_id uuid not null references public.sessions on delete cascade,
  student_id uuid not null references public.profiles on delete cascade,
  primary key (session_id, student_id)
);

create table public.attempts (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null,
  student_id uuid not null,
  started_at timestamptz not null default now(),
  -- Última parte de Listening iniciada (null = aún no empieza la Parte 1)
  current_part smallint,
  current_part_started_at timestamptz,
  -- Se fija al iniciar la última parte de Listening: inicio + duración del audio
  reading_started_at timestamptz,
  submitted_at timestamptz,
  unique (session_id, student_id),
  foreign key (session_id, student_id) references public.session_students on delete cascade
);

create table public.answers (
  attempt_id uuid not null references public.attempts on delete cascade,
  question_number smallint not null check (question_number between 1 and 200),
  selected_option char(1) not null check (selected_option in ('A', 'B', 'C', 'D')),
  saved_at timestamptz not null default now(),
  primary key (attempt_id, question_number)
);

-- ============================================================
-- Profiles: one row per auth user, student by default
-- ============================================================

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Users created before this migration
insert into public.profiles (id)
select id from auth.users
on conflict do nothing;

-- ============================================================
-- Sessions only for approved exams
-- ============================================================

create function public.check_exam_approved()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from public.exams where id = new.exam_id and status = 'approved') then
    raise exception 'El simulacro % no está aprobado', new.exam_id;
  end if;
  return new;
end;
$$;

create trigger sessions_exam_approved
  before insert or update of exam_id on public.sessions
  for each row execute function public.check_exam_approved();

-- ============================================================
-- Helpers
-- ============================================================

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- Estado efectivo con la hora del servidor: un intento vencido cuenta como enviado
-- sin depender de un proceso en segundo plano.
-- security definer: the student cannot read exams, but needs reading_minutes here.
create function public.attempt_status(attempt public.attempts)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when attempt.submitted_at is not null then 'submitted'
    when attempt.reading_started_at is not null
      and now() >= attempt.reading_started_at + make_interval(mins => exams.reading_minutes) then 'submitted'
    when attempt.reading_started_at is not null and now() >= attempt.reading_started_at then 'reading'
    when attempt.current_part is not null then 'listening'
    else 'pending'
  end
  from public.sessions
  join public.exams on exams.id = sessions.exam_id
  where sessions.id = attempt.session_id;
$$;

-- ============================================================
-- Row Level Security
-- Students never read exam content or keys directly: pages and audio arrive
-- as signed URLs, and answers are written only through RPC functions.
-- ============================================================

alter table public.profiles enable row level security;
alter table public.exams enable row level security;
alter table public.exam_parts enable row level security;
alter table public.exam_pages enable row level security;
alter table public.answer_key enable row level security;
alter table public.sessions enable row level security;
alter table public.session_students enable row level security;
alter table public.attempts enable row level security;
alter table public.answers enable row level security;

create policy "admin all" on public.profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin all" on public.exams for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin all" on public.exam_parts for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin all" on public.exam_pages for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin all" on public.answer_key for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin all" on public.sessions for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin all" on public.session_students for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin all" on public.attempts for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin all" on public.answers for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "student reads own profile" on public.profiles
  for select to authenticated
  using (id = auth.uid());

create policy "student reads own assignments" on public.session_students
  for select to authenticated
  using (student_id = auth.uid());

create policy "student reads assigned sessions" on public.sessions
  for select to authenticated
  using (exists (
    select 1 from public.session_students
    where session_students.session_id = sessions.id and session_students.student_id = auth.uid()
  ));

create policy "student reads own attempts" on public.attempts
  for select to authenticated
  using (student_id = auth.uid());

-- Tras enviar (o vencer) la estudiante ya no ve sus respuestas
create policy "student reads own answers while in progress" on public.answers
  for select to authenticated
  using (exists (
    select 1 from public.attempts
    where attempts.id = answers.attempt_id
      and attempts.student_id = auth.uid()
      and public.attempt_status(attempts) in ('listening', 'reading')
  ));

-- ============================================================
-- Storage: private bucket, admin only (students get signed URLs from the backend)
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('exams', 'exams', false, 52428800, array['image/webp', 'audio/mpeg']);

create policy "admin all exams bucket" on storage.objects
  for all to authenticated
  using (bucket_id = 'exams' and public.is_admin())
  with check (bucket_id = 'exams' and public.is_admin());
