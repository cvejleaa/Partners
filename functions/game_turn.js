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

/// Hvor frisk et presence-stempel skal vaere, foer vi regner modtageren for
/// at sidde og kigge. Klienten stempler hvert 12. sekund (kPresenceInterval),
/// og 35 s er samme graense som AI-overtagelsen bruger til "vaek" — saa de to
/// begreber ikke kan drive fra hinanden.
const PRESENT_WINDOW_MS = 35000;

/**
 * Skal der sendes en "din tur"-push, og til hvem? Kun et ægte turn-skift
 * i play-fasen af et spil i gang tæller — ikke lobby/exchange/afsluttede
 * spil, ikke en AI-plads.
 *
 * "Ægte turn-skift" er TO ting, ikke én:
 *  a) play-fasen BEGYNDER (bytte er slut, turen gives til starterIndex), og
 *  b) inden i play-fasen skifter cp/hn.
 *
 * (a) er ikke pynt — uden den udeblev beskeden ved hver fjerde håndstart.
 * `startNewHand` sætter fasen til 'exchange' og tæller `hn` op, men rører
 * ALDRIG `currentPlayerIndex`; den peger derfor stadig på den, der lavede
 * sidste træk i forrige hånd. Når det fjerde byttekort er afgivet, sættes
 * fasen til 'play' og turen til `starterIndex` — i DEN skrivning er `hn`
 * uændret. Var starteren tilfældigvis den samme som sidste træks spiller,
 * så cp og hn ens, og den gamle sameTurn-regel kaldte det "ingen ændring".
 *
 * Konsekvensen var værre end en manglende besked: AI-overtagelsen efter
 * kAiTakeoverTimeout gælder KUN spil med mindst én computer-plads, så i et
 * spil med fire mennesker ventede man på en besked, der aldrig kom, uden
 * nogen timeout til at bryde det (QC-fund).
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
  // Begyndte play-fasen med DENNE skrivning, er turen pr. definition ny —
  // uanset hvad cp/hn stod på før. Genkendes på positiv tilstedeværelse af
  // 'play' EFTER og fravær FØR, ikke på at noget bestemt ændrede sig.
  const playJustStarted = bState.ph !== "play";
  const sameTurn = !playJustStarted &&
    aState.cp === bState.cp && aState.hn === bState.hn;
  if (sameTurn) return null;
  const cp = aState.cp;
  if (!Number.isInteger(cp) || cp < 0) return null;
  const uids = (after || {}).uids || [];
  const uid = uids[cp];
  return (typeof uid === "string" && UID_FORM.test(uid)) ? uid : null;
}

/**
 * Hvem skal have en "vælg dit byttekort"-push? Når en ny hånd begynder
 * (fasen skifter TIL 'exchange', eller hånd-nummeret skifter i den), skal
 * hver menneskelig spiller, der har kort på hånden og endnu ikke har afgivet
 * sit byttekort, vælge et — og uden en besked stod et spil mellem to
 * mennesker stille efter hver hånd, til nogen tilfældigvis åbnede appen (fund
 * fra spil-rådgiveren på Duo online; gælder alle varianter).
 *
 * "Har kort på hånden" (state.pl[i].hd) genkender pladserne med en hånd
 * POSITIVT — Duos spejl-pladser har ingen kort og samme uid, så modtageren
 * nævnes én gang. AI-pladser har intet uid. Samme UID_FORM-vagt som
 * turnPushTarget: state skrives af klienten.
 * @param {object} before dokumentet før ændringen
 * @param {object} after dokumentet efter ændringen
 * @return {string[]} uids der skal have en byttefase-push (unikke)
 */
