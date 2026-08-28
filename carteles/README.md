# Carteles de almacén — Grimepur

Carteles A4 apaisados para imprimir, plastificar y pegar en las estanterías del almacén.

## Ficheros

- `estanteria-central.html` — 10 hojas A4 apaisadas: mapa general + 9 zonas.
- `ficha-caja.html` — ficha A5 apaisada para rellenar a mano y pegar en cada caja
  (A4 vertical con dos fichas por hoja, se corta por la línea de puntos).

## Cómo imprimir

1. Abre el fichero en el navegador (doble clic) y pulsa el botón de imprimir.
   Desde una vista incrustada (panel lateral, previsualización) el navegador bloquea el
   diálogo de impresión: hay que abrir el fichero en su propia pestaña.
2. En el diálogo de impresión:
   - Tamaño: **A4**
   - Orientación: **horizontal** para los carteles, **vertical** para las fichas de caja
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

## Ficha de caja

Campos: fecha de entrada, zona (casillas con los nueve códigos), cliente, origen o proveedor,
nº de incidencia o garantía, albarán o pedido, contenido, qué falta por llegar, un registro de
movimientos de tres líneas (fecha · zona · qué se ha hecho) y el pie de decisión y salida.

Los códigos de zona de la ficha son los mismos que los de los carteles: si cambias uno,
cámbialo en los dos ficheros (`ZONAS` en cada uno).
