import { test, expect } from '@playwright/test';

/**
 * Smoke tests for the Flutter web build of Partners.
 *
 * Flutter web renderer (CanvasKit by default) draws to a single canvas, so
 * widget-level interactions aren't directly addressable through DOM. These
 * tests verify the app boots, the canvas mounts, no JS errors are thrown
 * and screenshots can be captured as visual baselines.
 *
 * Full-game logic is verified two other ways:
 *  - `flutter test` (test/full_game_test.dart) plays 5 complete games in CI.
 *  - The in-app "Selvtest" screen plays full games in the browser with a
 *    visible pass/fail result (reachable from the setup screen).
 */

test.describe('App boots and renders', () => {
  test('renders without console errors and shows Flutter canvas', async ({
    page,
  }) => {
    const errors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') errors.push(msg.text());
    });
    page.on('pageerror', (err) => errors.push(err.message));

    await page.goto('/');
    await expect(page).toHaveTitle(/Partners/i);

    // Wait for Flutter to bootstrap. Flutter web inserts either a
    // <flt-glass-pane> (CanvasKit) or a <flutter-view> element.
    const flutterReady = page.locator(
      'flt-glass-pane, flutter-view, flt-scene-host',
    );
    await flutterReady.first().waitFor({ state: 'attached', timeout: 30_000 });

    // Give Flutter a moment to paint the first frame
    await page.waitForTimeout(1_500);

    await page.screenshot({
      path: 'test-results/screenshots/setup-screen.png',
      fullPage: true,
    });

    // Filter out known noisy errors (Flutter sometimes logs SW or font loader warnings)
    const fatalErrors = errors.filter(
      (e) =>
        !e.includes('ServiceWorker') &&
        !e.includes('manifest.json') &&
        !e.toLowerCase().includes('warn'),
    );
    expect(fatalErrors, fatalErrors.join('\n')).toEqual([]);
  });

  test('manifest.json is reachable', async ({ page }) => {
    const resp = await page.goto('/manifest.json');
    expect(resp?.status()).toBe(200);
    const json = await resp!.json();
    expect(json.name).toBe('Partners');
  });

  test('app shell loads required Flutter assets', async ({ page }) => {
    const responses: { url: string; status: number }[] = [];
    page.on('response', (r) =>
      responses.push({ url: r.url(), status: r.status() }),
    );
    await page.goto('/');
    await page.waitForLoadState('networkidle', { timeout: 30_000 });

    // At minimum the bootstrap script should be served
    const bootstrap = responses.find((r) =>
      r.url.endsWith('flutter_bootstrap.js'),
    );
    expect(bootstrap, 'flutter_bootstrap.js should be served').toBeTruthy();
    expect(bootstrap!.status).toBe(200);

    // No 4xx/5xx for primary resources
    const failed = responses.filter(
      (r) => r.status >= 400 && !r.url.includes('favicon'),
    );
    expect(failed, failed.map((f) => `${f.status} ${f.url}`).join('\n')).toEqual(
      [],
    );
  });
});

test.describe('Visual capture at key states', () => {
  test('captures setup screen on desktop viewport', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto('/');
    await page.waitForTimeout(2_000);
    await page.screenshot({
      path: 'test-results/screenshots/setup-desktop.png',
      fullPage: true,
    });
  });

  test('captures setup screen on mobile viewport', async ({ page }) => {
    await page.setViewportSize({ width: 414, height: 896 });
    await page.goto('/');
    await page.waitForTimeout(2_000);
    await page.screenshot({
      path: 'test-results/screenshots/setup-mobile.png',
      fullPage: true,
    });
  });
});
