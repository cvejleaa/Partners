// Niveau 3: virkede notifikationen? Ren beregning, ingen Firestore.
//
// Noeglefundet der gjorde det naesten gratis: hver log-post i et spil baerer
// allerede sit eget tidsstempel (entry['t']). Afstanden mellem to poster ER
// derfor, hvor laenge den naeste spiller var om at traekke, efter turen kom
// til dem — samme tal som ventetaelleren viser, bare historisk. Nul nye
// skrivninger.
//
// Men et gab er kun en svartid, hvis man kasserer de gab, der ikke er det.
// Kasse-reglerne herunder er QC's fund, ikke gaetteri:

/** Poster fra en AI-overtagelse: spilleren kom ALDRIG tilbage. */
const NEVER_ANSWERED = "never";

/**
 * Udled svartider af et spils log.
 *
 * @param {Array<object>} log spillets log-array (poster med player, type, hn, t)
 * @param {Array<*>} uids saederne (null = tom/AI-plads)
 * @return {{gaps: Array<object>, discarded: object}}
 */
function responseGaps(log, uids) {
  const gaps = [];
  const discarded = {
    handChange: 0, sameSeat: 0, aiSeat: 0, noTime: 0, negative: 0, exchange: 0,
  };
  for (let i = 1; i < log.length; i++) {
    const prev = log[i - 1];
    const cur = log[i];
    // Byttefasen skriver i dag INGEN poster online (exchangeLogEntry er
    // ubrugt), men skrives den en dag, bryder udregningen tavst. Eksplicit
    // vagt frem for en antagelse, der tilfaeldigvis er sand.
    if (prev.type === "exchange" || cur.type === "exchange") {
      discarded.exchange += 1;
      continue;
    }
    // Haandskifte: startNewHand skriver ingen post, saa gabet rummer
    // kortgivning + fire spilleres byttevalg — og der blev ikke sendt push.
    if (prev.hn !== cur.hn) {
      discarded.handChange += 1;
      continue;
    }
    // Samme spiller to gange i traek faar ingen push (turen skiftede ikke).
    if (prev.player === cur.player) {
      discarded.sameSeat += 1;
      continue;
    }
    // En AI-plads faar aldrig en besked.
    if (uids[cur.player] === null || uids[cur.player] === undefined) {
      discarded.aiSeat += 1;
      continue;
    }
    const a = prev.t;
    const b = cur.t;
    if (typeof a !== "number" || typeof b !== "number") {
      discarded.noTime += 1;
      continue;
    }
    // AI-overtagelse: spilleren svarede ALDRIG, en robot traak for dem. Det
    // er praecis de tilfaelde, hvor push'en ikke virkede — kasseres de, ser
    // medianen kunstigt paen ud. Taelles som censureret i stedet.
    if (cur.ai === true) {
      gaps.push({seat: cur.player, ms: NEVER_ANSWERED});
      continue;
    }
    const ms = b - a;
    if (ms < 0) {
      // Hvert gab er differencen mellem TO forskellige enheders ure, saa
      // skaevhed rammer hver eneste maaling — ikke kun de synligt negative.
      // Andelen rapporteres som et datakvalitets-tal.
      discarded.negative += 1;
      continue;
    }
    gaps.push({seat: cur.player, ms});
  }
  return {gaps, discarded};
}

/** Intervaller frem for kun median: robust over for ur-skaevhed, og viser
 * BAADE stoej-enden (<1 min = spilleren sad der allerede) og fiasko-enden. */
const BUCKETS = [
  ["under 1 min", 60e3],
  ["1-10 min", 600e3],
  ["10-60 min", 3600e3],
  ["1-24 timer", 86400e3],
  ["over 24 timer", Infinity],
];

function bucketOf(ms) {
  if (ms === NEVER_ANSWERED) return "aldrig (AI overtog)";
  for (const [name, max] of BUCKETS) if (ms < max) return name;
  return "over 24 timer";
}

function median(sorted) {
  if (!sorted.length) return null;
  const m = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[m] : Math.round((sorted[m - 1] + sorted[m]) / 2);
}

function percentile(sorted, p) {
  if (!sorted.length) return null;
  const i = Math.min(sorted.length - 1, Math.floor(sorted.length * p));
  return sorted[i];
}

/**
 * Sammenfat EEN gruppe. Returnerer aldrig en median under [minN] — i en
 * kreds paa under ti personer ville "medianen for dem uden push" i praksis
 * vaere EEN persons svartid (GDPR-krav).
 *
 * @param {Array<object>} gaps
 * @param {object} opts
 * @param {number} opts.minN mindste antal observationer
 * @param {number} opts.minPlayers mindste antal FORSKELLIGE spillere
 * @return {object}
 */
function summarize(gaps, {minN = 30, minPlayers = 3} = {}) {
  const answered = gaps.filter((g) => g.ms !== NEVER_ANSWERED);
  const never = gaps.length - answered.length;
  const players = new Set(gaps.map((g) => g.seat)).size;
  const buckets = {};
  for (const g of gaps) {
    const b = bucketOf(g.ms);
    buckets[b] = (buckets[b] || 0) + 1;
  }
  const out = {n: gaps.length, players, never, buckets};
  if (gaps.length < minN || players < minPlayers) {
    // Ingen median. "for faa observationer" er et aerligt svar; et tal her
    // ville blive citeret senere.
    out.median = null;
    out.p90 = null;
    out.suppressed = `for faa observationer (n=${gaps.length}, spillere=${players}; kraever n>=${minN} og >=${minPlayers} spillere)`;
    return out;
  }
  const sorted = answered.map((g) => g.ms).sort((a, b) => a - b);
  out.median = median(sorted);
  out.p90 = percentile(sorted, 0.9);
  return out;
}

module.exports = {
  responseGaps, summarize, bucketOf, NEVER_ANSWERED, BUCKETS,
};
