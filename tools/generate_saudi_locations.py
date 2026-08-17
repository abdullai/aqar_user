#!/usr/bin/env python3
"""Generate assets/data/saudi_locations*.json and saudi_districts.json from open SPL data."""

from __future__ import annotations

import json
import urllib.request
from collections import defaultdict
from pathlib import Path

BASE = "https://raw.githubusercontent.com/yasseralsamman/saudi-national-address/master/data/dist"
ROOT = Path(__file__).resolve().parents[1]
OUT_MAIN = ROOT / "assets" / "data" / "saudi_locations.json"
OUT_EXTRA = ROOT / "assets" / "data" / "saudi_locations_extra.json"
OUT_DISTRICTS = ROOT / "assets" / "data" / "saudi_districts.json"


def fetch(name: str) -> list | dict:
    url = f"{BASE}/{name}"
    print("fetch", url)
    with urllib.request.urlopen(url, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> None:
    regions = fetch("regions.lite.json")
    cities = fetch("cities.lite.json")
    districts = fetch("districts.lite.json")

    region_by_id = {r["region_id"]: r for r in regions}

    city_rows: list[dict] = []
    for c in cities:
        rid = c.get("region_id")
        reg = region_by_id.get(rid, {})
        center = c.get("center") or [0, 0]
        lat = float(center[0]) if len(center) > 0 else 0.0
        lng = float(center[1]) if len(center) > 1 else 0.0
        city_rows.append(
            {
                "city_ar": (c.get("name_ar") or "").strip(),
                "city_en": (c.get("name_en") or c.get("name") or "").strip(),
                "region_ar": (reg.get("name_ar") or "").strip(),
                "region_en": (reg.get("name_en") or reg.get("name") or "").strip(),
                "governorate_ar": (c.get("name_ar") or "").strip(),
                "governorate_en": (c.get("name_en") or c.get("name") or "").strip(),
                "lat": lat,
                "lng": lng,
            }
        )

    # dedupe by region+city ar
    seen: set[str] = set()
    unique_cities: list[dict] = []
    for row in city_rows:
        key = f"{row['region_ar']}|{row['city_ar']}"
        if not row["city_ar"] or key in seen:
            continue
        seen.add(key)
        unique_cities.append(row)

    # keep legacy main file small (capitals / major) — rest in extra
    major_names = {
        "الرياض",
        "جدة",
        "مكة",
        "المدينة",
        "الدمام",
        "الخبر",
        "الطائف",
        "تبوك",
        "بريدة",
        "خميس مشيط",
        "أبها",
        "حائل",
        "نجران",
        "جازان",
        "الجبيل",
        "ينبع",
        "القطيف",
        "الاحساء",
        "الأحساء",
        "عرعر",
        "سكاكا",
        "الباحة",
    }
    main = [r for r in unique_cities if r["city_ar"] in major_names]
    extra = [r for r in unique_cities if r["city_ar"] not in major_names]

    districts_by_city: dict[str, list[str]] = defaultdict(set)
    city_name_by_id = {c["city_id"]: c for c in cities}
    for d in districts:
        cid = d.get("city_id")
        city = city_name_by_id.get(cid)
        if not city:
            continue
        name_ar = (d.get("name_ar") or "").strip()
        if not name_ar:
            continue
        for key in {
            (city.get("name_ar") or "").strip(),
            (city.get("name_en") or "").strip(),
        }:
            if key:
                districts_by_city[key].add(name_ar)

    dist_out = {k: sorted(v) for k, v in sorted(districts_by_city.items()) if v}

    OUT_MAIN.write_text(json.dumps(main, ensure_ascii=False, indent=0), encoding="utf-8")
    OUT_EXTRA.write_text(json.dumps(extra, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    OUT_DISTRICTS.write_text(json.dumps(dist_out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    print(f"main cities: {len(main)}")
    print(f"extra cities: {len(extra)}")
    print(f"cities with districts: {len(dist_out)}")
    print(f"total districts: {sum(len(v) for v in dist_out.values())}")


if __name__ == "__main__":
    main()
