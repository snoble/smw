/* Summer Movie Wager inference worker.
 *
 * Protocol (main → worker):
 *   { type: "init", data }
 *   { type: "run", generation, seed, n_draws, overrides, quadrature: { eta, sigma } }
 *   { type: "cancel", generation }
 *
 * Protocol (worker → main):
 *   { type: "ready", engine: "wasm"|"js-fallback", ... }
 *   { type: "result", generation, status: "preview"|"refining"|"final", ...aggregates, telemetry }
 *   { type: "error", generation?, message }
 *
 * Progressive: 1k preview then continue same RNG stream to n_draws (default 20k).
 * Stale generations are rejected; cancel stops in-flight work for that generation.
 */

const PREVIEW_DRAWS = 1000;
const DEFAULT_FINAL_DRAWS = 20000;

let bundle = null;
let engine = "js-fallback";
let wasmPresent = false;
let activeGeneration = 0;
let cancelGeneration = 0;

// --- Kernel-matching RNG (Xoshiro256** + Box–Muller), mirrors src/wasm_kernel.jl ---

function splitmix64(x) {
  x = BigInt.asUintN(64, x + 0x9e3779b97f4a7c15n);
  let z = x;
  z = BigInt.asUintN(64, (z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n);
  z = BigInt.asUintN(64, (z ^ (z >> 27n)) * 0x94d049bb133111ebn);
  return [BigInt.asUintN(64, z ^ (z >> 31n)), x];
}

function seedRng(seed) {
  let x = BigInt.asUintN(64, BigInt(seed >>> 0) || BigInt(seed));
  let s0; let s1; let s2; let s3;
  [s0, x] = splitmix64(x);
  [s1, x] = splitmix64(x);
  [s2, x] = splitmix64(x);
  [s3, x] = splitmix64(x);
  return { s0, s1, s2, s3, hasSpare: false, spare: 0 };
}

function rotl(x, k) {
  return BigInt.asUintN(64, (x << BigInt(k)) | (x >> BigInt(64 - k)));
}

function nextU64(rng) {
  const result = BigInt.asUintN(64, rotl(BigInt.asUintN(64, rng.s1 * 5n), 7) * 9n);
  const t = BigInt.asUintN(64, rng.s1 << 17n);
  rng.s2 ^= rng.s0;
  rng.s3 ^= rng.s1;
  rng.s1 ^= rng.s2;
  rng.s0 ^= rng.s3;
  rng.s2 ^= t;
  rng.s3 = rotl(rng.s3, 45);
  return result;
}

function nextF64(rng) {
  return Number(nextU64(rng) >> 11n) * Math.pow(2, -53) + Math.pow(2, -53);
}

function nextRandn(rng) {
  if (rng.hasSpare) {
    rng.hasSpare = false;
    return rng.spare;
  }
  const u1 = Math.max(nextF64(rng), 1e-16);
  const u2 = nextF64(rng);
  const r = Math.sqrt(-2 * Math.log(u1));
  const theta = 2 * Math.PI * u2;
  rng.spare = r * Math.cos(theta);
  rng.hasSpare = true;
  return r * Math.sin(theta);
}

// --- Curve / conjugacy (mirrors wasm_kernel.jl) ---

function logistic(x) {
  return 1 / (1 + Math.exp(-x));
}

function curveFactor(d, t) {
  if (t <= 0) return 0;
  if (Math.abs(d - 1) < 1e-12) return t;
  return -Math.expm1(t * Math.log(d)) / (1 - d);
}

function intervalFactor(d, t0, t1) {
  if (t1 <= t0) return 0;
  return curveFactor(d, t1) - curveFactor(d, t0);
}

function remainingFactor(d, tPin, tCut) {
  if (tCut <= tPin) return 0;
  d = Math.min(Math.max(d, 1e-9), 1 - 1e-9);
  const num = Math.exp(tPin * Math.log(d)) - Math.exp(tCut * Math.log(d));
  const den = 1 - Math.exp(tPin * Math.log(d));
  if (den <= 0) return 0;
  return Math.max(num / den, 0);
}

function seasonTotal(O, d, tCut, banked, tNow) {
  d = Math.min(Math.max(d, 1e-6), 1 - 1e-6);
  if (banked <= 0 || tNow <= 0) return O * curveFactor(d, tCut);
  if (tCut <= tNow) return banked;
  const tPin = Math.max(tNow, 1);
  if (tCut <= tPin) return banked;
  return banked + banked * remainingFactor(d, tPin, tCut);
}

function logOPosterior(zs, sigma, muLogO, sigmaLogO) {
  sigma = Math.max(sigma, 1e-6);
  sigmaLogO = Math.max(sigmaLogO, 1e-6);
  const nK = zs.length;
  if (nK === 0) return { logZ: 0, mean: muLogO, std: sigmaLogO };
  const tau2 = sigmaLogO * sigmaLogO;
  const sigma2 = sigma * sigma;
  let sumz = 0;
  for (let i = 0; i < nK; i += 1) sumz += zs[i];
  const prec = 1 / tau2 + nK / sigma2;
  const postVar = 1 / prec;
  const postMean = postVar * (muLogO / tau2 + sumz / sigma2);
  const postStd = Math.sqrt(postVar);
  let Q = 0;
  let S = 0;
  for (let i = 0; i < nK; i += 1) {
    const r = zs[i] - muLogO;
    Q += r * r;
    S += r;
  }
  const logdet = nK * Math.log(sigma2) + Math.log1p(nK * tau2 / sigma2);
  const quad = Q / sigma2 - (tau2 / (sigma2 * (sigma2 + nK * tau2))) * S * S;
  const logZ = -0.5 * (nK * Math.log(2 * Math.PI) + logdet + quad);
  return { logZ, mean: postMean, std: postStd };
}

// 8-point GH nodes (kernel preview path); weights for ∫ f(x) e^{-x²} dx
const GH_X8 = [
  -2.930637420257244, -1.981656756334386, -1.157193712446780, -0.381186990207322,
  0.381186990207322, 1.157193712446780, 1.981656756334386, 2.930637420257244,
];
const GH_W8 = [
  0.000199604344352, 0.017077983007413, 0.207802325814892, 0.661147012558241,
  0.661147012558241, 0.207802325814892, 0.017077983007413, 0.000199604344352,
];

const GH_X16 = [
  -4.688738939305818, -3.869447904860123, -3.176999161979956, -2.546202157847481,
  -1.951787990716324, -1.380258895201282, -0.822951449144656, -0.273444895157662,
  0.273444895157662, 0.822951449144656, 1.380258895201282, 1.951787990716324,
  2.546202157847481, 3.176999161979956, 3.869447904860123, 4.688738939305818,
];
const GH_W16 = [
  2.654948647467865e-10, 2.320980773852886e-7, 2.711860092537882e-5, 0.000932068658579142,
  0.0128805775447012, 0.083810041487892, 0.280619092494332, 0.507431899351916,
  0.507431899351916, 0.280619092494332, 0.083810041487892, 0.0128805775447012,
  0.000932068658579142, 2.711860092537882e-5, 2.320980773852886e-7, 2.654948647467865e-10,
];

const GL_X16 = [
  -0.9894009349916499, -0.9445750230732326, -0.8656312023878318, -0.7554044083550030,
  -0.6178762444026438, -0.4580167776572274, -0.2816035507792589, -0.0950125098376374,
  0.0950125098376374, 0.2816035507792589, 0.4580167776572274, 0.6178762444026438,
  0.7554044083550030, 0.8656312023878318, 0.9445750230732326, 0.9894009349916499,
];
const GL_W16 = [
  0.0271524594117541, 0.0622535239386479, 0.0951585116824928, 0.1246289712555339,
  0.1495959888165767, 0.1691565193950025, 0.1826034150449236, 0.1894506104550685,
  0.1894506104550685, 0.1826034150449236, 0.1691565193950025, 0.1495959888165767,
  0.1246289712555339, 0.0951585116824928, 0.0622535239386479, 0.0271524594117541,
];

function hermiteGrid(mu, sigma, order) {
  const xs = order >= 16 ? GH_X16 : GH_X8;
  const ws = order >= 16 ? GH_W16 : GH_W8;
  const n = Math.min(order, xs.length);
  const invSqrtPi = 1 / Math.sqrt(Math.PI);
  const nodes = new Float64Array(n);
  const weights = new Float64Array(n);
  for (let i = 0; i < n; i += 1) {
    nodes[i] = mu + Math.SQRT2 * sigma * xs[i];
    weights[i] = ws[i] * invSqrtPi;
  }
  return { nodes, weights };
}

function legendreSigma(lo, hi, order) {
  const n = Math.min(order, GL_X16.length);
  const mid = 0.5 * (hi + lo);
  const half = 0.5 * (hi - lo);
  const nodes = new Float64Array(n);
  const weights = new Float64Array(n);
  for (let i = 0; i < n; i += 1) {
    nodes[i] = mid + half * GL_X16[i];
    weights[i] = GL_W16[i] * half;
  }
  return { nodes, weights };
}

function logTruncNormal(x, mu, sigma) {
  const z = (x - mu) / sigma;
  return -0.5 * z * z - Math.log(sigma) - 0.5 * Math.log(2 * Math.PI);
}

function theaterTail(banked, theaters, tNow, tCut) {
  if (!(banked > 0 && tCut > tNow && tNow > 0)) return null;
  const th = theaters == null ? 2000 : theaters;
  let remainingWeeks;
  let sigmaTail;
  if (th <= 50) {
    remainingWeeks = 0.5;
    sigmaTail = 0.25;
  } else if (th <= 200) {
    remainingWeeks = 1.0;
    sigmaTail = 0.35;
  } else if (th <= 500) {
    remainingWeeks = 1.5;
    sigmaTail = 0.45;
  } else {
    return null;
  }
  const weekly = (banked / Math.max(tNow, 1)) * (th / 3500);
  const expectedRemaining = Math.max(weekly * remainingWeeks, 1);
  return { logRemaining: Math.log(expectedRemaining), sigma: sigmaTail };
}

function filmEtaPosterior(film, intervals, sigma, etaOrder) {
  const { nodes: etas, weights: w0 } = hermiteGrid(film.mu_logit_d, film.sigma_logit_d, etaOrder);
  const n = etas.length;
  const logw = new Float64Array(n);
  const muO = new Float64Array(n);
  const sigmaO = new Float64Array(n);
  let maxlw = -1e300;
  const zs = [];
  for (let k = 0; k < n; k += 1) {
    const d = Math.min(Math.max(logistic(etas[k]), 1e-6), 1 - 1e-6);
    zs.length = 0;
    for (let j = 0; j < intervals.length; j += 1) {
      const iv = intervals[j];
      const fac = intervalFactor(d, iv.t_start, iv.t_end);
      if (fac > 0 && iv.interval_gross > 0) {
        zs.push(Math.log(iv.interval_gross) - Math.log(fac));
      }
    }
    let { logZ, mean, std } = logOPosterior(zs, sigma, film.mu_logO, film.sigma_logO);
    const tail = theaterTail(film.banked, film.theaters, film.t_now, film.t_cut);
    if (tail && film.banked > 0) {
      const tPin = Math.max(film.t_now, 1);
      const rf = remainingFactor(d, tPin, film.t_cut);
      const pred = film.banked * rf;
      if (pred > 0) {
        const resid = Math.log(pred) - tail.logRemaining;
        logZ -= 0.5 * (resid / tail.sigma) ** 2 + Math.log(tail.sigma) + 0.5 * Math.log(2 * Math.PI);
      }
    }
    const lw = Math.log(Math.max(w0[k], 1e-300)) + logZ;
    logw[k] = lw;
    muO[k] = mean;
    sigmaO[k] = std;
    if (lw > maxlw) maxlw = lw;
  }
  let sumw = 0;
  for (let k = 0; k < n; k += 1) {
    logw[k] = Math.exp(logw[k] - maxlw);
    sumw += logw[k];
  }
  for (let k = 0; k < n; k += 1) logw[k] /= sumw;
  return { etas, w: logw, muO, sigmaO, logEvidence: maxlw + Math.log(sumw) };
}

function prepareModel(data, overrides, quadrature) {
  const etaOrder = (quadrature && quadrature.eta) || data.quadrature.eta || 16;
  const sigmaOrder = (quadrature && quadrature.sigma) || data.quadrature.sigma || 16;
  const films = data.films.map((film) => {
    const copy = { ...film };
    if (film.controlled && overrides && overrides[film.controlled] != null) {
      copy.mu_logO = Math.log(Number(overrides[film.controlled]) * 1e6);
    }
    return copy;
  });
  const byFilm = new Map();
  data.intervals.forEach((iv) => {
    if (!byFilm.has(iv.film)) byFilm.set(iv.film, []);
    byFilm.get(iv.film).push(iv);
  });
  const filmIntervals = films.map((f) => byFilm.get(f.title) || []);

  const { nodes: sigmas, weights: wSigmaRaw } = legendreSigma(0.02, 1.0, sigmaOrder);
  const nSigma = sigmas.length;
  const logp = new Float64Array(nSigma);
  const cache = new Array(films.length);
  for (let fi = 0; fi < films.length; fi += 1) cache[fi] = new Array(nSigma);

  for (let j = 0; j < nSigma; j += 1) {
    let lp = logTruncNormal(sigmas[j], 0.15, 0.1) + Math.log(Math.max(wSigmaRaw[j], 1e-300));
    for (let fi = 0; fi < films.length; fi += 1) {
      const film = films[fi];
      if (!film.released) continue;
      const post = filmEtaPosterior(film, filmIntervals[fi], sigmas[j], etaOrder);
      cache[fi][j] = post;
      lp += post.logEvidence;
    }
    logp[j] = lp;
  }
  let maxlp = -1e300;
  for (let j = 0; j < nSigma; j += 1) if (logp[j] > maxlp) maxlp = logp[j];
  let sum = 0;
  const wSigma = new Float64Array(nSigma);
  for (let j = 0; j < nSigma; j += 1) {
    wSigma[j] = Math.exp(logp[j] - maxlp);
    sum += wSigma[j];
  }
  for (let j = 0; j < nSigma; j += 1) wSigma[j] /= sum;
  const cdfSigma = new Float64Array(nSigma);
  let c = 0;
  for (let j = 0; j < nSigma; j += 1) {
    c += wSigma[j];
    cdfSigma[j] = c;
  }

  return {
    films,
    filmIntervals,
    etaOrder,
    sigmaOrder,
    sigmas,
    cdfSigma,
    cache,
  };
}

function sampleCategorical(cdf, u) {
  let lo = 0;
  let hi = cdf.length - 1;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (u <= cdf[mid]) hi = mid;
    else lo = mid + 1;
  }
  return lo;
}

