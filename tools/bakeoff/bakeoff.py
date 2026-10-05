#!/usr/bin/env python3
"""Identification engine bake-off for HobbyLens (week 1 of the build plan).

Runs every labelled local photo through each engine and reports, per engine:
  * top-1 and top-3 accuracy at species and at genus level, with 95% Wilson intervals
  * the same broken down by photo group (e.g. orchids, roses)
  * median and 90th-percentile response time
  * cost per call and for the whole run
  * how often the engine returned a Bangla common name
and applies the decision rule from the plan: the cheapest engine reaching 85% top-3 (species)
whose 90th-percentile time is at most 4 s.

Photos go through the same preparation as the app (longest edge 1024 px, JPEG quality 80).

Usage
  python3 bakeoff.py --photos photos/ --labels labels.csv --engines plantid,plantnet,gemini,anthropic
  python3 bakeoff.py --demo            # offline self-check with a mock engine

labels.csv columns (header required):
  file            photo file name inside --photos
  kind            plant | cat | dog | bird
  expected        accepted scientific name (or breed), e.g. "Epipremnum aureum"
  also_accept     optional, extra accepted names separated by |, e.g. "Scindapsus aureus"
  group           optional label for the breakdown, e.g. "orchid", "rose", "foliage"

API keys come from the environment: PLANTID_API_KEY, PLANTNET_API_KEY, GEMINI_API_KEY,
ANTHROPIC_API_KEY. Prices per call can be overridden with --price engine=usd.
"""
from __future__ import annotations

import argparse
import base64
import csv
import io
import json
import math
import os
import re
import statistics
import sys
import time
import unicodedata
from dataclasses import dataclass, field
from typing import Callable

# Default prices per call in USD. Plant.id: EUR 0.05 at the smallest tier (x1.125 USD/EUR).
# Pl@ntNet: free tier. Vision models: ~1,800 input + 400 output tokens per photo.
DEFAULT_PRICES = {
    "plantid": 0.05625,
    "plantnet": 0.0,
    "gemini": (1800 * 0.30 + 400 * 2.50) / 1e6,
    "anthropic": (1800 * 1.00 + 400 * 5.00) / 1e6,
    "mock": 0.0,
}
TARGET_TOP3 = 0.85
TARGET_P90_SECONDS = 4.0


# ---------------------------------------------------------------------------
# Names
# ---------------------------------------------------------------------------

def normalise(name: str) -> str:
    """Lower-case scientific name without author, hybrid signs or cultivar quotes."""
    n = unicodedata.normalize("NFKC", name).lower().strip()
    n = n.replace("×", " ").replace(" x ", " ")
    n = re.sub(r"'[^']*'|\"[^\"]*\"", " ", n)  # cultivar names
    n = re.sub(r"\(.*?\)", " ", n)
    n = re.sub(r"[^a-z\s-]", " ", n)
    return re.sub(r"\s+", " ", n).strip()


def species_key(name: str) -> str:
    return " ".join(normalise(name).split()[:2])


def genus_key(name: str) -> str:
    parts = normalise(name).split()
    return parts[0] if parts else ""


def has_bangla(text: str) -> bool:
    return any("ঀ" <= ch <= "৿" for ch in text)


# ---------------------------------------------------------------------------
# Engines: each returns (candidate names best first, common names, raw json)
# ---------------------------------------------------------------------------

@dataclass
class EngineAnswer:
    names: list[str]
    common_names: list[str] = field(default_factory=list)
    error: str | None = None


def _post(url: str, *, headers: dict, json_body=None, files=None, data=None, timeout=30):
    import requests  # imported lazily so --demo needs no third-party packages
    r = requests.post(url, headers=headers, json=json_body, files=files, data=data, timeout=timeout)
    if r.status_code == 404:
        return r.status_code, {}
    r.raise_for_status()
    return r.status_code, r.json()


def engine_plantid(jpeg: bytes, kind: str) -> EngineAnswer:
    key = os.environ["PLANTID_API_KEY"]
    base = os.environ.get("PLANTID_BASE_URL", "https://plant.id/api/v3").rstrip("/")
    _, body = _post(
        f"{base}/identification?details=common_names&language=bn,en",
        headers={"Api-Key": key},
        json_body={"images": ["data:image/jpeg;base64," + base64.b64encode(jpeg).decode()], "similar_images": False},
    )
    sugg = body.get("result", {}).get("classification", {}).get("suggestions", [])
    commons = [c for s in sugg[:3] for c in (s.get("details", {}).get("common_names") or [])]
    return EngineAnswer([s.get("name", "") for s in sugg], commons)


