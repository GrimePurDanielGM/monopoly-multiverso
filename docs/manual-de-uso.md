# Manual de uso — Monopoly: El Multiverso

App acompañante (host-assisted) para jugar al Monopoly del Multiverso con tablero y fichas físicas.
La app lleva el dinero, las propiedades, los turnos, la cárcel, las cartas y los tratos; vosotros
movéis las fichas físicas. El **anfitrión** arbitra lo que no se automatiza.

## 1. Empezar una partida
1. **Crear partida** → eliges nombre y configuras la sala (ver §2). Recibes un **código**.
2. Cada jugador abre la app, pulsa **Unirse**, mete el código y su nombre, y **elige peón**.
3. Cuando todos estén **Listos**, el anfitrión pulsa **Iniciar**.

> Puedes instalar la app (PWA) para abrirla como una aplicación. Si pierdes la conexión, vuelve a
> entrar con el mismo dispositivo: se recupera tu sesión.

## 2. Configuración de la sala (anfitrión, antes de iniciar)
- Nombre, mínimo/máximo de jugadores, dinero inicial.
- **Dados:** solo virtuales / permitir físicos / solo físicos.
- **Stock de construcciones:** casas (mín. 32) y hoteles (mín. 12) — súbelo si usáis dos tableros.
- **Permitir construir sin el grupo completo.**
- **Permitir tratos con propiedades construidas** (si no, no se pueden intercambiar propiedades con
  casas/hotel).
- **Permitir incorporaciones tardías.**

## 3. Durante el turno
- **Tirar dados** (o introducir el resultado si jugáis con dados físicos) y mover la ficha física.
- **Comprar** la propiedad donde caes, o el anfitrión inicia **subasta**.
- **Pagar alquiler** cuando caes en propiedad ajena (la app calcula el importe).
- **Cárcel:** intento por turno, dobles, pagar fianza o usar carta «Sal de la cárcel».
- **Cartas:** al caer en Suerte/Comunidad/Pasado/Futuro se roba carta. Los efectos claros se aplican
  solos; los ambiguos muestran instrucción para resolver a mano.
- **Construir / hipotecar** desde la tarjeta de la propiedad (con aprobación del anfitrión si
  procede). **Terminar turno.**

## 4. Tratos entre jugadores
1. **Tratos → Crear trato.** Eliges con quién, qué **ofreces** (dinero, propiedades, cartas) y qué
   **pides**. Puedes añadir un **acuerdo personal** (texto): queda registrado pero **lo cumplís a
   mano** (la app no lo ejecuta).
2. La otra parte lo ve como **«Tú entregas / Tú recibes»** y puede **Aceptar**, **Contraofertar** o
   **Rechazar**.
3. Si el trato incluye propiedades, cartas o acuerdo, lo aprueba el **anfitrión** (solo dinero no).
4. Al aprobarse, el intercambio es **atómico**. Las propiedades hipotecadas pasan hipotecadas.

## 5. Fin de partida
El anfitrión puede **pausar / reanudar / finalizar**. La bancarrota (frente a la banca o a un
acreedor) transfiere o libera las propiedades del jugador.

## Limitaciones conocidas
- **Cartas:** los textos actuales son **temporales** hasta importar las cartas reales (ver
  [`datos-pendientes.md`](datos-pendientes.md)). Algunos efectos (mover a una casilla que cruza de
  tablero, reparaciones por casa/hotel) se resuelven **manualmente**.
- **Acuerdos personales** de los tratos: la app los **registra**, no los hace cumplir.
- **Cobros «a cada jugador»**: a mejor esfuerzo según el saldo disponible (la deuda fina se arbitra).
- **Imágenes de peones:** de momento emoji + nombre (pendiente de imágenes reales).
- **Historial de cartas:** se muestra la última carta robada; no hay aún un historial dedicado de
  cartas (sí hay historial de movimientos de dinero en el ledger).
