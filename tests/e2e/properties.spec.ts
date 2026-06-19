import { test, expect, type Page, type Locator } from '@playwright/test';

// Propiedades (Fase 3 corrección): compra con aprobación del anfitrión, subasta, alquiler,
// bancarrota frente a jugador y estado espectador. Anfitrión + 1 jugador (mínimo 2).
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Propiedades');
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
// Resumen ligero de la pantalla principal (Mis propiedades / por jugador).
function summary(page: Page) {
  return page.getByRole('region', { name: 'Propiedades' });
}
// Vista dedicada "Tablero de propiedades" (modal): aquí viven las acciones de compra/subasta/alquiler.
function board(page: Page) {
  return page.getByRole('dialog', { name: 'Tablero de propiedades' });
}
async function openBoard(page: Page) {
  await summary(page).getByRole('button', { name: 'Ver tablero de propiedades' }).click();
  await expect(board(page)).toBeVisible({ timeout: 20_000 });
}
function boardCard(page: Page, name: string) {
  return board(page).getByRole('listitem').filter({ hasText: name });
}
async function requestPurchase(page: Page, name: string) {
  await openBoard(page);
  await boardCard(page, name).getByRole('button', { name: 'Solicitar compra' }).click();
  await page.getByRole('dialog', { name: 'Solicitar compra' }).getByRole('button', { name: 'Solicitar compra' }).click();
}
// Fase 4: comprar exige turno + estar en la casilla. El anfitrión prepara al comprador.
async function openCorrections(host: Page) { await host.getByText('Correcciones del anfitrión').click(); }
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
async function reloadUntilVisible(page: Page, loc: () => Locator, timeout = 45_000) {
  await expect(async () => { await page.reload(); await expect(loc()).toBeVisible({ timeout: 5_000 }); }).toPass({ timeout });
}
const ESTACION = 'Estación del Norte';
const ESTACION_IX = 35;
const PRADO = 'Paseo del Prado';
const PRADO_IX = 39;

test('propiedades: compra con aprobación, subasta, bancarrota y espectador', async ({ browser }) => {
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

  // ── El anfitrión pone el turno a Marty y lo sitúa en la estación; B solicita comprarla.
  await hostFijarTurno(host, 'Marty');
  await hostPosicion(host, 'Marty', ESTACION_IX);
  await reloadUntilVisible(B, () => B.getByRole('region', { name: 'Movimiento', exact: true }).getByText(new RegExp(`Has caído en ${ESTACION}`)));
  await requestPurchase(B, ESTACION);
  await host.reload();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  await expect(host.getByText('Solicitudes de compra')).toBeVisible({ timeout: 20_000 });
  await host.getByRole('region', { name: 'Solicitudes de compra' }).getByRole('button', { name: 'Aprobar' }).click();
  // Aparece en "Mis propiedades" (resumen) y figura como "Tuya" en el tablero.
  await B.reload();
  await expect(summary(B).getByText(ESTACION)).toBeVisible({ timeout: 20_000 });
  await openBoard(B);
  await expect(boardCard(B, ESTACION).getByText('Tuya')).toBeVisible({ timeout: 20_000 });

  // ── El anfitrión sitúa a Marty en Paseo del Prado; B lo solicita; el anfitrión subasta en vez de aprobar.
  await hostFijarTurno(host, 'Marty');
  await hostPosicion(host, 'Marty', PRADO_IX);
  await reloadUntilVisible(B, () => B.getByRole('region', { name: 'Movimiento', exact: true }).getByText(new RegExp(`Has caído en ${PRADO}`)));
  await requestPurchase(B, PRADO);
  await host.reload();
  await expect(host.getByText('Solicitudes de compra')).toBeVisible({ timeout: 20_000 });
  await host.getByRole('region', { name: 'Solicitudes de compra' }).getByRole('button', { name: 'Subastar' }).click();

  // ── B puja desde el tablero; el anfitrión cierra y se adjudica (B único postor).
  await B.reload();
  await openBoard(B);
  const bAuctions = board(B).getByRole('region', { name: 'Subastas activas' });
  await expect(bAuctions).toBeVisible({ timeout: 20_000 });
  await bAuctions.getByLabel('Tu puja').fill('100');
  await bAuctions.getByRole('button', { name: 'Pujar' }).click();
  await host.reload();
  await openBoard(host);
  await expect(board(host).getByText(/Puja: 100/)).toBeVisible({ timeout: 20_000 });
  await board(host).getByRole('region', { name: 'Subastas activas' }).getByRole('button', { name: 'Cerrar subasta' }).click();
  await B.reload();
  await expect(summary(B).getByText(PRADO)).toBeVisible({ timeout: 20_000 });

  // ── B se declara en bancarrota frente al anfitrión; el anfitrión aprueba.
  await B.getByRole('button', { name: 'Declararme en bancarrota' }).click();
  const dlg = B.getByRole('dialog', { name: 'Declararme en bancarrota' });
  await dlg.getByText('Bancarrota por impago a otro jugador').click();
  await dlg.getByLabel('Acreedor').selectOption({ label: 'Anfitrión' });
  await dlg.getByPlaceholder(/motivo/i).fill('Sin liquidez');
  await dlg.getByRole('button', { name: 'Declararme en bancarrota' }).click();
  await host.reload();
  await expect(host.getByText('Solicitudes de bancarrota')).toBeVisible({ timeout: 20_000 });
  await host.getByRole('region', { name: 'Solicitudes de bancarrota' }).getByRole('button', { name: 'Aprobar' }).click();

  // ── B queda como espectador; sus propiedades pasaron al anfitrión.
  await B.reload();
  await expect(B.getByText(/Estás en bancarrota\. Puedes seguir consultando/)).toBeVisible({ timeout: 20_000 });
  await expect(B.getByRole('button', { name: 'Declararme en bancarrota' })).toHaveCount(0);
  await host.reload();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  // Las propiedades de B pasaron al anfitrión: aparecen en su resumen y como "Tuya" en el tablero.
  await expect(summary(host).getByText(ESTACION)).toBeVisible({ timeout: 20_000 });
  await expect(summary(host).getByText(PRADO)).toBeVisible({ timeout: 20_000 });
  await openBoard(host);
  await expect(boardCard(host, ESTACION).getByText('Tuya')).toBeVisible({ timeout: 20_000 });
  await expect(boardCard(host, PRADO).getByText('Tuya')).toBeVisible({ timeout: 20_000 });
  await board(host).getByRole('button', { name: 'Cerrar' }).click();
  await expect(host.getByText('Marty').first()).toBeVisible();
  await expect(host.getByText('En bancarrota').first()).toBeVisible({ timeout: 20_000 });

  await hostCtx.close();
  await bCtx.close();
});
