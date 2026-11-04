begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000b0', 'teacher@test.co'),
  ('00000000-0000-0000-0000-0000000000b1', 'pupil@test.co');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000000b0';

insert into public.exams (id, title, status) values ('w1', 'Old', 'approved'), ('w2', 'Future', 'approved');
insert into public.sessions (id, exam_id, starts_at, created_by) values
  ('50000000-0000-0000-0000-000000000001', 'w1', now() - interval '3 hours', '00000000-0000-0000-0000-0000000000b0'),
  ('50000000-0000-0000-0000-000000000002', 'w2', now() + interval '1 day', '00000000-0000-0000-0000-0000000000b0');
insert into public.session_students (session_id, student_id) values
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1'),
  ('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000b1');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000b1", "role": "authenticated"}';
select lives_ok($$select public.start_attempt('50000000-0000-0000-0000-000000000001')$$,
  'starts hours after the session began: there is no time limit');
select throws_ok($$select public.start_attempt('50000000-0000-0000-0000-000000000002')$$, 'La sesión aún no está disponible');
select throws_ok($$select public.enable_access('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000b1')$$,
  'Solo la docente puede habilitar pruebas');

set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000b0", "role": "authenticated"}';
select lives_ok($$select public.enable_access('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000b1')$$,
  'the teacher enables the test early');

set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000b1", "role": "authenticated"}';
select ok(
  (select public.available_at(s) <= now() from public.session_students s where session_id = '50000000-0000-0000-0000-000000000002'),
  'the enabled test is available now'
);
select lives_ok($$select public.start_attempt('50000000-0000-0000-0000-000000000002')$$, 'starts once enabled');
reset role;

select is(
  (select count(*)::int from public.attempts where student_id = '00000000-0000-0000-0000-0000000000b1'),
  2,
  'one attempt per session'
);

select * from finish();
rollback;
