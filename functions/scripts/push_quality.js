// MÅLING af notifikations-kvalitet — IKKE en deployet Cloud Function.
// Køres manuelt af et menneske med produktions-adgang.
//
// SKRIVER ALDRIG NOGET. Der findes ikke en --apply-tilstand, og det er med
// vilje: scriptet er en måling, ikke en migrering.
//
// Brug:
//   GOOGLE_APPLICATION_CREDENTIALS=/sti/til/service-account.json \
//     node functions/scripts/push_quality.js [--days=14]
//
// Hvad det svarer på:
//   1. Hvor mange AKTIVE spillere kan vi overhovedet nå med en notifikation?
//   2. Hvor hurtigt svarer de, der har push slået til — mod dem, der ikke har?
//
// GDPR-grænser (fra data/GDPR-gennemgangen), håndhævet i koden nedenfor:
//   - Rapporten viser KUN aggregater. Aldrig en linje pr. person eller pr.
//     spil, heller ikke i en debug-gren: i en lille, kendt kreds er selv
//     navnløse svartider afslørende ("det var tydeligvis ham, han spillede
//     sent i går").
//   - Ingen median udskrives for en gruppe under MIN_N observationer ELLER
//     under MIN_PLAYERS forskellige spillere. Er kredsen under ti personer,
//     ville "medianen for dem uden push" i praksis være én persons svartid.
//
// FORBEHOLD, der skal stå i enhver rapportering af tallene:
//   a) Tidsstemplerne sættes med KLIENTENS ur, ikke serverens. Hvert gab er
//      differencen mellem TO forskellige enheders ure, så skævhed rammer hver
//      eneste måling — ikke kun de synligt negative. Andelen af kasserede
//      negative gab printes som et datakvalitets-tal: er den over et par
//      procent, er hele målingen mistænkelig.
//   b) Det er en SAMMENLIGNING, ikke et forsøg. De, der har slået push til,
//      er formentlig også de mest ivrige spillere. Forskellen må ikke
//      fremstilles som push'ens fortjeneste alene.
//   c) Vi ved ikke, om en notifikation blev VIST — kun at FCM tog imod den.
//      Klik-registrering er fravalgt (en skrivning pr. notifikation, og den
//      rører persondata).
//   d) Niveau 1 (leveringsloggen) indeholder bevidst intet uid, og niveau 3
//      grupperer PÅ uid. De to kan derfor aldrig sammenkædes: vi kan ikke
//      efterprøve, at en langsom spiller rent faktisk MODTOG sine pushes.

const {getFirestore} = require("firebase-admin/firestore");
const {initializeApp} = require("firebase-admin/app");
const {responseGaps, summarize, headlineCounts} =
  require("../push_quality");

const MIN_N = 30;
const MIN_PLAYERS = 3;

function arg(name, fallback) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split("=")[1] : fallback;
}

