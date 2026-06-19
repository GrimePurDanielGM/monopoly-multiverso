import { test, expect, type Page, type Locator } from '@playwright/test';

// Cruce entre tableros (Fase 4 corrección 4): al alcanzar la cárcel-guardián con pasos restantes, el
// jugador debe ELEGIR destino (seguir gratis / cruzar pagando peaje); no avanza solo. Anfitrión + 1 jugador.
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Cruce');
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
    await form.getByLabel(/Casilla/).fill(String(index));
    await form.getByLabel('Motivo (obligatorio)').fill('situar (prueba)');
    await form.getByRole('button', { name: 'Actualizar posición' }).click();
    await expect(host.getByRole('alert')).toHaveCount(0, { timeout: 3_000 });
  }).toPass({ timeout: 60_000 });
}
async function reloadUntil(page: Page, loc: () => Locator, timeout = 45_000) {
  await expect(async () => { await page.reload(); await expect(loc()).toBeVisible({ timeout: 5_000 }); }).toPass({ timeout });
}

test('cruce: la cárcel-guardián obliga a elegir; cruzar paga peaje y cambia de tablero', async ({ browser }) => {
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

  // El anfitrión pone el turno a Marty y lo coloca 1 antes de la cárcel (índice 9).
  await hostFijarTurno(host, 'Marty');
  await hostPosicion(host, 'Marty', 9);

  // Marty mueve 2: alcanza la cárcel (10) con 1 restante → debe ELEGIR (no avanza solo).
  await reloadUntil(B, () => movement(B).getByRole('button', { name: 'Mover' }));
  await movement(B).getByLabel('Casillas a mover').fill('2');
  await movement(B).getByRole('button', { name: 'Mover' }).click();
  await reloadUntil(B, () => movement(B).getByText(/Has llegado a la cárcel/));
  // Hay dos destinos: seguir (gratis) y cruzar (peaje).
  await expect(movement(B).getByRole('button', { name: /Seguir.*Glorieta de Bilbao.*gratis/ })).toBeVisible();
  await expect(movement(B).getByRole('button', { name: /Cruzar.*Parking gratuito.*peaje/ })).toBeVisible();

  // Marty cruza (paga peaje) → cae en el Parking gratuito del tablero Regreso al Futuro.
  await movement(B).getByRole('button', { name: /Cruzar.*Parking gratuito/ }).click();
  // En la región de Movimiento, "Parking gratuito" y "Regreso al futuro" aparecen varias veces
  // (casilla actual, última jugada y nota), por eso usamos .first().
  await reloadUntil(B, () => movement(B).getByText('Parking gratuito').first());
  await expect(movement(B).getByText('Regreso al futuro').first()).toBeVisible();

  await hostCtx.close();
  await bCtx.close();
});
