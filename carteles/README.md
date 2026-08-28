# Carteles de almacén — Grimepur

Carteles A4 apaisados para imprimir, plastificar y pegar en las estanterías del almacén.

## Ficheros

- `estanteria-central.html` — 10 hojas: mapa general + 6 zonas acordadas + 3 propuestas opcionales.

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

| Código | Zona | Color |
|---|---|---|
| G1 | Recepción de garantías Kinetico | naranja |
| G2 | En espera de decisión | ámbar |
| G3 | Devolver a Kinetico | rojo |
| G4 | Pasa a stock | verde |
| C1 | Entrega a clientes (en mano) | azul |
| C2 | Envíos pendientes (balda inferior) | morado |
| E0 | Sin abrir · sin registrar *(propuesta)* | gris pizarra |
| C3 | Salidas de la semana *(propuesta)* | burdeos |
| DOC | Albaranes y etiquetas *(propuesta)* | gris oscuro |

## Cómo añadir o cambiar zonas

El texto de los carteles está en el array `ZONAS` al final de `estanteria-central.html`.
Cada entrada tiene `code`, `z` (color), `eyebrow`, `title`, `lead`, `yes[]`, `no[]` y `next`.
Añadir una zona nueva = añadir un objeto más al array. La hoja del mapa es la constante `MAPA`.
