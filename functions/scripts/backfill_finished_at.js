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
// adgang i det miljø ændringen blev lavet i. Sikkerheds-gennemgangen af
// selve logikken (kun `finishedAt` skrevet via merge, aldrig noget afledt
// af dokumentindhold, ingen sti-injektion, trigger-bivirkningen efterprøvet
// mod onGameTurn) er OK — men KØR DRY RUN FØRST og læs outputtet, jf.
// CLAUDE.md "tør-kørsel først på alt der skriver i produktionsdata".
//
// Brug:
//   GOOGLE_APPLICATION_CREDENTIALS=/sti/til/service-account.json \
//     node functions/scripts/backfill_finished_at.js
//       — DRY RUN (default): tæller og lister ramte spil, skriver INTET.
//   ... node functions/scripts/backfill_finished_at.js --apply --project=<forventet-projekt-id>
//       — Skriver `finishedAt` for de ramte spil (se fallback-strategi
//         nedenfor). Kræver EKSPLICIT --project=<id>, der skal matche det
//         projekt legitimationsoplysningerne faktisk peger på — sikkerhedsnet
//         mod at ramme det forkerte projekt ved en fejl i miljøvariablen.
//
// Fallback-strategi for den manglende dato: `createdAt` findes IKKE for
// disse spil heller (samme commit). Det ENESTE tidsstempel Firestore
// garanterer på ethvert dokument — uanset app-kode — er dokumentets egen
// `updateTime` (sat af Firestore selv ved hver skrivning). For et
// `status: 'over'`-dokument er `updateTime` typisk selve
// spil-slut-skrivningen, MEN: er dokumentet rørt SENERE (fx en forsinket
// `seen`-flush), bliver `updateTime` nyere end det reelle sluttidspunkt —
// spillet kan derfor ende med at se "friskere" ud end det er. Gennemse
// dry-run-listen for datoer der virker for nye, før du kører --apply.
//
// Upagineret læsning undgås bevidst: alle `status:'over'`-dokumenter hentes
// i sider af PAGE_SIZE ad gangen (ikke ét stort kald), så scriptet ikke
// OOM'er eller laver én kæmpe fakturering på en stor kollektion.

const {initializeApp, getApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

const APPLY = process.argv.includes("--apply");
const PROJECT_ARG = process.argv.find((a) => a.startsWith("--project="));
const PAGE_SIZE = 500;

async function main() {
  initializeApp();
  const db = getFirestore("partners");

  if (APPLY) {
    const actualProjectId = getApp().options.projectId;
    const expectedProjectId = PROJECT_ARG && PROJECT_ARG.slice("--project=".length);
    if (!expectedProjectId) {
      throw new Error(
          "--apply kræver --project=<forventet-projekt-id> som eksplicit " +
          "sikkerhedsnet mod at skrive i det forkerte projekt.");
    }
    if (expectedProjectId !== actualProjectId) {
      throw new Error(
          `--project=${expectedProjectId} matcher IKKE det projekt ` +
          `legitimationsoplysningerne peger på (${actualProjectId}). Stoppet ` +
          "uden at skrive noget.");
    }
    console.log(`Bekræftet projekt: ${actualProjectId}`);
  }

  const missing = [];
  let totalOver = 0;
  let cursor = null;
  for (;;) {
    let q = db.collection("games")
        .where("status", "==", "over")
        .orderBy("__name__")
        .limit(PAGE_SIZE);
    if (cursor) q = q.startAfter(cursor);
    const page = await q.get();
    if (page.empty) break;
    totalOver += page.size;
    for (const d of page.docs) {
      if (d.get("finishedAt") == null) missing.push(d);
    }
    cursor = page.docs[page.docs.length - 1];
    if (page.size < PAGE_SIZE) break;
  }

  console.log(`Afsluttede spil i alt: ${totalOver}`);
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
    console.log("\nDRY RUN — intet skrevet. Kør med --apply --project=<id> for at rette.");
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
