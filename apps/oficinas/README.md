# GrimePur · Planta de oficinas — app de iPhone (PWA)

Estudio interactivo de distribución de la planta alta (plano base, distribuciones A y B,
vista 3D con three.js, partidas de obra y datos pendientes de medir), empaquetado como
**PWA instalable en iPhone**: icono propio, pantalla completa (safe areas del notch),
gestos táctiles en los planos (pellizco / doble toque / arrastre) y funcionamiento
**sin conexión** una vez instalada.

Es una app **estática sin build**: no forma parte del workspace pnpm ni afecta al
proyecto Monopoly. Todo vive en esta carpeta.

## Estructura

| Archivo | Qué es |
|---|---|
| `index.html` | La app completa (estilos, contenido, three.js embebido y lógica). |
| `manifest.webmanifest` | Nombre, icono y modo standalone de la PWA. |
| `sw.js` | Service worker: precacheo + offline + aviso de "versión nueva". |
| `icons/` | Iconos PNG generados con `tools/make-icons.mjs`. |
| `vercel.json` | Cabeceras de caché para cuando esta carpeta se despliega como proyecto propio. |

Dentro de `index.html` los datos viven en dos bloques marcados del script principal:

- **`GEOMETRÍA BASE`** — cotas del local: `H`, `W_S`, `D_E`, `W_N`, `POLY`, `WINS`
  (ventanas), `COLS` (pilares) y `FF` (altura suelo-a-suelo supuesta, en el bloque 3D).
- **`DIST`** — mobiliario y tabiques de las distribuciones A y B.

Cuando se midan los datos de la pestaña «Datos que faltan», basta con actualizar esos
bloques (planos SVG y vista 3D se regeneran solos a partir de ellos) y subir la versión
de `CACHE` en `sw.js` para que los iPhone instalados avisen de la actualización.

## Probar en local

```bash
cd apps/oficinas
python3 -m http.server 8080     # o: npx serve .
# abrir http://localhost:8080
```

## Publicar (necesario para instalarla: la PWA exige HTTPS)

Con Vercel (mismo flujo que la web del Monopoly):

1. vercel.com → **Add New → Project** → importar este repo.
2. En **Root Directory** elegir `apps/oficinas`.
3. Framework: **Other**. Sin build command y sin output directory (es estática).
4. Deploy → queda en `https://<proyecto>.vercel.app`.

Cualquier otro hosting estático con HTTPS sirve igual (Netlify, GitHub Pages…).

## Instalar en el iPhone

1. Abrir la URL en **Safari**.
2. **Compartir → Añadir a pantalla de inicio** (la propia app lo recuerda con un aviso).
3. Abrir desde el icono: arranca a pantalla completa y funciona en modo avión.

## Actualizar la app

1. Editar `index.html` (o regenerar iconos con `node tools/make-icons.mjs`).
2. Subir el número de versión en `sw.js` (`gp-oficinas-v1` → `v2`).
3. Desplegar. Los iPhone con la app instalada mostrarán «Hay una versión nueva» al abrirla.
