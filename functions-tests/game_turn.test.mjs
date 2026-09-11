// Enhedstests for den sammenlagte onGameTurn-handler (tur-push +
// stats-forældelse ved spil-slut, forbrugs-fund #37). Kører UDEN emulator:
// `node --test functions-tests/`.
//
// Baggrund: onGameTurn og onGameOver var to separate Cloud Functions-
// triggers på SAMME dokument (games/{code}) — hver skrivning gav derfor TO
// invocations. De er slået sammen til én handler (functions/game_turn.js).
// Test Manager viste at selve fusionen var ubevist: en mutation af
// `isGameOverTransition`-tjekket (fx erstattet med `true`) ville sende
// stats-forældelse ved ENHVER skrivning til games/{code}, ikke kun ved
// spil-slut — og INGEN test fangede det, fordi game_over.test.mjs kun tester
// de rene game_over.js-hjælpere, aldrig den sammenlagte handler. Denne fil
// dækker netop det hul.

import {test} from "node:test";
import assert from "node:assert/strict";
import pkg from "../functions/game_turn.js";

const {turnPushTarget, handleGameTurnUpdate} = pkg;

// Realistiske Firebase-uid'er (28 tegn), som game_over.test.mjs.
const A = "AaBbCcDdEeFfGgHhIiJjKkLl0001";
const B = "AaBbCcDdEeFfGgHhIiJjKkLl0002";
const C = "AaBbCcDdEeFfGgHhIiJjKkLl0003";
const D = "AaBbCcDdEeFfGgHhIiJjKkLl0004";

test("turnPushTarget — ægte turn-skift i play-fasen giver den nye spillers uid", () => {
  const before = {status: "playing", state: {ph: "play", cp: 0, hn: 0}};
  const after = {status: "playing", state: {ph: "play", cp: 1, hn: 0}, uids: [A, B, C, D]};
  assert.equal(turnPushTarget(before, after), B);
});

test("turnPushTarget — HÅNDSTART: play begynder, og starteren er den SAMME " +
  "som sidste træks spiller → der skal stadig sendes push", () => {
  // FEJLEN (QC-fund), som denne test låser fast: startNewHand sætter fasen
  // til 'exchange' og tæller hn op, men rører aldrig cp — den peger derfor
  // stadig på den, der lavede sidste træk i forrige hånd. Når det fjerde
  // byttekort er afgivet, sættes ph='play' og cp=starterIndex, og hn er
  // UÆNDRET i dén skrivning. Var starteren den samme som sidste træks
  // spiller, var cp og hn ens, og den gamle regel kaldte det "ingen ændring".
  //
  // FØR rettelsen returnerede dette null. Med fire sæder skete det ca. hver
  // fjerde håndstart — og i et spil med fire MENNESKER findes der ingen
  // AI-overtagelse til at bryde ventetiden, så spillet kunne stå stille i
  // ubestemt tid.
  const before = {status: "playing", state: {ph: "exchange", cp: 2, hn: 5}};
  const after = {
    status: "playing",
    state: {ph: "play", cp: 2, hn: 5},
    uids: [A, B, C, D],
  };
  assert.equal(turnPushTarget(before, after), C);
});

test("turnPushTarget — håndstart hvor starteren er en ANDEN end sidste " +
  "træks spiller virkede allerede, og skal blive ved med det", () => {
  const before = {status: "playing", state: {ph: "exchange", cp: 2, hn: 5}};
  const after = {
    status: "playing",
    state: {ph: "play", cp: 0, hn: 5},
    uids: [A, B, C, D],
  };
  assert.equal(turnPushTarget(before, after), A);
});

test("turnPushTarget — selve BYTTE-fasen giver ingen push", () => {
  // Hver afgivelse af et byttekort skriver til dokumentet. Det er ingens tur
  // endnu, så vagten på ph==='play' EFTER skal holde dem alle ude — ellers
  // ville rettelsen ovenfor koste fire falske pushes pr. hånd.
  const before = {status: "playing", state: {ph: "play", cp: 2, hn: 4}};
  const after = {
    status: "playing",
    state: {ph: "exchange", cp: 2, hn: 5},
    uids: [A, B, C, D],
  };
  assert.equal(turnPushTarget(before, after), null);
});

test("turnPushTarget — håndstart til en AI-plads giver ingen push", () => {
  // Samme vagt som ved et almindeligt turn-skift: en tom/AI-plads har ingen
  // uid at sende til.
  const before = {status: "playing", state: {ph: "exchange", cp: 1, hn: 2}};
  const after = {
    status: "playing",
    state: {ph: "play", cp: 1, hn: 2},
    uids: [A, null, C, D],
  };
  assert.equal(turnPushTarget(before, after), null);
});

test("turnPushTarget — samme tur (uændret cp/hn) giver ingen push", () => {
  // MUTATION: fjern sameTurn-tjekket → hver eneste skrivning (fx en
  // heartbeat-afledt re-render, eller markSeen) ville sende en falsk
  // "din tur"-push.
  const before = {status: "playing", state: {ph: "play", cp: 1, hn: 0}};
  const after = {status: "playing", state: {ph: "play", cp: 1, hn: 0}, uids: [A, B, C, D]};
  assert.equal(turnPushTarget(before, after), null);
});

