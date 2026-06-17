// Cloud Functions for Partners.
//
// Lytter på nye invitationer i users/{uid}/inbox/{x} og sender en
// push-notifikation via FCM til alle modtagerens registrerede tokens.
// Bruger den navngivne Firestore-database 'partners' (ikke default).
//
// Deploy: `firebase deploy --only functions` — kræver Blaze-plan.

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {initializeApp} = require("firebase-admin/app");
const {FieldValue} = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore("partners");

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

    const fromName = invite.fromName || "En ven";
    const gameCode = invite.gameCode || "";

    const res = await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "Partners — invitation",
        body: `${fromName} har inviteret dig til et spil`,
      },
      data: {
        gameCode,
        click_action: "/",
      },
      webpush: {
        fcmOptions: {link: gameCode ? `/?invite=${gameCode}` : "/"},
        notification: {
          icon: "/icons/Icon-192.png",
          badge: "/icons/Icon-192.png",
        },
      },
    });

    // Ryd op i tokens der ikke længere er gyldige.
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
);
