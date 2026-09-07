// Efterprøver DEN FAKTISKE Firestore-forespørgsel bag "Mine spil"s
// 14-dages-arkivgrænse (myGamesFor/_myGamesBounded i online_service.dart,
// forbrugs-fund #18/#52) mod den rigtige emulator — ikke bare en ren
// Dart-funktion. Uden dette kunne en mutation af selve filter-grænsen (fx
// `>=` byttet til `<`, eller den forkerte feltnavn) lande med grøn suite:
// ingen ren Dart-test rører selve Firestore-forespørgslen (se
// test/my_games_merge_test.dart, som kun tester SAMMENLÆGNINGEN af de to
// resultatlister, ikke selve filtreringen).
//
// Genbruger samme emulator-harness som firestore.rules (se package.json
// "test:rules:run") — IKKE et angreb på reglerne (dem tester rules.test.mjs),
// men et tjek af forespørgslens FILTER-korrekthed mod en rigtig emulator.
// Kræver INTET sammensat indeks lokalt: emulatoren kræver ikke indekser for
// at udføre en forespørgsel (kun produktion gør) — se firestore.indexes.json
// og faldbacken i myGamesFor for produktions-siden af den grænse.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDocs,
  query,
  setDoc,
  setLogLevel,
  Timestamp,
  where,
} from 'firebase/firestore';

let env;

before(async () => {
  setLogLevel('error');
  env = await initializeTestEnvironment({
    projectId: 'demo-partners',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const UID = 'u1';
const DAY_MS = 24 * 60 * 60 * 1000;
const ARCHIVE_WINDOW_MS = 14 * DAY_MS;

const as = (uid) => env.authenticatedContext(uid, {}).firestore();
const seed = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

function seedGame(db, code, extra) {
  return setDoc(doc(db, 'games', code), {
    members: [UID],
    uids: [UID, null, null, null],
    hostUid: UID,
    hostName: 'Vært',
    ...extra,
  });
}

// Samme to forespørgsler som OnlineService._myGamesBounded
// (lib/online/online_service.dart) — hold dem i sync, ellers tester dette
// filen ikke det den påstår.
function fetchActive(db) {
  return getDocs(query(
    collection(db, 'games'),
    where('members', 'array-contains', UID),
    where('status', 'in', ['lobby', 'playing']),
  ));
}

function fetchRecentlyOver(db, cutoff) {
  return getDocs(query(
    collection(db, 'games'),
    where('members', 'array-contains', UID),
    where('status', '==', 'over'),
    where('finishedAt', '>=', cutoff),
  ));
}

describe('"Mine spil" — 14-dages-arkivgrænsen (forbrugs-fund #18/#52)', () => {
  it('afsluttet spil for 20 dage siden er UDENFOR vinduet', async () => {
    const now = Date.now();
    await seed((db) => seedGame(db, 'OLD', {
      status: 'over',
      finishedAt: Timestamp.fromMillis(now - 20 * DAY_MS),
    }));
    const cutoff = Timestamp.fromMillis(now - ARCHIVE_WINDOW_MS);
    const snap = await fetchRecentlyOver(as(UID), cutoff);
    assert.equal(snap.size, 0);
  });

  it('afsluttet spil for 2 dage siden er INDENFOR vinduet', async () => {
    const now = Date.now();
    await seed((db) => seedGame(db, 'NEW', {
      status: 'over',
      finishedAt: Timestamp.fromMillis(now - 2 * DAY_MS),
    }));
    const cutoff = Timestamp.fromMillis(now - ARCHIVE_WINDOW_MS);
    const snap = await fetchRecentlyOver(as(UID), cutoff);
    assert.equal(snap.size, 1);
  });

  it('aktive spil (lobby/playing) kommer med UANSET alder', async () => {
    const now = Date.now();
    await seed((db) => seedGame(db, 'OLDLOBBY', {
      status: 'lobby',
      createdAt: Timestamp.fromMillis(now - 90 * DAY_MS),
    }));
    const snap = await fetchActive(as(UID));
    assert.equal(snap.size, 1);
  });

  it('et afsluttet spil ses IKKE af aktiv-forespørgslen, og et aktivt spil ses IKKE af arkiv-forespørgslen', async () => {
    const now = Date.now();
    await seed((db) => seedGame(db, 'PLAYING', { status: 'playing' }));
    const cutoff = Timestamp.fromMillis(now - ARCHIVE_WINDOW_MS);
    const [activeSnap, overSnap] = await Promise.all([
      fetchActive(as(UID)),
      fetchRecentlyOver(as(UID), cutoff),
    ]);
    assert.equal(activeSnap.size, 1);
    assert.equal(overSnap.size, 0);
  });

  it('spil hvor uid IKKE er medlem, kommer aldrig med', async () => {
    const now = Date.now();
    await seed((db) => setDoc(doc(db, 'games', 'FREMMED'), {
      members: ['andet-uid'],
      uids: ['andet-uid', null, null, null],
      status: 'playing',
    }));
    await seed((db) => seedGame(db, 'FREMMED2', {
      status: 'over',
      finishedAt: Timestamp.fromMillis(now),
      members: ['andet-uid'],
    }));
    const cutoff = Timestamp.fromMillis(now - ARCHIVE_WINDOW_MS);
    const [activeSnap, overSnap] = await Promise.all([
      fetchActive(as(UID)),
      fetchRecentlyOver(as(UID), cutoff),
    ]);
    assert.equal(activeSnap.size, 0);
    assert.equal(overSnap.size, 0);
  });
});