function drawGrosses(model, rng, grossRow) {
  const uSigma = nextF64(rng);
  let jSigma = 0;
  while (jSigma < model.cdfSigma.length - 1 && uSigma > model.cdfSigma[jSigma]) jSigma += 1;

  for (let fi = 0; fi < model.films.length; fi += 1) {
    const film = model.films[fi];
    if (!film.released) {
      const logO = film.mu_logO + film.sigma_logO * nextRandn(rng);
      const eta = film.mu_logit_d + film.sigma_logit_d * nextRandn(rng);
      const d = Math.min(Math.max(logistic(eta), 1e-6), 1 - 1e-6);
      let g = Math.exp(logO) * curveFactor(d, film.t_cut);
      grossRow[fi] = g;
      continue;
    }
    let post = model.cache[fi][jSigma];
    if (!post) {
      post = filmEtaPosterior(film, model.filmIntervals[fi], model.sigmas[jSigma], model.etaOrder);
      model.cache[fi][jSigma] = post;
    }
    const cdf = new Float64Array(post.w.length);
    let c = 0;
    for (let k = 0; k < post.w.length; k += 1) {
      c += post.w[k];
      cdf[k] = c;
    }
    const k = sampleCategorical(cdf, nextF64(rng));
    const eta = post.etas[k];
    const d = Math.min(Math.max(logistic(eta), 1e-6), 1 - 1e-6);
    const logO = post.muO[k] + post.sigmaO[k] * nextRandn(rng);
    let g = seasonTotal(Math.exp(logO), d, film.t_cut, film.banked, film.t_now);
    if (film.banked > 0 && g < film.banked) g = film.banked;
    grossRow[fi] = g;
  }
}

