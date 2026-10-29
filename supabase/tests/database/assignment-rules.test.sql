begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a0', 'teacher@test.co'),
  ('00000000-0000-0000-0000-0000000000a1', 'pupil1@test.co'),
  ('00000000-0000-0000-0000-0000000000a2', 'pupil2@test.co');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000000a0';
update public.profiles set full_name = 'Ana' where id = '00000000-0000-0000-0000-0000000000a1';

insert into public.exams (id, title, status) values ('x1', 'Exam 1', 'approved'), ('x2', 'Exam 2', 'approved');
insert into public.sessions (id, exam_id, starts_at, created_by) values
  ('30000000-0000-0000-0000-000000000001', 'x1', now(), '00000000-0000-0000-0000-0000000000a0'),
  ('30000000-0000-0000-0000-000000000002', 'x1', now(), '00000000-0000-0000-0000-0000000000a0'),
  ('30000000-0000-0000-0000-000000000003', 'x2', now(), '00000000-0000-0000-0000-0000000000a0');

-- Duplicate assignment rule
select lives_ok($$insert into public.session_students values
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1')$$, 'first assignment of an exam');
select throws_ok($$insert into public.session_students values
  ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a1')$$,
  'Ana ya tiene este simulacro asignado');
select lives_ok($$insert into public.session_students values
  ('30000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000000a1')$$, 'a different exam is allowed');
select lives_ok($$insert into public.session_students values
  ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a2')$$, 'another student gets the same exam');

-- Delete student
insert into public.attempts (id, session_id, student_id, current_part, current_part_started_at)
values ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', 1, now());
insert into public.answers (attempt_id, question_number, selected_option)
values ('40000000-0000-0000-0000-000000000001', 1, 'A');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000a2", "role": "authenticated"}';
select throws_ok($$select public.delete_student('00000000-0000-0000-0000-0000000000a1')$$,
  'Solo la docente puede eliminar estudiantes');

set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000a0", "role": "authenticated"}';
select throws_ok($$select public.delete_student('00000000-0000-0000-0000-0000000000a0')$$, 'Estudiante no encontrada');
select lives_ok($$select public.delete_student('00000000-0000-0000-0000-0000000000a1')$$, 'the teacher deletes a student');
reset role;

select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-0000000000a1'), 0, 'the account is gone');
select is(
  (select count(*)::int from public.session_students where student_id = '00000000-0000-0000-0000-0000000000a1')
  + (select count(*)::int from public.attempts where student_id = '00000000-0000-0000-0000-0000000000a1')
  + (select count(*)::int from public.answers where attempt_id = '40000000-0000-0000-0000-000000000001'),
  0,
  'assignments, attempts and answers are gone too'
);

select * from finish();
rollback;
