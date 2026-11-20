-- =====================================================================
-- Cuentas de prueba (Supabase Auth) + datos de demostración.
-- Ejecutar DESPUÉS de las migraciones (SQL Editor del proyecto o `supabase db reset`).
-- Todas las cuentas usan la contraseña: Porto2026!
-- Las cuentas quedan con el correo confirmado: no se envía ningún mail.
-- =====================================================================

do $$
declare
  v_email text;
  v_id uuid;
  v_cuentas text[] := array[
    'marta@porto.test', 'comision@porto.test', 'norma@porto.test', 'ruben@porto.test', 'julia@porto.test',
    'hugo@porto.test', 'carla@porto.test', 'elena@porto.test', 'tomas@porto.test', 'lucia@porto.test',
    'raul@porto.test', 'sofia@porto.test', 'andres@porto.test', 'beatriz@porto.test', 'ines@porto.test', 'diego@porto.test'];
begin
  foreach v_email in array v_cuentas loop
    select id into v_id from auth.users where email = v_email;
    if v_id is null then
      v_id := gen_random_uuid();
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, email_change, email_change_token_new, recovery_token)
      values (
        '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
        extensions.crypt('Porto2026!', extensions.gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}', jsonb_build_object('nombre', split_part(v_email, '@', 1)),
        now(), now(), '', '', '', '');
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), v_id, v_id::text,
        jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true), 'email', now(), now(), now());
    end if;
  end loop;
end $$;

-- El trigger de alta creó los perfiles como «comprador»; la demo asigna los roles del personal.
select interno.cargar_demo();
