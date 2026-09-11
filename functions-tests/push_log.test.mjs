// Hvad log-linjen indeholder — og fremfor alt hvad den ALDRIG indeholder.
//
// GDPR-gennemgangen satte graenserne: intet uid, intet gameCode, ingen
// token-straenge, ingen err.message. De tre sidste er lette at bryde ved en
// senere "lige for at debugge"-tilfoejelse, saa de er testet som NEGATIVE
// paastande paa hele den serialiserede linje — ikke felt for felt.

import {test} from "node:test";
import assert from "node:assert/strict";
import pkg from "../functions/push_log.js";

const {pushLogFields, skippedLogFields, severityFor} = pkg;

const TOKEN = "fVx9k:APA91bHxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
const UID = "AaBbCcDdEeFfGgHhIiJjKkLl0001";

test("alt lykkedes → delivered:true, ingen errors-felt", () => {
  const f = pushLogFields({type: "turn", responses: [{success: true}, {success: true}]});
  assert.equal(f.tokens, 2);
  assert.equal(f.ok, 2);
  assert.equal(f.failed, 0);
  assert.equal(f.delivered, true);
  assert.equal(f.errors, undefined);
  assert.equal(severityFor(f), "info");
});

test("delvis fejl tælles pr. FEJLKODE, ikke som ét tal", () => {
  // Uden kode-opdelingen kan man ikke se forskel paa "mange doede tokens"
  // (normalt) og "kvoten er opbrugt" (en alarm).
  const f = pushLogFields({type: "turn", responses: [
    {success: true},
    {success: false, error: {code: "messaging/registration-token-not-registered"}},
    {success: false, error: {code: "messaging/invalid-argument"}},
  ]});
  assert.equal(f.ok, 1);
  assert.equal(f.failed, 2);
  assert.equal(f.stale, 1);
  assert.deepEqual(f.errors, {
    "messaging/registration-token-not-registered": 1,
    "messaging/invalid-argument": 1,
  });
  assert.equal(f.delivered, true, "een kom frem, saa det er ikke en alarm");
  assert.equal(severityFor(f), "info");
});

test("INTET kom frem, selvom der VAR tokens → error, ikke info", () => {
  // Den handlingskraevende sag. En samlet fejlrate drukner den enkelte
  // bruger, der intet faar.
  const f = pushLogFields({type: "turn", responses: [
    {success: false, error: {code: "messaging/invalid-argument"}},
  ]});
  assert.equal(f.delivered, false);
  assert.equal(severityFor(f), "error");
});

test("ingen tokens er IKKE en fejl — men skal stadig ses", () => {
  // Svaret paa "kom der ingen push fordi der ingen ture var, eller fordi
  // ingen har slaaet det til?".
  const f = skippedLogFields("invite");
  assert.equal(f.skipped, "no-tokens");
  assert.equal(f.tokens, 0);
  assert.equal(f.type, "invite", "uden type kan man ikke se HVAD der udeblev");
  assert.equal(severityFor(f), "info");
});

test("present logges kun naar vi ved det", () => {
  const uden = pushLogFields({type: "invite", responses: [{success: true}]});
  assert.equal("present" in uden, false);
  const med = pushLogFields({type: "turn", responses: [{success: true}], present: true});
  assert.equal(med.present, true);
  const fravaerende = pushLogFields({type: "turn", responses: [{success: true}], present: false});
  assert.equal(fravaerende.present, false,
      "false skal med — det er hele pointen med at maale overfloedige pushes");
});

test("GDPR: linjen indeholder ALDRIG uid, gameCode, token eller fejlbesked", () => {
  // Negativ paastand paa HELE den serialiserede linje: en fremtidig
  // tilfoejelse af et af felterne bliver roed, uanset hvad den hedder.
  const f = pushLogFields({type: "turn", responses: [
    {success: false, error: {
      code: "messaging/invalid-registration-token",
      message: `The registration token ${TOKEN} is not valid`,
    }},
  ], present: false});
  const s = JSON.stringify(f);
  assert.equal(s.includes(UID), false, "uid maa aldrig i loggen");
  assert.equal(s.includes(TOKEN), false, "token er et enheds-credential");
  assert.equal(s.includes("registration token"), false,
      "err.message kan indeholde selve tokenet — kun err.code maa med");
  assert.equal(s.includes("gameCode"), false,
      "gameCode kan slaas op i games og give navne + uid'er");
  // Og det POSITIVE: fejlkoden ER med, ellers kan man ikke stille en alarm op.
  assert.equal(f.errors["messaging/invalid-registration-token"], 1);
});
