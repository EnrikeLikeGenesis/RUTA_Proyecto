# prueba_flutter

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Imágenes en reportes

Las imágenes se guardan en el bucket público `report-images` de Supabase y la
URL se almacena en `report_points.image_url`. Ejecutá este SQL en el editor SQL
de Supabase antes de crear reportes con imágenes:

```sql
alter table public.report_points
  add column if not exists image_url text;

insert into storage.buckets (id, name, public)
values ('report-images', 'report-images', true)
on conflict (id) do update set public = true;

drop policy if exists "Authenticated users can upload report images"
on storage.objects;

create policy "Authenticated users can upload report images"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'report-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users and admins can update reports"
on public.report_points;

create policy "Users and admins can update reports"
on public.report_points for update to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and profiles.is_admin is true
  )
)
with check (
  user_id = auth.uid()
  or exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and profiles.is_admin is true
  )
);
```

El bucket público permite mostrar las imágenes en el mapa y en los detalles del
reporte. La política limita las subidas a usuarios autenticados y a su propia
carpeta. La política de `UPDATE` permite modificar reportes propios y, si el
perfil tiene `is_admin = true`, también los de otros usuarios. La tabla también
debe tener una política `SELECT` que permita al usuario leer el reporte; la app
usa esa lectura para verificar que el cambio se haya guardado.

## Cuenta, perfil y consultas privadas

La sección de cuenta usa `profiles.phone_number` y `profiles.avatar_url`. La
foto se guarda en el bucket público `profile-images`. El soporte utiliza la
tabla `support_questions`; cada usuario solo puede leer sus propios hilos y los
administradores pueden leer y responder todos. Ejecutá este SQL en Supabase
antes de usar estas funciones. La política existente de lectura de `profiles`
debe permitir que el usuario lea su propio perfil.

```sql
alter table public.profiles
  add column if not exists phone_number text,
  add column if not exists avatar_url text;

drop policy if exists "Users can update their own profile"
on public.profiles;

create policy "Users can update their own profile"
on public.profiles for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- Limita los campos modificables para impedir que una cuenta se otorgue
-- privilegios de administración editando profiles.is_admin.
revoke update on public.profiles from authenticated;
grant update (username, first_name, last_name, email, phone_number, avatar_url)
on public.profiles to authenticated;

insert into storage.buckets (id, name, public)
values ('profile-images', 'profile-images', true)
on conflict (id) do update set public = true;

drop policy if exists "Users can upload their own profile image"
on storage.objects;

create policy "Users can upload their own profile image"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create table if not exists public.support_questions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  subject text not null check (char_length(subject) between 1 and 100),
  message text not null check (char_length(message) between 1 and 2000),
  admin_reply text,
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

alter table public.support_questions enable row level security;

drop policy if exists "Authors and admins can read support questions"
on public.support_questions;

create policy "Authors and admins can read support questions"
on public.support_questions for select to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.profiles
    where profiles.id = auth.uid() and profiles.is_admin is true
  )
);

drop policy if exists "Users can submit their own support questions"
on public.support_questions;

create policy "Users can submit their own support questions"
on public.support_questions for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "Admins can answer support questions"
on public.support_questions;

create policy "Admins can answer support questions"
on public.support_questions for update to authenticated
using (
  exists (
    select 1 from public.profiles
    where profiles.id = auth.uid() and profiles.is_admin is true
  )
)
with check (
  exists (
    select 1 from public.profiles
    where profiles.id = auth.uid() and profiles.is_admin is true
  )
);

revoke update on public.support_questions from authenticated;
grant update (admin_reply, responded_at)
on public.support_questions to authenticated;
```

Las consultas se muestran en la misma bandeja a administración, y solo el
autor y las personas administradoras pueden leer cada hilo. El cambio de correo
se solicita a Supabase Auth y puede requerir confirmación por email. Las
preferencias de tema, idioma y notificaciones se guardan localmente en el
dispositivo. Las alertas de tráfico y promociones solo guardan la preferencia;
todavía no hay una fuente conectada que las envíe. El texto de términos y
privacidad dentro de la app es un borrador informativo y debe ser revisado y
reemplazado por contenido legal aprobado antes de publicar.




.-----kkjhkjkjk......-----
