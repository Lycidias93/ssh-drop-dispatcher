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
      ["Readiness", "test on demand"],
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
      const response = await fetch("/api/v1/inventory?name=targets", {
        credentials: "same-origin",
        cache: "no-store",
      });
      if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
      const envelope = await response.json();
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

  refresh.addEventListener("click", loadTargets);
  loadTargets();
})();