test("turnPushTarget — uden for play-fasen (fx exchange) giver ingen push", () => {
  const before = {status: "playing", state: {ph: "exchange", cp: 0, hn: 0}};
  const after = {status: "playing", state: {ph: "exchange", cp: 1, hn: 0}, uids: [A, B, C, D]};
  assert.equal(turnPushTarget(before, after), null);
});

test("turnPushTarget — lobby/afsluttet spil giver ingen push", () => {
  const lobbyAfter = {status: "lobby", state: {ph: "play", cp: 1, hn: 0}, uids: [A, B, C, D]};
  assert.equal(turnPushTarget({status: "lobby"}, lobbyAfter), null);
  const overAfter = {status: "over", state: {ph: "play", cp: 1, hn: 0}, uids: [A, B, C, D]};
  assert.equal(turnPushTarget({status: "playing"}, overAfter), null);
});

test("turnPushTarget — AI-plads (intet uid i sædet) giver ingen push", () => {
  const before = {status: "playing", state: {ph: "play", cp: 0, hn: 0}};
  const after = {status: "playing", state: {ph: "play", cp: 1, hn: 0}, uids: [A, null, C, D]};
  assert.equal(turnPushTarget(before, after), null);
});

test("turnPushTarget — ANGREB: fabrikeret cp (prototype-nøgle) rammer ikke Array/Object-prototypen", () => {
  // Security-fund: `state` skrives af klienten, reglerne validerer den ikke.
  // Uden Number.isInteger-tjekket ville `uids['__proto__']` returnere
  // Array.prototype (et truthy objekt) i stedet for undefined.
  // MUTATION: fjern `!Number.isInteger(cp) || cp < 0`-tjekket → rød.
  const before = {status: "playing", state: {ph: "play", cp: 0, hn: 0}};
  const after = {
    status: "playing",
    state: {ph: "play", cp: "__proto__", hn: 1},
    uids: [A, B, C, D],
  };
  assert.equal(turnPushTarget(before, after), null);
});

test("turnPushTarget — ANGREB: et sti-agtigt uid i sædet returneres ikke", () => {
  // Samme klasse fejl som staleTargets' UID_FORM-tjek beskytter imod
  // (game_over.test.mjs) — her genbrugt, ikke duplikeret løsere.
  // MUTATION: fjern UID_FORM-tjekket → denne bliver rød.
  const before = {status: "playing", state: {ph: "play", cp: 0, hn: 0}};
  const after = {
    status: "playing",
    state: {ph: "play", cp: 1, hn: 1},
    uids: [A, "../../config/cardRules", C, D],
  };
  assert.equal(turnPushTarget(before, after), null);
});

test("handleGameTurnUpdate — sender push VED turn-skift, markerer IKKE stats", async () => {
  const pushed = [];
  const staled = [];
  const before = {status: "playing", state: {ph: "play", cp: 0, hn: 0}};
  const after = {status: "playing", state: {ph: "play", cp: 1, hn: 0}, uids: [A, B, C, D]};
  await handleGameTurnUpdate({
    before, after, code: "XYZ",
    pushToUser: async (uid, msg) => pushed.push([uid, msg]),
    markStale: async (uids) => staled.push(uids),
  });
  assert.equal(pushed.length, 1);
  assert.equal(pushed[0][0], B);
  assert.equal(pushed[0][1].data.gameCode, "XYZ");
  assert.equal(pushed[0][1].data.type, "turn");
  assert.equal(staled.length, 0);
});

test("handleGameTurnUpdate — markerer stats VED spil-slut, sender IKKE en tur-push", async () => {
  const pushed = [];
  const staled = [];
  const before = {status: "playing"};
  const after = {status: "over", uids: [A, B, C, D]};
  await handleGameTurnUpdate({
    before, after, code: "XYZ",
    pushToUser: async (uid, msg) => pushed.push([uid, msg]),
    markStale: async (uids) => staled.push(uids),
  });
  assert.equal(pushed.length, 0);
  assert.deepEqual(staled, [[A, B, C, D]]);
});

test("handleGameTurnUpdate — INGEN markering uden en ægte over-overgang (allerede slut før og efter)", async () => {
  // Kernen i Test Managers fund: uden isGameOverTransition-tjekket ville
  // ENHVER senere skrivning på et afsluttet spil markere deltagerne igen.
  // MUTATION: erstat `isGameOverTransition(before, after)` med `true` i
  // functions/game_turn.js → denne test bliver rød (staled ville ikke
  // længere være tom).
  const staled = [];
  const before = {status: "over"};
  const after = {status: "over", uids: [A, B, C, D]};
  await handleGameTurnUpdate({
    before, after, code: "XYZ",
    pushToUser: async () => { throw new Error("skal ikke kaldes"); },
    markStale: async (uids) => staled.push(uids),
  });
  assert.deepEqual(staled, []);
});

test("handleGameTurnUpdate — hverken push eller markering ved en uvedkommende skrivning (fx lobby-opsætning)", async () => {
  const pushed = [];
  const staled = [];
  await handleGameTurnUpdate({
    before: {status: "lobby"},
    after: {status: "lobby", ready: {[A]: true}},
    code: "XYZ",
    pushToUser: async (uid, msg) => pushed.push([uid, msg]),
    markStale: async (uids) => staled.push(uids),
  });
  assert.equal(pushed.length, 0);
  assert.equal(staled.length, 0);
});
