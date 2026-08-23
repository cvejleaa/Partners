// Rene hjælpere til spil-slut-markeringen — udskilt fra index.js så de kan
// unit-testes med `node --test` UDEN emulator og uden at deploye noget.
//
// Baggrund: en brugers statistik skrives kun af brugerens EGEN klient (kun
// ejeren må skrive sit stats-dokument). Lå makkerens app i baggrunden da
// partiet sluttede, blev deres tal aldrig opdateret — derfor manglede
// spillere i variant-toplisterne. Serveren markerer nu alle deltagere som
// forældede, og hver klient genberegner sine egne tal ved næste app-start.

/**
 * Er dette netop overgangen til "spillet er slut"?
 * Kun overgangen tæller: ellers ville enhver senere skrivning på et
 * afsluttet spil markere deltagerne forfra.
 * @param {object} before dokumentet før ændringen
 * @param {object} after dokumentet efter ændringen
 * @return {boolean} true når status netop skiftede til 'over'
 */
function isGameOverTransition(before, after) {
  const b = (before || {}).status;
  const a = (after || {}).status;
  return a === "over" && b !== "over";
}

/**
 * Deltagere hvis statistik skal markeres forældet: rigtige uids, uden
 * dubletter og uden AI-pladser (null/tomme felter).
 * @param {object} game spil-dokumentet
 * @return {string[]} unikke uids
 */
const UID_FORM = /^[A-Za-z0-9_-]{6,128}$/;

/**
 * Deltagere hvis statistik skal markeres forældet: rigtige uids, uden
 * dubletter og uden AI-pladser (null/tomme felter).
 *
 * Uid'et valideres på FORM — serveren omgår Firestore-reglerne, så den må
 * aldrig være mere gavmild end klienten. Uden formkravet kunne fx ".." eller
 * "a/b/c" skabe dokumenter i utilsigtede stier (efterprøvet i emulatoren), og
 * ét skævt felt kunne vælte hele markeringen for de ægte deltagere.
 * Antallet skæres af ved bordets størrelse, så en fabrikeret liste ikke kan
 * udløse tusindvis af skrivninger.
 * @param {object} game spil-dokumentet
 * @param {number} maxSeats loft på antal markerede (default 4 = bordet)
 * @return {string[]} unikke, velformede uids
 */
function staleTargets(game, maxSeats = 4) {
  const uids = Array.isArray((game || {}).uids) ? game.uids : [];
  const real = uids.filter((u) => typeof u === "string" && UID_FORM.test(u));
  return Array.from(new Set(real)).slice(0, maxSeats);
}

module.exports = {isGameOverTransition, staleTargets};
