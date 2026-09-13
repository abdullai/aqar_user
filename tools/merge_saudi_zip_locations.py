#!/usr/bin/env python3
"""Union SPL locations + Saudi-Arabia-Cities zip into app JSON.

Places (cities, villages, hijras, centers) are listed under official
governorates (nearest seat in the same region). District names are stored
bilingual: Arabic lists under Arabic city keys, English under English keys.
Polygon boundaries are not imported (form fields need names, not 51MB GeoJSON).
"""

from __future__ import annotations

import json
import math
import re
import zipfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ZIP_PATH = Path(r"c:\Users\2023\Downloads\Saudi-Arabia-Cities-Based-on-Regions-master.zip")
OUT_MAIN = ROOT / "assets" / "data" / "saudi_locations.json"
OUT_EXTRA = ROOT / "assets" / "data" / "saudi_locations_extra.json"
OUT_DISTRICTS = ROOT / "assets" / "data" / "saudi_districts.json"

REGION_LABELS = [
    ("riyadh", "منطقة الرياض", "Riyadh"),
    ("makkah", "منطقة مكة المكرمة", "Makkah"),
    ("madinah", "منطقة المدينة المنورة", "Madinah"),
    ("qassim", "منطقة القصيم", "Qassim"),
    ("eastern", "المنطقة الشرقية", "Eastern Province"),
    ("asir", "منطقة عسير", "Asir"),
    ("tabuk", "منطقة تبوك", "Tabuk"),
    ("hail", "منطقة حائل", "Hail"),
    ("northern", "منطقة الحدود الشمالية", "Northern Borders"),
    ("jazan", "منطقة جازان", "Jazan"),
    ("najran", "منطقة نجران", "Najran"),
    ("bahah", "منطقة الباحة", "Bahah"),
    ("jawf", "منطقة الجوف", "Jawf"),
]

