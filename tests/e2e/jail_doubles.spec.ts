import { test, expect, type Page, type Locator } from '@playwright/test';

// Cárcel completa (Fase 5 corrección): estado con "Intento N/3", intento de dobles, salida pagando, y
// banner GLOBAL al cobrar el bote del Parking (quien cobra lo ve sin recargar). Anfitrión + 1 jugador.
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Cárcel');
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
async function reloadUntil(page: Page, loc: () => Locator, timeout = 45_000) {
  await expect(async () => { await page.reload(); await expect(loc()).toBeVisible({ timeout: 5_000 }); }).toPass({ timeout });
}
async function landOn(host: Page, B: Page, index: number) {
  await hostPosicion(host, 'Marty', index - 1);
  await reloadUntil(B, () => movement(B).getByRole('button', { name: '1 casilla', exact: true }));
  await movement(B).getByRole('button', { name: '1 casilla', exact: true }).click();
  await movement(B).getByRole('button', { name: 'Mover 1', exact: true }).click();
}

test('cárcel: intento de dobles, salida pagando y banner global del bote', async ({ browser }) => {
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
  await hostFijarTurno(host, 'Marty');

  // ── Ve a la cárcel (idx 30): estado con "Intento 1/3" y botón de intentar dobles.
  await landOn(host, B, 30);
  await reloadUntil(B, () => movement(B).getByText(/Estás en la cárcel/));
  await expect(movement(B).getByText(/Intento 1\/3/)).toBeVisible();
  await expect(movement(B).getByRole('button', { name: /Intentar sacar dobles/ })).toBeVisible();
  await expect(movement(B).getByRole('button', { name: /Tirar dados/ })).toHaveCount(0);

  // ── Un intento de dobles: produce una tirada y CONSUME la acción de cárcel del turno (resultado aleatorio:
  //    sale por dobles o sigue preso). En ambos casos, "Intentar sacar dobles" ya no está disponible.
  await movement(B).getByRole('button', { name: /Intentar sacar dobles/ }).click();
  await reloadUntil(B, () => movement(B).getByText(/Última tirada/));
  await expect(movement(B).getByRole('button', { name: /Intentar sacar dobles/ })).toHaveCount(0); // una sola acción por turno

  // ── Salir pagando 50 (re-encarcelamos en limpio para tener la acción del turno disponible).
  await landOn(host, B, 30);   // vuelve a la cárcel (acción del turno reiniciada)
  await reloadUntil(B, () => movement(B).getByRole('button', { name: /Pagar 50 ₥ para salir/ }));
  await movement(B).getByRole('button', { name: /Pagar 50 ₥ para salir/ }).click();
  await reloadUntil(B, () => movement(B).getByRole('button', { name: '1 casilla', exact: true }));

  // ── Bote del Parking: Marty paga un impuesto (bote=200) y luego cae en Parking → cobra el bote.
  await landOn(host, B, 4);   // Impuesto sobre el capital (200) → alimenta el bote
  await reloadUntil(B, () => movement(B).getByText(/Has pagado 200 ₥ de impuesto/));
  await landOn(host, B, 20);  // Parking → cobra el bote (200); el cobrador ve el banner global sin recargar

  // Banner GLOBAL central (independiente del privado): "Marty ha cobrado el bote de Parking".
  await expect(B.getByText(/ha cobrado el bote de Parking/)).toBeVisible({ timeout: 20_000 });

  await hostCtx.close();
  await bCtx.close();
});
