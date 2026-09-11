// Svartids-udregningen bag "virkede notifikationen?".
//
// Et gab mellem to log-poster er kun en svartid, hvis man kasserer de gab,
// der IKKE er det. Hver kasse-regel her er et fund fra gennemgangen, ikke et
// gaet — og hver af dem er testet, fordi en manglende regel ikke goer
// maalingen tom, men SKAEV, hvilket er vaerre.

import {test} from "node:test";
import assert from "node:assert/strict";
import pkg from "../functions/push_quality.js";

const {responseGaps, summarize, bucketOf, headlineCounts, NEVER_ANSWERED} =
  pkg;

const UIDS = ["u0", "u1", "u2", "u3"];
const T = 1_700_000_000_000;
const e = (player, hn, t, extra = {}) =>
  ({player, type: "move", hn, t, ...extra});

test("almindeligt turskifte giver svartiden", () => {
  const {gaps} = responseGaps([e(0, 1, T), e(1, 1, T + 90e3)], UIDS);
  assert.deepEqual(gaps, [{seat: 1, ms: 90e3}]);
});

test("HÅNDSKIFTE kasseres — der blev ikke sendt push i den overgang", () => {
  // Gabet rummer kortgivning + fire spilleres byttevalg. Uden hn kan det
  // ikke skelnes, og det ville traekke p90 systematisk op.
  const {gaps, discarded} = responseGaps([e(2, 1, T), e(0, 2, T + 4 * 3600e3)], UIDS);
  assert.equal(gaps.length, 0);
  assert.equal(discarded.handChange, 1);
});

test("samme spiller to gange i træk kasseres — turen skiftede ikke", () => {
  const {gaps, discarded} = responseGaps([e(1, 1, T), e(1, 1, T + 5e3)], UIDS);
  assert.equal(gaps.length, 0);
  assert.equal(discarded.sameSeat, 1);
});

test("en AI-plads kasseres — den får aldrig en besked", () => {
  const {gaps, discarded} = responseGaps(
      [e(0, 1, T), e(1, 1, T + 10e3)], ["u0", null, "u2", "u3"]);
  assert.equal(gaps.length, 0);
  assert.equal(discarded.aiSeat, 1);
});

test("AI-OVERTAGELSE kasseres IKKE — den tælles som 'svarede aldrig'", () => {
  // Det er PRÆCIS de tilfælde, hvor push'en ikke virkede. Kastes de væk,
  // fjerner man kun fejlene og gør medianen kunstigt pæn.
  const {gaps} = responseGaps(
      [e(0, 1, T), e(1, 1, T + 40e3, {ai: true})], UIDS);
  assert.deepEqual(gaps, [{seat: 1, ms: NEVER_ANSWERED}]);
  assert.equal(bucketOf(NEVER_ANSWERED), "aldrig (AI overtog)");
});

test("negativt gab kasseres og TÆLLES — ur-skævhed er et datakvalitets-tal", () => {
  // Hvert gab er differencen mellem to forskellige enheders ure, så skævhed
  // rammer hver måling. Kasseres kun de negative, skubbes medianen opad.
  const {gaps, discarded} = responseGaps([e(0, 1, T), e(1, 1, T - 5e3)], UIDS);
  assert.equal(gaps.length, 0);
  assert.equal(discarded.negative, 1);
});

test("post uden tidsstempel kasseres", () => {
  const {gaps, discarded} = responseGaps(
      [e(0, 1, T), {player: 1, type: "move", hn: 1}], UIDS);
  assert.equal(gaps.length, 0);
  assert.equal(discarded.noTime, 1);
});

test("exchange-poster kasseres eksplicit, ikke ved et tilfælde", () => {
  // exchangeLogEntry er ubrugt online i dag. Begynder nogen at logge byttet,
  // bryder udregningen tavst uden denne vagt.
  const {gaps, discarded} = responseGaps(
      [e(0, 1, T), {player: 1, type: "exchange", hn: 1, t: T + 1e3}], UIDS);
  assert.equal(gaps.length, 0);
  assert.equal(discarded.exchange, 1);
});

test("GDPR: for få observationer → INGEN median, kun en forklaring", () => {
  // I en kreds under ti personer ville "medianen for dem uden push" i
  // praksis være én persons svartid.
  const few = [{seat: 1, ms: 1000}, {seat: 2, ms: 2000}];
  const s = summarize(few, {minN: 30, minPlayers: 3});
  assert.equal(s.median, null);
  assert.equal(s.p90, null);
  assert.match(s.suppressed, /for faa observationer/);
  assert.equal(s.n, 2, "antallet maa gerne staa — det er ikke identificerende");
});

test("GDPR: nok observationer men for FÅ spillere → stadig ingen median", () => {
  // 40 svar fra to personer er to personers adfaerd, ikke en gruppe.
  const many = Array.from({length: 40}, (_, i) => ({seat: i % 2, ms: i * 1000}));
  const s = summarize(many, {minN: 30, minPlayers: 3});
  assert.equal(s.median, null);
  assert.match(s.suppressed, /spillere/);
});

test("nok data → median og p90, og intervallerne summer til n", () => {
  const gaps = Array.from({length: 40}, (_, i) => ({seat: i % 4, ms: i * 1000}));
  const s = summarize(gaps, {minN: 30, minPlayers: 3});
  assert.equal(s.n, 40);
  assert.equal(s.players, 4);
  assert.equal(s.suppressed, undefined);
  assert.ok(s.median > 0);
  assert.ok(s.p90 >= s.median);
  const sum = Object.values(s.buckets).reduce((a, b) => a + b, 0);
  assert.equal(sum, 40, "hver observation skal ligge i praecis eet interval");
});

test("'svarede aldrig' tælles for sig og trækker ikke medianen ned", () => {
  const gaps = [
    ...Array.from({length: 30}, (_, i) => ({seat: i % 4, ms: 60e3})),
    {seat: 0, ms: NEVER_ANSWERED},
  ];
  const s = summarize(gaps, {minN: 30, minPlayers: 3});
  assert.equal(s.never, 1);
  assert.equal(s.median, 60e3, "de ubesvarede maa ikke indgaa i medianen");
  assert.equal(s.buckets["aldrig (AI overtog)"], 1);
});

// ---- Optællingerne, ikke kun medianen ----
// Jeg havde først kun spærret median/p90. GDPR-gennemgangen pegede på, at
// netop optællingerne er de mest afslørende: i en kreds på seks er "1 kan
// ikke nås" en udpegning af én bestemt person.

test("GDPR: for lille kreds → optællingerne vises IKKE", () => {
  const h = headlineCounts({active: 4, chose: 3, reachable: 2}, 5);
  assert.match(h.suppressed, /for faa aktive spillere/);
  assert.equal(h.chose, undefined);
  assert.equal(h.reachable, undefined);
  assert.equal(h.unreachable, undefined,
      "deltaet er det mest afsloerende af dem alle");
  assert.equal(h.active, 4, "selve antallet aktive er ikke identificerende");
});

test("stor nok kreds → tallene vises, og deltaet udregnes", () => {
  const h = headlineCounts({active: 12, chose: 9, reachable: 7}, 5);
  assert.equal(h.suppressed, undefined);
  assert.equal(h.unreachable, 2);
});

test("deltaet kan ikke blive negativt", () => {
  // reachable > chose kan ske for en spiller med en gammel token, der aldrig
  // har sat pushOn (feltet er nyt). Det maa ikke give "-1 kan ikke naas".
  const h = headlineCounts({active: 12, chose: 2, reachable: 5}, 5);
  assert.equal(h.unreachable, 0);
});
