import { test, expect, type Page, type Locator } from '@playwright/test';

// La corrección de posición del anfitrión dispara una RPC asíncrona; recargamos hasta que el efecto es
// visible (absorbe la carrera RPC↔reload bajo carga del runtime local, sin enmascarar fallos reales).
async function reloadUntilVisible(page: Page, locator: () => Locator, timeout = 45_000) {
  await expect(async () => {
    await page.reload();
    await expect(locator()).toBeVisible({ timeout: 5_000 });
  }).toPass({ timeout });
}

// Movimiento (Fase 4): posición inicial, tirar dados, ver tablero/fichas, corrección de posición por
// el anfitrión, compra/alquiler desde el contexto de la casilla y paso por salida. Anfitrión + 1 jugador.
const PIN = '246813';
const PROP_INDEX = 1;           // índice de la primera propiedad del anillo (Ronda de Valencia)
const PROP_NAME = 'Ronda de Valencia';

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
const boardDialog = (p: Page) => p.getByRole('dialog', { name: 'Tablero', exact: true });

// Coloca a un jugador (por nombre visible) en una casilla concreta vía el formulario del anfitrión.
// Recarga el anfitrión antes (versión fresca) y reintenta si la RPC choca por VERSION_CONFLICT.
async function hostSetPosition(host: Page, playerName: string, index: number) {
  await expect(async () => {
    await host.reload();
    await movement(host).getByRole('button', { name: 'Ver tablero', exact: true }).click();
    await expect(boardDialog(host)).toBeVisible({ timeout: 8_000 });
    await boardDialog(host).getByText('Corregir posición (anfitrión)').click();
    await boardDialog(host).getByLabel('Jugador', { exact: true }).selectOption({ label: playerName });
    await boardDialog(host).getByLabel(/Casilla/).fill(String(index));
    await boardDialog(host).getByLabel('Motivo (obligatorio)').fill('recolocar para prueba');
    await boardDialog(host).getByRole('button', { name: 'Corregir posición' }).click();
    // Si hubo conflicto de versión u otro error, el panel muestra una alerta: reintentar con versión fresca.
    await expect(host.getByRole('alert')).toHaveCount(0, { timeout: 4_000 });
    await boardDialog(host).getByRole('button', { name: 'Cerrar' }).click();
  }).toPass({ timeout: 60_000 });
}

test('movimiento: posición, dados, tablero, corrección, compra/alquiler por casilla y salida', async ({ browser }) => {
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

  // ── Posición inicial: ambos en la Salida.
  await expect(movement(host)).toBeVisible({ timeout: 20_000 });
  await expect(movement(host).getByText('Salida').first()).toBeVisible();
  await B.reload();
  await expect(movement(B).getByText('Salida').first()).toBeVisible({ timeout: 20_000 });

  // ── El jugador actual tira los dados y ve el resultado.
  const hostRolls = await movement(host).getByRole('button', { name: /Tirar dados/ }).count();
  const roller = hostRolls > 0 ? { page: host, name: 'Anfitrión' } : { page: B, name: 'Marty' };
  await movement(roller.page).getByRole('button', { name: /Tirar dados/ }).click();
  await expect(movement(roller.page).getByText(/Última tirada/)).toBeVisible({ timeout: 20_000 });

  // ── Abrir el tablero y ver fichas de jugadores (agrupado por tablero).
  await movement(host).getByRole('button', { name: 'Ver tablero', exact: true }).click();
  await expect(boardDialog(host)).toBeVisible({ timeout: 20_000 });
  await expect(boardDialog(host).getByRole('heading', { name: 'Clásico' })).toBeVisible();
  await expect(boardDialog(host).getByRole('heading', { name: 'Regreso al futuro' })).toBeVisible();
  await expect(boardDialog(host).getByTitle('Marty').first()).toBeVisible();
  await boardDialog(host).getByRole('button', { name: 'Cerrar' }).click();

  // ── El anfitrión coloca a Marty en una propiedad disponible; Marty solicita compra desde el contexto.
  await hostSetPosition(host, 'Marty', PROP_INDEX);
  await reloadUntilVisible(B, () => movement(B).getByText(new RegExp(`Has caído en ${PROP_NAME}`)));
  await movement(B).getByRole('button', { name: 'Solicitar compra' }).click();
  await B.getByRole('dialog', { name: 'Solicitar compra' }).getByRole('button', { name: 'Solicitar compra' }).click();
  await reloadUntilVisible(host, () => host.getByText('Solicitudes de compra'));
  await host.getByRole('region', { name: 'Solicitudes de compra' }).getByRole('button', { name: 'Aprobar' }).click();
  await reloadUntilVisible(B, () => B.getByRole('region', { name: 'Propiedades' }).getByText(PROP_NAME));

  // ── El anfitrión se coloca en esa misma propiedad y paga alquiler desde el contexto.
  await hostSetPosition(host, 'Anfitrión', PROP_INDEX);
  await reloadUntilVisible(host, () => movement(host).getByText(/Has caído en propiedad de Marty/));
  await movement(host).getByRole('button', { name: /Pagar alquiler/ }).click();
  await host.getByRole('dialog', { name: 'Pagar alquiler' }).getByRole('button', { name: 'Pagar alquiler' }).click();
  await expect(movement(host).getByText(/Has caído en propiedad de Marty/)).toBeVisible({ timeout: 20_000 });

  // ── Pasar por salida: el anfitrión coloca al jugador actual en la última casilla y este avanza 1.
  await hostSetPosition(host, roller.name, 28);   // ring classic = 29 (índices 0..28); 28 = Compañía de Electricidad
  await reloadUntilVisible(roller.page, () => movement(roller.page).getByText('Compañía de Electricidad').first());
  await movement(roller.page).getByLabel('Casillas a mover').fill('1');
  await movement(roller.page).getByRole('button', { name: 'Mover' }).click();
  await expect(movement(roller.page).getByText(/pasó por salida/)).toBeVisible({ timeout: 20_000 });

  // ── Recargar y confirmar persistencia: el jugador actual quedó en la Salida.
  await roller.page.reload();
  await expect(movement(roller.page).getByText('Salida').first()).toBeVisible({ timeout: 20_000 });

  await hostCtx.close();
  await bCtx.close();
});
