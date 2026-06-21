import { test, expect, type Page, type Locator } from '@playwright/test';

// Fase 7 — Tratos: A (host) compra una propiedad, propone un trato (propiedad a cambio de dinero), B acepta,
// el anfitrión aprueba y se ejecuta. Además: un trato dinero↔dinero no requiere anfitrión.
const PIN = '371824';
const RONDA = 1;

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Tratos');
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
const board = (p: Page) => p.getByRole('dialog', { name: 'Tablero de propiedades' });
const tradesPanel = (p: Page) => p.getByRole('region', { name: 'Tratos' });
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

test('fase 7: trato propiedad↔dinero con aprobación del anfitrión + dinero↔dinero sin anfitrión', async ({ browser }) => {
  test.setTimeout(240_000);
  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  await host.getByText('Configuración de la sala').click();
  await host.getByLabel('Mínimo').fill('2');
  await host.getByLabel('Configuración de dados').selectOption('physical_allowed');
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

  // El anfitrión compra Ronda y propone un trato: Ronda a cambio de 500 € de Marty.
  await buyStreet(host, 'Ronda de Valencia', RONDA);
  await host.reload();
  await tradesPanel(host).getByRole('button', { name: 'Crear trato' }).click();
  const modal = host.getByRole('dialog', { name: 'Crear trato' });
  await expect(modal).toBeVisible({ timeout: 10_000 });
  await modal.getByLabel('Jugador').selectOption({ label: 'Marty' });
  await modal.locator('label', { hasText: 'Ronda de Valencia' }).getByRole('checkbox').check();
  await modal.getByLabel('Dinero que pido').fill('500');
  await modal.getByRole('button', { name: 'Enviar propuesta' }).click();
  await expect(modal).toBeHidden({ timeout: 10_000 });

  // Marty ve el trato recibido y lo acepta → pasa a revisión del anfitrión.
  await reloadUntil(B, () => tradesPanel(B).getByRole('button', { name: 'Aceptar' }));
  await tradesPanel(B).getByRole('button', { name: 'Aceptar' }).click();

  // El anfitrión aprueba el trato en su bandeja.
  await reloadUntil(host, () => host.getByRole('region', { name: 'Tratos a aprobar' }));
  await host.getByRole('region', { name: 'Tratos a aprobar' }).getByRole('button', { name: 'Aprobar' }).click();
  await expect(host.getByText('Tratos a aprobar')).toHaveCount(0, { timeout: 20_000 });

  // Ronda cambió de dueño: en el tablero del anfitrión figura como de otro jugador (Marty).
  await host.reload();
  await openBoard(host);
  await boardCard(host, 'Ronda de Valencia').getByRole('button', { name: 'Ver tarjeta' }).click();
  await expect(host.getByRole('dialog', { name: /Ficha de Ronda de Valencia/ })).toContainText('Marty');
  await host.getByRole('dialog', { name: /Ficha de Ronda de Valencia/ }).getByRole('button', { name: 'Cerrar' }).click();
  await host.getByRole('button', { name: 'Cerrar' }).click();

  // Trato dinero↔dinero: el anfitrión ofrece 100 € a Marty → no requiere anfitrión; Marty acepta y se ejecuta.
  await host.reload();
  await tradesPanel(host).getByRole('button', { name: 'Crear trato' }).click();
  const m2 = host.getByRole('dialog', { name: 'Crear trato' });
  await m2.getByLabel('Jugador').selectOption({ label: 'Marty' });
  await m2.getByLabel('Dinero que ofrezco').fill('100');
  await m2.getByRole('button', { name: 'Enviar propuesta' }).click();
  await expect(m2).toBeHidden({ timeout: 10_000 });
  await reloadUntil(B, () => tradesPanel(B).getByRole('button', { name: 'Aceptar' }));
  await tradesPanel(B).getByRole('button', { name: 'Aceptar' }).click();
  // Sin pasar por el anfitrión: el historial de Marty muestra un trato ejecutado.
  await reloadUntil(B, () => tradesPanel(B).getByText(/Historial reciente/));
  await tradesPanel(B).getByText(/Historial reciente/).click();
  await expect(tradesPanel(B).getByText('Ejecutado').first()).toBeVisible();

  await hostCtx.close();
  await bCtx.close();
});