GOVS: dict[str, list[tuple[str, str]]] = {
    "riyadh": [
        ("الرياض", "Riyadh"), ("الدرعية", "Diriyah"), ("الخرج", "Al Kharj"),
        ("الدوادمي", "Al Duwadimi"), ("المجمعة", "Al Majmaah"),
        ("القويعية", "Al Quwayiyah"), ("وادي الدواسر", "Wadi Al Dawasir"),
        ("الأفلاج", "Aflaj"), ("الزلفي", "Az Zulfi"), ("شقراء", "Shaqra"),
        ("حوطة بني تميم", "Hawtat Bani Tamim"), ("عفيف", "Afif"),
        ("السليل", "As Sulayyil"), ("ضرما", "Duruma"),
        ("المزاحمية", "Al Muzahimiyah"), ("رماح", "Rumah"), ("ثادق", "Thadiq"),
        ("حريملاء", "Huraymila"), ("الحريق", "Al Hariq"), ("الغاط", "Al Ghat"),
        ("مرات", "Marat"),
    ],
    "makkah": [
        ("مكة المكرمة", "Makkah"), ("جدة", "Jeddah"), ("الطائف", "Taif"),
        ("القنفذة", "Al Qunfudhah"), ("الليث", "Al Lith"), ("رابغ", "Rabigh"),
        ("خليص", "Khulais"), ("الكامل", "Al Kamil"), ("أضم", "Adham"),
        ("رنية", "Ranyah"), ("تربة", "Turbah"), ("الخرمة", "Al Khurmah"),
        ("المويه", "Al Muwayh"), ("ميسان", "Maysan"), ("بحرة", "Bahrah"),
    ],
    "madinah": [
        ("المدينة المنورة", "Madinah"), ("ينبع", "Yanbu"), ("العلا", "Al Ula"),
        ("مهد الذهب", "Mahd Al Dhahab"), ("الحناكية", "Al Hinakiyah"),
        ("بدر", "Badr"), ("خيبر", "Khaybar"), ("العيص", "Al Iss"),
        ("وادي الفرع", "Wadi Al Fara"),
    ],
    "qassim": [
        ("بريدة", "Buraydah"), ("عنيزة", "Unayzah"), ("الرس", "Ar Rass"),
        ("المذنب", "Al Mithnab"), ("البكيرية", "Al Bukayriyah"),
        ("البدائع", "Al Badai"), ("الأسياح", "Al Asyah"),
        ("النبهانية", "Al Nabbhaniyah"), ("عيون الجواء", "Uyun Al Jawa"),
        ("رياض الخبراء", "Riyad Al Khabra"), ("عقلة الصقور", "Uqlat Al Suqur"),
        ("ضرية", "Dariyah"),
    ],
    "eastern": [
        ("الدمام", "Dammam"), ("الأحساء", "Al Ahsa"),
        ("حفر الباطن", "Hafar Al Batin"), ("الجبيل", "Jubail"),
        ("القطيف", "Qatif"), ("الخبر", "Khobar"), ("الخفجي", "Khafji"),
        ("رأس تنورة", "Ras Tanura"), ("بقيق", "Buqayq"), ("النعيرية", "Nairyah"),
        ("قرية العليا", "Qaryat Al Ulya"), ("العديد", "Al Udayd"),
    ],
    "asir": [
        ("أبها", "Abha"), ("خميس مشيط", "Khamis Mushait"), ("بيشة", "Bisha"),
        ("النماص", "Al Namas"), ("محايل", "Muhayil"),
        ("سراة عبيدة", "Sarat Abidah"), ("تثليث", "Tathlith"),
        ("رجال ألمع", "Rijal Alma"), ("أحد رفيدة", "Ahad Rifaydah"),
        ("ظهران الجنوب", "Dhahran Al Janub"), ("بلقرن", "Balqarn"),
        ("المجاردة", "Al Majardah"), ("بارق", "Bariq"), ("تنومة", "Tanumah"),
        ("طريب", "Tarib"),
    ],
    "tabuk": [
        ("تبوك", "Tabuk"), ("الوجه", "Al Wajh"), ("ضباء", "Duba"),
        ("تيماء", "Tayma"), ("أملج", "Umluj"), ("حقل", "Haql"), ("البدع", "Al Bad"),
    ],
    "hail": [
        ("حائل", "Hail"), ("بقعاء", "Baqaa"), ("الغزالة", "Al Ghazalah"),
        ("الشنان", "Al Shinan"), ("الحائط", "Al Hait"), ("السليمي", "Al Sulaimi"),
        ("الشملي", "Al Shamli"), ("موقق", "Mawqaq"), ("سميراء", "Sumaira"),
    ],
    "northern": [
        ("عرعر", "Arar"), ("رفحاء", "Rafha"), ("طريف", "Turaif"),
        ("العويقيلة", "Al Uwayqilah"),
    ],
    "jazan": [
        ("جازان", "Jazan"), ("صبيا", "Sabya"), ("أبو عريش", "Abu Arish"),
        ("صامطة", "Samtah"), ("الحرث", "Al Harth"), ("ضمد", "Damad"),
        ("الريث", "Al Reeth"), ("فرسان", "Farasan"), ("الدائر", "Al Dair"),
        ("أحد المسارحة", "Ahad Al Masarihah"), ("العارضة", "Al Aridah"),
        ("العيدابي", "Al Aydabi"), ("فيفاء", "Fayfa"), ("هروب", "Harub"),
        ("بيش", "Baysh"),
    ],
    "najran": [
        ("نجران", "Najran"), ("شرورة", "Sharurah"), ("حبونا", "Hubuna"),
        ("بدر الجنوب", "Badr Al Janub"), ("يدمة", "Yadamah"), ("ثار", "Thar"),
        ("خباش", "Khubash"), ("الخرخير", "Al Kharkhir"),
    ],
    "bahah": [
        ("الباحة", "Al Bahah"), ("بلجرشي", "Baljurashi"),
        ("المندق", "Al Mandag"), ("المخواة", "Al Mikhwah"), ("العقيق", "Al Aqiq"),
        ("قلوة", "Qilwah"), ("بني حسن", "Bani Hassan"),
        ("غامد الزناد", "Ghamid Al Zinad"), ("الحجرة", "Al Hajrah"),
    ],
    "jawf": [
        ("سكاكا", "Sakaka"), ("القريات", "Al Qurayyat"),
        ("دومة الجندل", "Dumat Al Jandal"), ("طبرجل", "Tabarjal"),
    ],
}

