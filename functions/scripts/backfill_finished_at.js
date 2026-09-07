// ENGANGS-BACKFILL — IKKE en deployet Cloud Function, køres manuelt af et
// menneske med produktions-adgang.
//
// Baggrund (Quality Control-fund ved commit cb1286f): `finishedAt` (og
// `createdAt`) blev først indført i commit 2cf06df (2026-08-21). "Mine
// spil"s nye 14-dages-arkivforespørgsel (lib/online/online_service.dart,
// _myGamesBounded, forbrugs-fund #18/#52) filtrerer på
// `.where('finishedAt', isGreaterThanOrEqualTo: cutoff)` — et Firestore
// range-filter matcher KUN dokumenter hvor feltet findes. Ethvert spil med
// `status: 'over'` fra FØR 2026-08-21, der mangler `finishedAt`, bliver
// derfor USYNLIGT for forespørgslen: hverken "aktiv" (status er 'over',
// ikke 'lobby'/'playing') eller "nyligt afsluttet" (mangler feltet
// range-filteret kræver) — det forsvinder stille fra brugerens "Mine
// spil"-liste, permanent, uden fejl nogen steder.
//
// Dette script er IKKE kørt af Claude — der er ingen produktions-Firebase-
// adgang i det miljø ændringen blev lavet i. Et menneske med adgang til
// projektets service-account skal køre det (eller vurdere om risikoen —
// formentlig et lille antal spil fra en kort periode tidligt i appens
// levetid — er acceptabel uden backfill).
//
// Brug:
//   GOOGLE_APPLICATION_CREDENTIALS=/sti/til/service-account.json \
//     node functions/scripts/backfill_finished_at.js
//       — DRY RUN (default): tæller og lister ramte spil, skriver INTET.
//   ... node functions/scripts/backfill_finished_at.js --apply
//       — Skriver `finishedAt` for de ramte spil (se fallback-strategi
//         nedenfor), én dokument-opdatering ad gangen, med et resumé
//         til sidst.
//
// Fallback-strategi for den manglende dato: `createdAt` findes IKKE for
// disse spil heller (samme commit). Det ENESTE tidsstempel Firestore
// garanterer på ethvert dokument — uanset app-kode — er dokumentets egen
// `updateTime` (sat af Firestore selv ved hver skrivning). For et
// `status: 'over'`-dokument er `updateTime` typisk selve
// spil-slut-skrivningen (eller en skrivning kort efter, fx `seen`), altså
// den bedst tilgængelige tilnærmelse til "hvornår sluttede spillet".

const {initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

const APPLY = process.argv.includes("--apply");

async function main() {
  initializeApp();
  const db = getFirestore("partners");

  const snap = await db.collection("games")
      .where("status", "==", "over")
      .get();

  const missing = snap.docs.filter((d) => d.get("finishedAt") == null);

  console.log(`Afsluttede spil i alt: ${snap.size}`);
  console.log(`Mangler finishedAt:    ${missing.length}`);
  if (!missing.length) {
    console.log("Intet at rette.");
    return;
  }

  console.log("\nRamte spil (kode → foreslået finishedAt fra updateTime):");
  for (const d of missing) {
    const fallback = d.updateTime ? d.updateTime.toDate().toISOString() : "?";
    console.log(`  ${d.id} → ${fallback}`);
  }

  if (!APPLY) {
    console.log("\nDRY RUN — intet skrevet. Kør med --apply for at rette.");
    return;
  }

  console.log(`\nSkriver finishedAt for ${missing.length} spil...`);
  let ok = 0;
  let failed = 0;
  for (const d of missing) {
    const finishedAt = d.updateTime || Timestamp.now();
    try {
      // merge:true — rører KUN finishedAt, ingen risiko for at ødelægge
      // andre felter (samme forsigtighedsprincip som onGameTurns
      // staleSince-markering).
      await d.ref.set({finishedAt}, {merge: true});
      ok++;
    } catch (e) {
      failed++;
      console.error(`  FEJL ved ${d.id}: ${e.message}`);
    }
  }
  console.log(`\nFærdig: ${ok} rettet, ${failed} fejlede.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
