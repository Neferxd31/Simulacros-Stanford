begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'old@test.co'),
  ('00000000-0000-0000-0000-0000000000e2', 'taken@test.co');
insert into auth.identities (provider_id, user_id, identity_data, provider) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e1',
   '{"sub": "00000000-0000-0000-0000-0000000000e1", "email": "old@test.co"}', 'email');

set local role anon;
select throws_ok($$select public.change_my_email('anon@test.co')$$, 'Debes iniciar sesión');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000e1", "role": "authenticated"}';
select throws_ok($$select public.change_my_email('no-es-correo')$$, 'El correo no es válido');
select throws_ok($$select public.change_my_email('Taken@test.co')$$, 'Ese correo ya está en uso');
select lives_ok($$select public.change_my_email('  New@Test.co ')$$, 'a user changes their own email');
reset role;

select is(
  (select email from auth.users where id = '00000000-0000-0000-0000-0000000000e1'),
  'new@test.co',
  'the login email is trimmed and lowercased'
);
select is(
  (select email from auth.identities where user_id = '00000000-0000-0000-0000-0000000000e1'),
  'new@test.co',
  'the email identity follows the new email'
);
select is(
  (select email from public.profiles where id = '00000000-0000-0000-0000-0000000000e1'),
  'new@test.co',
  'the profile email stays in sync'
);

select * from finish();
rollback;