MAJOR = {
    "الرياض", "جدة", "مكة المكرمة", "المدينة المنورة", "الدمام", "الخبر",
    "الطائف", "تبوك", "بريدة", "خميس مشيط", "أبها", "حائل", "نجران", "جازان",
    "الجبيل", "ينبع", "القطيف", "الأحساء", "عرعر", "سكاكا", "الباحة",
}


def norm(s: str) -> str:
    s = (s or "").strip().replace("\u200e", "").replace("\u200f", "")
    s = s.replace("ة", "ه").replace("أ", "ا").replace("إ", "ا").replace("آ", "ا").replace("ى", "ي")
    return re.sub(r"\s+", " ", s)


def region_id_of(raw: str) -> str | None:
    s = (raw or "").strip().lower()
    if not s:
        return None
    pairs = [
        ("riyadh", ("رياض", "riyadh")),
        ("makkah", ("مكة", "makkah", "mecca")),
        ("madinah", ("مدينة", "madinah", "medina")),
        ("qassim", ("قصيم", "qassim", "qasim")),
        ("eastern", ("شرقية", "eastern", "sharq")),
        ("asir", ("عسير", "asir", "aseer")),
        ("tabuk", ("تبوك", "tabuk")),
        ("hail", ("حائل", "hail")),
        ("northern", ("حدود", "northern", "عرعر")),
        ("jazan", ("جازان", "jazan", "jizan")),
        ("najran", ("نجران", "najran")),
        ("bahah", ("باحة", "bahah", "baha")),
        ("jawf", ("جوف", "jawf")),
    ]
    for rid, keys in pairs:
        if any(k in s for k in keys):
            return rid
    return None


