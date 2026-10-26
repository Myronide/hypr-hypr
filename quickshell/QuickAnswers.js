.pragma library
// Schnelle Antworten für die Suche: Rechnen (mit Funktionen), Prozent, Einheiten umrechnen.

const FUNCS = { sqrt: "Math.sqrt", sin: "Math.sin", cos: "Math.cos", tan: "Math.tan", log: "Math.log10", ln: "Math.log", abs: "Math.abs",
                round: "Math.round", floor: "Math.floor", ceil: "Math.ceil", exp: "Math.exp", pi: "Math.PI", e: "Math.E" };

function fmt(v) {
    if (!isFinite(v)) return null;
    const r = Math.abs(v) >= 1e12 || (Math.abs(v) < 1e-6 && v !== 0) ? v.toExponential(6) : String(Math.round(v * 1e10) / 1e10);
    return r.replace(".", ",");
}

function calc(q) {
    let t = q.trim().toLowerCase();
    if (t === "") return null;
    // „20% von 150“ und „150 + 20%“
    let m = t.match(/^([\d.,]+)\s*%\s*(?:von|of)\s*([\d.,]+)$/);
    if (m) { const v = parseFloat(m[1].replace(",", ".")) / 100 * parseFloat(m[2].replace(",", ".")); return fmt(v); }
    t = t.replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, ":").replace(/:/g, "/").replace(/\^/g, "**").replace(/(\d)\s*x\s*(\d)/g, "$1*$2");
    t = t.replace(/(\d+(?:\.\d+)?)\s*([+\-])\s*(\d+(?:\.\d+)?)\s*%/g, "($1$2$1*$3/100)");
    t = t.replace(/(\d+(?:\.\d+)?)\s*%/g, "($1/100)");
    // nur Zahlen, Operatoren, Klammern und bekannte Funktionen zulassen
    const words = t.match(/[a-z]+/g) || [];
    for (const w of words) if (!(w in FUNCS)) return null;
    if (!/[(+\-*/]/.test(t.replace(/^-/, ""))) return null;          // ohne Rechenzeichen ist es keine Rechnung (z. B. "e" oder "12")
    if (!/^[0-9a-z+\-*/().\s]+$/.test(t)) return null;
    t = t.replace(/[a-z]+/g, w => FUNCS[w]);
    try {
        const v = Function('"use strict"; return (' + t + ")")();
        if (typeof v === "number") return fmt(v);
    } catch (e) {}
    return null;
}

// ---- Einheiten: Faktor zur Basiseinheit ----
const U = {
    length: { base: "m", u: { mm: 0.001, cm: 0.01, m: 1, km: 1000, zoll: 0.0254, inch: 0.0254, in: 0.0254, ft: 0.3048, fuß: 0.3048, yd: 0.9144, mi: 1609.344, meile: 1609.344, meilen: 1609.344 } },
    mass: { base: "kg", u: { mg: 1e-6, g: 0.001, kg: 1, t: 1000, lb: 0.45359237, pfund: 0.5, oz: 0.028349523 } },
    data: { base: "b", u: { b: 1, byte: 1, kb: 1000, mb: 1e6, gb: 1e9, tb: 1e12, kib: 1024, mib: 1048576, gib: 1073741824, tib: 1099511627776 } },
    time: { base: "s", u: { ms: 0.001, s: 1, sek: 1, min: 60, h: 3600, std: 3600, d: 86400, tag: 86400, tage: 86400, woche: 604800, wochen: 604800 } },
    volume: { base: "l", u: { ml: 0.001, cl: 0.01, dl: 0.1, l: 1, gal: 3.785411784, floz: 0.0295735 } },
    speed: { base: "ms", u: { ms: 1, "m/s": 1, kmh: 1 / 3.6, "km/h": 1 / 3.6, mph: 0.44704, kn: 0.514444 } },
    area: { base: "m2", u: { m2: 1, qm: 1, km2: 1e6, ha: 10000, cm2: 0.0001, ft2: 0.09290304, acre: 4046.8564224 } },
};
const TEMP = ["c", "f", "k", "°c", "°f"];

function toTemp(v, from, to) {
    from = from.replace("°", ""); to = to.replace("°", "");
    const c = from === "c" ? v : (from === "f" ? (v - 32) * 5 / 9 : v - 273.15);
    return to === "c" ? c : (to === "f" ? c * 9 / 5 + 32 : c + 273.15);
}

function convert(q) {
    const m = q.trim().toLowerCase().replace(/,/g, ".").match(/^(-?[\d.]+)\s*([a-z°\/²2µ]+)\s+(?:in|to|nach|zu|->|=|als)\s+([a-z°\/²2µ]+)$/);
    if (!m) return null;
    const v = parseFloat(m[1]); if (isNaN(v)) return null;
    const a = m[2].replace("²", "2"), b = m[3].replace("²", "2");
    if (TEMP.indexOf(a) >= 0 && TEMP.indexOf(b) >= 0) {
        const r = toTemp(v, a, b); return fmt(r) + " " + (b.startsWith("°") ? b.toUpperCase() : "°" + b.toUpperCase());
    }
    for (const k in U) {
        const t = U[k].u;
        if (a in t && b in t) { const r = v * t[a] / t[b]; return fmt(r) + " " + m[3]; }
    }
    return null;
}