def engine_plantnet(jpeg: bytes, kind: str) -> EngineAnswer:
    key = os.environ["PLANTNET_API_KEY"]
    status, body = _post(
        f"https://my-api.plantnet.org/v2/identify/all?api-key={key}&lang=bn&nb-results=5",
        headers={},
        files={"images": ("photo.jpg", jpeg, "image/jpeg")},
        data={"organs": "auto"},
    )
    if status == 404:
        return EngineAnswer([])
    res = body.get("results", [])
    commons = [c for r in res[:3] for c in (r.get("species", {}).get("commonNames") or [])]
    return EngineAnswer([r.get("species", {}).get("scientificNameWithoutAuthor", "") for r in res], commons)


VISION_PROMPT = (
    "Identify the {kind} in this photo. Reply with JSON only: "
    '{{"candidates":[{{"name":"scientific name or breed","common_name_bn":"Bangla common name if one exists"}}]}} '
    "with at most 3 candidates, best first."
)


def _parse_vision(text: str) -> EngineAnswer:
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        return EngineAnswer([], error="no JSON in reply")
    data = json.loads(m.group(0))
    cands = data.get("candidates", [])
    return EngineAnswer([c.get("name", "") for c in cands], [c.get("common_name_bn", "") for c in cands])


def engine_gemini(jpeg: bytes, kind: str) -> EngineAnswer:
    model = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
    _, body = _post(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        headers={"x-goog-api-key": os.environ["GEMINI_API_KEY"]},
        json_body={
            "contents": [{"parts": [
                {"inline_data": {"mime_type": "image/jpeg", "data": base64.b64encode(jpeg).decode()}},
                {"text": VISION_PROMPT.format(kind=kind)},
            ]}],
            "generationConfig": {"responseMimeType": "application/json", "temperature": 0},
        },
    )
    text = "".join(p.get("text", "") for p in body.get("candidates", [{}])[0].get("content", {}).get("parts", []))
    return _parse_vision(text)


def engine_anthropic(jpeg: bytes, kind: str) -> EngineAnswer:
    _, body = _post(
        "https://api.anthropic.com/v1/messages",
        headers={"x-api-key": os.environ["ANTHROPIC_API_KEY"], "anthropic-version": "2023-06-01"},
        json_body={
            "model": os.environ.get("ANTHROPIC_MODEL", "claude-haiku-4-5"),
            "max_tokens": 400,
            "messages": [{"role": "user", "content": [
                {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": base64.b64encode(jpeg).decode()}},
                {"type": "text", "text": VISION_PROMPT.format(kind=kind)},
            ]}],
        },
    )
    text = "".join(b.get("text", "") for b in body.get("content", []) if b.get("type") == "text")
    return _parse_vision(text)


def make_mock(answers: dict[str, list[str]]) -> Callable[[bytes, str], EngineAnswer]:
    """Answers by photo content hash; used by --demo and the tests."""
    def run(jpeg: bytes, kind: str) -> EngineAnswer:
        return EngineAnswer(answers.get(jpeg.decode(errors="ignore"), []), ["মানি প্ল্যান্ট"])
    return run


ENGINES: dict[str, Callable[[bytes, str], EngineAnswer]] = {
    "plantid": engine_plantid,
    "plantnet": engine_plantnet,
    "gemini": engine_gemini,
    "anthropic": engine_anthropic,
}


# ---------------------------------------------------------------------------
# Photo preparation (same as the app)
# ---------------------------------------------------------------------------

def prepare(path: str) -> bytes:
    from PIL import Image, ImageOps  # lazily imported for the same reason as requests
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im).convert("RGB")
        im.thumbnail((1024, 1024))
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=80)
        return buf.getvalue()


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------

@dataclass
class Photo:
    file: str
    kind: str
    accepted: list[str]
    group: str


@dataclass
class Row:
    engine: str
    photo: Photo
    names: list[str]
    seconds: float
    bangla: bool
    error: str | None

    def hit(self, k: int, level: str) -> bool:
        key = species_key if level == "species" else genus_key
        want = {key(a) for a in self.photo.accepted}
        return any(key(n) in want for n in self.names[:k] if n)


