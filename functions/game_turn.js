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
// invocation, men er stadig to uafhængige beslutninger på samme event.

const {isGameOverTransition, staleTargets} = require("./game_over");

/**
 * Skal der sendes en "din tur"-push, og til hvem? Kun et ægte turn-skift
 * (ændret currentPlayerIndex/hånd) i play-fasen af et spil i gang tæller —
 * ikke lobby/exchange/afsluttede spil, og ikke en AI-plads.
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
  const uids = (after || {}).uids || [];
  return uids[aState.cp] || null; // null/undefined uid → AI-plads
}

/**
 * Håndter ÉN skrivning til games/{code}: send evt. en "din tur"-push, og
 * markér evt. deltagernes statistik som forældet ved spil-slut. De to
 * beslutninger er uafhængige af hinanden — samme event kan i princippet slå
 * begge eller ingen, se turnPushTarget/isGameOverTransition.
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
  if (turnUid) {
    // DATA-only: service-workeren viser notifikationen (én gang) og
    // håndterer klik → åbner selve spillet (/?game=<code>).
    await pushToUser(turnUid, {
      data: {
        type: "turn",
        gameCode: code,
        title: "Partners — din tur",
        body: `Det er din tur i spil ${code}`,
      },
      webpush: {headers: {Urgency: "high", TTL: "300"}},
    });
  }

  if (isGameOverTransition(before, after)) {
    const staleUids = staleTargets(after);
    if (staleUids.length) {
      await markStale(staleUids);
    }
  }
}

module.exports = {turnPushTarget, handleGameTurnUpdate};
