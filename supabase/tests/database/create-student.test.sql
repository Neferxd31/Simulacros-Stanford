begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f0', 'teacher@test.co'),
  ('00000000-0000-0000-0000-0000000000f1', 'pupil@test.co');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000000f0';

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000f1", "role": "authenticated"}';
select throws_ok($$select public.create_student('new@test.co', 'password123', 'New')$$,
  'Solo la docente puede crear estudiantes');

set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000f0", "role": "authenticated"}';
select throws_ok($$select public.create_student('no-es-correo', 'password123', 'New')$$, 'El correo no es válido');
select throws_ok($$select public.create_student('new@test.co', 'corta', 'New')$$,
  'La contraseña debe tener al menos 8 caracteres');
select throws_ok($$select public.create_student('Pupil@test.co', 'password123', 'New')$$, 'Ese correo ya está en uso');
select lives_ok($$select public.create_student(' New@Test.co ', 'password123', ' Ana Pérez ')$$, 'the teacher creates a student');
reset role;

select is(
  (select row(email, full_name, role)::text from public.profiles where email = 'new@test.co'),
  row('new@test.co', 'Ana Pérez', 'student')::text,
  'the new account gets a student profile with its name'
);
select ok(
  (select encrypted_password = extensions.crypt('password123', encrypted_password) and email_confirmed_at is not null
   from auth.users where email = 'new@test.co'),
  'the password works and the email needs no verification'
);
select is(
  (select count(*)::int from auth.identities where email = 'new@test.co' and provider = 'email'),
  1,
  'the account has an email identity'
);

select * from finish();
rollback;