def wilson(successes: int, n: int, z: float = 1.96) -> tuple[float, float]:
    if n == 0:
        return (0.0, 0.0)
    p = successes / n
    centre = (p + z * z / (2 * n)) / (1 + z * z / n)
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
    return (max(0.0, centre - half), min(1.0, centre + half))


def percentile(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    idx = max(0, min(len(s) - 1, math.ceil(q * len(s)) - 1))
    return s[idx]


def summarise(rows: list[Row], prices: dict[str, float]) -> list[dict]:
    out = []
    for engine in sorted({r.engine for r in rows}):
        rs = [r for r in rows if r.engine == engine]
        n = len(rs)
        stats = {"engine": engine, "photos": n, "errors": sum(1 for r in rs if r.error)}
        for level in ("species", "genus"):
            for k in (1, 3):
                hits = sum(1 for r in rs if r.hit(k, level))
                lo, hi = wilson(hits, n)
                stats[f"top{k}_{level}"] = hits / n if n else 0.0
                stats[f"top{k}_{level}_ci"] = (round(lo, 3), round(hi, 3))
        times = [r.seconds for r in rs if not r.error]
        stats["median_s"] = round(statistics.median(times), 2) if times else None
        stats["p90_s"] = round(percentile(times, 0.9), 2) if times else None
        stats["bangla_name_rate"] = sum(1 for r in rs if r.bangla) / n if n else 0.0
        stats["usd_per_call"] = prices.get(engine, 0.0)
        stats["usd_total"] = round(prices.get(engine, 0.0) * n, 4)
        stats["groups"] = {}
        for g in sorted({r.photo.group for r in rs}):
            gr = [r for r in rs if r.photo.group == g]
            stats["groups"][g] = {"photos": len(gr), "top3_species": sum(1 for r in gr if r.hit(3, "species")) / len(gr)}
        stats["passes"] = (
            stats["top3_species"] >= TARGET_TOP3 and stats["p90_s"] is not None and stats["p90_s"] <= TARGET_P90_SECONDS
        )
        out.append(stats)
    return out


def decide(summary: list[dict]) -> dict | None:
    passing = [s for s in summary if s["passes"]]
    return min(passing, key=lambda s: (s["usd_per_call"], -s["top3_species"])) if passing else None


def report_markdown(summary: list[dict], winner: dict | None) -> str:
    pct = lambda v: f"{v * 100:.0f}%"
    lines = [
        "# Engine bake-off results",
        "",
        f"Decision rule: cheapest engine with top-3 species accuracy of at least {pct(TARGET_TOP3)} "
        f"and a 90th-percentile response time of at most {TARGET_P90_SECONDS:.0f} s.",
        "",
        f"**Recommended engine: {winner['engine']}**" if winner else "**No engine met both targets.**",
        "",
        "| Engine | Photos | Top-1 species | Top-3 species (95% CI) | Top-3 genus | Median s | P90 s | Bangla names | USD per call | Passes |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for s in summary:
        lo, hi = s["top3_species_ci"]
        lines.append(
            f"| {s['engine']} | {s['photos']} | {pct(s['top1_species'])} | {pct(s['top3_species'])} ({pct(lo)}–{pct(hi)}) | "
            f"{pct(s['top3_genus'])} | {s['median_s']} | {s['p90_s']} | {pct(s['bangla_name_rate'])} | "
            f"{s['usd_per_call']:.4f} | {'yes' if s['passes'] else 'no'} |"
        )
    lines += ["", "## Top-3 species accuracy by photo group", ""]
    groups = sorted({g for s in summary for g in s["groups"]})
    lines.append("| Group | " + " | ".join(s["engine"] for s in summary) + " |")
    lines.append("| --- |" + " --- |" * len(summary))
    for g in groups:
        cells = [pct(s["groups"][g]["top3_species"]) if g in s["groups"] else "–" for s in summary]
        lines.append(f"| {g} | " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------

def load_labels(path: str) -> list[Photo]:
    photos = []
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            accepted = [row["expected"]] + [a for a in (row.get("also_accept") or "").split("|") if a.strip()]
            photos.append(Photo(row["file"], row.get("kind") or "plant", accepted, row.get("group") or "all"))
    return photos


def run(photos: list[Photo], loader: Callable[[Photo], bytes], engines: dict[str, Callable], pause: float = 0.0) -> list[Row]:
    rows = []
    for photo in photos:
        jpeg = loader(photo)
        for name, fn in engines.items():
            if name in ("plantid", "plantnet") and photo.kind != "plant":
                continue  # plant engines are not asked about animals
            t0 = time.perf_counter()
            try:
                ans = fn(jpeg, photo.kind)
                err = ans.error
            except Exception as e:  # noqa: BLE001 - every failure is recorded, not fatal
                ans, err = EngineAnswer([]), f"{type(e).__name__}: {e}"
            rows.append(Row(name, photo, ans.names, time.perf_counter() - t0, any(has_bangla(c) for c in ans.common_names), err))
            if pause:
                time.sleep(pause)
    return rows


def write_outputs(rows: list[Row], summary: list[dict], winner: dict | None, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "per_photo.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["engine", "file", "group", "expected", "answer_1", "answer_2", "answer_3", "top1_species", "top3_species",
                    "top3_genus", "seconds", "bangla_name", "error"])
        for r in rows:
            names = (r.names + ["", "", ""])[:3]
            w.writerow([r.engine, r.photo.file, r.photo.group, r.photo.accepted[0], *names, r.hit(1, "species"),
                        r.hit(3, "species"), r.hit(3, "genus"), round(r.seconds, 3), r.bangla, r.error or ""])
    with open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8") as f:
        json.dump({"summary": summary, "recommended": winner["engine"] if winner else None}, f, indent=2, ensure_ascii=False)
    with open(os.path.join(out_dir, "report.md"), "w", encoding="utf-8") as f:
        f.write(report_markdown(summary, winner))


def demo() -> int:
    """Offline self-check: two mock engines, one good and one poor."""
    photos = [Photo(f"p{i}.jpg", "plant", ["Epipremnum aureum", "Scindapsus aureus"], "foliage" if i % 2 else "orchid") for i in range(20)]
    good = make_mock({f"p{i}.jpg": ["Scindapsus aureus (L.) Engl."] for i in range(20)})
    poor = make_mock({f"p{i}.jpg": ["Philodendron hederaceum", "Epipremnum pinnatum"] for i in range(20)})
    rows = run(photos, lambda p: p.file.encode(), {"good": good, "poor": poor})
    summary = summarise(rows, {"good": 0.05, "poor": 0.0})
    winner = decide(summary)
    print(report_markdown(summary, winner))
    return 0 if winner and winner["engine"] == "good" else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--photos", help="folder of labelled photos")
    ap.add_argument("--labels", help="labels.csv")
    ap.add_argument("--engines", default="plantid,plantnet,gemini", help="comma-separated: " + ",".join(ENGINES))
    ap.add_argument("--out", default="results", help="output folder")
    ap.add_argument("--price", action="append", default=[], help="override price, e.g. --price plantid=0.03375")
    ap.add_argument("--pause", type=float, default=0.5, help="seconds between calls (rate limits)")
    ap.add_argument("--demo", action="store_true", help="offline self-check with mock engines")
    args = ap.parse_args(argv)

    if args.demo:
        return demo()
    if not args.photos or not args.labels:
        ap.error("--photos and --labels are required (or use --demo)")

    names = [e.strip() for e in args.engines.split(",") if e.strip()]
    unknown = [e for e in names if e not in ENGINES]
    if unknown:
        ap.error(f"unknown engine(s): {', '.join(unknown)}")
    prices = dict(DEFAULT_PRICES)
    for p in args.price:
        k, v = p.split("=", 1)
        prices[k] = float(v)

    photos = load_labels(args.labels)
    missing = [p.file for p in photos if not os.path.exists(os.path.join(args.photos, p.file))]
    if missing:
        print(f"missing photos: {', '.join(missing[:10])}", file=sys.stderr)
        return 2
    rows = run(photos, lambda p: prepare(os.path.join(args.photos, p.file)), {n: ENGINES[n] for n in names}, args.pause)
    summary = summarise(rows, prices)
    winner = decide(summary)
    write_outputs(rows, summary, winner, args.out)
    print(report_markdown(summary, winner))
    print(f"Wrote {args.out}/report.md, summary.json and per_photo.csv")
    return 0


if __name__ == "__main__":
    sys.exit(main())
