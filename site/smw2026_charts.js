(function () {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const esc = (value) => String(value)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const pct = (value) => `${(100 * value).toFixed(1)}%`;
  const money = (value) => value > 0 ? `$${Math.round(value / 1e6)}M` : "—";
  const DEBOUNCE_MS = 180;
  const FINAL_DRAWS = 20000;

  const VIRIDIS = [
    [0, [68, 1, 84]], [.25, [59, 82, 139]], [.5, [33, 145, 140]],
    [.75, [94, 201, 98]], [1, [253, 231, 37]],
  ];
  function viridis(value) {
    const t = Math.max(0, Math.min(1, value));
    for (let i = 1; i < VIRIDIS.length; i += 1) {
      if (t <= VIRIDIS[i][0]) {
        const a = VIRIDIS[i - 1];
        const b = VIRIDIS[i];
        const f = (t - a[0]) / (b[0] - a[0]);
        const rgb = a[1].map((channel, j) => Math.round(channel + f * (b[1][j] - channel)));
        return `rgb(${rgb.join(",")})`;
      }
    }
    return "rgb(253,231,37)";
  }

  function renderControls(data, assumptions, onInput) {
    const definitions = data.controls.map((control) => ({ ...control, unit: "M" }));
    $("controls").innerHTML = definitions.map((control) => `
      <div class="control">
        <label for="control-${control.key}">${esc(control.label)}
          <small>${esc(control.hint || "Expected opening-week domestic gross")}</small>
        </label>
        <output class="readout" id="value-${control.key}" for="control-${control.key}"></output>
        <input id="control-${control.key}" data-key="${control.key}" data-unit="${control.unit}"
          type="range" min="${control.min}" max="${control.max}" step="${control.step}"
          value="${control.default}" aria-label="${esc(control.label)}"
          title="${esc(control.hint || "")}">
      </div>`).join("");

    definitions.forEach((control) => {
      assumptions[control.key] = control.default;
      const input = $(`control-${control.key}`);
      const update = () => {
        assumptions[control.key] = Number(input.value);
        $(`value-${control.key}`).textContent = `$${input.value}${control.unit}`;
      };
      update();
      input.addEventListener("input", () => { update(); onInput(); });
    });
  }

  function renderSummary(assumptions, statusLabel) {
    $("assumption-summary").innerHTML =
      `<span class="status-pill" data-status="${esc(statusLabel)}">${esc(statusLabel)}</span>` +
      `Spidey <strong>$${assumptions.spidey}M</strong> · ` +
      `Odyssey <strong>$${assumptions.odyssey}M</strong> · PAW <strong>$${assumptions.paw}M</strong> · ` +
      `Mutiny <strong>$${assumptions.mutiny}M</strong> · Insidious <strong>$${assumptions.insidious}M</strong>`;
  }

  function renderTelemetry(telemetry) {
    if (!telemetry) {
      $("telemetry").textContent = "";
      return;
    }
    const status = telemetry.status || "—";
    $("telemetry").innerHTML =
      `<strong>${esc(status)}</strong>` +
      ` · ${telemetry.draws?.toLocaleString?.() ?? telemetry.draws} draws` +
      ` · η×σ ${telemetry.eta_order}×${telemetry.sigma_order}` +
      ` · ${Number(telemetry.runtime_ms).toFixed(0)} ms` +
      ` · seed ${telemetry.seed}` +
      ` · prior ${esc(telemetry.prior_version || "—")}` +
      ` · ${esc(telemetry.engine || "—")}`;
  }

  function renderPlayers(data, sim) {
    const rows = data.players.map((player, index) => ({
      index, name: player.name, sole: sim.winSole[index], shared: sim.winShared[index],
      average: sim.scoreMean[index],
      p10: sim.scoreP10[index],
      p50: sim.scoreP50[index],
      p90: sim.scoreP90[index],
    })).sort((a, b) => b.shared - a.shared || a.name.localeCompare(b.name));
    $("player-table").innerHTML = `<table>
      <thead><tr><th>Player</th><th>Sole</th><th>Win / tie</th><th>Avg score</th><th>P10</th><th>Median</th><th>P90</th></tr></thead>
      <tbody>${rows.map((row) => `<tr>
        <td class="player-name">${esc(row.name)}</td><td>${pct(row.sole)}</td>
        <td class="${row.shared >= .25 ? "prob-strong" : ""}">${pct(row.shared)}</td>
        <td>${row.average.toFixed(1)}</td><td>${row.p10.toFixed(1)}</td>
        <td>${row.p50.toFixed(1)}</td><td>${row.p90.toFixed(1)}</td>
      </tr>`).join("")}</tbody></table>`;
  }

  function renderScenarios(data, sim) {
    $("win-scenarios").innerHTML = sim.scenarios.map((scenario) => {
      const player = data.players[scenario.playerIndex];
      const tie = scenario.tiedWith.length ? `tied with ${scenario.tiedWith.join(", ")}` : "sole first";
      return `<article class="scenario-card">
        <h3>${esc(player.name)}</h3>
        <div class="scenario-meta">${pct(scenario.nWins / sim.n)} win / tie · ${scenario.score} pts · ${esc(tie)}</div>
        <ol>${scenario.ranking.map((filmIndex) => `<li>${esc(data.films[filmIndex].title)}</li>`).join("")}</ol>
      </article>`;
    }).join("");
  }

  function renderField(data, sim) {
    $("field-table").innerHTML = `<table>
      <thead><tr><th>#</th><th>Film</th><th>Banked</th><th>Median</th><th>5–95%</th><th>Top 10</th><th>#1</th></tr></thead>
      <tbody>${sim.order.map((filmIndex, rank) => {
        const film = data.films[filmIndex];
        return `<tr><td class="rank-num">${rank + 1}</td>
          <td class="film-name">${esc(film.title)}${film.released ? '<span class="released-mark">released</span>' : ""}</td>
          <td>${money(film.banked)}</td><td>${money(sim.medians[filmIndex])}</td>
          <td>${money(sim.low[filmIndex])}–${money(sim.high[filmIndex])}</td>
          <td class="${sim.top10Prob[filmIndex] >= .5 ? "prob-strong" : ""}">${pct(sim.top10Prob[filmIndex])}</td>
          <td>${pct(sim.rankProb[filmIndex][0])}</td></tr>`;
      }).join("")}</tbody></table>`;

    const warnings = data.films.map((film, index) => ({
      film, index, ratio: film.banked > 0 ? sim.medians[index] / film.banked : 0,
    })).filter((item) => item.ratio > 2).sort((a, b) => b.ratio - a.ratio);
    $("warnings").innerHTML = warnings.length ? `<aside class="warning">
      <strong>High remaining: median season total exceeds 2× banked</strong>
      <ul>${warnings.map(({ film, index, ratio }) =>
        `<li>${esc(film.title)} — ${money(film.banked)} banked, ${money(sim.medians[index])} median (${ratio.toFixed(2)}×)</li>`).join("")}</ul>
    </aside>` : "";
  }

  function competitiveIndices(sim) {
    const keep = new Set(sim.order.slice(0, 20));
    sim.top10Prob.forEach((probability, index) => { if (probability > .01) keep.add(index); });
    return sim.order.filter((index) => keep.has(index));
  }

  function renderHeatmap(data, sim) {
    const indices = competitiveIndices(sim);
    const cellWidth = 38;
    const rowHeight = 25;
    const left = 270;
    const top = 46;
    const right = 74;
    const bottom = 46;
    const width = left + cellWidth * 10 + right;
    const height = top + rowHeight * indices.length + bottom;
    let svg = `<svg viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="heat-title">
      <title id="heat-title">Probability each competitive film finishes at ranks one through ten</title>
      <text x="${left}" y="21" class="svg-title">P(finish at rank r) · ${indices.length} of ${data.films.length} films</text>`;
    indices.forEach((filmIndex, row) => {
      const y = top + row * rowHeight;
      svg += `<text x="${left - 10}" y="${y + 17}" text-anchor="end" class="svg-label">${esc(data.films[filmIndex].title)}</text>`;
      sim.rankProb[filmIndex].forEach((probability, rank) => {
        const x = left + rank * cellWidth;
        svg += `<rect x="${x}" y="${y}" width="${cellWidth - 2}" height="${rowHeight - 2}" rx="1" fill="${viridis(probability)}"><title>${esc(data.films[filmIndex].title)} · #${rank + 1}: ${pct(probability)}</title></rect>`;
        if (probability >= .1) {
          svg += `<text x="${x + (cellWidth - 2) / 2}" y="${y + 16}" text-anchor="middle" class="svg-cell" fill="${probability > .58 ? "#171714" : "#fff"}">${Math.round(probability * 100)}</text>`;
        }
      });
    });
    for (let rank = 0; rank < 10; rank += 1) {
      svg += `<text x="${left + rank * cellWidth + (cellWidth - 2) / 2}" y="${top + indices.length * rowHeight + 19}" text-anchor="middle" class="svg-axis">${rank + 1}</text>`;
    }
    const barX = left + 10 * cellWidth + 22;
    const barHeight = indices.length * rowHeight;
    for (let i = 0; i < 40; i += 1) {
      const value = i / 39;
      svg += `<rect x="${barX}" y="${top + barHeight - (i + 1) * barHeight / 40}" width="14" height="${barHeight / 40 + 1}" fill="${viridis(value)}"/>`;
    }
    svg += `<text x="${barX + 20}" y="${top + 8}" class="svg-axis">100%</text>
      <text x="${barX + 20}" y="${top + barHeight}" class="svg-axis">0%</text>
      <style>.svg-title{font:700 14px Georgia,serif;fill:#171714}.svg-label{font:11px Avenir,sans-serif;fill:#35332e}.svg-axis{font:10px Avenir,sans-serif;fill:#716c62}.svg-cell{font:700 9px Avenir,sans-serif}</style></svg>`;
    $("heat-chart").innerHTML = svg;
  }

  function renderFan(data, sim) {
    const indices = sim.order.slice(0, 20);
    const width = 980;
    const left = 64;
    const right = 18;
    const top = 48;
    const plotHeight = 320;
    const bottom = 160;
    const plotWidth = width - left - right;
    const maxValue = Math.max(...indices.map((index) => sim.high[index])) * 1.06;
    const y = (value) => top + plotHeight - value / maxValue * plotHeight;
    const step = plotWidth / indices.length;
    let svg = `<svg viewBox="0 0 ${width} ${top + plotHeight + bottom}" role="img" aria-labelledby="fan-title">
      <title id="fan-title">Median and five to ninety-five percent season gross for the top twenty films</title>
      <text x="${left + plotWidth / 2}" y="20" text-anchor="middle" class="svg-title">Labor Day domestic gross · median + 5–95% band</text>`;
    for (let tick = 0; tick <= 4; tick += 1) {
      const value = maxValue * tick / 4;
      svg += `<line x1="${left}" y1="${y(value)}" x2="${width - right}" y2="${y(value)}" stroke="#ddd6c7"/>
        <text x="${left - 8}" y="${y(value) + 4}" text-anchor="end" class="svg-axis">$${Math.round(value / 1e6)}M</text>`;
    }
    indices.forEach((filmIndex, position) => {
      const x = left + (position + .5) * step;
      svg += `<line x1="${x}" y1="${y(sim.low[filmIndex])}" x2="${x}" y2="${y(sim.high[filmIndex])}" stroke="#8d897f" stroke-width="4" stroke-linecap="round">
          <title>${esc(data.films[filmIndex].title)}: ${money(sim.low[filmIndex])}–${money(sim.high[filmIndex])}</title></line>
        <circle cx="${x}" cy="${y(sim.medians[filmIndex])}" r="5" fill="#c93427"><title>Median ${money(sim.medians[filmIndex])}</title></circle>
        <text x="${x - 2}" y="${top + plotHeight + 15}" transform="rotate(48 ${x - 2} ${top + plotHeight + 15})" class="svg-label">${esc(data.films[filmIndex].title)}</text>`;
    });
    svg += `<style>.svg-title{font:700 15px Georgia,serif;fill:#171714}.svg-label{font:10px Avenir,sans-serif;fill:#35332e}.svg-axis{font:10px Avenir,sans-serif;fill:#716c62}</style></svg>`;
    $("fan-chart").innerHTML = svg;
  }

  function renderWinChart(data, sim) {
    const width = 900;
    const left = 55;
    const right = 20;
    const top = 42;
    const plotHeight = 220;
    const bottom = 56;
    const plotWidth = width - left - right;
    const step = plotWidth / data.players.length;
    const y = (value) => top + plotHeight - value * plotHeight;
    let svg = `<svg viewBox="0 0 ${width} ${top + plotHeight + bottom}" role="img" aria-labelledby="win-title">
      <title id="win-title">Sole and shared win probabilities by player</title>
      <text x="${left + plotWidth / 2}" y="19" text-anchor="middle" class="svg-title">Win probability</text>`;
    [0, .25, .5, .75, 1].forEach((value) => {
      svg += `<line x1="${left}" y1="${y(value)}" x2="${width - right}" y2="${y(value)}" stroke="#e0d9ca"/>
        <text x="${left - 8}" y="${y(value) + 4}" text-anchor="end" class="svg-axis">${Math.round(value * 100)}%</text>`;
    });
    data.players.forEach((player, index) => {
      const center = left + (index + .5) * step;
      const barWidth = Math.min(34, step * .3);
      const soleHeight = sim.winSole[index] * plotHeight;
      const sharedHeight = sim.winShared[index] * plotHeight;
      svg += `<rect x="${center - barWidth - 2}" y="${top + plotHeight - soleHeight}" width="${barWidth}" height="${soleHeight}" fill="#164b65"><title>${esc(player.name)} sole: ${pct(sim.winSole[index])}</title></rect>
        <rect x="${center + 2}" y="${top + plotHeight - sharedHeight}" width="${barWidth}" height="${sharedHeight}" fill="#c93427"><title>${esc(player.name)} win / tie: ${pct(sim.winShared[index])}</title></rect>
        <text x="${center}" y="${top + plotHeight + 22}" text-anchor="middle" class="svg-label">${esc(player.name)}</text>`;
    });
    svg += `<rect x="${width - 185}" y="7" width="10" height="10" fill="#164b65"/><text x="${width - 170}" y="16" class="svg-axis">sole</text>
      <rect x="${width - 115}" y="7" width="10" height="10" fill="#c93427"/><text x="${width - 100}" y="16" class="svg-axis">win / tie</text>
      <style>.svg-title{font:700 15px Georgia,serif;fill:#171714}.svg-label{font:11px Avenir,sans-serif;fill:#35332e}.svg-axis{font:10px Avenir,sans-serif;fill:#716c62}</style></svg>`;
    $("win-chart").innerHTML = svg;
  }

  function renderAll(data, assumptions, sim) {
    const statusLabel = sim.status === "final" ? "final"
      : sim.status === "refining" ? "refining"
        : "preview";
    renderSummary(assumptions, statusLabel);
    renderTelemetry(sim.telemetry);
    renderPlayers(data, sim);
    renderScenarios(data, sim);
    renderField(data, sim);
    renderWinChart(data, sim);
    renderHeatmap(data, sim);
    renderFan(data, sim);
    const draws = sim.telemetry?.draws ?? sim.n;
    const ms = sim.telemetry?.runtime_ms;
    $("status").textContent = ms != null
      ? `${statusLabel}: ${Number(draws).toLocaleString()} draws · ${Number(ms).toFixed(0)} ms`
      : `${statusLabel}: ${Number(draws).toLocaleString()} draws`;
    return sim;
  }

  function startViewer(data) {
    const assumptions = {};
    let generation = 0;
    let debounceTimer = null;
    let workerReady = false;
    const worker = new Worker("smw_engine_worker.js");

    const overridesFromAssumptions = () => {
      const overrides = {};
      data.controls.forEach((control) => {
        overrides[control.key] = assumptions[control.key];
      });
      return overrides;
    };

    const requestRun = () => {
      if (!workerReady) return;
      generation += 1;
      const gen = generation;
      worker.postMessage({ type: "cancel", generation: gen - 1 });
      worker.postMessage({
        type: "run",
        generation: gen,
        seed: data.seeds.default,
        n_draws: FINAL_DRAWS,
        overrides: overridesFromAssumptions(),
        quadrature: data.quadrature,
      });
      $("status").textContent = "Running preview…";
      renderTelemetry({
        status: "preview",
        draws: 0,
        eta_order: data.quadrature.eta,
        sigma_order: data.quadrature.sigma,
        runtime_ms: 0,
        seed: data.seeds.default,
        prior_version: data.prior_version,
        engine: "…",
      });
    };

    const schedule = () => {
      if (debounceTimer !== null) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        debounceTimer = null;
        requestRun();
      }, DEBOUNCE_MS);
    };

    worker.onmessage = (event) => {
      const msg = event.data;
      if (msg.type === "ready") {
        workerReady = true;
        $("method-note").textContent =
          `In-browser quadrature · ${msg.engine}` +
          (msg.wasm_present ? " · wasm binary present" : " · wasm missing");
        requestRun();
        return;
      }
      if (msg.type === "error") {
        console.error(msg);
        if (msg.generation != null && msg.generation !== generation) return;
        $("status").textContent = `Inference error: ${msg.message}`;
        return;
      }
      if (msg.type === "result") {
        if (msg.generation !== generation) return;
        window.SMWViewer.lastSimulation = renderAll(data, assumptions, msg);
      }
    };
    worker.onerror = (error) => {
      console.error(error);
      $("status").textContent = "Worker failed";
      $("controls").innerHTML = `<p class="error">Inference worker failed: ${esc(error.message || "unknown")}</p>`;
    };

    renderControls(data, assumptions, schedule);
    window.SMWViewer = {
      data,
      assumptions,
      worker,
      lastSimulation: null,
      requestRun,
    };
    worker.postMessage({ type: "init", data });
    $("status").textContent = "Starting inference worker…";
  }

  fetch("smw2026_data.json")
    .then((response) => {
      if (!response.ok) throw new Error(`data request failed (${response.status})`);
      return response.json();
    })
    .then((data) => {
      if (!data.schema_version || data.schema_version < 2) {
        throw new Error("viewer data is not a v2 input bundle — re-run export_viewer_data.jl");
      }
      const mastFilms = document.getElementById("mast-films");
      if (mastFilms) mastFilms.textContent = `${data.films.length} films`;
      startViewer(data);
    })
    .catch((error) => {
      console.error(error);
      $("controls").innerHTML = `<p class="error">Could not load viewer data: ${esc(error.message)}</p>`;
      $("status").textContent = "Viewer unavailable";
    });
}());
