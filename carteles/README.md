# Carteles de almacén — Grimepur

Carteles A4 apaisados para imprimir, plastificar y pegar en las estanterías del almacén.

## Ficheros

- `estanteria-central.html` — 10 hojas: mapa general + 9 zonas.

## Cómo imprimir

1. Abre el fichero en el navegador (doble clic) y pulsa **Imprimir todo**.
2. En el diálogo de impresión:
   - Tamaño: **A4**
   - Orientación: **horizontal**
   - Márgenes: **ninguno**
   - Escala: **100 %** (tamaño real, nunca «ajustar a la página»)
   - Marca **Gráficos de fondo** (si no, las bandas de color salen en blanco)
3. Si prefieres llevarlo a imprimir fuera, usa «Guardar como PDF» con esos mismos ajustes.

Todo el color queda a 9 mm del borde, así que ninguna impresora recorta contenido.

## Zonas

| Código | Zona | Balda | Color |
|---|---|---|---|
| E0 | Sin abrir · sin registrar | 2 | gris pizarra |
| G1 | Recepción de garantías Kinetico | 2 | naranja |
| G2 | En espera de decisión | 2 | ámbar |
| G3 | Devolver a Kinetico | 3 | rojo |
| G4 | Pasa a stock | 3 | verde |
| C1 | Entrega a clientes (en mano) | 3 | azul |
| C2 | Envíos pendientes | 4 (abajo) | morado |
| C3 | Salidas de la semana | 4 (abajo) | burdeos |
| DOC | Albaranes y etiquetas | 1 (arriba) | gris oscuro |

La balda 1 queda reservada para los recambios de descalcificadores, con una ranura estrecha
para DOC. Las hojas se imprimen en el orden en que se mueve el material: entrada, garantías,
salidas y papeles.

## Cómo añadir o cambiar zonas

El texto de los carteles está en el array `ZONAS` al final de `estanteria-central.html`.
Cada entrada tiene `code`, `z` (color), `eyebrow`, `title`, `lead`, `yes[]`, `no[]` y `next`.
Añadir una zona nueva = añadir un objeto más al array. La hoja del mapa es la constante `MAPA`.
