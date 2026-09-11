// Hvad vi logger om en push — og hvad vi ALDRIG logger.
//
// Baggrund: pushToUser hentede allerede udfaldet fra FCM (res.responses), men
// brugte det udelukkende til at rydde doede tokens op. successCount/
// failureCount blev aldrig logget, saa en push der fejlede af enhver anden
// grund forsvandt tavst. Det har bidt os foer: kommentaren ved
// `memory: "256MiB"` i index.js fortaeller, at 128 MiB fik funktionen til at
// crashe, saa "push-notifikationer udeblev (selvom deployet lykkedes)".
//
// GDPR-graenser, besluttet af data/GDPR-gennemgangen og efterproevet mod
// firestore.rules — de staar HER, samlet, saa en fremtidig "lige for at
// debugge"-tilfoejelse skal igennem dem:
//
//  - INTET uid. Cloud Logging kan ikke slette EEN persons poster (kun hele
//    boetten eller vente paa udloebet), saa et uid i loggen ville goere en
//    fremtidig anmodning om kontosletning umulig at honorere.
//  - INTET gameCode. Det er ikke teoretisk sammenkaedeligt: firestore.rules
//    giver enhver indlogget laeseadgang til hele games-samlingen, saa et
//    opslag paa koden giver navne og uid'er. "gameCode + tokens:3 + failed:1"
//    ville reelt vaere "denne navngivne person har tre enheder".
//  - INGEN token-straenge. En FCM-registreringstoken er et enheds-credential.
//  - INGEN err.message — kun err.code. FCM's fejltekster kan indeholde selve
//    tokenet.
//
// Prisen for de graenser er, at loggen svarer paa RATER, ikke paa enkeltsager.
// Det er et bevidst valg: "jeg fik ingen besked i spil ABC" kan den ikke
// besvare.

/** Fejlkoder vi rydder op paa — en doed token, ikke en fejl i vores kode. */
const STALE_CODES = [
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
];

/**
 * Byg felterne til EEN log-linje ud fra FCM's svar.
 *
 * Ren funktion med vilje: den kan testes uden emulator og uden firebase-admin,
 * og GDPR-graenserne kan mutationstestes.
 *
 * @param {object} opts
 * @param {string} opts.type "turn" | "invite"
 * @param {Array<object>} opts.responses res.responses fra sendEachForMulticast
 * @param {boolean|null} [opts.present] sad modtageren og kiggede? (kun turn)
 * @return {object} felter til logger.info/error
 */
function pushLogFields({type, responses, present = null}) {
  const tokens = responses.length;
  let ok = 0;
  const errors = {};
  let stale = 0;
  for (const r of responses) {
    if (r.success) {
      ok += 1;
      continue;
    }
    const code = (r.error || {}).code || "unknown";
    errors[code] = (errors[code] || 0) + 1;
    if (STALE_CODES.includes(code)) stale += 1;
  }
  const fields = {
    event: "push",
    type,
    tokens,
    ok,
    failed: tokens - ok,
    stale,
    // Den HANDLINGSKRAEVENDE sag, skilt ud: en samlet fejlrate drukner den
    // enkelte bruger, der intet faar. Den logges paa ERROR, se severityFor.
    delivered: ok > 0,
  };
  if (Object.keys(errors).length) fields.errors = errors;
  if (present !== null) fields.present = present;
  return fields;
}

/** Linjen for den gren, der i dag returnerer helt tavst. */
function skippedLogFields(type) {
  // Svaret paa "kom der ingen push fordi der ingen ture var, eller fordi
  // ingen har slaaet det til?". `type` skal med: ellers kan man ikke se, at
  // det er invitationerne der ikke naar frem, mens tur-push flyder.
  return {event: "push", type, tokens: 0, skipped: "no-tokens"};
}

/** "error" naar der VAR tokens og intet kom frem; ellers "info". */
function severityFor(fields) {
  return (fields.tokens > 0 && fields.ok === 0) ? "error" : "info";
}

module.exports = {pushLogFields, skippedLogFields, severityFor, STALE_CODES};