def haversine(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371 * 2 * math.asin(min(1, math.sqrt(h)))


def load_json(zf: zipfile.ZipFile, name: str):
    for info in zf.namelist():
        if info.endswith(name) and not info.endswith("/"):
            with zf.open(info) as fh:
                return json.loads(fh.read().decode("utf-8"))
    raise FileNotFoundError(name)


def main() -> None:
    if not ZIP_PATH.exists():
        raise SystemExit(f"zip not found: {ZIP_PATH}")

    with zipfile.ZipFile(ZIP_PATH) as zf:
        zcities = load_json(zf, "json/cities.json")
        zregs = load_json(zf, "json/regions.json")
        zdists = load_json(zf, "json/districts.json")

    reg_by_id = {str(r["region_id"]): r for r in zregs}
    zcity_by_id = {int(c["city_id"]): c for c in zcities}

    existing: list[dict] = []
    for p in (OUT_MAIN, OUT_EXTRA):
        if p.exists():
            existing.extend(json.loads(p.read_text(encoding="utf-8")))

    by_key: dict[str, dict] = {}

    def upsert(row: dict) -> None:
        car = (row.get("city_ar") or "").strip().replace("\u200e", "").replace("\u200f", "")
        rar = (row.get("region_ar") or "").strip()
        if not car:
            return
        rid = region_id_of(rar) or region_id_of(row.get("region_en") or "")
        labels = next((x for x in REGION_LABELS if x[0] == rid), None)
        if labels:
            row["region_ar"], row["region_en"] = labels[1], labels[2]
        key = f"{norm(row['region_ar'])}|{norm(car)}"
        prev = by_key.get(key)
        if prev is None:
            row["city_ar"] = car
            by_key[key] = row
            return
        if not (prev.get("city_en") or "").strip():
            prev["city_en"] = (row.get("city_en") or "").strip()
        if (prev.get("lat") or 0) == 0 and row.get("lat"):
            prev["lat"] = row["lat"]
            prev["lng"] = row["lng"]

    for e in existing:
        upsert(dict(e))

    for c in zcities:
        reg = reg_by_id.get(str(c.get("region_id")), {})
        center = c.get("center") or [0, 0]
        lat = float(center[0]) if isinstance(center, list) and center else 0.0
        lng = float(center[1]) if isinstance(center, list) and len(center) > 1 else 0.0
        upsert(
            {
                "city_ar": (c.get("name_ar") or "").strip(),
                "city_en": (c.get("name_en") or "").strip(),
                "region_ar": (reg.get("name_ar") or "").strip(),
                "region_en": (reg.get("name_en") or "").strip(),
                "lat": lat,
                "lng": lng,
            }
        )

    rows = list(by_key.values())

    seats: dict[str, list[tuple[tuple[str, str], tuple[float, float]]]] = defaultdict(list)
    for rid, govs in GOVS.items():
        for ga, ge in govs:
            coord = (0.0, 0.0)
            for r in rows:
                if region_id_of(r["region_ar"]) != rid:
                    continue
                if norm(r["city_ar"]) == norm(ga) or norm(r.get("city_en") or "") == norm(ge):
                    lat, lng = float(r.get("lat") or 0), float(r.get("lng") or 0)
                    if lat or lng:
                        coord = (lat, lng)
                        break
            seats[rid].append(((ga, ge), coord))

    assigned = 0
    for r in rows:
        rid = region_id_of(r["region_ar"])
        if not rid:
            continue
        city_n = norm(r["city_ar"])
        city_en_n = norm(r.get("city_en") or "")
        hit = None
        for ga, ge in GOVS[rid]:
            if city_n == norm(ga) or city_en_n == norm(ge):
                hit = (ga, ge)
                break
        if hit is None:
            lat, lng = float(r.get("lat") or 0), float(r.get("lng") or 0)
            best = None
            best_d = 1e18
            for (ga, ge), coord in seats[rid]:
                if coord == (0.0, 0.0):
                    continue
                if lat == 0 and lng == 0:
                    continue
                d = haversine((lat, lng), coord)
                if d < best_d:
                    best_d = d
                    best = (ga, ge)
            hit = best or (GOVS[rid][0] if GOVS[rid] else None)
        if hit:
            r["governorate_ar"], r["governorate_en"] = hit
            assigned += 1

    main = [r for r in rows if r["city_ar"] in MAJOR]
    extra = [r for r in rows if r["city_ar"] not in MAJOR]
    main.sort(key=lambda x: (x["region_ar"], x["city_ar"]))
    extra.sort(key=lambda x: (x["region_ar"], x["city_ar"]))

    districts: dict[str, set[str]] = defaultdict(set)
    if OUT_DISTRICTS.exists():
        old = json.loads(OUT_DISTRICTS.read_text(encoding="utf-8"))
        for k, v in old.items():
            if isinstance(v, list):
                for name in v:
                    n = str(name).strip()
                    if n:
                        districts[k].add(n)

    for d in zdists:
        name_ar = (d.get("name_ar") or "").strip()
        name_en = (d.get("name_en") or "").strip()
        try:
            city = zcity_by_id.get(int(d.get("city_id")))
        except (TypeError, ValueError):
            city = None
        if not city:
            continue
        car = (city.get("name_ar") or "").strip()
        cen = (city.get("name_en") or "").strip()
        if car and name_ar:
            districts[car].add(name_ar)
            if car == "الاحساء":
                districts["الأحساء"].add(name_ar)
        if cen and name_en:
            districts[cen].add(name_en)
            if cen.lower() in {"al ahsa", "alahsa", "al-ahsa"}:
                districts["Al Ahsa"].add(name_en)

    dist_out = {k: sorted(v) for k, v in sorted(districts.items()) if v}

    OUT_MAIN.write_text(json.dumps(main, ensure_ascii=False, indent=0), encoding="utf-8")
    OUT_EXTRA.write_text(json.dumps(extra, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    OUT_DISTRICTS.write_text(json.dumps(dist_out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    print(f"places {len(rows)} (main {len(main)} extra {len(extra)}) gov-assigned {assigned}")
    print(f"district keys {len(dist_out)} names {sum(len(v) for v in dist_out.values())}")
    print(f"zip cities {len(zcities)} zip districts {len(zdists)}")


if __name__ == "__main__":
    main()
