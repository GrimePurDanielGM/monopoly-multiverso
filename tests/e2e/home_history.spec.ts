import { test, expect, type Page } from '@playwright/test';

// Historial local de partidas (Fase 4 pulido): al crear/entrar en una sala, Home muestra "Mis partidas"
// con el código; "Entrar" vuelve a la sala y "Quitar" la elimina del historial local del dispositivo.
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Historial');
  await page.getByPlaceholder('Daniel').fill('Anfitrión');
  await page.getByRole('radiogroup', { name: 'Ficha del anfitrión' }).getByRole('radio').first().click();
  await page.getByPlaceholder('••••••').fill(PIN);
  await page.getByRole('button', { name: 'Crear y entrar' }).click();
  await page.waitForURL(/\/sala\/[A-Z0-9]{6}$/, { timeout: 30_000 });
  return page.url().match(/\/sala\/([A-Z0-9]{6})$/)![1]!;
}

// La sala se considera cargada (y el historial ya escrito por LobbyScreen.load) cuando aparece la
// configuración de la sala del anfitrión.
const lobbyReady = (page: Page) => expect(page.getByText('Configuración de la sala')).toBeVisible({ timeout: 20_000 });

test('historial local: Home lista la partida creada, Entrar vuelve y Quitar la elimina', async ({ page }) => {
  test.setTimeout(90_000);
  const code = await createGame(page);
  await lobbyReady(page); // el historial se escribe al cargar la sala

  // En Home aparece "Mis partidas" con el código de la sala recién creada.
  await page.goto('/');
  const mis = page.getByRole('region', { name: 'Mis partidas' });
  await expect(mis).toBeVisible({ timeout: 20_000 });
  await expect(mis.getByText(code)).toBeVisible();

  // "Entrar" vuelve a la sala.
  await mis.getByRole('button', { name: 'Entrar' }).first().click();
  await page.waitForURL(new RegExp(`/sala/${code}$`), { timeout: 30_000 });
  await lobbyReady(page);

  // De vuelta en Home, "Quitar" elimina la partida del historial local.
  await page.goto('/');
  await expect(page.getByRole('region', { name: 'Mis partidas' }).getByText(code)).toBeVisible({ timeout: 20_000 });
  await page.getByRole('button', { name: new RegExp(`Quitar ${code}`) }).click();
  await expect(page.getByText(code)).toHaveCount(0);
});
