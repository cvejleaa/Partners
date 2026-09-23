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
  arrayUnion,
  collection,
  deleteDoc,
  deleteField,
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

  // SEMANTIK-vagter (ikke adgang): config/cardRules bærer nu BÅDE de klassiske
  // regler ('rules') og admins variant-regler ('variants.p25'). Klienten
  // skriver med SetOptions(mergeFields: ...), netop så et klassisk-gem ikke
  // sletter variant-reglerne (og omvendt). Disse tests beviser mergeFields/
  // deleteField-semantikken mod emulatoren; payload-FORMEN (at klassisk-gemmet
  // kun bærer 'rules') bevises i Dart-unit-tests (card_rules_payload).
  it('mergeFields: klassisk-gem SLETTER IKKE variants (25 år-reglerne)', async () => {
    const db = as('adm', admin);
    await setDoc(doc(db, 'config/cardRules'), {
      rules: { five: { forwardSteps: [5] } },
      variants: { p25: { rules: { five: { forwardSteps: [5], jumpsBlockade: true } } } },
    });
    // Klassisk-gem: kun 'rules' i payload + mergeFields.
    await setDoc(doc(db, 'config/cardRules'),
      { rules: { five: { forwardSteps: [6] } } },
      { mergeFields: ['rules'] });
    const snap = await getDoc(doc(db, 'config/cardRules'));
    const d = snap.data();
    if (!d.variants?.p25?.rules?.five?.jumpsBlockade) {
      throw new Error('variants.p25 blev slettet af klassisk-gemmet (merge-fælden!)');
    }
    if (d.rules.five.forwardSteps[0] !== 6) {
      throw new Error('klassisk-gemmet slog ikke igennem');
    }
  });
  it('mergeFields: variant-gem ERSTATTER variants.p25 (fjernet rang forsvinder) uden at røre rules', async () => {
    const db = as('adm', admin);
    await setDoc(doc(db, 'config/cardRules'), {
      rules: { five: { forwardSteps: [5] } },
      variants: { p25: { rules: { five: { jumpsBlockade: true }, jack: { swap: true } } } },
    });
    // Variant-gem uden 'jack' — mergeFields på variants.p25 skal ERSTATTE
    // feltet, så jack-override reelt forsvinder (et dybt merge ville beholde den).
    await setDoc(doc(db, 'config/cardRules'),
      { variants: { p25: { rules: { five: { jumpsBlockade: true } } } } },
      { mergeFields: ['variants.p25'] });
    const d = (await getDoc(doc(db, 'config/cardRules'))).data();
    if (d.variants.p25.rules.jack !== undefined) {
      throw new Error('fjernet rang overlevede variant-gemmet (dyb-merge-fælden)');
    }
    if (!d.rules?.five) throw new Error('rules blev rørt af variant-gemmet');
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
  // Fixturen får et SÆDE, ikke bare et medlemskab: et igangværende spil UDEN
  // uids kan ikke opstå i virkeligheden (startGameFromLobby skriver sæderne
  // sammen med status), og et sådant fixture ville skjule, at adgangen nu
  // hviler på sædet frem for på 'members'.
  const seated = { uids: ['alice', 'bob', null, null] };
  it('en SIDDENDE spiller må opdatere et igangværende spil', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game(seated)));
    await assertSucceeds(updateDoc(doc(as('alice'), 'games/G1'), { seq: 2 }));
  });
  it('ANGREB: ikke-medlem må IKKE opdatere et igangværende (playing) spil', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game(seated)));
    await assertFails(updateDoc(doc(as('mallory'), 'games/G1'), { seq: 99 }));
  });
  // ---- ANGREB mod spil-dokumentets deltagerliste (security-gennemgang) ----
  // Roden til tre efterprøvede angreb: kunne man skrive FREMMEDE uid'er ind i
  // et spil, kunne man (1) forgifte ofrenes statistik — den genberegnes ud fra
  // alle spil der nævner deres uid, (2) få serveren (onGameOver) til at skrive
  // på deres vegne, og (3) spamme dem med "din tur"-push via onGameTurn.
  it('ANGREB: må IKKE oprette et spil med FREMMEDE uid\'er i sæderne', async () => {
    await assertFails(setDoc(doc(as('mallory'), 'games/EVIL1'), {
      hostUid: 'mallory', status: 'lobby', members: ['mallory'],
      uids: ['alice', 'bob', null, 'mallory'],
    }));
  });
  it('ANGREB: må IKKE oprette et spil med fremmede MEDLEMMER', async () => {
    await assertFails(setDoc(doc(as('mallory'), 'games/EVIL2'), {
      hostUid: 'mallory', status: 'lobby', members: ['mallory', 'alice'],
      uids: ['mallory', null, null, null],
    }));
  });
  it('må oprette et spil med sig selv i ét sæde (det ægte flow)', async () => {
    await assertSucceeds(setDoc(doc(as('mallory'), 'games/OK1'), {
      hostUid: 'mallory', status: 'lobby', members: ['mallory'],
      uids: ['mallory', null, null, null],
    }));
  });
  it('må gemme et færdigt AI-solospil direkte som over (kun egen uid)', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), 'games/AI1'), {
      hostUid: 'alice', status: 'over', members: ['alice'],
      uids: ['alice', null, null, null],
    }));
  });
  it('ANGREB: må IKKE skrive fremmede uid\'er ind i en ÅBEN lobby', async () => {
    await seed((db) => setDoc(doc(db, 'games/G9'), {
      hostUid: 'alice', status: 'lobby', members: ['alice'],
      uids: ['alice', null, null, null],
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/G9'), {
      uids: ['alice', 'bob', 'carol', 'mallory'],
    }));
  });
  it('join: må sætte SIG SELV i en ledig plads (det ægte flow)', async () => {
    await seed((db) => setDoc(doc(db, 'games/G10'), {
      hostUid: 'alice', status: 'lobby', members: ['alice'],
      uids: ['alice', null, null, null],
    }));
    await assertSucceeds(updateDoc(doc(as('bob'), 'games/G10'), {
      uids: ['alice', 'bob', null, null],
      members: ['alice', 'bob'],
    }));
  });
  it('join: sædeskift frigør egen plads (null skal stadig være tilladt)', async () => {
    await seed((db) => setDoc(doc(db, 'games/G11'), {
      hostUid: 'alice', status: 'lobby', members: ['alice', 'bob'],
      uids: ['alice', 'bob', null, null],
    }));
    await assertSucceeds(updateDoc(doc(as('bob'), 'games/G11'), {
      uids: ['alice', null, 'bob', null],
    }));
  });
  it('vært må invitere en ANDEN (tilføjer dem til members)', async () => {
    // Invitationer og revanche skriver den INVITEREDES uid i members. En
    // "kun sig selv"-regel på members ville slå begge ihjel — members er
    // alene en adgangsliste og fodrer ingen af misbrugs-stierne.
    await seed((db) => setDoc(doc(db, 'games/G14'), {
      hostUid: 'alice', status: 'lobby', members: ['alice'],
      uids: ['alice', null, null, null], invitedUids: [],
    }));
    await assertSucceeds(updateDoc(doc(as('alice'), 'games/G14'), {
      invitedUids: ['bob'], members: ['alice', 'bob'],
    }));
    // ... men en invitation må stadig ikke sætte den inviterede i et SÆDE.
    await assertFails(updateDoc(doc(as('alice'), 'games/G14'), {
      uids: ['alice', 'bob', null, null],
    }));
  });

  // ---- TO-TRINS-OVERTAGELSE af en åben lobby (sikkerheds-gennemgang) ----
  // Ét-trins-testen nedenfor var GRØN hele tiden og gav falsk tryghed: samme
  // angriber nåede målet i to skridt, fordi 'members' bevidst er ubegrænset.
  // Efterprøvet i emulatoren FØR rettelsen: alle tre skridt lykkedes.
  it('ANGREB: udenforstående må IKKE skrive sig ind i members og DERFRA ' +
      'flippe en fremmed lobby til playing', async () => {
    await seed((db) => setDoc(doc(db, 'games/TAKE1'), {
      hostUid: 'alice', status: 'lobby', members: ['alice', 'bob'],
      uids: ['alice', 'bob', null, null],
    }));
    const m = as('mallory');
    // Trin 1 er stadig tilladt — 'members' SKAL kunne vokse (invite/revanche).
    await assertSucceeds(updateDoc(doc(m, 'games/TAKE1'),
        { members: ['alice', 'bob', 'mallory'] }));
    // Trin 2 er dét, der nu afvises: status kræver et SÆDE, ikke et medlemskab.
    await assertFails(updateDoc(doc(m, 'games/TAKE1'), { status: 'playing' }));
    await assertFails(updateDoc(doc(m, 'games/TAKE1'), { status: 'over' }));
  });

  it('ANGREB: et MEDLEM uden sæde må ikke skrive state i et igangværende spil',
      async () => {
    // Trin 3 i kæden, isoleret: selv hvis angriberen står i members (fx fordi
    // de blev inviteret og aldrig satte sig), må de ikke røre brættet — det
    // ville både korrumpere spillet og udløse "din tur"-push i ring.
    await seed((db) => setDoc(doc(db, 'games/TAKE2'), {
      hostUid: 'alice', status: 'playing', members: ['alice', 'bob', 'mallory'],
      uids: ['alice', 'bob', null, null],
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/TAKE2'),
        { state: { ph: 'play', cp: 1, hn: 1 } }));
  });

  it('TILLADT: en inviteret UDEN sæde må stadig skrive sit EGET seen-stempel',
      async () => {
    // Undtagelsen der holder arkivet i live: man kan være inviteret uden at
    // have taget plads, og åbner man spillet, kalder skærmen markSeen.
    await seed((db) => setDoc(doc(db, 'games/SEEN1'), {
      hostUid: 'alice', status: 'over', members: ['alice', 'bob', 'mallory'],
      uids: ['alice', 'bob', null, null], seen: { alice: 3 },
    }));
    await assertSucceeds(updateDoc(doc(as('mallory'), 'games/SEEN1'),
        { 'seen.mallory': 7 }));
  });

  // Den ægte flow-dækning ovenfor bruger status 'over' — men markSeen kaldes
  // fra online_game_screen ved ÅBNING af skærmen, UANSET status (også et
  // spil der stadig er i gang). onlyOwnSeen() har ingen status-betingelse i
  // koden, men INGEN eksisterende test beviste det: alle andre seen-tests med
  // status 'playing' er ANGREB (der SKAL fejle uanset), så en fremtidig
  // for-stram regel (fx "seen-undtagelsen gælder kun for 'over'") ville
  // stadig lade dem fejle korrekt — og ville brække netop dette ægte flow
  // uden at noget blev rødt.
  it('TILLADT: en inviteret UDEN sæde må skrive sit EGET seen-stempel på et ' +
      'IGANGVÆRENDE (playing) spil, ikke kun et afsluttet', async () => {
    await seed((db) => setDoc(doc(db, 'games/SEEN1B'), {
      hostUid: 'alice', status: 'playing', members: ['alice', 'bob', 'mallory'],
      uids: ['alice', 'bob', null, null], seen: { alice: 3 },
    }));
    await assertSucceeds(updateDoc(doc(as('mallory'), 'games/SEEN1B'),
        { 'seen.mallory': 7 }));
  });

  it('ANGREB: seen-undtagelsen må IKKE bruges til at skrive ANDRES stempel',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/SEEN2'), {
      hostUid: 'alice', status: 'over', members: ['alice', 'bob', 'mallory'],
      uids: ['alice', 'bob', null, null], seen: { alice: 3 },
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/SEEN2'),
        { 'seen.alice': 0 }));
  });

  it('ANGREB: seen-undtagelsen må IKKE smugle andre felter med', async () => {
    await seed((db) => setDoc(doc(db, 'games/SEEN3'), {
      hostUid: 'alice', status: 'playing', members: ['alice', 'bob', 'mallory'],
      uids: ['alice', 'bob', null, null], seen: { alice: 3 },
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/SEEN3'),
        { 'seen.mallory': 7, status: 'over' }));
  });

  it('ANGREB: seen-undtagelsen må IKKE smugle STATE med (K1 ad bagvejen)',
      async () => {
    // Min første udgave af denne test smuglede `status` med — men `status` er
    // allerede dækket af statusUnchangedOrSeated, så testen blev rød på en
    // HELT ANDEN vagt end den, den troede den målte. hasOnly(['seen']) på
    // topniveau var dermed utestet, og kunne løsnes til hasAny uden at noget
    // blev rødt — hvilket genåbner K1 ordret (sikkerheds-fund).
    await seed((db) => setDoc(doc(db, 'games/SEEN4'), {
      hostUid: 'alice', status: 'playing', members: ['alice', 'bob', 'mallory'],
      uids: ['alice', 'bob', null, null], seen: { alice: 3 },
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/SEEN4'),
        { 'seen.mallory': 7, state: { ph: 'play', cp: 1, hn: 1 } }));
  });

  it('ANGREB: seen-undtagelsen må IKKE skrive eget OG andres stempel', async () => {
    // Skrives KUN andres nøgle, afvises det også af en for-løs hasAny-udgave,
    // så den test kunne ikke skelne. Eget + andres er dét, der kan.
    await seed((db) => setDoc(doc(db, 'games/SEEN5'), {
      hostUid: 'alice', status: 'playing', members: ['alice', 'bob', 'mallory'],
      uids: ['alice', 'bob', null, null], seen: { alice: 3, bob: 2 },
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/SEEN5'),
        { 'seen.mallory': 7, 'seen.alice': 0 }));
  });

  it('ANGREB: seen-stemplet må ikke være andet end et tal', async () => {
    // Ellers kunne et medlem uden sæde puste dokumentet op mod 1 MiB-loftet
    // og gøre det uskrivbart for de rigtige spillere.
    await seed((db) => setDoc(doc(db, 'games/SEEN6'), {
      hostUid: 'alice', status: 'playing', members: ['alice', 'bob', 'mallory'],
      uids: ['alice', 'bob', null, null], seen: { alice: 3 },
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/SEEN6'),
        { 'seen.mallory': 'x'.repeat(50000) }));
  });

  // ---- ANDRES SÆDER (regression indført af sæde-kravet, efterprøvet) ----
  //
  // NAVNGIVET, IKKE LUKKET (QC-fund): vagterne beskytter mod at FJERNE en
  // andens sæde, ikke mod at FLYTTE det. En siddende spiller kan omrokere en
  // medspiller fra plads 1 til plads 2 uden samtykke — alle uid'er er jo
  // stadig til stede, så othersSeatsKept er tilfreds. Sædet afgør
  // turrækkefølge og farver, så det er en reel, om end sjælden, skrøbelighed.
  // Den fandtes før denne ændring og lukkes ikke af den.
  it('ANGREB: må IKKE skubbe en siddende spiller ud af en åben lobby', async () => {
    // Før denne vagt kunne Mallory overskrive værtens sæde, flippe til
    // playing, og så var værten LÅST ude af sit eget spil for altid — sæde-
    // kravet gjorde udelukkelsen permanent, hvor 'members' før var en vej hjem.
    await seed((db) => setDoc(doc(db, 'games/SEAT2'), {
      hostUid: 'alice', status: 'lobby', members: ['alice', 'bob'],
      uids: ['alice', 'bob', null, null],
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/SEAT2'),
        { uids: ['mallory', null, null, null] }));
  });

  it('ANGREB: må IKKE erstatte ÉN ud af flere siddende spillere og lade ' +
      'resten stå (partiel-fjernelse, adskiller hasAll fra hasAny)', async () => {
    // SEAT2 fjerner ALLE andre sæder på én gang — det skelner IKKE
    // othersSeatsKept()'s `hasAll` fra en svækket `hasAny` (begge er "false"
    // når INGEN andre er tilbage). Her beholder mallory bob, men sletter
    // carol og tager hendes plads — det kræver netop hasALL for at blive
    // fanget.
    await seed((db) => setDoc(doc(db, 'games/SEAT5'), {
      hostUid: 'alice', status: 'lobby', members: ['alice', 'bob', 'carol'],
      uids: ['alice', 'bob', 'carol', null],
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/SEAT5'), {
      uids: ['alice', 'bob', 'mallory', null],
    }));
  });

  it('ANGREB: en siddende spiller må ikke TØMME sæderne (brick)', async () => {
    // Er ingen længere siddende, er dokumentet uskrivbart for alle — også
    // værten. Kun sletning ville hjælpe.
    await seed((db) => setDoc(doc(db, 'games/SEAT3'), {
      hostUid: 'alice', status: 'playing', members: ['alice', 'bob'],
      uids: ['alice', 'bob', null, null],
    }));
    await assertFails(updateDoc(doc(as('alice'), 'games/SEAT3'), { uids: [] }));
  });

  it('TILLADT: man må flytte sit EGET sæde (joinGame skifter plads)', async () => {
    // Den for-stramme side: othersSeatsKept må ikke låse et sædeskift.
    await seed((db) => setDoc(doc(db, 'games/SEAT4'), {
      hostUid: 'alice', status: 'lobby', members: ['alice', 'bob'],
      uids: ['alice', 'bob', null, null],
    }));
    await assertSucceeds(updateDoc(doc(as('bob'), 'games/SEAT4'),
        { uids: ['alice', null, 'bob', null] }));
  });

  it('ANGREB: må IKKE kapre værtskabet (og derfra slette spillet)', async () => {
    // 'kun vært/admin må slette' hviler på hostUid. Var feltet skrivbart, var
    // reglen reelt 'enhver må slette enhver åben lobby'. Efterprøvet i to
    // skridt før vagten.
    await seed((db) => setDoc(doc(db, 'games/HOST1'), {
      hostUid: 'alice', status: 'lobby', members: ['alice'],
      uids: ['alice', null, null, null],
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/HOST1'),
        { hostUid: 'mallory' }));
  });

  it('TILLADT: en SIDDENDE spiller starter og spiller sit spil', async () => {
    // Den for-stramme mutation skal også fanges: gøres sæde-kravet gældende
    // for bredt, dør de rigtige flows.
    await seed((db) => setDoc(doc(db, 'games/SEAT1'), {
      hostUid: 'alice', status: 'lobby', members: ['alice', 'bob'],
      uids: ['alice', 'bob', null, null],
    }));
    await assertSucceeds(updateDoc(doc(as('alice'), 'games/SEAT1'),
        { status: 'playing', state: { ph: 'exchange', cp: 0, hn: 1 } }));
    await assertSucceeds(updateDoc(doc(as('bob'), 'games/SEAT1'),
        { state: { ph: 'play', cp: 1, hn: 1 } }));
    await assertSucceeds(updateDoc(doc(as('alice'), 'games/SEAT1'),
        { status: 'over', winningTeamIndex: 0 }));
  });

  it('TILLADT: en udenforstående tager plads i en åben lobby', async () => {
    await seed((db) => setDoc(doc(db, 'games/JOIN1'), {
      hostUid: 'alice', status: 'lobby', members: ['alice'],
      uids: ['alice', null, null, null],
    }));
    await assertSucceeds(updateDoc(doc(as('mallory'), 'games/JOIN1'), {
      uids: ['alice', 'mallory', null, null],
      members: ['alice', 'mallory'],
      'ready.mallory': false,
    }));
  });

  it('ANGREB: ikke-medlem må IKKE flippe en lobby til playing/over', async () => {
    await seed((db) => setDoc(doc(db, 'games/G12'), {
      hostUid: 'alice', status: 'lobby', members: ['alice'],
      uids: ['alice', null, null, null],
    }));
    // 'over' ville udløse onGameOver-markeringen; 'playing' åbner for
    // "din tur"-push-spam via onGameTurn.
    await assertFails(updateDoc(doc(as('mallory'), 'games/G12'), {
      status: 'over',
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/G12'), {
      status: 'playing',
    }));
  });
  it('en SIDDENDE spiller må selv starte og afslutte spillet', async () => {
    await seed((db) => setDoc(doc(db, 'games/G13'), {
      hostUid: 'alice', status: 'lobby', members: ['alice'],
      uids: ['alice', null, null, null],
    }));
    await assertSucceeds(
      updateDoc(doc(as('alice'), 'games/G13'), { status: 'playing' }));
    await assertSucceeds(
      updateDoc(doc(as('alice'), 'games/G13'), { status: 'over' }));
  });

  it('en udenforstående må opdatere et spil i LOBBY (for at kunne joine)', async () => {
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
  // variantId (variant-valg i lobbyen) må skrives af VÆRTEN (alice i
  // game()-fixturet) — se variantUnchangedOrHost og angrebene nedenfor.
  it('værten må sætte variantId (variant vælges i lobbyen)', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game({ status: 'lobby' })));
    await assertSucceeds(
      updateDoc(doc(as('alice'), 'games/G1'), { variantId: 'p25' }));
  });
  it('ANGREB: ikke-medlem må IKKE sætte variantId på et igangværende (playing) spil', async () => {
    await seed((db) => setDoc(doc(db, 'games/G1'), game()));
    await assertFails(
      updateDoc(doc(as('mallory'), 'games/G1'), { variantId: 'p25' }));
  });

  // ---- VARIANT-VALG ER VÆRTENS + PARTNERS DUO (spejlede pladser) ----
  //
  // Duo: to spillere på fire pladser; plads 2/3 er spejle af 0/1 (samme uid).
  // othersSeatsKept er mængde-baseret, så uden duoSeatsMirrored kunne en
  // fremmed overtage en spejl-plads (værtens uid står jo stadig på plads 0).
  // Og uden variantUnchangedOrHost kunne han i SAMME skrivning skifte
  // varianten væk fra Duo og dermed omgå spejl-kravet (QC-fund på planen).
  const duoLobby = (over) => ({
    hostUid: 'alice', status: 'lobby', members: ['alice', 'bob'],
    variantId: 'duo', uids: ['alice', 'bob', 'alice', 'bob'], ...over,
  });

  it('ANGREB: en gæst i lobbyen må IKKE skifte variant (kun værten)', async () => {
    await seed((db) => setDoc(doc(db, 'games/VAR1'), {
      hostUid: 'alice', status: 'lobby', members: ['alice', 'bob'],
      variantId: 'classic', uids: ['alice', 'bob', null, null],
    }));
    await assertFails(
      updateDoc(doc(as('bob'), 'games/VAR1'), { variantId: 'p25' }));
    // Værten må.
    await assertSucceeds(
      updateDoc(doc(as('alice'), 'games/VAR1'), { variantId: 'p25' }));
  });

  it('ANGREB: en fremmed må IKKE tage en Duo-spejlplads', async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO1'), duoLobby({
      members: ['alice'], uids: ['alice', null, 'alice', null],
    })));
    await assertFails(updateDoc(doc(as('mallory'), 'games/DUO1'),
        { uids: ['alice', null, 'mallory', null] }));
  });

  it('ANGREB: modstanderen må IKKE bryde spejlet (omrokere sig til plads 2)',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO2'), duoLobby()));
    await assertFails(updateDoc(doc(as('bob'), 'games/DUO2'),
        { uids: ['alice', 'bob', 'bob', 'bob'] }));
  });

  it('ANGREB: variant-skift + spejlplads i ÉN skrivning er afvist', async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO3'), duoLobby()));
    await assertFails(updateDoc(doc(as('mallory'), 'games/DUO3'), {
      variantId: 'classic', uids: ['alice', 'bob', 'mallory', 'bob'],
    }));
  });

  it('TILLADT: gæsten tager hånd-pladsen MED spejl i en Duo-lobby', async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO4'), duoLobby({
      members: ['alice'], uids: ['alice', null, 'alice', null],
    })));
    await assertSucceeds(updateDoc(doc(as('bob'), 'games/DUO4'),
        { uids: ['alice', 'bob', 'alice', 'bob'] }));
  });

  it('TILLADT: værten skifter fra Duo til klassisk og rydder spejlene',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO5'), duoLobby()));
    await assertSucceeds(updateDoc(doc(as('alice'), 'games/DUO5'), {
      variantId: 'classic', uids: ['alice', 'bob', null, null],
    }));
  });

  it('TILLADT: et spillende Duo-spil kan skrives (træk, seen)', async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO6'),
        duoLobby({ status: 'playing', state: { ph: 'play', cp: 1, hn: 1 } })));
    await assertSucceeds(updateDoc(doc(as('bob'), 'games/DUO6'),
        { 'state.cp': 0, seq: 1 }));
  });

  it('TILLADT: lokalt Duo-spil (mode ai, intet variantId) — seen virker',
      async () => {
    // Lokale Duo-spil gemmes med [a,null,a,null] og kun state.vid — ingen
    // variantId på topniveau. Spejl-kravet må ikke ramme dem.
    await seed((db) => setDoc(doc(db, 'games/DUO7'), {
      hostUid: 'alice', status: 'over', mode: 'ai', members: ['alice'],
      uids: ['alice', null, 'alice', null], state: { vid: 'duo' },
    }));
    await assertSucceeds(
      updateDoc(doc(as('alice'), 'games/DUO7'), { 'seen.alice': 3 }));
  });

  // ---- Security-gennemgang af Duo online (angreb efterprøvet i emulatoren) ----
  it('ANGREB: gæsten må IKKE SLETTE variantId (duo -> "ingen") og bryde spejlet',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO8'), duoLobby()));
    await assertFails(updateDoc(doc(as('bob'), 'games/DUO8'),
        { variantId: deleteField() }));
    await assertFails(updateDoc(doc(as('bob'), 'games/DUO8'), {
      variantId: deleteField(), uids: ['alice', 'bob', 'bob', 'bob'],
    }));
    // En fremmed i den åbne lobby heller ikke.
    await assertFails(updateDoc(doc(as('mallory'), 'games/DUO8'),
        { variantId: deleteField() }));
  });

  it('ANGREB: gæsten må IKKE ændre variantId-TYPEN (tal/map/null)', async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO9'), duoLobby()));
    for (const v of [7, { id: 'duo' }, null]) {
      await assertFails(
          updateDoc(doc(as('bob'), 'games/DUO9'), { variantId: v }));
    }
  });

  it('ANGREB: variantId må ikke TILFØJES af en gæst på et doc uden feltet',
      async () => {
    // Gamle docs har intet variantId (get-default null). Kun værten må sætte
    // det — ellers kunne en gæst gøre et klassisk spil til Duo (eller omvendt).
    await seed((db) => setDoc(doc(db, 'games/DUO10'), {
      hostUid: 'alice', status: 'lobby', members: ['alice', 'bob'],
      uids: ['alice', 'bob', null, null],
    }));
    await assertFails(updateDoc(doc(as('bob'), 'games/DUO10'),
        { variantId: 'classic' }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/DUO10'),
        { variantId: 'duo', uids: ['alice', 'bob', 'alice', 'bob'] }));
  });

  it('ANGREB: Duo-uids med 5 pladser (spejlet ellers "intakt") er afvist',
      async () => {
    // [a,b,a,b,b] opfylder uids[2]==uids[0] og uids[3]==uids[1] — kun
    // size()==4 fanger den. Uden den vagt kunne et ekstra "sæde" smugles ind.
    await seed((db) => setDoc(doc(db, 'games/DUO11'), duoLobby()));
    await assertFails(updateDoc(doc(as('bob'), 'games/DUO11'),
        { uids: ['alice', 'bob', 'alice', 'bob', 'bob'] }));
  });

  it('ANGREB: en fremmed må IKKE tage den ledige hånd i et SPILLENDE Duo-spil',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO12'), duoLobby({
      status: 'playing', members: ['alice'], uids: ['alice', null, 'alice', null],
    })));
    await assertFails(updateDoc(doc(as('mallory'), 'games/DUO12'),
        { uids: ['alice', 'mallory', 'alice', 'mallory'] }));
  });

  it('TILLADT: Duo-lobbyens øvrige flows (invitation, klar, forlad, start)',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO13'), duoLobby({
      members: ['alice'], uids: ['alice', null, 'alice', null],
    })));
    // Værten inviterer (arrayUnion af members/invitedUids).
    await assertSucceeds(updateDoc(doc(as('alice'), 'games/DUO13'), {
      members: arrayUnion('bob'), invitedUids: arrayUnion('bob'),
    }));
    // Gæsten sætter sig (med spejl), melder klar og forlader igen.
    await assertSucceeds(updateDoc(doc(as('bob'), 'games/DUO13'),
        { uids: ['alice', 'bob', 'alice', 'bob'] }));
    await assertSucceeds(
        updateDoc(doc(as('bob'), 'games/DUO13'), { 'ready.bob': true }));
    await assertSucceeds(updateDoc(doc(as('bob'), 'games/DUO13'),
        { uids: ['alice', null, 'alice', null] }));
    // Værten starter.
    await assertSucceeds(updateDoc(doc(as('alice'), 'games/DUO13'),
        { status: 'playing', state: { vid: 'duo' } }));
  });

  it('TILLADT: revanche — værten skifter sin nye lobby til Duo (setVariant)',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO14'), {
      hostUid: 'alice', status: 'lobby', members: ['alice'],
      variantId: 'classic', uids: ['alice', null, null, null],
    }));
    await assertSucceeds(updateDoc(doc(as('alice'), 'games/DUO14'), {
      variantId: 'duo', uids: ['alice', null, 'alice', null],
      'cardRulesVariants.duo': { rules: {} },
    }));
  });

  it('TILLADT: en inviteret uden plads må markere et afsluttet Duo-spil set',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO15'), duoLobby({
      status: 'over', members: ['alice', 'bob', 'eve'],
    })));
    await assertSucceeds(
        updateDoc(doc(as('eve'), 'games/DUO15'), { 'seen.eve': 2 }));
  });

  it('TILLADT: værten kan redde et gammelt doc med variantId duo uden spejl',
      async () => {
    // Før denne ændring kunne ENHVER i lobbyen skrive variantId: 'duo'. Et
    // sådant doc med fire forskellige uids afviser nu alle andre skrivninger
    // (duoSeatsMirrored) — værten skal kunne skifte det tilbage.
    await seed((db) => setDoc(doc(db, 'games/DUO16'), {
      hostUid: 'alice', status: 'playing', members: ['alice', 'bob', 'c', 'd'],
      variantId: 'duo', uids: ['alice', 'bob', 'c', 'd'],
    }));
    await assertSucceeds(updateDoc(doc(as('alice'), 'games/DUO16'),
        { variantId: 'classic' }));
  });

  // Security-fund på Duo online, lukket af seatsKeptByPosition: mængde-
  // vagten (othersSeatsKept) lod en fremmed GENTAGE eller BYTTE andres uid'er.
  it('ANGREB: en fremmed må IKKE sætte værten på begge hænder [a,a,a,a]',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO17'), duoLobby({
      members: ['alice'], uids: ['alice', null, 'alice', null],
    })));
    await assertFails(updateDoc(doc(as('mallory'), 'games/DUO17'),
        { uids: ['alice', 'alice', 'alice', 'alice'] }));
  });
  it('ANGREB: en fremmed må IKKE bytte andres pladser [b,a,b,a]', async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO18'), duoLobby()));
    await assertFails(updateDoc(doc(as('mallory'), 'games/DUO18'),
        { uids: ['bob', 'alice', 'bob', 'alice'] }));
  });
  // duoSeatsMirrored: DUO11 (5 pladser fra en GÆST) fanges allerede af
  // seatsKeptByPosition()'s n.size()==o.size() — men hostArrangingLobby()
  // gør netop DEN vagt uvirksom for værten selv. Uden duoSeatsMirrored()'s
  // EGEN size()==4 kunne værten smugle et 5. sæde ind (spejlet ellers
  // "intakt": uids[2]==uids[0] og uids[3]==uids[1] holder stadig).
  it('ANGREB: værten må IKKE tilføje et 5. sæde i sin egen Duo-lobby',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO20'), duoLobby()));
    await assertFails(updateDoc(doc(as('alice'), 'games/DUO20'),
        { uids: ['alice', 'bob', 'alice', 'bob', 'bob'] }));
  });
  // duoSeatsMirrored har TO lige-tegn (pos2==pos0 og pos3==pos1) — hver
  // fanger sin egen halvdel af spejlet. En test, der kun bryder FØRSTE par
  // (DUO19), beviser ikke at det ANDET par også er dækket: fjernes kun
  // uids[3]==uids[1], er DUO19 stadig rød på sin egen (uids[2]==uids[0]),
  // og suiten forbliver grøn med den anden vagt væk.
  it('ANGREB: værten må IKKE bryde spejlet for den ANDEN hånd (pos3)',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO21'), duoLobby()));
    await assertFails(updateDoc(doc(as('alice'), 'games/DUO21'),
        { uids: ['alice', 'bob', 'alice', 'alice'] }));
  });
  // duoSeatsMirrored: seatsKeptByPosition() alene stopper IKKE dette —
  // hostArrangingLobby() gør positions-vagten helt uvirksom for VÆRTEN i en
  // åben lobby, og de resterende (værdi-baserede) vagter tillader enhver
  // omrokering af allerede-kendte uid'er. Uden duoSeatsMirrored kunne værten
  // selv (eller en fremtidig lobby-handling på hendes vegne) parre pladserne
  // forkert (uids[2]!=uids[0]) og dermed lade bob "styre" et sæt uden at
  // stå på den hånd-plads, det spejler.
  it('ANGREB: værten må IKKE bryde SIT EGET Duo-spejl (uparrede sæder)',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/DUO19'), duoLobby()));
    await assertFails(updateDoc(doc(as('alice'), 'games/DUO19'),
        { uids: ['alice', 'bob', 'bob', 'alice'] }));
  });
  it('ANGREB: en siddende spiller må IKKE bytte pladser midt i et spil',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/POS1'), {
      hostUid: 'alice', status: 'playing', members: ['alice', 'bob', 'carol'],
      uids: ['alice', 'bob', 'carol', null],
    }));
    await assertFails(updateDoc(doc(as('bob'), 'games/POS1'),
        { uids: ['alice', 'carol', 'bob', null] }));
  });
  it('ANGREB: en fremmed må IKKE bytte pladser i en klassisk lobby',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/POS2'), {
      hostUid: 'alice', status: 'lobby', members: ['alice', 'bob'],
      uids: ['alice', 'bob', null, null],
    }));
    await assertFails(updateDoc(doc(as('mallory'), 'games/POS2'),
        { uids: ['alice', 'bob', 'bob', null] }));
  });
  it('ANGREB: værten må IKKE gentage en gæsts uid uden for Duo ' +
      '(ét parti talt som to i statistikken)', async () => {
    await seed((db) => setDoc(doc(db, 'games/POS3'), {
      hostUid: 'alice', status: 'lobby', members: ['alice', 'bob'],
      variantId: 'classic', uids: ['alice', 'bob', null, null],
    }));
    await assertFails(updateDoc(doc(as('alice'), 'games/POS3'),
        { uids: ['alice', 'bob', 'alice', 'bob'] }));
  });
  it('TILLADT: værten skifter til Duo og flytter gæsten fra plads 2 til 1',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/POS4'), {
      hostUid: 'alice', status: 'lobby', members: ['alice', 'bob'],
      variantId: 'classic', uids: ['alice', null, 'bob', null],
    }));
    await assertSucceeds(updateDoc(doc(as('alice'), 'games/POS4'),
        { variantId: 'duo', uids: ['alice', 'bob', 'alice', 'bob'] }));
  });
  it('ANGREB: værten må IKKE omrokere andres pladser i et spil i gang',
      async () => {
    await seed((db) => setDoc(doc(db, 'games/POS5'), duoLobby({
      status: 'playing',
    })));
    await assertFails(updateDoc(doc(as('alice'), 'games/POS5'),
        { uids: ['bob', 'alice', 'bob', 'alice'] }));
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
