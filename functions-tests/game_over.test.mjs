// Rene enhedstests for spil-slut-markeringen (functions/game_over.js).
// Kører UDEN emulator og uden at deploye: `node --test functions-tests/`.
//
// Baggrund: markeringen er hele grunden til at en spillers tal ikke længere
// afhænger af, om deres app tilfældigvis kiggede på skærmen, da partiet
// sluttede. Hver test er skrevet så en realistisk fejl gør den rød.

import {test} from "node:test";
import assert from "node:assert/strict";
import pkg from "../functions/game_over.js";

const {isGameOverTransition, staleTargets} = pkg;

test("kun selve OVERGANGEN til 'over' markerer", () => {
  assert.equal(isGameOverTransition({status: "playing"}, {status: "over"}), true);
  // Allerede slut: enhver senere skrivning på doc'et må IKKE markere igen
  // (ellers ville deltagerne blive markeret forfra i det uendelige).
  assert.equal(isGameOverTransition({status: "over"}, {status: "over"}), false);
  assert.equal(isGameOverTransition({status: "lobby"}, {status: "playing"}), false);
  assert.equal(isGameOverTransition({status: "playing"}, {status: "playing"}), false);
});

test("tåler manglende/tomme dokumenter", () => {
  assert.equal(isGameOverTransition(undefined, {status: "over"}), true);
  assert.equal(isGameOverTransition({}, {}), false);
  assert.equal(isGameOverTransition(null, null), false);
});

// Realistiske Firebase-uid'er (28 tegn) — testene skal ramme den samme
// formvalidering som produktionen, ikke en løsere legetøjsudgave.
const A = "AaBbCcDdEeFfGgHhIiJjKkLl0001";
const B = "AaBbCcDdEeFfGgHhIiJjKkLl0002";
const C = "AaBbCcDdEeFfGgHhIiJjKkLl0003";
const D = "AaBbCcDdEeFfGgHhIiJjKkLl0004";

test("markerer ALLE menneskelige deltagere — ikke kun den der trak sidst", () => {
  // Kernen i brugerens fund: makkeren manglede i toplisterne.
  assert.deepEqual(staleTargets({uids: [A, B, C, D]}), [A, B, C, D]);
});

test("AI-pladser og skæve felter springes over", () => {
  assert.deepEqual(staleTargets({uids: [A, null, C, null]}), [A, C]);
  assert.deepEqual(staleTargets({uids: [A, "", 42, {x: 1}]}), [A]);
});

test("samme spiller på to pladser markeres kun én gang", () => {
  assert.deepEqual(staleTargets({uids: [A, B, A, B]}), [A, B]);
});

test("sti-injektion og vanformede uid'er afvises (serveren omgår reglerne)", () => {
  // Efterprøvet i emulatoren: admin-SDK'et afviser IKKE ".." eller "a/b/c" —
  // uden formkravet ville serveren skrive i utilsigtede stier, og ét skævt
  // felt kunne vælte markeringen for de ægte deltagere.
  // MUTATION: fjern UID_FORM-tjekket → denne bliver rød.
  assert.deepEqual(staleTargets({uids: ["..", "a/b/c", A]}), [A]);
  assert.deepEqual(staleTargets({uids: [".", "kort", "æøå123456789012"]}), []);
});

test("fan-out har et loft: højst bordets fire pladser", () => {
  // En fabrikeret liste med hundredvis af uid'er må ikke give hundredvis af
  // skrivninger. MUTATION: fjern .slice(0, maxSeats) → rød.
  const many = Array.from({length: 800}, (_, i) =>
    `AaBbCcDdEeFfGgHhIiJjKkLl${String(i).padStart(4, "0")}`);
  assert.equal(staleTargets({uids: many}).length, 4);
});

test("intet uids-felt giver tom liste (ingen skrivninger)", () => {
  assert.deepEqual(staleTargets({}), []);
  assert.deepEqual(staleTargets(undefined), []);
  assert.deepEqual(staleTargets({uids: "ikke-en-liste"}), []);
});