// --- Scoring / aggregates ---

function scorePick(predictedRank, actualRank) {
  if (actualRank < 0) return 0;
  const difference = Math.abs(predictedRank - actualRank);
  if (difference === 0) return predictedRank === 1 || predictedRank === 10 ? 13 : 10;
  if (difference === 1) return 7;
  if (difference === 2) return 5;
  return 3;
}

function scorePlayer(player, ranking) {
  const actual = new Map(ranking.map((filmIndex, index) => [filmIndex, index + 1]));
  let score = 0;
  player.ranked.forEach((filmIndex, index) => {
    score += scorePick(index + 1, actual.get(filmIndex) || -1);
  });
  player.dark_horses.forEach((filmIndex) => {
    if (actual.has(filmIndex)) score += 1;
  });
  return score;
}

function quantileSorted(sorted, p) {
  if (!sorted.length) return NaN;
  const h = (sorted.length - 1) * p;
  const lo = Math.floor(h);
  const fraction = h - lo;
  return sorted[lo] + fraction * (sorted[Math.min(lo + 1, sorted.length - 1)] - sorted[lo]);
}

function rankListDistance(a, b) {
  const posB = new Map(b.map((t, i) => [t, i]));
  let dist = 0;
  a.forEach((t, i) => {
    const j = posB.has(t) ? posB.get(t) : b.length + 2;
    dist += Math.abs(i - j);
  });
  const setA = new Set(a);
  b.forEach((t, j) => {
    if (!setA.has(t)) dist += Math.abs(j - (a.length + 2));
  });
  return dist;
}

