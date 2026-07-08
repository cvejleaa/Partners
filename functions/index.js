// Cloud Functions for Partners.
//
// Lytter på nye invitationer i users/{uid}/inbox/{x} og sender en
// push-notifikation via FCM til alle modtagerens registrerede tokens.
// Bruger den navngivne Firestore-database 'partners' (ikke default).
//
// Deploy: `firebase deploy --only functions` — kræver Blaze-plan.

const {onDocumentCreated, onDocumentUpdated} =
  require("firebase-functions/v2/firestore");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {initializeApp} = require("firebase-admin/app");
const {FieldValue} = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore("partners");

/// Send FCM til alle en brugers tokens og ryd stale tokens op.
async function pushToUser(uid, message) {
  const userSnap = await db.collection("users").doc(uid).get();
  const tokens = (userSnap.data() || {}).fcmTokens || [];
  if (!tokens.length) return;
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    ...message,
  });
  const stale = [];
  res.responses.forEach((r, i) => {
    const err = r.error;
    if (!r.success && err && (
      err.code === "messaging/registration-token-not-registered" ||
      err.code === "messaging/invalid-registration-token"
    )) {
      stale.push(tokens[i]);
    }
  });
  if (stale.length) {
    await db.collection("users").doc(uid).update({
      fcmTokens: FieldValue.arrayRemove(...stale),
    });
  }
}

exports.onInboxCreate = onDocumentCreated(
  {
    document: "users/{uid}/inbox/{inviteId}",
    database: "partners",
    region: "europe-west1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const invite = snap.data() || {};
    if (invite.type !== "gameInvite") return;

    const uid = event.params.uid;
    const userSnap = await db.collection("users").doc(uid).get();
    const tokens = (userSnap.data() || {}).fcmTokens || [];
    if (!tokens.length) return;

    // Defensiv validering af klient-leveret indhold, så en manipuleret
    // afsender ikke kan lave vildledende/overlange notifikationer eller
    // manipulere deep-link'et. (Firestore-reglerne validerer også, men
    // functionen bør ikke stole blindt på input.)
    const sanitize = (v, max) =>
      (typeof v === "string" ? v : "").replace(/[\r\n]+/g, " ").slice(0, max);
    const fromName = sanitize(invite.fromName, 60) || "En ven";
    const rawCode = sanitize(invite.gameCode, 12);
    // Kun et gyldigt spil-kode-format (A-Z0-9) må ind i deep-link'et.
    const gameCode = /^[A-Za-z0-9]{1,12}$/.test(rawCode) ? rawCode : "";

    // DATA-only: notifikationen vises af service-workeren (onBackgroundMessage)
    // — IKKE også automatisk af browseren. Ellers fik man to notifikationer.
    await pushToUser(uid, {
      data: {
        type: "invite",
        gameCode,
        title: "Partners — invitation",
        body: `${fromName} har inviteret dig til et spil`,
      },
      webpush: {headers: {Urgency: "high", TTL: "600"}},
    });
  }
);

/// Notificér en spiller når det bliver DERES tur i et online-spil — men kun
/// hvis de IKKE er aktive på spillepladen (deres presence-stempel er forældet).
/// Trigges når spil-dokumentet opdateres; kun rigtige turn-skift (ændret
/// currentPlayerIndex/hånd i play-fasen) fører til en push.
const AWAY_MS = 20000; // presence ældre end dette = "ikke aktiv"

exports.onGameTurn = onDocumentUpdated(
  {
    document: "games/{code}",
    database: "partners",
    region: "europe-west1",
  },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (after.status !== "playing") return;

    const aState = after.state || {};
    const bState = before.state || {};
    if (aState.ph !== "play") return;

    // Kun ægte turn-skift: currentPlayerIndex eller hånd ændret.
    const sameTurn =
      aState.cp === bState.cp && aState.hn === bState.hn;
    if (sameTurn) return;

    const seat = aState.cp;
    const uids = after.uids || [];
    const uid = uids[seat];
    if (!uid) return; // AI-plads

    // Aktiv på brættet? presence-stempel friskt → ingen push.
    const presence = after.presence || {};
    const ts = presence[uid];
    const ms = ts && typeof ts.toMillis === "function" ? ts.toMillis() : 0;
    const nowMs = Date.now();
    if (ms && nowMs - ms < AWAY_MS) return;

    const code = event.params.code;
    // DATA-only: service-workeren viser notifikationen (én gang) og håndterer
    // klik → åbner selve spillet (/?game=<code>).
    await pushToUser(uid, {
      data: {
        type: "turn",
        gameCode: code,
        title: "Partners — din tur",
        body: `Det er din tur i spil ${code}`,
      },
      webpush: {headers: {Urgency: "high", TTL: "300"}},
    });
  }
);
