import { test, expect, type Page, type Locator } from '@playwright/test';

// Movimiento + corrección Fase 4: tablero visual, privacidad de saldos, restricción de compra
// (solo en tu turno y en tu casilla), alquiler por contexto y paso por salida. Anfitrión + 1 jugador.
const PIN = '246813';
const RONDA = 'Ronda de Valencia';      // Classic índice 1
const RONDA_IX = 1;
const LAST_IX = 39;                       // Classic: ring 40 (0..39); 39 = Paseo del Prado

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Movimiento');
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
const visualBoard = (p: Page) => p.getByRole('dialog', { name: 'Tablero', exact: true });

async function openCorrections(host: Page) {
  await host.getByText('Correcciones del anfitrión').click();
}
// El anfitrión fija el turno a un jugador (reintenta ante VERSION_CONFLICT con versión fresca).
async function hostFijarTurno(host: Page, name: string) {
  await expect(async () => {
    await host.reload();
    await openCorrections(host);
    const form = host.locator('form', { has: host.getByRole('button', { name: 'Fijar turno' }) });
    await form.getByLabel('Jugador en turno').selectOption({ label: name });
    await form.getByLabel('Motivo (obligatorio)').fill('fijar turno (prueba)');
    await form.getByRole('button', { name: 'Fijar turno' }).click();
    await expect(host.getByRole('alert')).toHaveCount(0, { timeout: 3_000 });
  }).toPass({ timeout: 60_000 });
}
// El anfitrión coloca a un jugador en una casilla del tablero Clásico.
async function hostPosicion(host: Page, name: string, index: number) {
  await expect(async () => {
    await host.reload();
    await openCorrections(host);
    const form = host.locator('form', { has: host.getByRole('button', { name: 'Actualizar posición' }) });
    await form.getByLabel('Jugador', { exact: true }).selectOption({ label: name });
    await form.getByLabel(/Casilla/).fill(String(index));
    await form.getByLabel('Motivo (obligatorio)').fill('situar (prueba)');
    await form.getByRole('button', { name: 'Actualizar posición' }).click();
    await expect(host.getByRole('alert')).toHaveCount(0, { timeout: 3_000 });
  }).toPass({ timeout: 60_000 });
}
async function reloadUntil(page: Page, loc: () => Locator, timeout = 45_000) {
  await expect(async () => { await page.reload(); await expect(loc()).toBeVisible({ timeout: 5_000 }); }).toPass({ timeout });
}

test('Fase 4 corrección: tablero visual, privacidad, restricción de compra, alquiler y salida', async ({ browser }) => {
  test.setTimeout(220_000);
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

  // ── Tablero visual: pestañas de ambos tableros + nombres de jugadores; ver RdF (provisional).
  await movement(host).getByRole('button', { name: 'Ver tablero', exact: true }).click();
  await expect(visualBoard(host)).toBeVisible({ timeout: 20_000 });
  await expect(visualBoard(host).getByRole('tab', { name: 'Clásico' })).toBeVisible();
  await expect(visualBoard(host).getByRole('tab', { name: 'Regreso al futuro' })).toBeVisible();
  await expect(visualBoard(host).getByText('Marty')).toBeVisible();          // nombre, no ficha
  await visualBoard(host).getByRole('tab', { name: 'Regreso al futuro' }).click();
  await expect(visualBoard(host).getByText(/provisional/)).toBeVisible();
  await visualBoard(host).getByRole('button', { name: 'Cerrar' }).click();

  // ── Privacidad: cada uno solo ve su saldo; el ajeno aparece "Saldo oculto".
  await expect(host.getByText('Saldo oculto').first()).toBeVisible();
  await B.reload();
  await expect(B.getByText('Saldo oculto').first()).toBeVisible({ timeout: 20_000 });

  // ── El anfitrión pone el turno a Marty y lo sitúa en Ronda de Valencia; Marty solicita compra.
  await hostFijarTurno(host, 'Marty');
  await hostPosicion(host, 'Marty', RONDA_IX);
  await reloadUntil(B, () => movement(B).getByText(new RegExp(`Has caído en ${RONDA}`)));
  await movement(B).getByRole('button', { name: 'Solicitar compra' }).click();
  await B.getByRole('dialog', { name: 'Solicitar compra' }).getByRole('button', { name: 'Solicitar compra' }).click();
  await reloadUntil(host, () => host.getByText('Solicitudes de compra'));
  await host.getByRole('region', { name: 'Solicitudes de compra' }).getByRole('button', { name: 'Aprobar' }).click();
  await reloadUntil(B, () => B.getByRole('region', { name: 'Propiedades' }).getByText(RONDA));

  // ── Restricción: fuera de tu turno NO hay botón de compra; se explica por qué.
  await hostFijarTurno(host, 'Anfitrión');               // ahora Marty NO es el actual
  await B.reload();
  await B.getByRole('region', { name: 'Propiedades' }).getByRole('button', { name: 'Ver tablero de propiedades' }).click();
  const propBoard = B.getByRole('dialog', { name: 'Tablero de propiedades' });
  await expect(propBoard.getByText(/Solo puedes solicitar comprar la propiedad en la que has caído/).first()).toBeVisible({ timeout: 20_000 });
  await expect(propBoard.getByRole('button', { name: 'Solicitar compra' })).toHaveCount(0);
  await propBoard.getByRole('button', { name: 'Cerrar' }).click();

  // ── El anfitrión (actual) se coloca en Ronda (de Marty) y paga alquiler desde el contexto.
  await hostPosicion(host, 'Anfitrión', RONDA_IX);
  await reloadUntil(host, () => movement(host).getByText(/Has caído en propiedad de Marty/));
  await movement(host).getByRole('button', { name: /Pagar alquiler/ }).click();
  await host.getByRole('dialog', { name: 'Pagar alquiler' }).getByRole('button', { name: 'Pagar alquiler' }).click();
  await expect(movement(host).getByText(/Has caído en propiedad de Marty/)).toBeVisible({ timeout: 20_000 });

  // ── Pasar por salida: el anfitrión (actual) en la última casilla avanza 1 y cobra.
  await hostPosicion(host, 'Anfitrión', LAST_IX);
  await reloadUntil(host, () => movement(host).getByRole('button', { name: /Tirar dados/ }));
  await movement(host).getByLabel('Casillas a mover').fill('1');
  await movement(host).getByRole('button', { name: 'Mover' }).click();
  await expect(movement(host).getByText(/pasó por salida/)).toBeVisible({ timeout: 20_000 });

  // ── Recargar y confirmar persistencia: el anfitrión quedó en la Salida.
  await host.reload();
  await expect(movement(host).getByText('Salida').first()).toBeVisible({ timeout: 20_000 });

  await hostCtx.close();
  await bCtx.close();
});
