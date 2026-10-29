begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

-- Fixtures (as postgres, bypassing RLS)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'admin@test.co'),
  ('00000000-0000-0000-0000-000000000001', 'student1@test.co'),
  ('00000000-0000-0000-0000-000000000002', 'student2@test.co');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000000a';

insert into public.exams (id, title, status) values ('e1', 'Exam', 'approved'), ('e2', 'Future exam', 'approved');
insert into public.exam_parts (exam_id, part, section, first_q, last_q, choices_count, audio_path, audio_duration_s) values
  ('e1', 1, 'listening', 1, 10, 4, 'e1/audio/part-1.mp3', 300),
  ('e1', 2, 'listening', 11, 40, 3, 'e1/audio/part-2.mp3', 200),
  ('e1', 5, 'reading', 101, 140, 4, null, null);
insert into public.exam_pages (exam_id, page_order, part, image_path, first_q, last_q) values
  ('e1', 1, 1, 'e1/pages/1.webp', 1, 10),
  ('e1', 2, 2, 'e1/pages/2.webp', 11, 40),
  ('e1', 3, 5, 'e1/pages/3.webp', 101, 140);
insert into storage.objects (bucket_id, name) values
  ('exams', 'e1/pages/1.webp'),
  ('exams', 'e1/pages/2.webp'),
  ('exams', 'e1/pages/3.webp'),
  ('exams', 'e1/audio/part-1.mp3'),
  ('exams', 'e1/audio/part-2.mp3');

insert into public.sessions (id, exam_id, starts_at, created_by) values
  ('10000000-0000-0000-0000-000000000001', 'e1', now() - interval '1 minute', '00000000-0000-0000-0000-00000000000a'),
  ('10000000-0000-0000-0000-000000000002', 'e2', now() + interval '1 day', '00000000-0000-0000-0000-00000000000a');
insert into public.session_students (session_id, student_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001');

select is((select email from public.profiles where id = '00000000-0000-0000-0000-000000000001'), 'student1@test.co',
  'profile keeps the email');

-- Student1 starts
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select throws_ok($$select public.start_attempt('10000000-0000-0000-0000-000000000002')$$,
  'P0001', null, 'cannot start before starts_at');
select is(public.attempt_status(public.start_attempt('10000000-0000-0000-0000-000000000001')), 'pending',
  'start_attempt creates a pending attempt');
select lives_ok($$select public.start_attempt('10000000-0000-0000-0000-000000000001')$$, 'start_attempt can be called again');
select is((select count(*) from public.attempts), 1::bigint, 'only one attempt per session');
select is((select count(*) from storage.objects where bucket_id = 'exams'), 0::bigint, 'no files before part 1');
select throws_ok($$select public.save_answer((select id from public.attempts), 1, 'A')$$,
  'P0001', null, 'cannot answer before part 1 starts');

-- Listening part 1
select lives_ok($$select public.start_next_part((select id from public.attempts))$$, 'starts part 1');
select is((select current_part from public.attempts), 1::smallint, 'current part is 1');
select throws_ok($$select public.start_next_part((select id from public.attempts))$$,
  'P0001', null, 'cannot skip a part still playing');
select lives_ok($$select public.save_answer((select id from public.attempts), 1, 'A')$$, 'answers current part');
select throws_ok($$select public.save_answer((select id from public.attempts), 11, 'A')$$,
  'P0001', null, 'cannot answer a future part');
select is((select count(*) from storage.objects where bucket_id = 'exams'), 2::bigint, 'sees only part 1 page and audio');
select is(json_array_length(public.attempt_state((select id from public.attempts)) -> 'pages'), 1,
  'state lists only part 1 pages');

-- Part 1 audio ends
reset role;
update public.attempts set current_part_started_at = now() - interval '301 seconds' where student_id = '00000000-0000-0000-0000-000000000001';
select set_config('test.attempt_id', (select id::text from public.attempts where student_id = '00000000-0000-0000-0000-000000000001'), true);
set local role authenticated;

select lives_ok($$select public.start_next_part((select id from public.attempts))$$, 'starts part 2 after part 1 ends');
select is((select reading_started_at from public.attempts), now() + interval '200 seconds',
  'reading starts when the last audio ends');
select throws_ok($$select public.save_answer((select id from public.attempts), 11, 'D')$$,
  'P0001', null, 'part 2 only has A-C');
select lives_ok($$select public.save_answer((select id from public.attempts), 11, 'C')$$, 'answers part 2');
select throws_ok($$select public.save_answer((select id from public.attempts), 2, 'B')$$,
  'P0001', null, 'cannot go back to part 1');
select throws_ok($$select public.submit_attempt((select id from public.attempts))$$,
  'P0001', null, 'cannot submit during listening');

-- Reading
reset role;
update public.attempts set reading_started_at = now() - interval '1 minute' where student_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;

select is((select public.attempt_status(attempts) from public.attempts), 'reading', 'reading after last audio');
select lives_ok($$select public.save_answer((select id from public.attempts), 101, 'B')$$, 'answers reading');
select throws_ok($$select public.save_answer((select id from public.attempts), 11, 'A')$$,
  'P0001', null, 'listening is closed during reading');
select is((select count(*) from storage.objects where bucket_id = 'exams'), 1::bigint, 'sees only reading pages');

-- Another student cannot touch it
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';
select throws_ok($$select public.save_answer(current_setting('test.attempt_id')::uuid, 101, 'A')$$,
  'P0001', null, 'another student cannot write into the attempt');

-- Submit
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}';
select lives_ok($$select public.submit_attempt((select id from public.attempts))$$, 'submits during reading');
select throws_ok($$select public.save_answer((select id from public.attempts), 102, 'A')$$,
  'P0001', null, 'no answers after submit');
select is(public.attempt_state((select id from public.attempts))::jsonb, '{"status": "submitted"}'::jsonb,
  'state hides everything after submit');
select is((select count(*) from storage.objects where bucket_id = 'exams'), 0::bigint, 'no files after submit');
select lives_ok($$select public.submit_attempt((select id from public.attempts))$$, 'submit can be called again');

select * from finish();
rollback;
