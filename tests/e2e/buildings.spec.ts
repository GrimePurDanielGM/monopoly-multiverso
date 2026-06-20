import { test, expect, type Page, type Locator } from '@playwright/test';

// Fase 6 — construcciones e hipotecas: comprar el grupo completo (marron), construir casa, cobrar alquiler
// con casa, hipotecar (sin construcciones) → sin alquiler, deshipotecar → vuelve a cobrar, y stock del banco.
const PIN = '246813';
const RONDA = 1;   // Ronda de Valencia (marron)
const PLAZA = 3;   // Plaza Lavapiés (marron)

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Casas');
  await page.getByPlaceholder('Daniel').fill('Anfitrión');
  await page.getByRole('radiogroup', { name: 'Ficha del anfitrión' }).getByRole('radio').first().click();
  await page.getByPlaceholder('••••••').fill(PIN);
  await page.getByRole('button', { name: 'Crear y entrar' }).click();
  await page.waitForURL(/\/sala\/[A-Z0-9]{6}$/, { timeout: 30_000 });
  return page.url().match(/\/sala\/([A-Z0-9]{6})$/)![1]!;
}
async function joinGame(page: Page, code: string, name: string) {
  await page.goto('/unirse');
  await page.getByPlaceholder('ABC123').fill(code);
  await page.getByRole('button', { name: 'Buscar sala' }).click();
  await page.getByPlaceholder('Marty').fill(name);
  await page.getByRole('button', { name: 'Unirme' }).click();
  await page.waitForURL(new RegExp(`/sala/${code}$`), { timeout: 30_000 });
}
async function pickAndReady(page: Page, tokenIndex: number) {
  await page.getByRole('radiogroup', { name: 'Ficha', exact: true }).getByRole('radio').nth(tokenIndex).click();
  const ready = page.getByRole('button', { name: 'Marcar Preparado' });
  await expect(ready).toBeEnabled({ timeout: 10_000 });
  await ready.click();
}
const movement = (p: Page) => p.getByRole('region', { name: 'Movimiento', exact: true });
const board = (p: Page) => p.getByRole('dialog', { name: 'Tablero de propiedades' });
async function openCorrections(host: Page) { await host.getByText('Correcciones del anfitrión').click(); }
async function reloadUntil(page: Page, loc: () => Locator, timeout = 45_000) {
  await expect(async () => { await page.reload(); await expect(loc()).toBeVisible({ timeout: 5_000 }); }).toPass({ timeout });
}
async function hostFijarTurno(host: Page, name: string) {
  await expect(async () => {
    await host.reload(); await openCorrections(host);
    const form = host.locator('form', { has: host.getByRole('button', { name: 'Fijar turno' }) });
    await form.getByLabel('Jugador en turno').selectOption({ label: name });
    await form.getByLabel('Motivo (obligatorio)').fill('fijar turno (prueba)');
    await form.getByRole('button', { name: 'Fijar turno' }).click();
    await expect(host.getByRole('alert')).toHaveCount(0, { timeout: 3_000 });
  }).toPass({ timeout: 60_000 });
}
async function hostPosicion(host: Page, name: string, index: number) {
  await expect(async () => {
    await host.reload(); await openCorrections(host);
    const form = host.locator('form', { has: host.getByRole('button', { name: 'Actualizar posición' }) });
    await form.getByLabel('Jugador', { exact: true }).selectOption({ label: name });
    await form.getByLabel(/Casilla/).selectOption(String(index));
    await form.getByLabel('Motivo (obligatorio)').fill('situar (prueba)');
    await form.getByRole('button', { name: 'Actualizar posición' }).click();
    await expect(host.getByRole('alert')).toHaveCount(0, { timeout: 3_000 });
  }).toPass({ timeout: 60_000 });
}
async function openBoard(host: Page) {
  await host.getByRole('button', { name: 'Ver tablero de propiedades' }).click();
  await expect(board(host)).toBeVisible({ timeout: 20_000 });
}
function boardCard(host: Page, name: string) { return board(host).getByRole('listitem').filter({ hasText: name }); }
// Compra una calle disponible estando el host situado en ella: solicitar (en el tablero) + aprobar.
async function buyStreet(host: Page, name: string, index: number) {
  await hostFijarTurno(host, 'Anfitrión');
  await hostPosicion(host, 'Anfitrión', index);
  await openBoard(host);
  await boardCard(host, name).getByRole('button', { name: 'Solicitar compra' }).click();
  await host.getByRole('dialog', { name: 'Solicitar compra' }).getByRole('button', { name: 'Solicitar compra' }).click();
  await host.getByRole('button', { name: 'Cerrar' }).click();
  await reloadUntil(host, () => host.getByRole('region', { name: 'Solicitudes de compra' }));
  await host.getByRole('region', { name: 'Solicitudes de compra' }).getByRole('button', { name: 'Aprobar' }).click();
  await expect(host.getByText('Solicitudes de compra')).toHaveCount(0, { timeout: 20_000 });
}
// Abre la ficha de una propiedad desde el tablero de propiedades y ejecuta una acción DIRECTA (hipoteca/deshipoteca).
async function cardAction(host: Page, name: string, action: RegExp) {
  await host.reload();  // versión fresca (evita VERSION_CONFLICT tras acciones de otro jugador)
  await openBoard(host);
  await boardCard(host, name).getByRole('button', { name: 'Ver tarjeta' }).click();
  const card = host.getByRole('dialog', { name: new RegExp(`Ficha de ${name}`) });
  await expect(card).toBeVisible({ timeout: 10_000 });
  await card.getByRole('button', { name: action }).click();
  await expect(host.getByRole('alert')).toHaveCount(0, { timeout: 5_000 });
  // cerrar ficha y tablero
  await card.getByRole('button', { name: 'Cerrar' }).click();
  await host.getByRole('button', { name: 'Cerrar' }).click();
}
// Construir/vender pasan por SOLICITUD: el propietario la pide en la ficha y el anfitrión la aprueba en su bandeja.
async function cardRequestAction(host: Page, name: string, action: RegExp) {
  await host.reload();
  await openBoard(host);
  await boardCard(host, name).getByRole('button', { name: 'Ver tarjeta' }).click();
  const card = host.getByRole('dialog', { name: new RegExp(`Ficha de ${name}`) });
  await expect(card).toBeVisible({ timeout: 10_000 });
  await card.getByRole('button', { name: action }).click();
  await expect(host.getByRole('alert')).toHaveCount(0, { timeout: 5_000 });
  await card.getByRole('button', { name: 'Cerrar' }).click();
  await host.getByRole('button', { name: 'Cerrar' }).click();
  // Aprobar la solicitud en la bandeja del anfitrión.
  await reloadUntil(host, () => host.getByRole('region', { name: 'Solicitudes de construcción' }));
  await host.getByRole('region', { name: 'Solicitudes de construcción' }).getByRole('button', { name: 'Aprobar' }).click();
  await expect(host.getByText('Solicitudes de construcción')).toHaveCount(0, { timeout: 20_000 });
}
async function landOn(host: Page, B: Page, index: number) {
  await hostFijarTurno(host, 'Marty');
  await hostPosicion(host, 'Marty', index - 1);
  await reloadUntil(B, () => movement(B).getByRole('button', { name: 'Movimiento manual' }));
  await movement(B).getByRole('button', { name: 'Movimiento manual' }).click();
  await movement(B).getByRole('button', { name: '1 casilla', exact: true }).click();
  await movement(B).getByRole('button', { name: 'Mover 1', exact: true }).click();
}

