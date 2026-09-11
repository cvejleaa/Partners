#!/usr/bin/env bash
# Alarm på "notifikationerne holdt op med at komme frem".
#
# KØRES EN GANG, manuelt, af et menneske med produktions-adgang. Det er ikke
# en del af udrulningen, og det skriver intet i Firestore.
#
# HVORFOR: en log er ikke en alarm. Beskederne udeblev i august, fordi
# funktionen løb tør for hukommelse — og udrulningen så grøn ud imens. Vi
# opdagede det, fordi nogen undrede sig, ikke fordi noget sagde fra.
#
# Den bygger to ting i Google Cloud:
#   1. Et log-baseret måltal, der tæller de push-linjer, hvor INTET kom frem
#      (severity=ERROR på event=push — se functions/push_log.js).
#   2. En alarm-politik, der sender mail, når det tal stiger.
#
# GRÆNSEN sættes bevidst IKKE her. Den kan først vælges, når der er en uges
# rigtige tal: "falder til nul" ville i en app med en håndfuld spil om dagen
# være en falsk alarm hver eneste nat. Kør trin 1 nu, se på tallene om en uge,
# og kør så trin 2 med en grænse, der passer til jeres aktivitet.
#
# Brug:
#   PROJECT=<projekt-id> EMAIL=<din@mail.dk> bash functions/scripts/setup_push_alert.sh metric
#   PROJECT=<projekt-id> EMAIL=<din@mail.dk> THRESHOLD=3 bash functions/scripts/setup_push_alert.sh alert
set -euo pipefail

: "${PROJECT:?sæt PROJECT=<projekt-id>}"
: "${EMAIL:?sæt EMAIL=<din@mail.dk>}"
STEP="${1:-metric}"
METRIC="push_not_delivered"

case "$STEP" in
metric)
  echo "Opretter log-baseret måltal '$METRIC' i $PROJECT ..."
  # Tæller præcis de linjer, hvor der VAR enheder at sende til, og intet kom
  # frem. delivered:false sættes af severityFor() i functions/push_log.js.
  gcloud logging metrics create "$METRIC" \
    --project="$PROJECT" \
    --description="Push hvor intet kom frem (tokens>0, ok=0)" \
    --log-filter='resource.type="cloud_function"
severity=ERROR
jsonPayload.event="push"
jsonPayload.delivered=false'
  echo
  echo "Færdig. Lad det køre en uge, og se så tallene her:"
  echo "  https://console.cloud.google.com/logs/metrics?project=$PROJECT"
  echo "Kør derefter: THRESHOLD=<tal> bash $0 alert"
  ;;
alert)
  : "${THRESHOLD:?sæt THRESHOLD=<antal pr. time, valgt ud fra en uges tal>}"
  echo "Opretter mail-kanal til $EMAIL ..."
  CHANNEL=$(gcloud alpha monitoring channels create \
    --project="$PROJECT" \
    --display-name="Partners drift" \
    --type=email \
    --channel-labels="email_address=$EMAIL" \
    --format="value(name)")
  echo "Kanal: $CHANNEL"

  # Alarm-politikken som fil, saa den er efterproevelig frem for et klik.
  POLICY=$(mktemp)
  cat > "$POLICY" <<JSON
{
  "displayName": "Partners: notifikationer kommer ikke frem",
  "documentation": {
    "content": "Push-beskeder fejler for ALLE en brugers enheder. Se Cloud Functions-loggen, soeg event=push. Beskeden udeblev i august 2026 paa grund af for lidt hukommelse i funktionen, uden at noget sagde fra — denne alarm findes for at det ikke gentager sig.",
    "mimeType": "text/markdown"
  },
  "conditions": [{
    "displayName": "push_not_delivered over $THRESHOLD pr. time",
    "conditionThreshold": {
      "filter": "metric.type=\\"logging.googleapis.com/user/$METRIC\\" AND resource.type=\\"cloud_function\\"",
      "comparison": "COMPARISON_GT",
      "thresholdValue": $THRESHOLD,
      "duration": "0s",
      "aggregations": [{
        "alignmentPeriod": "3600s",
        "perSeriesAligner": "ALIGN_SUM"
      }]
    }
  }],
  "combiner": "OR",
  "notificationChannels": ["$CHANNEL"]
}
JSON
  gcloud alpha monitoring policies create --project="$PROJECT" --policy-from-file="$POLICY"
  rm -f "$POLICY"
  echo
  echo "Alarmen er sat. Afproev den MED VILJE, foer du stoler paa den:"
  echo "  send en push til et ugyldigt token og se at mailen kommer."
  echo "En alarm, der aldrig er blevet udloest, er et loefte — ikke en alarm."
  ;;
*)
  echo "Ukendt trin '$STEP'. Brug 'metric' eller 'alert'." >&2
  exit 1
  ;;
esac
