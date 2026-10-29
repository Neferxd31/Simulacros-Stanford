begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000b0', 'teacher@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'pupil@test.co');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000000b0';

insert into public.exams (id, title, status) values
  ('w1', 'Open', 'approved'), ('w2', 'Late', 'approved'), ('w3', 'Started', 'approved');
insert into public.sessions (id, exam_id, starts_at, created_by) values
  ('50000000-0000-0000-0000-000000000001', 'w1', now() - interval '30 minutes', '00000000-0000-0000-0000-0000000000b0'),
  ('50000000-0000-0000-0000-000000000002', 'w2', now() - interval '2 hours', '00000000-0000-0000-0000-0000000000b0'),
  ('50000000-0000-0000-0000-000000000003', 'w3', now() - interval '2 hours', '00000000-0000-0000-0000-0000000000b0');
insert into public.session_students (session_id, student_id) values
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1'),
  ('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000b1'),
  ('50000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000000b1');
-- Started within its hour, an hour and a half ago
insert into public.attempts (session_id, student_id, started_at)
values ('50000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000000b1', now() - interval '90 minutes');

select is(
  (select public.access_ends_at(s) from public.session_students s where session_id = '50000000-0000-0000-0000-000000000001'),
  (select starts_at + interval '1 hour' from public.sessions where id = '50000000-0000-0000-0000-000000000001'),
  'access ends one hour after the session starts'
);

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000b1", "role": "authenticated"}';
select lives_ok($$select public.start_attempt('50000000-0000-0000-0000-000000000001')$$, 'starts within the hour');
select throws_ok($$select public.start_attempt('50000000-0000-0000-0000-000000000002')$$,
  'La hora para iniciar esta prueba ya pasó. Comunícate con tu docente.');
select lives_ok($$select public.start_attempt('50000000-0000-0000-0000-000000000003')$$,
  'an attempt already started can be resumed after the hour');
select throws_ok($$select public.reopen_access('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000b1')$$,
  'Solo la docente puede rehabilitar pruebas');

set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000b0", "role": "authenticated"}';
select lives_ok($$select public.reopen_access('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000b1')$$,
  'the teacher reopens the access');

set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000b1", "role": "authenticated"}';
select ok(
  (select public.access_ends_at(s) > now() from public.session_students s where session_id = '50000000-0000-0000-0000-000000000002'),
  'the reopened access ends in the future'
);
select lives_ok($$select public.start_attempt('50000000-0000-0000-0000-000000000002')$$, 'starts after being reopened');
reset role;

select is(
  (select count(*)::int from public.attempts where student_id = '00000000-0000-0000-0000-0000000000b1'),
  3,
  'one attempt per session'
);

select * from finish();
rollback;