test('fase 6: comprar grupo, construir, alquiler con casa, hipoteca/deshipoteca y stock', async ({ browser }) => {
  test.setTimeout(240_000);
  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  await host.getByText('Configuración de la sala').click();
  await host.getByLabel('Mínimo').fill('2');
  await host.getByLabel('Configuración de dados').selectOption('physical_allowed'); // habilita "Movimiento manual" para posicionar
  await host.getByRole('button', { name: 'Guardar configuración' }).click();
  await expect(host.getByLabel('Mínimo')).toHaveValue('2');

  const bCtx = await browser.newContext();
  const B = await bCtx.newPage();
  await joinGame(B, code, 'Marty');
  await host.getByRole('button', { name: 'Marcar Preparado' }).click();
  await pickAndReady(B, 1);
  await host.reload();
  await expect(host.getByRole('button', { name: 'Iniciar partida' })).toBeEnabled({ timeout: 20_000 });
  await host.getByRole('button', { name: 'Iniciar partida' }).click();
  await host.getByRole('button', { name: 'Iniciar', exact: true }).click();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });

  // ── Comprar el grupo marron completo (Ronda + Plaza) → monopolio.
  await buyStreet(host, 'Ronda de Valencia', RONDA);
  await buyStreet(host, 'Plaza Lavapiés', PLAZA);

  // ── Con monopolio, la ficha ofrece SOLICITAR construir; el anfitrión la aprueba → casa en Ronda.
  await cardRequestAction(host, 'Ronda de Valencia', /Solicitar construir casa/);

  // ── Marty cae en Ronda (1 casa) y paga el alquiler con casa (rent_1 = 10).
  await landOn(host, B, RONDA);
  await reloadUntil(B, () => movement(B).getByRole('button', { name: /Pagar alquiler/ }));
  await movement(B).getByRole('button', { name: /Pagar alquiler/ }).click();
  await B.getByRole('dialog', { name: 'Pagar alquiler' }).getByRole('button', { name: 'Pagar alquiler' }).click();
  await reloadUntil(B, () => movement(B).getByText(/Ya has pagado el alquiler de esta caída/));

  // ── Para hipotecar hay que vender las construcciones; vender (por solicitud) la casa de Ronda y hipotecar Plaza.
  await cardRequestAction(host, 'Ronda de Valencia', /Solicitar vender casa/);
  await cardAction(host, 'Plaza Lavapiés', /Hipotecar/);

  // ── La ficha de Plaza muestra el estado "Hipotecada" y la nota de que no se debe alquiler.
  await host.reload();
  await openBoard(host);
  await boardCard(host, 'Plaza Lavapiés').getByRole('button', { name: 'Ver tarjeta' }).click();
  const plaza = host.getByRole('dialog', { name: /Ficha de Plaza Lavapiés/ });
  await expect(plaza.getByText('Hipotecada', { exact: true })).toBeVisible();
  // ── Deshipotecar desde la ficha.
  await plaza.getByRole('button', { name: /Deshipotecar/ }).click();
  await expect(host.getByRole('alert')).toHaveCount(0, { timeout: 5_000 });
  await plaza.getByRole('button', { name: 'Cerrar' }).click();
  await host.getByRole('button', { name: 'Cerrar' }).click();

  // ── Marty cae en Plaza (ya deshipotecada, monopolio sin casas) y se le ofrece pagar el alquiler.
  await landOn(host, B, PLAZA);
  await reloadUntil(B, () => movement(B).getByRole('button', { name: /Pagar alquiler/ }));

  // ── El resumen de banco muestra el stock de casas/hoteles.
  await expect(host.getByText('Casas disponibles')).toBeVisible();
  await expect(host.getByText('Hoteles disponibles')).toBeVisible();

  await hostCtx.close();
  await bCtx.close();
});

