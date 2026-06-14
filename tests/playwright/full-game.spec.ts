import { test, expect, Page } from '@playwright/test';

/**
 * End-to-end full game playthrough via the in-app test bridge.
 *
 * The app exposes window.partnersTest when loaded with ?test=1 — this lets
 * Playwright drive the game logic without trying to click through the
 * Flutter canvas. See lib/utils/test_bridge_web.dart for the available
 * methods.
 *
 * Required URL parameter:  ?test=1
 */

const TEST_URL = '/?test=1';

async function waitForBridge(page: Page, timeoutMs = 30_000): Promise<void> {
  await page.waitForFunction(
    () =>
      typeof (window as any).partnersTest === 'object' &&
      typeof (window as any).partnersTest.ready === 'function' &&
      (window as any).partnersTest.ready() === true,
    null,
    { timeout: timeoutMs },
  );
}

interface BridgeState {
  phase: string;
  handNumber: number;
  currentPlayer: number;
  winningTeam: number | null;
  players: Array<{
    index: number;
    name: string;
    hand: string[];
    pieces: Array<{ id: string; position: string; hasLeftStart: boolean }>;
  }>;
}

interface FullGameResult {
  winningTeam: number;
  handsPlayed: number;
  moves: number;
  log: Array<{ phase: string; player: number; card: string }>;
  state: BridgeState;
}

test.describe('Full game via test bridge', () => {
  test('bridge is exposed after load with ?test=1', async ({ page }) => {
    await page.goto(TEST_URL);
    await waitForBridge(page);
    const version = await page.evaluate(() =>
      (window as any).partnersTest.version(),
    );
    expect(version).toBe('0.1.0');
  });

  test('startGame initializes 4 players with chosen names and colors', async ({
    page,
  }) => {
    await page.goto(TEST_URL);
    await waitForBridge(page);

    const state = (await page.evaluate(() =>
      (window as any).partnersTest.startGame(
        ['Alice', 'Bob', 'Charlie', 'Dave'],
        [0xffe53935, 0xff1e88e5, 0xff43a047, 0xfffdd835],
      ),
    )) as BridgeState;

    expect(state.players).toHaveLength(4);
    expect(state.players.map((p) => p.name)).toEqual([
      'Alice',
      'Bob',
      'Charlie',
      'Dave',
    ]);
    // Hver spiller har 4 brikker i starten
    for (const p of state.players) {
      expect(p.pieces).toHaveLength(4);
      for (const pc of p.pieces) {
        expect(pc.position).toMatch(/^start:/);
      }
      expect(p.hand).toHaveLength(4);
    }
    expect(state.phase).toBe('exchange');
  });

  test('AI plays a full game to completion with a valid winner', async ({
    page,
  }) => {
    test.setTimeout(180_000);
    await page.goto(TEST_URL);
    await waitForBridge(page);

    await page.evaluate(() =>
      (window as any).partnersTest.startGame(
        ['Du', 'Mads', 'Anna', 'Peter'],
        [0xffe53935, 0xff1e88e5, 0xff43a047, 0xfffdd835],
      ),
    );

    const result = (await page.evaluate(() =>
      (window as any).partnersTest.playFullGame(500),
    )) as FullGameResult;

    expect(result.winningTeam, 'A team must win').not.toBeNull();
    expect([0, 1]).toContain(result.winningTeam);
    expect(result.handsPlayed).toBeGreaterThan(0);
    expect(result.handsPlayed).toBeLessThanOrEqualTo(500);
    expect(result.moves).toBeGreaterThan(0);

    // Alle vinderholdets brikker skal være i hjemstrækket
    const winning = result.winningTeam;
    const winningPlayers = result.state.players.filter(
      (p) => p.index % 2 === winning,
    );
    for (const p of winningPlayers) {
      for (const piece of p.pieces) {
        expect(piece.position).toMatch(/^home:/);
      }
    }

    console.log(
      `Hold ${result.winningTeam} vandt på ${result.handsPlayed} hænder med ${result.moves} træk`,
    );

    await page.screenshot({
      path: 'test-results/screenshots/game-over.png',
      fullPage: true,
    });
  });

  test('multiple games complete successfully (seeded variety)', async ({
    page,
  }) => {
    test.setTimeout(300_000);
    await page.goto(TEST_URL);
    await waitForBridge(page);

    const results: number[] = [];
    for (let i = 0; i < 3; i++) {
      await page.evaluate(() => (window as any).partnersTest.reset());
      await page.evaluate(() =>
        (window as any).partnersTest.startGame(
          ['P1', 'P2', 'P3', 'P4'],
          [0xffe53935, 0xff1e88e5, 0xff43a047, 0xfffdd835],
        ),
      );
      const res = (await page.evaluate(() =>
        (window as any).partnersTest.playFullGame(500),
      )) as FullGameResult;
      expect(res.winningTeam, `game ${i + 1} should end`).not.toBeNull();
      results.push(res.handsPlayed);
    }
    console.log('Hænder pr. spil:', results.join(', '));
  });

  test('captures screenshots at exchange and play phases', async ({ page }) => {
    await page.goto(TEST_URL);
    await waitForBridge(page);
    await page.evaluate(() =>
      (window as any).partnersTest.startGame(
        ['Du', 'Mads', 'Anna', 'Peter'],
        [0xffe53935, 0xff1e88e5, 0xff43a047, 0xfffdd835],
      ),
    );
    await page.waitForTimeout(500);
    await page.screenshot({
      path: 'test-results/screenshots/phase-exchange.png',
      fullPage: true,
    });

    // Lad AI'erne submit deres exchange-kort + menneske
    await page.evaluate(() => {
      const t = (window as any).partnersTest;
      for (let i = 0; i < 4; i++) t.aiSubmitExchange(i);
    });
    await page.waitForTimeout(500);
    await page.screenshot({
      path: 'test-results/screenshots/phase-play.png',
      fullPage: true,
    });
  });
});
