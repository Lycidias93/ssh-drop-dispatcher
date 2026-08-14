(() => {
  "use strict";

  const cards = document.getElementById("sddTargetCards");
  const refresh = document.getElementById("sddTargetRefresh");
  if (!cards || !refresh) return;

  function node(tag, className, text) {
    const item = document.createElement(tag);
    if (className) item.className = className;
    if (text !== undefined) item.textContent = text;
    return item;
  }

  async function apiJSON(path, options = {}) {
    const headers = new Headers(options.headers || {});
    if (options.body !== undefined) {
      headers.set("Content-Type", "application/json");
      headers.set("X-WebUI-Request", "1");
    }
    const response = await fetch(path, { ...options, headers, credentials: "same-origin", cache: "no-store" });
    if (!response.ok) {
      let message = `${response.status} ${response.statusText}`;
      try { message = (await response.json()).error || message; } catch { /* keep HTTP status */ }
      throw new Error(message);
    }
    return response.json();
  }

  function normalizedEnabled(value) {
    return value === 1 || value === true || String(value) === "1" || String(value).toLowerCase() === "true";
  }

  function targetCard(item) {
    const enabled = normalizedEnabled(item.enabled);
    const card = node("article", "card sdd-target-card");
    const top = node("div", "sdd-target-top");
    top.append(
      node("strong", "sdd-target-name", item.name || "unknown"),
      node("span", `badge ${enabled ? "good" : "muted"}`, enabled ? "enabled" : "disabled")
    );

    const details = node("dl", "sdd-target-details");
    const pairs = [
      ["Shell", item.shell || "unknown"],
      ["SCP", item.scp || "default"],
      ["Readiness", enabled ? "included in smoke" : "disabled"],
    ];
    for (const [label, value] of pairs) {
      details.append(node("dt", "", label), node("dd", "", String(value)));
    }
    card.append(top, details);
    return card;
  }

  async function loadTargets() {
    refresh.disabled = true;
    cards.setAttribute("aria-busy", "true");
    try {
      const envelope = await apiJSON("/api/v1/inventory?name=targets");
      const inventory = envelope && envelope.data ? envelope.data : envelope;
      const items = Array.isArray(inventory?.items) ? inventory.items : [];
      cards.replaceChildren(...(items.length
        ? items.map(targetCard)
        : [node("p", "muted", "No configured targets reported.")]));
    } catch (error) {
      cards.replaceChildren(node("p", "muted", `Target matrix unavailable: ${error.message || error}`));
    } finally {
      cards.removeAttribute("aria-busy");
      refresh.disabled = false;
    }
  }

  const targetOutput = node("pre", "job-output", "No readiness smoke run in this browser session.");
  targetOutput.setAttribute("aria-live", "polite");
  const smoke = node("button", "caution", "Test all enabled targets");
  smoke.type = "button";
  refresh.parentElement?.append(smoke);
  cards.parentElement?.append(targetOutput);

  async function waitForJob(id) {
    for (;;) {
      const envelope = await apiJSON(`/api/v1/jobs/${encodeURIComponent(id)}`);
      const job = envelope.data || envelope;
      targetOutput.textContent = `Target smoke: ${job.status || "unknown"}`;
      if (!["queued", "running"].includes(job.status)) return job;
      await new Promise(resolve => window.setTimeout(resolve, 1400));
    }
  }

  async function jobOutput(id, stream) {
    const envelope = await apiJSON(`/api/v1/jobs/${encodeURIComponent(id)}/output?stream=${stream}&offset=0&limit=65536`);
    return envelope.data?.text || "";
  }

  smoke.addEventListener("click", async () => {
    smoke.disabled = true;
    targetOutput.textContent = "Starting readiness smoke for all enabled targets…";
    try {
      const started = await apiJSON("/api/v1/jobs", {
        method: "POST",
        body: JSON.stringify({ name: "target-test-all-enabled" }),
      });
      const id = started.data?.id;
      if (!id) throw new Error("job id missing");
      const job = await waitForJob(id);
      const stdout = await jobOutput(id, "stdout");
      const stderr = await jobOutput(id, "stderr");
      targetOutput.textContent = `${stdout}${stderr ? `\n--- stderr ---\n${stderr}` : ""}` || `Target smoke ${job.status}.`;
      await loadTargets();
    } catch (error) {
      targetOutput.textContent = `Target smoke failed: ${error.message || error}`;
    } finally {
      smoke.disabled = false;
    }
  });

  function activateTab(button) {
    document.querySelectorAll(".tab").forEach(item => item.classList.remove("active"));
    document.querySelectorAll(".tab-panel").forEach(item => item.classList.remove("active"));
    button.classList.add("active");
    document.getElementById(button.dataset.panel)?.classList.add("active");
    button.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" });
  }

  function addSortifyPanel() {
    const tabs = document.querySelector(".tabs");
    const shell = document.querySelector(".shell");
    const safety = document.getElementById("safetyPanel");
    if (!tabs || !shell || !safety || document.getElementById("sddSortifyPanel")) return;

    const button = node("button", "tab", "Sortify");
    button.type = "button";
    button.dataset.panel = "sddSortifyPanel";
    button.addEventListener("click", () => activateTab(button));
    tabs.insertBefore(button, [...tabs.children].find(item => item.dataset.panel === "safetyPanel") || null);

    const panel = node("section", "panel tab-panel");
    panel.id = "sddSortifyPanel";
    const heading = node("div", "panel-heading");
    const headingText = node("div");
    headingText.append(
      node("h2", "", "Sortify companion"),
      node("p", "", "Read-only shared status. Sortify Dispatch remains authoritative for its own settings.")
    );
    const reload = node("button", "", "Refresh Sortify");
    reload.type = "button";
    heading.append(headingText, reload);
    const status = node("div", "cards");
    const note = node("p", "muted", "Changes belong in the Sortify WebUI; SSH Drop Dispatcher does not duplicate-write Sortify configuration.");
    panel.append(heading, status, note);
    shell.insertBefore(panel, safety);

    async function loadSortify() {
      reload.disabled = true;
      try {
        const envelope = await apiJSON("/api/v1/inventory?name=sortify");
        const inventory = envelope.data || envelope;
        const item = Array.isArray(inventory?.items) ? inventory.items[0] : null;
        if (!item) {
          status.replaceChildren(node("p", "muted", "Sortify status unavailable."));
          return;
        }
        const values = [
          ["Module", item.present === "yes" ? `installed · ${item.version}` : "not installed"],
          ["Dispatcher link", item.dispatcher_integration],
          ["Sort mode", item.sort_mode],
          ["Protected hold", item.hold_protected === "1" ? "on" : item.hold_protected === "0" ? "off" : item.hold_protected],
          ["Normal sorting", item.normal_sort === "1" ? "on" : item.normal_sort === "0" ? "off" : item.normal_sort],
          ["Duplicate mode", item.duplicate_mode],
          ["Interval", item.interval_seconds === "unknown" ? "unknown" : `${item.interval_seconds}s`],
        ];
        status.replaceChildren(...values.map(([label, value]) => {
          const card = node("div", "card");
          card.append(node("div", "label", label), node("div", "value", String(value ?? "unknown")));
          return card;
        }));
      } catch (error) {
        status.replaceChildren(node("p", "muted", `Sortify status unavailable: ${error.message || error}`));
      } finally {
        reload.disabled = false;
      }
    }

    reload.addEventListener("click", loadSortify);
    loadSortify();
  }

  refresh.addEventListener("click", loadTargets);
  addSortifyPanel();
  loadTargets();
})();