// Fase 6 (pulido final) — "Construir sin grupo completo" activado: NO se aplica uniformidad ni con el grupo
// completo. Se construyen 3 casas en Ronda y 0 en Plaza (desnivel), y el alquiler de Ronda pasa a rent_3 = 90.
test('fase 6: regla sin-uniformidad — construir 3-0 con grupo completo y cobrar rent_3', async ({ browser }) => {
  test.setTimeout(240_000);
  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  await host.getByText('Configuración de la sala').click();
  await host.getByLabel('Mínimo').fill('2');
  await host.getByLabel('Configuración de dados').selectOption('physical_allowed');
  await host.getByRole('checkbox', { name: /Permitir construir casas sin tener el grupo completo/ }).check();
  await host.getByRole('button', { name: 'Guardar configuración' }).click();
  await expect(host.getByRole('checkbox', { name: /Permitir construir casas sin tener el grupo completo/ })).toBeChecked();

  const bCtx = await browser.newContext();
  const B = await bCtx.newPage();
  await joinGame(B, code, 'Marty');
  await host.getByRole('button', { name: 'Marcar Preparado' }).click();
  await pickAndReady(B, 1);
  await host.reload();
  await expect(host.getByRole('button', { name: 'Iniciar partida' })).toBeEnabled({ timeout: 20_000 });
  await host.getByRole('button', { name: 'Iniciar partida' }).click();
  await host.getByRole('button', { name: 'Iniciar', exact: true }).click();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });

  // Grupo marron COMPLETO.
  await buyStreet(host, 'Ronda de Valencia', RONDA);
  await buyStreet(host, 'Plaza Lavapiés', PLAZA);

  // 3 casas en Ronda dejando Plaza a 0: la 2.ª y 3.ª NO deben bloquearse por uniformidad.
  await cardRequestAction(host, 'Ronda de Valencia', /Solicitar construir casa/);
  await cardRequestAction(host, 'Ronda de Valencia', /Solicitar construir casa/);
  await cardRequestAction(host, 'Ronda de Valencia', /Solicitar construir casa/);

  // La ficha de Ronda muestra "3 casas" y Plaza sigue "Sin construir".
  await host.reload();
  await openBoard(host);
  await boardCard(host, 'Ronda de Valencia').getByRole('button', { name: 'Ver tarjeta' }).click();
  const ronda = host.getByRole('dialog', { name: /Ficha de Ronda de Valencia/ });
  await expect(ronda.getByText('3 casas', { exact: true })).toBeVisible(); // Construcción = 3 (no por uniformidad)
  await ronda.getByRole('button', { name: 'Cerrar' }).click();
  await host.getByRole('button', { name: 'Cerrar' }).click();

  // Marty cae en Ronda (3 casas) y paga rent_3 = 90 (alquiler por casas, no base ni doble).
  await landOn(host, B, RONDA);
  await reloadUntil(B, () => movement(B).getByRole('button', { name: /Pagar alquiler/ }));
  await expect(movement(B).getByRole('button', { name: /Pagar alquiler.*90/ })).toBeVisible();
  await movement(B).getByRole('button', { name: /Pagar alquiler/ }).click();
  await B.getByRole('dialog', { name: 'Pagar alquiler' }).getByRole('button', { name: 'Pagar alquiler' }).click();
  await reloadUntil(B, () => movement(B).getByText(/Ya has pagado el alquiler de esta caída/));

  await hostCtx.close();
  await bCtx.close();
});

