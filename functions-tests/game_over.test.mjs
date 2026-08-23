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

test("markerer ALLE menneskelige deltagere — ikke kun den der trak sidst", () => {
  // Kernen i brugerens fund: makkeren manglede i toplisterne.
  const uids = staleTargets({uids: ["a", "b", "c", "d"]});
  assert.deepEqual(uids, ["a", "b", "c", "d"]);
});

test("AI-pladser og skæve felter springes over", () => {
  assert.deepEqual(staleTargets({uids: ["a", null, "c", null]}), ["a", "c"]);
  assert.deepEqual(staleTargets({uids: ["a", "", 42, {x: 1}]}), ["a"]);
});

test("samme spiller på to pladser markeres kun én gang", () => {
  assert.deepEqual(staleTargets({uids: ["a", "b", "a", "b"]}), ["a", "b"]);
});

test("intet uids-felt giver tom liste (ingen skrivninger)", () => {
  assert.deepEqual(staleTargets({}), []);
  assert.deepEqual(staleTargets(undefined), []);
  assert.deepEqual(staleTargets({uids: "ikke-en-liste"}), []);
});
