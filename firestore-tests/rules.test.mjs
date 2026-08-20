// Angreb mod firestore.rules i Firestore-emulatoren.
//
// Hver regel efterprøves med (a) et ANGREB der SKAL afvises, og (b) en tilladt
// handling der SKAL lykkes — så en for-løs mutation (fx `allow write: if true`)
// gør et angreb grønt og fanges, OG en for-stram mutation gør den tilladte
// handling rød og fanges. Køres via `firebase emulators:exec` (se package.json).

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  setLogLevel,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';

const ADMIN_EMAIL = 'cvejleaa@gmail.com';
const admin = { email: ADMIN_EMAIL, email_verified: true };

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

const as = (uid, token = {}) => env.authenticatedContext(uid, token).firestore();
const anon = () => env.unauthenticatedContext().firestore();
// Seed data der IGNORERER reglerne (til at bygge en udgangsstilling op).
const seed = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

describe('config/{document}', () => {
  it('alle (også ikke-indloggede) må læse — nye spil arver kortreglerne', async () => {
    await seed((db) => setDoc(doc(db, 'config/ui'), { boardMinPx: 230 }));
    await assertSucceeds(getDoc(doc(anon(), 'config/ui')));
  });
  it('ANGREB: almindelig indlogget bruger må ikke skrive config', async () => {
    await assertFails(setDoc(doc(as('mallory'), 'config/ui'), { boardMinPx: 999 }));
  });
  it('admin må skrive config', async () => {
    await assertSucceeds(
      setDoc(doc(as('adm', admin), 'config/ui'), { boardMinPx: 240 }));
  });
  it('ANGREB: admin-email UDEN email_verified er IKKE admin', async () => {
    // email/password sætter email_verified=false indtil verifikation — en
    // nyoprettet konto med admin-adressen må ikke opnå admin-rettigheder.
    const notVerified = { email: ADMIN_EMAIL, email_verified: false };
    await assertFails(
      setDoc(doc(as('imposter', notVerified), 'config/ui'), { boardMinPx: 1 }));
  });
});

describe('users/{uid}/friends/{friendUid}', () => {
  it('ejeren må læse og skrive sin egen venneliste', async () => {
    await assertSucceeds(
      setDoc(doc(as('alice'), 'users/alice/friends/bob'), { since: 1 }));
    await assertSucceeds(getDoc(doc(as('alice'), 'users/alice/friends/bob')));
  });
  it('ANGREB: må ikke læse en ANDENS venneliste', async () => {
    await seed((db) => setDoc(doc(db, 'users/alice/friends/bob'), { since: 1 }));
    await assertFails(getDoc(doc(as('mallory'), 'users/alice/friends/bob')));
  });
  it('ANGREB: må ikke skrive i en ANDENS venneliste', async () => {
    await assertFails(
      setDoc(doc(as('mallory'), 'users/alice/friends/bob'), { since: 2 }));
  });
});

describe('users/{uid}', () => {
  it('indlogget må læse andres profil (venne-søgning)', async () => {
    await seed((db) => setDoc(doc(db, 'users/alice'), { name: 'Alice' }));
    await assertSucceeds(getDoc(doc(as('bob'), 'users/alice')));
  });
  it('ANGREB: ikke-indlogget må ikke læse profiler', async () => {
    await seed((db) => setDoc(doc(db, 'users/alice'), { name: 'Alice' }));
    await assertFails(getDoc(doc(anon(), 'users/alice')));
  });
  it('må skrive sin EGEN profil', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), 'users/alice'), { name: 'A' }));
  });
  it('ANGREB: må ikke skrive en ANDENS profil', async () => {
    await assertFails(setDoc(doc(as('bob'), 'users/alice'), { name: 'hacked' }));
  });
});

describe('users/{uid}/inbox — anti-spoof af invitationer', () => {
  const invite = (from, over = {}) => ({
    fromUid: from,
    type: 'gameInvite',
    fromName: 'Ven',
    gameCode: 'ABCD',
    ...over,
  });
  it('må oprette invitation i andens indbakke MED sin egen uid som afsender', async () => {
    await assertSucceeds(
      addDoc(collection(as('bob'), 'users/alice/inbox'), invite('bob')));
  });
  it('ANGREB: forfalsket afsender (fromUid != egen uid) afvises', async () => {
    await assertFails(
      addDoc(collection(as('bob'), 'users/alice/inbox'), invite('someone-else')));
  });
  it('ANGREB: forkert type afvises', async () => {
    await assertFails(addDoc(collection(as('bob'), 'users/alice/inbox'),
      invite('bob', { type: 'spam' })));
  });
  it('ANGREB: for langt fromName (>60) afvises', async () => {
    await assertFails(addDoc(collection(as('bob'), 'users/alice/inbox'),
      invite('bob', { fromName: 'x'.repeat(61) })));
  });
  it('ANGREB: for lang gameCode (>12) afvises', async () => {
    await assertFails(addDoc(collection(as('bob'), 'users/alice/inbox'),
      invite('bob', { gameCode: 'x'.repeat(13) })));
  });
  it('ANGREB: må ikke læse en ANDENS indbakke', async () => {
    await seed((db) => setDoc(doc(db, 'users/alice/inbox/i1'), invite('bob')));
    await assertFails(getDoc(doc(as('bob'), 'users/alice/inbox/i1')));
  });
  it('ejeren må opdatere og slette i sin egen indbakke', async () => {
    await seed((db) => setDoc(doc(db, 'users/alice/inbox/i1'), invite('bob')));
    await assertSucceeds(updateDoc(doc(as('alice'), 'users/alice/inbox/i1'), { seen: true }));
    await assertSucceeds(deleteDoc(doc(as('alice'), 'users/alice/inbox/i1')));
  });
  it('ANGREB: afsenderen (ikke-ejer) må ikke opdatere/slette invitationen bagefter', async () => {
    await seed((db) => setDoc(doc(db, 'users/alice/inbox/i1'), invite('bob')));
    await assertFails(updateDoc(doc(as('bob'), 'users/alice/inbox/i1'), { seen: true }));
    await assertFails(deleteDoc(doc(as('bob'), 'users/alice/inbox/i1')));
  });
});