function representativeWin(rankings, winDraws, filmCount, gross) {
  if (!winDraws.length) return null;
  const medG = new Float64Array(filmCount);
  for (let fi = 0; fi < filmCount; fi += 1) {
    const vals = winDraws.map((draw) => gross[fi][draw]).sort((a, b) => a - b);
    medG[fi] = quantileSorted(vals, 0.5);
  }
  const consensus = Array.from({ length: filmCount }, (_, i) => i)
    .sort((a, b) => medG[b] - medG[a] || a - b)
    .slice(0, 10);

  let best = winDraws[0];
  let bestD = Infinity;
  winDraws.forEach((draw) => {
    const d = rankListDistance(rankings[draw], consensus);
    if (d < bestD) {
      bestD = d;
      best = draw;
    }
  });
  return best;
}

function buildAggregates(data, gross, rankings, scores, soleCounts, sharedCounts, winDraws, n) {
  const filmCount = data.films.length;
  const playerCount = data.players.length;
  const medians = new Float64Array(filmCount);
  const low = new Float64Array(filmCount);
  const high = new Float64Array(filmCount);
  const rankProb = Array.from({ length: filmCount }, () => new Float64Array(10));
  const top10Prob = new Float64Array(filmCount);
  const rankCounts = Array.from({ length: filmCount }, () => new Uint32Array(10));
  const top10Counts = new Uint32Array(filmCount);

  for (let draw = 0; draw < n; draw += 1) {
    rankings[draw].forEach((filmIndex, rank) => {
      rankCounts[filmIndex][rank] += 1;
      top10Counts[filmIndex] += 1;
    });
  }
  for (let fi = 0; fi < filmCount; fi += 1) {
    const col = new Float64Array(n);
    for (let draw = 0; draw < n; draw += 1) col[draw] = gross[fi][draw];
    col.sort();
    low[fi] = quantileSorted(col, 0.05);
    medians[fi] = quantileSorted(col, 0.5);
    high[fi] = quantileSorted(col, 0.95);
    for (let r = 0; r < 10; r += 1) rankProb[fi][r] = rankCounts[fi][r] / n;
    top10Prob[fi] = top10Counts[fi] / n;
  }
  const order = Array.from({ length: filmCount }, (_, i) => i)
    .sort((a, b) => medians[b] - medians[a] || a - b);

  const scoreMean = new Float64Array(playerCount);
  const scoreP10 = new Float64Array(playerCount);
  const scoreP50 = new Float64Array(playerCount);
  const scoreP90 = new Float64Array(playerCount);
  const winSole = new Float64Array(playerCount);
  const winShared = new Float64Array(playerCount);
  for (let p = 0; p < playerCount; p += 1) {
    const arr = Array.from(scores[p].subarray(0, n)).sort((a, b) => a - b);
    let sum = 0;
    for (let i = 0; i < n; i += 1) sum += arr[i];
    scoreMean[p] = sum / n;
    scoreP10[p] = quantileSorted(arr, 0.1);
    scoreP50[p] = quantileSorted(arr, 0.5);
    scoreP90[p] = quantileSorted(arr, 0.9);
    winSole[p] = soleCounts[p] / n;
    winShared[p] = sharedCounts[p] / n;
  }

  const scenarios = [];
  for (let p = 0; p < playerCount; p += 1) {
    const bestDraw = representativeWin(rankings, winDraws[p], filmCount, gross);
    if (bestDraw == null) continue;
    const ranking = rankings[bestDraw];
    const scenarioScores = data.players.map((player) => scorePlayer(player, ranking));
    const playerScore = scenarioScores[p];
    scenarios.push({
      playerIndex: p,
      ranking: Array.from(ranking),
      score: playerScore,
      nWins: winDraws[p].length,
      tiedWith: scenarioScores
        .map((score, index) => (score === playerScore && index !== p ? data.players[index].name : null))
        .filter(Boolean)
        .sort(),
    });
  }
  scenarios.sort((a, b) => b.nWins - a.nWins || a.playerIndex - b.playerIndex);

  return {
    n,
    medians: Array.from(medians),
    low: Array.from(low),
    high: Array.from(high),
    order,
    rankProb: rankProb.map((row) => Array.from(row)),
    top10Prob: Array.from(top10Prob),
    winSole: Array.from(winSole),
    winShared: Array.from(winShared),
    scoreMean: Array.from(scoreMean),
    scoreP10: Array.from(scoreP10),
    scoreP50: Array.from(scoreP50),
    scoreP90: Array.from(scoreP90),
    scenarios,
  };
}

