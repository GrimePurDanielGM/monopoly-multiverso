# Datos que faltan por aportar

Este documento lista lo único que la app NO puede completar por sí sola porque depende de
material físico/oficial que debes proporcionar tú. Todo lo demás está implementado.

---

## 1. Textos reales de las cartas (Suerte, Caja de Comunidad, Pasado, Futuro)

**Estado:** el sistema de cartas está **completo** (mazos, robo, descarte, efectos automáticos,
cartas conservables, inventario, snapshot y UI). Lo que falta son los **textos reales**: ahora
mismo hay **36 cartas placeholder** (9 por mazo) marcadas con `temporary=true` y el aviso
«Carta temporal — pendiente de sustituir por carta real».

**Qué tienes que aportar:** el texto (y, si quieres, foto) de cada carta real de los cuatro mazos.

**Cómo se importan (turnkey, sin tocar código):**

1. Rellena [`docs/cards_import_template.csv`](cards_import_template.csv) — una fila por carta. Las
   columnas y los `effect_type` válidos están documentados en la cabecera del propio CSV.
   - Efectos automáticos disponibles: `bank_credit`, `bank_debit`, `each_player_credit`,
     `each_player_debit`, `to_start`, `to_jail`, `back_steps`, `jail_free`.
   - Para efectos aún no automatizados (p. ej. «muévete a una casilla concreta» que cruza de
     tablero, o «reparaciones por casa/hotel»): usa `effect_type = manual` y rellena
     `manual_instruction`. El anfitrión las resuelve a mano (la app ya soporta este flujo).
2. Pásame el CSV. Yo genero **una migración** que llama a `public._p8_load_deck(deck, json)` por
   cada mazo. Esa función (migración `0065`) **desactiva los placeholders e inserta las cartas
   reales** de forma idempotente y respetando las cartas ya repartidas. Ejemplo de uso:

   ```sql
   select public._p8_load_deck('chance', $$[
     {"card_ref":"chance-advance-go","title":"Avanza a la Salida","description":"…",
      "effect_type":"to_start","sort_order":1},
     {"card_ref":"chance-jail-free","title":"Sal de la cárcel","description":"Consérvala.",
      "effect_type":"jail_free","keepable":true,"sort_order":2}
   ]$$::jsonb);
   ```

3. Las partidas nuevas usarán automáticamente solo las cartas activas (las reales).

> Mientras no aportes los textos, las partidas funcionan con las cartas temporales (claramente
> marcadas como tales en la app).

---

## 2. Imágenes de los peones (opcional, estético)

**Estado:** la estructura está preparada (`token_catalog.image_url` / `image_alt`, migración
`0059`), pero **no hay imágenes asignadas**. Mientras tanto cada peón se muestra con su **nombre en
español** y un **emoji** derivado del slug.

**Qué tienes que aportar (si quieres el efecto 3D):** una imagen por peón + su texto alternativo.
Cuando las tengas, se cargan en `image_url`/`image_alt` y el frontend las usará automáticamente.

---

## 3. Catálogo de propiedades — pendientes menores (Fase 3)

Según `docs/catalog_extraction_phase3.md`, algunos importes se modelaron por convención
(precio = 2 × hipoteca; utilities sin alquiler por dados). Si alguna carta de propiedad oficial
difiere, indícamelo y ajusto el catálogo. No es bloqueante para jugar.

---

## Nada más es bloqueante

Reglas, turnos, banco, propiedades, subastas, bancarrota, tablero/cruce/guardianes, cárcel,
impuestos, parking, dados, servicios/estaciones, construcción/hipotecas, alquiler avanzado y
tratos están implementados y probados. Ver [`docs/reglas-implementadas.md`](reglas-implementadas.md).