describe('games/{game}', () => {
  const game = (over = {}) => ({
    hostUid: 'alice', status: 'playing', members: ['alice'], ...over,
  });
  it('må oprette spil med SIG SELV som vært', async () => {
    await assertSucceeds(
      setDoc(doc(as('alice'), 'games/G1'), game({ status: 'lobby' })));
  });
  it('ANGREB: må ikke oprette spil med en anden som vært', async () => {
    await assertFails(
      setDoc(doc(as('bob'), 'games/G1'), game({ hostUid: 'alice', status: 'lobby' })));
  });
  it('enhver indlogget må læse et spil', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game()));
    await assertSucceeds(getDoc(doc(as('carol'), 'games/G1')));
  });
  it('ANGREB: ikke-indlogget må hverken læse eller oprette et spil', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game()));
    await assertFails(getDoc(doc(anon(), 'games/G1')));
    await assertFails(
      setDoc(doc(anon(), 'games/G2'), game({ hostUid: 'x', status: 'lobby' })));
  });
  it('medlem må opdatere et igangværende spil', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game()));
    await assertSucceeds(updateDoc(doc(as('alice'), 'games/G1'), { seq: 2 }));
  });
  it('ANGREB: ikke-medlem må IKKE opdatere et igangværende (playing) spil', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game()));
    await assertFails(updateDoc(doc(as('mallory'), 'games/G1'), { seq: 99 }));
  });
  it('ikke-medlem må opdatere et spil i LOBBY (for at kunne joine)', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game({ status: 'lobby' })));
    await assertSucceeds(updateDoc(doc(as('newbie'), 'games/G1'), { seq: 1 }));
  });
  it('vært må slette sit spil', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game()));
    await assertSucceeds(deleteDoc(doc(as('alice'), 'games/G1')));
  });
  it('ANGREB: ikke-vært/ikke-admin må IKKE slette et spil', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game()));
    await assertFails(deleteDoc(doc(as('mallory'), 'games/G1')));
  });
  // variantId (variant-valg i lobbyen) ligger BEVIDST i samme skrive-flade som
  // de øvrige lobby-felter (aiLevel/names). Disse to vagter fastholder den flade
  // netop for variant-feltet, så en fremtidig stramning/mutation af games-
  // update-reglen fanges på variant-stien og ikke kun på seq/aiLevel.
  it('medlem må sætte variantId (variant vælges i lobbyen)', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game({ status: 'lobby' })));
    await assertSucceeds(
      updateDoc(doc(as('alice'), 'games/G1'), { variantId: 'p25' }));
  });
  it('ANGREB: ikke-medlem må IKKE sætte variantId på et igangværende (playing) spil', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game()));
    await assertFails(
      updateDoc(doc(as('mallory'), 'games/G1'), { variantId: 'p25' }));
  });
});

describe('games/{game}/presence/{uid}', () => {
  it('må skrive sit EGET stempel på formen {t: <timestamp>}', async () => {
    await assertSucceeds(setDoc(
      doc(as('alice'), 'games/G1/presence/alice'), { t: Timestamp.now() }));
  });
  it('ANGREB: må ikke skrive en ANDEN spillers presence', async () => {
    await assertFails(setDoc(
      doc(as('bob'), 'games/G1/presence/alice'), { t: Timestamp.now() }));
  });
  it('ANGREB: ekstra felter afvises (kun {t} tilladt)', async () => {
    await assertFails(setDoc(doc(as('alice'), 'games/G1/presence/alice'),
      { t: Timestamp.now(), spoof: 'x' }));
  });
  it('ANGREB: t der ikke er et timestamp afvises', async () => {
    await assertFails(setDoc(
      doc(as('alice'), 'games/G1/presence/alice'), { t: 'ikke-et-timestamp' }));
  });
  it('indlogget må læse presence-markører', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1/presence/alice'), { t: Timestamp.now() }));
    await assertSucceeds(getDoc(doc(as('bob'), 'games/G1/presence/alice')));
  });
});

for (const col of ['userStats', 'userStatsOnline']) {
  describe(`${col}/{uid}`, () => {
    it('indlogget må læse (ranglisten viser andres tal)', async () => {
      await seed((db) => setDoc(doc(db, `${col}/alice`), { gamesPlayed: 3 }));
      await assertSucceeds(getDoc(doc(as('bob'), `${col}/alice`)));
    });
    it('må skrive sin EGEN stats-doc', async () => {
      await assertSucceeds(
        setDoc(doc(as('alice'), `${col}/alice`), { gamesPlayed: 4 }));
    });
    it('ANGREB: må IKKE skrive en ANDENS stats (rangliste-snyd)', async () => {
      await assertFails(
        setDoc(doc(as('mallory'), `${col}/alice`), { gamesPlayed: 999 }));
    });
    it('admin må skrive alles stats (genberegning)', async () => {
      await assertSucceeds(
        setDoc(doc(as('adm', admin), `${col}/alice`), { gamesPlayed: 4 }));
    });
  });
}
