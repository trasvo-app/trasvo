// Todo es mejora progresiva: sin JavaScript la página funciona igual.

// Cabecera con borde al bajar y menú en pantallas chicas.
const top = document.querySelector(".top");
if (top) {
  const onScroll = () => top.classList.toggle("is-scrolled", window.scrollY > 8);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
}
const menuBtn = document.querySelector(".menu-btn");
const nav = document.querySelector(".nav");
if (menuBtn && nav) {
  menuBtn.addEventListener("click", () => {
    const open = nav.classList.toggle("is-open");
    menuBtn.setAttribute("aria-expanded", String(open));
  });
}

// Botón principal según el sistema: en Android se ofrece el APK primero.
const isAndroid = /Android/i.test(navigator.userAgent);
if (isAndroid) {
  document.querySelectorAll("[data-cta]").forEach((group) => {
    const win = group.querySelector('[data-file="Trasvo-Setup-x64.exe"]');
    const apk = group.querySelector('[data-file="Trasvo.apk"]');
    if (!win || !apk) return;
    apk.classList.replace("btn--ghost", "btn--primary");
    win.classList.replace("btn--primary", "btn--ghost");
    group.prepend(apk);
  });
  document.querySelectorAll("[data-android-note]").forEach((el) => (el.hidden = false));
  document.querySelectorAll("[data-windows-note]").forEach((el) => (el.hidden = true));
}

// Versión, tamaños y SHA-256 desde release.json (lo escribe scripts/release.ps1).
const mb = (bytes) => (bytes / 1048576).toLocaleString("es", { maximumFractionDigits: bytes < 10485760 ? 1 : 0 }) + " MB";
fetch("assets/release.json")
  .then((r) => (r.ok ? r.json() : Promise.reject()))
  .then((release) => {
    document.querySelectorAll("[data-version]").forEach((el) => (el.textContent = release.version));
    for (const file of release.files) {
      document.querySelectorAll(`[data-size="${file.name}"]`).forEach((el) => (el.textContent = mb(file.size)));
      document.querySelectorAll(`[data-hash="${file.name}"]`).forEach((el) => {
        el.textContent = file.sha256;
        el.closest(".hash")?.removeAttribute("hidden");
      });
    }
  })
  .catch(() => {});

// Copiar el hash.
document.addEventListener("click", async (e) => {
  const btn = e.target.closest("[data-copy]");
  if (!btn) return;
  const text = document.querySelector(`[data-hash="${btn.dataset.copy}"]`)?.textContent;
  if (!text) return;
  try {
    await navigator.clipboard.writeText(text);
    const before = btn.textContent;
    btn.textContent = "Copiado";
    setTimeout(() => (btn.textContent = before), 1600);
  } catch {}
});

// Índice lateral: marca la sección visible.
const tocLinks = [...document.querySelectorAll(".toc a")];
if (tocLinks.length && "IntersectionObserver" in window) {
  const byId = new Map(tocLinks.map((a) => [a.hash.slice(1), a]));
  const io = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        tocLinks.forEach((a) => a.classList.remove("is-active"));
        byId.get(entry.target.id)?.classList.add("is-active");
      }
    },
    { rootMargin: "-20% 0px -70% 0px" },
  );
  byId.forEach((_, id) => {
    const el = document.getElementById(id);
    if (el) io.observe(el);
  });
}

document.querySelectorAll("[data-print]").forEach((b) => b.addEventListener("click", () => window.print()));