function isCancelled(generation) {
  return cancelGeneration >= generation || activeGeneration !== generation;
}

async function runSimulation(msg) {
  const generation = msg.generation;
  activeGeneration = generation;
  const seed = msg.seed != null ? msg.seed : bundle.seeds.default;
  const nFinal = msg.n_draws != null ? msg.n_draws : DEFAULT_FINAL_DRAWS;
  const nPreview = Math.min(PREVIEW_DRAWS, nFinal);
  const overrides = msg.overrides || {};
  const quadrature = msg.quadrature || bundle.quadrature;
  const started = performance.now();

  const model = prepareModel(bundle, overrides, quadrature);
  if (isCancelled(generation)) return;

  const filmCount = bundle.films.length;
  const playerCount = bundle.players.length;
  const gross = Array.from({ length: filmCount }, () => new Float64Array(nFinal));
  const rankings = new Array(nFinal);
  const scores = Array.from({ length: playerCount }, () => new Float64Array(nFinal));
  const soleCounts = new Uint32Array(playerCount);
  const sharedCounts = new Uint32Array(playerCount);
  const winDraws = Array.from({ length: playerCount }, () => []);
  const filmIndices = Array.from({ length: filmCount }, (_, i) => i);
  const grossRow = new Float64Array(filmCount);
  const rng = seedRng(seed);

  const processDraw = (draw) => {
    drawGrosses(model, rng, grossRow);
    for (let fi = 0; fi < filmCount; fi += 1) gross[fi][draw] = grossRow[fi];
    const ranking = filmIndices.slice().sort((a, b) => grossRow[b] - grossRow[a] || a - b).slice(0, 10);
    rankings[draw] = ranking;
    const drawScores = bundle.players.map((player) => scorePlayer(player, ranking));
    drawScores.forEach((score, p) => { scores[p][draw] = score; });
    const best = Math.max(...drawScores);
    const winners = [];
    drawScores.forEach((score, p) => { if (score === best) winners.push(p); });
    if (winners.length === 1) soleCounts[winners[0]] += 1;
    winners.forEach((p) => {
      sharedCounts[p] += 1;
      winDraws[p].push(draw);
    });
  };

  for (let draw = 0; draw < nPreview; draw += 1) {
    if (isCancelled(generation)) return;
    processDraw(draw);
    if ((draw & 63) === 63) await Promise.resolve();
  }

  const previewAggs = buildAggregates(
    bundle, gross, rankings, scores, soleCounts, sharedCounts, winDraws, nPreview,
  );
  self.postMessage({
    type: "result",
    generation,
    status: "preview",
    ...previewAggs,
    telemetry: {
      engine,
      wasm_present: wasmPresent,
      status: "preview",
      draws: nPreview,
      eta_order: model.etaOrder,
      sigma_order: model.sigmaOrder,
      runtime_ms: performance.now() - started,
      seed,
      prior_version: bundle.prior_version,
      model_version: bundle.model_version,
      kernel_version: bundle.kernel_version,
      schema_version: bundle.schema_version,
    },
  });

  if (nPreview >= nFinal || isCancelled(generation)) return;

  // Mid-refine checkpoint ~halfway if long
  const mid = Math.min(nFinal, Math.max(nPreview + 1, Math.floor((nPreview + nFinal) / 2)));
  for (let draw = nPreview; draw < nFinal; draw += 1) {
    if (isCancelled(generation)) return;
    processDraw(draw);
    if ((draw & 127) === 127) await Promise.resolve();
    if (draw + 1 === mid && mid < nFinal) {
      const refiningAggs = buildAggregates(
        bundle, gross, rankings, scores, soleCounts, sharedCounts, winDraws, draw + 1,
      );
      self.postMessage({
        type: "result",
        generation,
        status: "refining",
        ...refiningAggs,
        telemetry: {
          engine,
          wasm_present: wasmPresent,
          status: "refining",
          draws: draw + 1,
          eta_order: model.etaOrder,
          sigma_order: model.sigmaOrder,
          runtime_ms: performance.now() - started,
          seed,
          prior_version: bundle.prior_version,
          model_version: bundle.model_version,
          kernel_version: bundle.kernel_version,
          schema_version: bundle.schema_version,
        },
      });
    }
  }

  if (isCancelled(generation)) return;
  const finalAggs = buildAggregates(
    bundle, gross, rankings, scores, soleCounts, sharedCounts, winDraws, nFinal,
  );
  self.postMessage({
    type: "result",
    generation,
    status: "final",
    ...finalAggs,
    telemetry: {
      engine,
      wasm_present: wasmPresent,
      status: "final",
      draws: nFinal,
      eta_order: model.etaOrder,
      sigma_order: model.sigmaOrder,
      runtime_ms: performance.now() - started,
      seed,
      prior_version: bundle.prior_version,
      model_version: bundle.model_version,
      kernel_version: bundle.kernel_version,
      schema_version: bundle.schema_version,
    },
  });
}

