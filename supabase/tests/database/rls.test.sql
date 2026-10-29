begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

-- Fixtures (as postgres, bypassing RLS)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'admin@test.co'),
  ('00000000-0000-0000-0000-000000000001', 'student1@test.co'),
  ('00000000-0000-0000-0000-000000000002', 'student2@test.co');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000000a';

insert into public.exams (id, title, status) values
  ('e1', 'Approved exam', 'approved'),
  ('e2', 'Draft exam', 'draft');
insert into public.exam_parts (exam_id, part, section, first_q, last_q, choices_count, audio_path, audio_duration_s) values
  ('e1', 1, 'listening', 1, 10, 4, 'exams/e1/audio/part-1.mp3', 300),
  ('e1', 5, 'reading', 101, 140, 4, null, null);
insert into public.exam_pages (exam_id, page_order, part, image_path, first_q, last_q)
values ('e1', 1, 1, 'exams/e1/pages/1.webp', 1, 5);
insert into public.answer_key (exam_id, question_number, correct_option) values ('e1', 101, 'C');

insert into public.sessions (id, exam_id, starts_at, created_by)
values ('10000000-0000-0000-0000-000000000000', 'e1', now(), '00000000-0000-0000-0000-00000000000a');
insert into public.session_students (session_id, student_id) values
  ('10000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000002');

-- student1 reading in progress, student2 already submitted
insert into public.attempts (id, session_id, student_id, current_part, current_part_started_at, reading_started_at, submitted_at) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000001',
   1, now() - interval '20 minutes', now() - interval '10 minutes', null),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000002',
   1, now() - interval '20 minutes', now() - interval '10 minutes', now());
insert into public.answers (attempt_id, question_number, selected_option) values
  ('20000000-0000-0000-0000-000000000001', 101, 'A'),
  ('20000000-0000-0000-0000-000000000002', 101, 'B');

insert into storage.objects (bucket_id, name) values ('exams', 'exams/e1/pages/1.webp');

-- Schema rules
select is((select role from public.profiles where id = '00000000-0000-0000-0000-000000000002'), 'student',
  'new auth user gets a student profile');
select throws_ok(
  $$insert into public.sessions (exam_id, starts_at, created_by) values ('e2', now(), '00000000-0000-0000-0000-00000000000a')$$,
  'P0001', null, 'session cannot use a draft exam');
select throws_ok(
  $$insert into public.exam_parts (exam_id, part, section, first_q, last_q, choices_count) values ('e2', 1, 'listening', 1, 10, 4)$$,
  '23514', null, 'listening part requires audio');

-- Effective attempt status
select is((select public.attempt_status(a) from public.attempts a where id = '20000000-0000-0000-0000-000000000001'), 'reading',
  'reading in progress');
select is((select public.attempt_status(a) from public.attempts a where id = '20000000-0000-0000-0000-000000000002'), 'submitted',
  'submitted attempt');
update public.attempts set reading_started_at = now() - interval '76 minutes' where id = '20000000-0000-0000-0000-000000000001';
select is((select public.attempt_status(a) from public.attempts a where id = '20000000-0000-0000-0000-000000000001'), 'submitted',
  'expired reading counts as submitted');
update public.attempts set reading_started_at = now() + interval '5 minutes' where id = '20000000-0000-0000-0000-000000000001';
select is((select public.attempt_status(a) from public.attempts a where id = '20000000-0000-0000-0000-000000000001'), 'listening',
  'last audio still playing is listening');
update public.attempts set current_part = null, current_part_started_at = null, reading_started_at = null
where id = '20000000-0000-0000-0000-000000000001';
select is((select public.attempt_status(a) from public.attempts a where id = '20000000-0000-0000-0000-000000000001'), 'pending',
  'no part started is pending');
update public.attempts set current_part = 1, current_part_started_at = now() - interval '20 minutes',
  reading_started_at = now() - interval '10 minutes'
where id = '20000000-0000-0000-0000-000000000001';

-- As student1
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(public.is_admin(), false, 'student is not admin');
select is((select count(*) from public.answer_key), 0::bigint, 'student cannot read answer key');
select is((select count(*) from public.exams), 0::bigint, 'student cannot read exams');
select is((select count(*) from public.exam_parts), 0::bigint, 'student cannot read exam parts');
select is((select count(*) from public.exam_pages), 0::bigint, 'student cannot read exam pages');
select is((select count(*) from public.profiles), 1::bigint, 'student reads only own profile');
select is((select count(*) from public.sessions), 1::bigint, 'student reads assigned session');
select is((select count(*) from public.attempts), 1::bigint, 'student reads only own attempt');
select is((select count(*) from public.answers), 1::bigint, 'student reads own answers while in progress');
select throws_ok(
  $$insert into public.answers (attempt_id, question_number, selected_option) values ('20000000-0000-0000-0000-000000000001', 102, 'A')$$,
  '42501', null, 'student cannot write answers directly');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000000001';
select is((select count(*) from storage.objects where bucket_id = 'exams'), 0::bigint, 'student cannot list exam files');

-- As student2 (submitted)
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';
select is((select count(*) from public.answers), 0::bigint, 'submitted student cannot read answers');

-- As admin
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}';
select is(public.is_admin(), true, 'admin is admin');
select is((select count(*) from public.answer_key), 1::bigint, 'admin reads answer key');
select is((select count(*) from public.answers where attempt_id::text like '20000000-%'), 2::bigint, 'admin reads all answers');
select is((select count(*) from storage.objects where bucket_id = 'exams' and name like 'exams/e1/%'), 1::bigint, 'admin lists exam files');
select lives_ok(
  $$insert into public.sessions (exam_id, starts_at) values ('e1', now())$$,
  'admin creates session for approved exam');

reset role;
select is((select role from public.profiles where id = '00000000-0000-0000-0000-000000000001'), 'student',
  'student could not promote herself');

select * from finish();
rollback;
