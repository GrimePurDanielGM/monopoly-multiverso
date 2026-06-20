import { test, expect, type Page, type Locator } from '@playwright/test';

// Dados físicos/virtuales configurables + alquiler de servicios combinable (Fase 5 corrección ampliada).
// El anfitrión activa físicos en el lobby; el jugador mueve con dados físicos; el modo se cambia en
// activa y bloquea lo que no corresponda; un servicio de otro jugador cobra alquiler por dados × multiplicador.
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Dados');
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
async function hostSetDiceMode(host: Page, label: string) {
  await expect(async () => {
    await host.reload(); await openCorrections(host);
    const form = host.locator('form', { has: host.getByRole('button', { name: 'Aplicar modo de dados' }) });
    await form.getByLabel('Modo de dados').selectOption({ label });
    await form.getByRole('button', { name: 'Aplicar modo de dados' }).click();
    await expect(host.getByRole('alert')).toHaveCount(0, { timeout: 3_000 });
  }).toPass({ timeout: 60_000 });
}
// Tira físicamente desde el panel de movimiento (entrada por botones de dado).
async function physicalRoll(p: Page, d1: number, d2: number, cta: RegExp) {
  await movement(p).getByRole('button', { name: `Dado 1: ${d1}` }).click();
  await movement(p).getByRole('button', { name: `Dado 2: ${d2}` }).click();
  await movement(p).getByRole('button', { name: cta }).click();
}

test('dados físicos configurables y alquiler de servicios combinado', async ({ browser }) => {
  test.setTimeout(220_000);
  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  // Lobby: mínimo 2 + activar dados físicos y virtuales.
  await host.getByText('Configuración de la sala').click();
  await host.getByLabel('Mínimo').fill('2');
  await host.getByLabel('Configuración de dados').selectOption('physical_allowed');
  await host.getByRole('button', { name: 'Guardar configuración' }).click();
  await expect(host.getByLabel('Configuración de dados')).toHaveValue('physical_allowed');

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

  // ── (1) Movimiento con dados FÍSICOS: Marty en idx 1 introduce 3+4 → idx 8 (propiedad), última tirada 7.
  //    (Se evita idx 7 «Suerte», que abriría el modal de carta.)
  await hostFijarTurno(host, 'Marty');
  await hostPosicion(host, 'Marty', 1);
  await reloadUntil(B, () => movement(B).getByText('Introducir tirada física'));
  await physicalRoll(B, 3, 4, /Mover con estos dados/);
  await reloadUntil(B, () => movement(B).getByText(/Última tirada: 3 \+ 4 = 7/));

  // ── (2) Cambio a SOLO VIRTUALES: desaparece la entrada física, queda "Tirar dados".
  await hostSetDiceMode(host, 'Solo dados virtuales');
  await reloadUntil(B, () => movement(B).getByRole('button', { name: /Tirar dados/ }));
  await expect(movement(B).getByText('Introducir tirada física')).toHaveCount(0);

  // ── (3) Cambio a SOLO FÍSICOS: desaparece "Tirar dados", queda la entrada física.
  await hostSetDiceMode(host, 'Solo dados físicos');
  await reloadUntil(B, () => movement(B).getByText('Introducir tirada física'));
  await expect(movement(B).getByRole('button', { name: /Tirar dados/ })).toHaveCount(0);

  // ── (4) Intento de cárcel con dados físicos: dobles 3+3 → sale de la cárcel.
  await hostSetDiceMode(host, 'Permitir dados físicos y virtuales');
  await hostPosicion(host, 'Marty', 29);
  await reloadUntil(B, () => movement(B).getByRole('button', { name: '1 casilla', exact: true }));
  await movement(B).getByRole('button', { name: '1 casilla', exact: true }).click();
  await movement(B).getByRole('button', { name: 'Mover 1', exact: true }).click();
  await reloadUntil(B, () => movement(B).getByText(/Estás en la cárcel/));
  await physicalRoll(B, 3, 3, /Intentar salir con estos dados/);
  await reloadUntil(B, () => movement(B).getByText(/Has sacado dobles/));

  // ── (5) Servicio combinado: el anfitrión compra Compañía de Electricidad (idx 12).
  await hostFijarTurno(host, 'Anfitrión');
  await hostPosicion(host, 'Anfitrión', 12);
  await reloadUntil(host, () => movement(host).getByRole('button', { name: 'Solicitar compra' }));
  await movement(host).getByRole('button', { name: 'Solicitar compra' }).click();
  await host.getByRole('dialog', { name: 'Solicitar compra' }).getByRole('button', { name: 'Solicitar compra' }).click();
  await reloadUntil(host, () => host.getByRole('region', { name: 'Solicitudes de compra' }));
  await host.getByRole('region', { name: 'Solicitudes de compra' }).getByRole('button', { name: 'Aprobar' }).click();
  await expect(host.getByText('Solicitudes de compra')).toHaveCount(0, { timeout: 20_000 });

  // ── (6) Marty tira físicamente 3+4 (idx 0 → 7) para fijar su tirada y luego se le sitúa en el servicio
  //    (idx 12): el alquiler usa su última tirada (7) × ×4 = 28 € para el Anfitrión.
  await hostFijarTurno(host, 'Marty');
  await hostPosicion(host, 'Marty', 1);
  await reloadUntil(B, () => movement(B).getByText('Introducir tirada física'));
  await physicalRoll(B, 3, 4, /Mover con estos dados/);
  await reloadUntil(B, () => movement(B).getByText(/Última tirada: 3 \+ 4 = 7/));
  await hostPosicion(host, 'Marty', 12);
  await reloadUntil(B, () => movement(B).getByText(/Servicios poseídos por Anfitrión: 1\/4/));
  await expect(movement(B).getByText(/Multiplicador ×4/)).toBeVisible();
  await expect(movement(B).getByText(/Alquiler 28/)).toBeVisible();
  await movement(B).getByRole('button', { name: /Pagar alquiler \(28/ }).click();
  // El pago se procesa sin error (la matemática del alquiler está cubierta por las pruebas SQL).
  await reloadUntil(B, () => movement(B).getByText(/Servicios poseídos por Anfitrión: 1\/4/));
  await expect(B.getByRole('alert')).toHaveCount(0);

  await hostCtx.close();
  await bCtx.close();
});
