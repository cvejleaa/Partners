// Rene hjælpere til den sammenlagte onGameTurn-handler — udskilt fra
// index.js (samme mønster som game_over.js) så gren-logikken kan unit-testes
// med `node --test` UDEN emulator og uden at deploye noget. Modulet kalder
// ALDRIG firebase-admin direkte: selve Firestore/FCM-arbejdet (pushToUser,
// markStale) injiceres som funktioner udefra.
//
// Baggrund: onGameTurn og onGameOver var to separate Cloud Functions-
// triggers på SAMME dokument (games/{code}) — hver skrivning gav derfor to
// invocations. De er slået sammen til én handler (forbrugs-fund #37): "din
// tur"-push og stats-forældelse-markering ved spil-slut sker nu i samme
// invocation. De to beslutninger er gensidigt udelukkende på samme event
// (push kræver status==='playing', markering kræver en overgang TIL 'over')
// — men kører alligevel via allSettled, ikke sekventielt, så en fremtidig
// løsnet betingelse aldrig kan lade den ene fejle den anden (security-fund).

const {isGameOverTransition, staleTargets, UID_FORM} = require("./game_over");

/**
 * Skal der sendes en "din tur"-push, og til hvem? Kun et ægte turn-skift
 * (ændret currentPlayerIndex/hånd) i play-fasen af et spil i gang tæller —
 * ikke lobby/exchange/afsluttede spil, ikke en AI-plads.
 *
 * `state` (og dermed `cp`) skrives af KLIENTEN — reglerne validerer ikke
 * dens indhold. Uden UID_FORM-tjekket kunne et fabrikeret `cp` (fx
 * `"__proto__"`) få `uids[cp]` til at ramme en Array/Object-prototype-
 * egenskab i stedet for undefined (security-fund: samme klasse fejl som
 * `staleTargets`s UID_FORM-tjek i game_over.js beskytter imod — ÉN vagt,
 * genbrugt her i stedet for en ny, løsere kopi).
 * @param {object} before dokumentet før ændringen
 * @param {object} after dokumentet efter ændringen
 * @return {string|null} uid der skal have en "din tur"-push, ellers null
 */
function turnPushTarget(before, after) {
  if ((after || {}).status !== "playing") return null;
  const aState = (after || {}).state || {};
  const bState = (before || {}).state || {};
  if (aState.ph !== "play") return null;
  const sameTurn = aState.cp === bState.cp && aState.hn === bState.hn;
  if (sameTurn) return null;
  const cp = aState.cp;
  if (!Number.isInteger(cp) || cp < 0) return null;
  const uids = (after || {}).uids || [];
  const uid = uids[cp];
  return (typeof uid === "string" && UID_FORM.test(uid)) ? uid : null;
}

/**
 * Håndter ÉN skrivning til games/{code}: send evt. en "din tur"-push, og
 * markér evt. deltagernes statistik som forældet ved spil-slut.
 * @param {object} opts
 * @param {object} opts.before dokumentet før ændringen
 * @param {object} opts.after dokumentet efter ændringen
 * @param {string} opts.code spil-koden (event.params.code)
 * @param {function(string, object): Promise<void>} opts.pushToUser
 * @param {function(string[]): Promise<void>} opts.markStale
 * @return {Promise<void>}
 */
async function handleGameTurnUpdate({before, after, code, pushToUser, markStale}) {
  const turnUid = turnPushTarget(before, after);
  const staleUids = isGameOverTransition(before, after) ?
    staleTargets(after) : [];

  const tasks = [];
  if (turnUid) {
    // DATA-only: service-workeren viser notifikationen (én gang) og
    // håndterer klik → åbner selve spillet (/?game=<code>).
    tasks.push(pushToUser(turnUid, {
      data: {
        type: "turn",
        gameCode: code,
        title: "Partners — din tur",
        body: `Det er din tur i spil ${code}`,
      },
      webpush: {headers: {Urgency: "high", TTL: "300"}},
    }));
  }
  if (staleUids.length) {
    tasks.push(markStale(staleUids));
  }
  if (!tasks.length) return;
  const results = await Promise.allSettled(tasks);
  const rejected = results.find((r) => r.status === "rejected");
  if (rejected) throw rejected.reason;
}

module.exports = {turnPushTarget, handleGameTurnUpdate};