async function probeWasm() {
  try {
    const response = await fetch("wasm/smw_kernel.wasm");
    if (!response.ok) return false;
    const bytes = await response.arrayBuffer();
    // WasmTarget binaries currently need WasmGC + stringref; instantiate may fail
    // in stock browsers. Presence alone is recorded; draws use the JS fallback.
    try {
      await WebAssembly.instantiate(bytes);
      return true;
    } catch (err) {
      console.warn("WASM present but not instantiable in this runtime:", err.message || err);
      return true; // file exists; runtime still uses js-fallback for draws
    }
  } catch (err) {
    console.warn("WASM kernel missing, using js-fallback:", err.message || err);
    return false;
  }
}

self.onmessage = async (event) => {
  const msg = event.data;
  try {
    if (msg.type === "init") {
      bundle = msg.data;
      wasmPresent = await probeWasm();
      engine = "js-fallback";
      self.postMessage({
        type: "ready",
        engine,
        wasm_present: wasmPresent,
        schema_version: bundle.schema_version,
        model_version: bundle.model_version,
        kernel_version: bundle.kernel_version,
        prior_version: bundle.prior_version,
      });
      return;
    }
    if (msg.type === "cancel") {
      cancelGeneration = Math.max(cancelGeneration, msg.generation);
      return;
    }
    if (msg.type === "run") {
      if (!bundle) throw new Error("worker not initialized");
      cancelGeneration = Math.max(cancelGeneration, msg.generation - 1);
      await runSimulation(msg);
      return;
    }
    throw new Error(`unknown message type: ${msg.type}`);
  } catch (err) {
    self.postMessage({
      type: "error",
      generation: msg && msg.generation,
      message: err && err.message ? err.message : String(err),
    });
  }
};