function exchangePushTargets(before, after) {
  if ((after || {}).status !== "playing") return [];
  const aState = (after || {}).state || {};
  const bState = (before || {}).state || {};
  if (aState.ph !== "exchange") return [];
  const began = bState.ph !== "exchange" || aState.hn !== bState.hn;
  if (!began) return [];
  const uids = Array.isArray((after || {}).uids) ? after.uids : [];
  const pl = Array.isArray(aState.pl) ? aState.pl : [];
  const eb = (aState.eb && typeof aState.eb === "object") ? aState.eb : {};
  const out = [];
  const n = Math.min(uids.length, pl.length, 4);
  for (let i = 0; i < n; i++) {
    const hand = (pl[i] || {}).hd;
    if (!Array.isArray(hand) || hand.length === 0) continue;
    if (Object.prototype.hasOwnProperty.call(eb, String(i))) continue;
    const uid = uids[i];
    if (typeof uid === "string" && UID_FORM.test(uid) && !out.includes(uid)) {
      out.push(uid);
    }
  }
  return out;
}

/**
 * Håndter ÉN skrivning til games/{code}: send evt. en "din tur"-push, og
 * markér evt. deltagernes statistik som forældet ved spil-slut.
 * @param {object} opts
 * @param {object} opts.before dokumentet før ændringen
 * @param {object} opts.after dokumentet efter ændringen
 * @param {string} opts.code spil-koden (event.params.code)
 * @param {function(string, object, object=): Promise<void>} opts.pushToUser
 * @param {function(string[]): Promise<void>} opts.markStale
 * @param {function(string, string): Promise<number|null>} [opts.presenceAt]
 *   sidste presence-stempel (ms) for en uid i et spil, eller null
 * @param {number} [opts.now] "nu" i ms — gives af kalderen, saa tests ikke
 *   afhaenger af uret
 * @return {Promise<void>}
 */
async function handleGameTurnUpdate({
  before, after, code, pushToUser, markStale, presenceAt = null, now = null,
}) {
  const turnUid = turnPushTarget(before, after);
  const exchangeUids = exchangePushTargets(before, after);
  const staleUids = isGameOverTransition(before, after) ?
    staleTargets(after) : [];

  // Sad modtageren og kiggede? Kan KUN afgoeres nu: presence-stemplet
  // overskrives ved hvert heartbeat, saa der er ingen historik at regne
  // baglaens fra. Svarer paa "sender vi til nogen, der allerede sidder der" —
  // og kan senere begrunde at springe push'en over. Koster eet ekstra
  // dokument-read pr. tur-push.
  //
  // Maalingen maa ALDRIG kunne forhindre selve push'en: fejler opslaget,
  // logger vi bare "ved ikke" (null).
  let present = null;
  if (turnUid && presenceAt) {
    try {
      const at = await presenceAt(code, turnUid);
      const t = now === null ? Date.now() : now;
      present = at === null || at === undefined ?
        false : (t - at) < PRESENT_WINDOW_MS;
    } catch (e) {
      present = null;
    }
  }

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
    }, {present}));
  }
  // Byttefase-push. Modsat tur-push'en springes den OVER for den, der sidder
  // i spillet lige nu: den går til flere på én gang, og den, der lavede
  // håndens sidste træk (og dermed udløste den), sidder næsten altid der.
  // Fejler presence-opslaget, sendes den (hellere én for meget end et spil,
  // der står stille).
  for (const uid of exchangeUids) {
    tasks.push((async () => {
      let present = null;
      if (presenceAt) {
        try {
          const at = await presenceAt(code, uid);
          const t = now === null ? Date.now() : now;
          present = at === null || at === undefined ?
            false : (t - at) < PRESENT_WINDOW_MS;
        } catch (e) {
          present = null;
        }
      }
      if (present === true) return;
      await pushToUser(uid, {
        data: {
          type: "exchange",
          gameCode: code,
          title: "Partners — vælg dit byttekort",
          body: `Ny hånd i spil ${code} — vælg dit byttekort`,
        },
        webpush: {headers: {Urgency: "high", TTL: "300"}},
      }, {present});
    })());
  }
  if (staleUids.length) {
    tasks.push(markStale(staleUids));
  }
  if (!tasks.length) return;
  const results = await Promise.allSettled(tasks);
  const rejected = results.find((r) => r.status === "rejected");
  if (rejected) throw rejected.reason;
}

module.exports = {
  turnPushTarget, exchangePushTargets, handleGameTurnUpdate, PRESENT_WINDOW_MS,
};
