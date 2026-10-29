# Simulacros TOEIC

React + Vite (Netlify) sobre Supabase (Postgres, Auth, Storage). Spec: `toeic-simulacros-spec.md`.

## Variables (`.env.local`, nunca en git)

```
VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
SUPABASE_SECRET_KEY=sb_secret_...   # solo scripts de carga; nunca con prefijo VITE_
```

En Netlify solo van las dos `VITE_`. En GitHub Secrets (keepalive): `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY`.

## Comandos

```bash
npm run dev                      # app contra el proyecto en la nube
npm run lint && npm run build
npx supabase start               # Supabase local (Docker)
npx supabase test db             # pruebas pgTAP de esquema, RLS y flujo del intento
npx supabase db push --linked    # subir migraciones al proyecto en la nube
```

## Agregar un simulacro

1. PDF y audios en `../simulacros-originales/<exam-id>/` (fuera del repo).
2. Escribir `exams/<exam-id>/exam-config.json` (partes, páginas, zonas a tapar).
3. Procesar y cargar (queda en borrador):
   ```bash
   python scripts/process-exam.py exams/<exam-id>/exam-config.json "../simulacros-originales/<exam-id>"
   node --env-file=.env.local scripts/upload-exam.js "../simulacros-originales/<exam-id>/processed"
   ```
4. Revisar y aprobar en la app (Docente → Simulacros).

## Roles

Todo usuario nuevo es `student`. Para hacer admin a alguien, en el SQL Editor:

```sql
update public.profiles set role = 'admin' where email = '<correo>';
```

## Prueba local de punta a punta

`.env.e2e.local` apunta al Supabase local y guarda las credenciales de prueba. `npm run dev -- --mode e2e` levanta la app contra él.