async function main() {
  const days = Number(arg("days", "14"));
  if (!Number.isFinite(days) || days <= 0) {
    throw new Error("--days skal være et positivt tal");
  }
  initializeApp();
  const db = getFirestore("partners");
  const cutoff = new Date(Date.now() - days * 86400e3);

  // Nævneren: AKTIVE spillere, ikke alle konti. "Hvor mange har push slået
  // til" tæller døde konti med og bliver kønnere med tiden uden at betyde
  // noget. Vinduet er det samme, brugeren ser i "Mine spil".
  const games = await db.collection("games")
      .where("lastActionAt", ">=", cutoff).get();

  const pushOnByUid = new Map();
  const active = new Set();
  const withPush = [];
  const withoutPush = [];
  const discardTotals = {
    handChange: 0, sameSeat: 0, aiSeat: 0, noTime: 0, negative: 0, exchange: 0,
  };
  let considered = 0;

  for (const doc of games.docs) {
    const d = doc.data();
    if (d.mode === "ai") continue; // solospil mod computeren får ingen push
    const uids = d.uids || [];
    const log = (d.log || []).map((e) => ({
      ...e,
      t: e.t && e.t.toMillis ? e.t.toMillis() : e.t,
    }));
    for (const u of uids) if (u) active.add(u);
    const {gaps, discarded} = responseGaps(log, uids);
    for (const k of Object.keys(discardTotals)) discardTotals[k] += discarded[k];
    considered += Math.max(0, log.length - 1);
    for (const g of gaps) {
      const uid = uids[g.seat];
      if (!uid) continue;
      if (!pushOnByUid.has(uid)) {
        const snap = await db.collection("users").doc(uid).get();
        const u = snap.data() || {};
        // `pushOn` er brugerens VALG. `fcmTokens` alene duer ikke som
        // skillelinje: serveren sletter døde tokens, så en spiller der HAVDE
        // push, men hvis token døde, ville tælle som "uden" — og det er
        // systematisk de mest fraværende, altså de langsomste.
        pushOnByUid.set(uid, {
          chose: u.pushOn === true,
          reachable: Array.isArray(u.fcmTokens) && u.fcmTokens.length > 0,
        });
      }
      (pushOnByUid.get(uid).reachable ? withPush : withoutPush).push(g);
    }
  }

  const chose = [...pushOnByUid.values()].filter((v) => v.chose).length;
  const reachable = [...pushOnByUid.values()].filter((v) => v.reachable).length;
  const opts = {minN: MIN_N, minPlayers: MIN_PLAYERS};

  console.log(`\n=== Notifikations-kvalitet, seneste ${days} dage ===\n`);
  // Samme spærre som medianen: i en lille, kendt kreds er "1 kan ikke nås"
  // lige så identificerende som et navn.
  const head = headlineCounts(
      {active: active.size, chose, reachable}, MIN_PLAYERS);
  if (head.suppressed) {
    console.log(`Aktive spillere i vinduet:        ${head.active}`);
    console.log(`  fordeling: ${head.suppressed}`);
  } else {
    console.log(`Aktive spillere i vinduet:        ${head.active}`);
    console.log(`  heraf valgt push til:           ${head.chose}`);
    console.log(`  heraf faktisk KAN nås nu:       ${head.reachable}`);
    if (head.unreachable > 0) {
      console.log(`  → ${head.unreachable} tror de har notifikationer, men` +
          ` har ingen levende enhed. Det er det mest handlingsanvisende tal` +
          ` her.`);
    }
  }
  const totalDiscarded = Object.values(discardTotals).reduce((a, b) => a + b, 0);
  console.log(`\nGab i spil-loggene: ${considered} betragtet, ` +
      `${totalDiscarded} kasseret`);
  for (const [k, v] of Object.entries(discardTotals)) {
    if (v) console.log(`  ${k}: ${v}`);
  }
  const negPct = considered ? (100 * discardTotals.negative / considered) : 0;
  console.log(`  negative (ur-skævhed): ${negPct.toFixed(1)} %` +
      (negPct > 2 ? "  ← over 2 %: hele målingen er mistænkelig" : ""));

  for (const [navn, gaps] of [["MED push", withPush], ["UDEN push", withoutPush]]) {
    const s = summarize(gaps, opts);
    console.log(`\n--- ${navn} ---`);
    console.log(`  observationer: ${s.n} (${s.players} spillere)`);
    if (s.suppressed) {
      console.log(`  median/p90: ${s.suppressed}`);
    } else {
      console.log(`  median: ${Math.round(s.median / 1000)} s` +
          `   p90: ${Math.round(s.p90 / 1000)} s`);
    }
    for (const [b, n] of Object.entries(s.buckets)) {
      console.log(`    ${b.padEnd(20)} ${n}`);
    }
  }
  console.log(`\nForbehold: klientens ur, en sammenligning (ikke et forsøg),` +
      ` og vi ved kun at FCM tog imod — ikke at beskeden blev vist.` +
      ` Se filhovedet.\n`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
