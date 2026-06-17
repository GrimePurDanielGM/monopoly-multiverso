import { test, expect, type Page } from '@playwright/test';

// Acceso visible a la recuperación de anfitrión + recuperación funcional (lobby).
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Recuperación');
  await page.getByPlaceholder('Daniel').fill('Anfitrión');
  await page.getByRole('radiogroup', { name: 'Ficha del anfitrión' }).getByRole('radio').first().click();
  await page.getByPlaceholder('••••••').fill(PIN);
  await page.getByRole('button', { name: 'Crear y entrar' }).click();
  await page.waitForURL(/\/sala\/[A-Z0-9]{6}$/, { timeout: 30_000 });
  const m = page.url().match(/\/sala\/([A-Z0-9]{6})$/);
  if (!m) throw new Error('sin código');
  return m[1];
}

test('la pantalla inicial ofrece recuperar como anfitrión y lleva a /recuperar', async ({ page }) => {
  await page.goto('/');
  const action = page.getByRole('button', { name: 'Recuperar partida como anfitrión' });
  await expect(action).toBeVisible();
  await action.click();
  await expect(page).toHaveURL(/\/recuperar$/);
  await expect(page.getByRole('heading', { name: 'Recuperar control de anfitrión' })).toBeVisible();
  // Explica código + PIN y NO sugiere crear una partida nueva.
  await expect(page.getByText(/Introduce el código de la sala/i)).toBeVisible();
  await expect(page.getByText(/No crea una partida nueva ni sirve para volver como jugador normal/i)).toBeVisible();
  await expect(page.getByText(/Funciona tanto en la sala de espera como con la partida ya iniciada/i)).toBeVisible();
});

test('recuperación funcional (lobby): el nuevo dispositivo es anfitrión y el antiguo lo pierde', async ({ browser }) => {
  test.setTimeout(90_000);

  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  await expect(host.getByRole('heading', { name: 'Controles del anfitrión' })).toBeVisible();

  // Nuevo dispositivo: recupera por la acción visible.
  const newCtx = await browser.newContext();
  const dev = await newCtx.newPage();
  await dev.goto('/');
  await dev.getByRole('button', { name: 'Recuperar partida como anfitrión' }).click();
  await dev.getByPlaceholder('ABC123').fill(code);
  await dev.getByPlaceholder('••••••').fill(PIN);
  await dev.getByRole('button', { name: 'Recuperar control' }).click();
  await dev.waitForURL(new RegExp(`/sala/${code}$`), { timeout: 30_000 });
  // El nuevo dispositivo es anfitrión (ve los controles del anfitrión).
  await expect(dev.getByRole('heading', { name: 'Controles del anfitrión' })).toBeVisible({ timeout: 20_000 });

  // El dispositivo anterior pierde el rol: al recargar ya no forma parte de la sala.
  await host.reload();
  await expect(host.getByText('No formas parte de esta sala.')).toBeVisible({ timeout: 20_000 });
  await expect(host.getByRole('heading', { name: 'Controles del anfitrión' })).toHaveCount(0);

  await hostCtx.close();
  await newCtx.close();
});