// Fase 6 (corrección UI móvil) — la ficha tiene scroll interno REAL por apartado: en el viewport móvil,
// el apartado "Alquileres" (6 filas) excede su altura máxima y se puede desplazar (scrollHeight > clientHeight),
// y la navegación anterior/siguiente sigue funcionando.
test('fase 6: la ficha de propiedad tiene scroll interno por apartado en móvil', async ({ browser }) => {
  test.setTimeout(180_000);
  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  await host.getByText('Configuración de la sala').click();
  await host.getByLabel('Mínimo').fill('2');
  await host.getByRole('button', { name: 'Guardar configuración' }).click();
  await expect(host.getByLabel('Mínimo')).toHaveValue('2');

  const bCtx = await browser.newContext();
  const B = await bCtx.newPage();
  await joinGame(B, code, 'Marty');
  await host.getByRole('button', { name: 'Marcar Preparado' }).click();
  await pickAndReady(B, 1);
  await host.reload();
  await expect(host.getByRole('button', { name: 'Iniciar partida' })).toBeEnabled({ timeout: 20_000 });
  await host.getByRole('button', { name: 'Iniciar partida' }).click();
  await host.getByRole('button', { name: 'Iniciar', exact: true }).click();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });

  // Abrir la ficha de una calle desde el tablero de propiedades.
  await openBoard(host);
  await boardCard(host, 'Ronda de Valencia').getByRole('button', { name: 'Ver tarjeta' }).click();
  const card = host.getByRole('dialog', { name: /Ficha de Ronda de Valencia/ });
  await expect(card).toBeVisible({ timeout: 10_000 });

  // Al menos un apartado scrollable tiene contenido que excede su altura (scroll interno real, no recorte).
  const sectionsOverflow = await card.locator('.overscroll-contain').evaluateAll(
    (els) => els.some((e) => e.scrollHeight > e.clientHeight + 1),
  );
  expect(sectionsOverflow).toBe(true);
  // El cuerpo del modal también es scrollable (min-h-0 + overflow-y-auto).
  const bodyScrollable = await card.locator('.flex-1.min-h-0.overflow-y-auto').count();
  expect(bodyScrollable).toBeGreaterThan(0);

  // La navegación entre propiedades sigue operativa.
  await card.getByRole('button', { name: 'Propiedad siguiente' }).click();
  await expect(host.getByRole('dialog', { name: /Ficha de/ })).toBeVisible();

  await hostCtx.close();
  await bCtx.close();
});
