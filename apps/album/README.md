# 📸 Álbum familiar — web del álbum compartido de iCloud

Web para que **toda la familia** (Android incluido) pueda **ver en directo** el álbum
compartido de iCloud y **subir sus propias fotos y vídeos** desde cualquier móvil u ordenador.

- **Ver**: la web lee el álbum compartido de iCloud en directo (se actualiza sola cada
  pocos minutos). Cualquier foto que se añada al álbum desde un iPhone aparece aquí.
- **Subir**: cualquiera puede subir fotos con su nombre desde el navegador. Se ven al
  momento en la web para todo el mundo, en la sección «Subidas desde la web».
- **Instalar como app**: en Android, Chrome → menú ⋮ → «Añadir a pantalla de inicio»
  (es una PWA). En iPhone, Safari → Compartir → «Añadir a pantalla de inicio».

Sin dependencias: solo Node.js ≥ 20. Arranque local:

```bash
node server.mjs
# → http://localhost:8787
```

## ⚠️ Lo que Apple permite y lo que no (léelo, es importante)

Apple **no ofrece ninguna vía** para añadir fotos a un álbum compartido de iCloud desde
Android o desde una web: solo se puede publicar desde un dispositivo Apple con la app
Fotos. Por eso la sincronización funciona así:

| Dirección | ¿Automática? | Cómo funciona |
|---|---|---|
| iCloud → web | ✅ Sí | La web lee el feed público del álbum en directo |
| Web → iCloud | 🤝 Semiautomática | Las subidas quedan guardadas y visibles en la web; el anfitrión las pasa al álbum desde su iPhone en un minuto |

**Flujo del anfitrión** (una vez cada pocos días, desde el iPhone):

1. Abre la web y entra en «Modo anfitrión» (botón ☰, con tu PIN).
2. En «Subidas desde la web», abre cada foto nueva y toca **Descargar** → se guarda en Fotos.
3. En la app Fotos, selecciona las descargadas → Compartir → «Añadir a álbum compartido».
4. De vuelta en la web, marca cada una con ✓ («ya en iCloud»). En unos minutos aparecerán
   en la sección principal, ya sincronizadas por iCloud para todos.

> Consejo: los cuñados con iPhone pueden suscribirse al álbum con el enlace de iCloud y
> publicar directamente desde Fotos; esta web es la vía para los que tienen Android.

## Configuración (variables de entorno)

| Variable | Por defecto | Para qué sirve |
|---|---|---|
| `ALBUM_URL` | el álbum «PortAventura World 2026» | Enlace público del álbum (`https://www.icloud.com/sharedalbum/#…`). También vale `ALBUM_TOKEN` con solo el código |
| `PORT` | `8787` | Puerto del servidor |
| `DATA_DIR` | `./data` | Carpeta donde se guardan las fotos subidas (¡debe ser un disco persistente!) |
| `ADMIN_PIN` | *(vacío = desactivado)* | PIN del modo anfitrión (marcar como «ya en iCloud», borrar subidas) |
| `MAX_UPLOAD_MB` | `100` | Tamaño máximo por archivo subido |
| `CACHE_SEGUNDOS` | `60` | Cada cuánto se relee el álbum de iCloud como máximo |

El enlace del álbum es público: cualquiera que tenga la URL de esta web podrá ver las
fotos (igual que ocurre con el propio enlace de iCloud). No compartas la dirección fuera
de la familia.

## Cómo publicarla en internet (gratis o casi)

### Opción A — Vercel + Supabase (la que usa este repo; gratis y sin cuentas nuevas)

El monorepo ya se despliega en Vercel: al hacer push a `main`, el álbum queda publicado
automáticamente en **`https://<tu-dominio-de-vercel>/album`** gracias a:

- `api/*.mjs` (raíz del repo): funciones serverless que leen iCloud y gestionan subidas.
- `scripts/build-album-static.mjs`: copia `apps/album/public` a `apps/web/dist/album`
  tras el build de la web del juego (ver `buildCommand` en `vercel.json`).
- Las subidas van **directas del navegador a Supabase Storage** con URL firmada
  (el bucket `album-familiar` se crea solo, público, la primera vez), porque las
  funciones de Vercel limitan las peticiones a ~4,5 MB.

Para activar las **subidas** hay que darle a Vercel la clave de Supabase
(hasta entonces la web funciona en modo solo-ver). En el panel de Vercel →
proyecto → *Settings → Environment Variables*, añadir:

| Variable | Valor |
|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | La clave `service_role` (Supabase → *Project Settings → API*) |
| `ADMIN_PIN` | El PIN del modo anfitrión |
| `SUPABASE_URL` | Solo si no existe ya `VITE_SUPABASE_URL` (se reutiliza) |

y redeplegar. La clave `service_role` nunca llega al navegador: solo la usan las
funciones serverless.

### Opción B — Render.com (servidor Node propio, con disco)

1. En [render.com](https://render.com): **New → Web Service**, conecta este repositorio.
2. Ajustes:
   - **Root Directory**: `apps/album`
   - **Runtime**: Node · **Build Command**: *(vacío)* · **Start Command**: `node server.mjs`
3. **Disks**: añade un disco (1 GB basta para empezar) montado en `/data`.
4. **Environment**: `DATA_DIR=/data`, `ADMIN_PIN=<tu-pin>`, y si cambias de álbum, `ALBUM_URL=…`.
5. Comparte la URL que te da Render (`https://….onrender.com`) con la familia por WhatsApp.

### Opción C — Docker (NAS, Raspberry Pi, cualquier VPS)

```bash
cd apps/album
docker build -t album-familiar .
docker run -d --name album -p 8787:8787 -v album-datos:/data \
  -e ADMIN_PIN=1234 album-familiar
```

### Opción D — Node directo

```bash
ADMIN_PIN=1234 node server.mjs
```

## API interna (por si quieres trastear)

- `GET /api/album` — feed del álbum de iCloud normalizado (con `?refrescar=1` fuerza relectura)
- `GET /api/uploads` · `POST /api/upload` (multipart: `nombre`, `comentario`, `fotos`)
- `GET /api/descargar?checksum=…` — descarga una foto del álbum a través del servidor
- `POST /api/admin` — acciones del anfitrión (`comprobar`, `en_icloud`, `pendiente`, `borrar`)
- `GET /uploads/<archivo>` — sirve una foto subida (`?descargar` fuerza la descarga)

La lectura del álbum usa el API público de `sharedstreams.icloud.com` (el mismo que usa
la web oficial de Apple para los enlaces `icloud.com/sharedalbum`): `webstream` para el
feed y `webasseturls` para las URLs firmadas de las imágenes, que caducan cada ~3 h y el
servidor renueva solo.

## Tests

```bash
node --test
```
