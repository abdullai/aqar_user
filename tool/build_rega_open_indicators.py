"""Builds assets/data/rega_open_indicators.json from REGA quarterly CSVs.

Usage (no Node required):
  py tool/build_rega_open_indicators.py <quarterlies-dir> <out.json> [--sales 2026-1] [--rental 2026-1]
Without --sales/--rental the latest quarter found in the file names is used.
Folder layout: <dir>/sales/*.csv and <dir>/rental/*.csv
"""
import csv
import json
import os
import re
import sys

ORD = {1: '1st', 2: '2nd', 3: '3rd', 4: '4th'}


def rx(yq):
    y, q = yq.split('-')
    return re.compile(rf'(Q{q}-{y}|{ORD[int(q)]}-?Q-?{y})', re.I)


def rows(path):
    with open(path, encoding='utf-8-sig', newline='') as f:
        for r in csv.DictReader(f):
            yield {re.sub(r'\s+', '', (k or '')): (v or '').strip() for k, v in r.items()}


def num(v):
    try:
        n = float(str(v).replace(',', ''))
        return n
    except ValueError:
        return None


def detect_latest(files, kind):
    pat = re.compile(r'Q([1-4])-(\d{4})|([1-4])(?:st|nd|rd|th)-?Q-?(\d{4})', re.I)
    best = None
    for f in files:
        if kind not in f.lower():
            continue
        m = pat.search(os.path.basename(f))
        if not m:
            continue
        q, y = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(4))
        cand = (int(y), int(q))
        if best is None or cand > best:
            best = cand
    return f'{best[0]}-{best[1]}' if best else None


def main():
    args = sys.argv[1:]
    opts = {'--sales': None, '--rental': None}
    pos = []
    i = 0
    while i < len(args):
        if args[i] in opts:
            opts[args[i]] = args[i + 1]
            i += 2
        else:
            pos.append(args[i])
            i += 1
    if len(pos) != 2:
        sys.exit(__doc__)
    root, out = pos
    files = [os.path.join(d, n) for d, _, ns in os.walk(root) for n in ns if n.lower().endswith('.csv')]
    # بدون تحديد الربع يُكتشف أحدث ربع متاح لكل نوع تلقائيًا.
    opts['--sales'] = opts['--sales'] or detect_latest(files, 'sales')
    opts['--rental'] = opts['--rental'] or detect_latest(files, 'rental')
    if not opts['--sales'] or not opts['--rental']:
        sys.exit('no sales/rental quarterly files found')
    s_re, r_re = rx(opts['--sales']), rx(opts['--rental'])
    sales_files = [f for f in files if 'sales' in f.lower() and s_re.search(os.path.basename(f))]
    rental_files = [f for f in files if 'rental' in f.lower() and r_re.search(os.path.basename(f))]

    sales = []
    for f in sales_files:
        for r in rows(f):
            city, typ = r.get('المدينة', ''), r.get('النوع', '')
            deals = num(r.get('عددالصفقات'))
            avg = num(r.get('متوسطسعرالمترر.س'))
            if not city or not typ or not deals or deals <= 0 or avg is None or avg <= 0:
                continue
            sales.append({
                'region': r.get('المنطقة', ''), 'city': city, 'type': typ,
                'klass': r.get('الاستخدام', ''), 'deals': int(deals) if deals == int(deals) else deals,
                'avg_m2': round(avg * 100) / 100,
            })

    acc = {}
    for f in rental_files:
        for r in rows(f):
            city, typ = r.get('المدينة', ''), r.get('نوعالعقار', '')
            klass = r.get('تصنيفالعقار', '')
            deals = num(r.get('عددالصفقات')) or 0
            rent = num(r.get('متوسطالايجارر.س') or r.get('متوسطالايجار') or r.get('متوسطالإيجار'))
            m2 = num(r.get('متوسطالايجارلكلمترمربعر.س') or r.get('متوسطالايجارلكلمترمربع'))
            if not city or not typ or deals <= 0 or rent is None or rent <= 0:
                continue
            k = (r.get('المنطقة', ''), city, typ, klass)
            c = acc.setdefault(k, {'deals': 0, 'rent': 0.0, 'm2': 0.0, 'm2d': 0.0})
            c['deals'] += deals
            c['rent'] += rent * deals
            if m2 and m2 > 0:
                c['m2'] += m2 * deals
                c['m2d'] += deals
    rentals = [{
        'region': k[0], 'city': k[1], 'type': k[2], 'klass': k[3],
        'deals': int(c['deals']), 'avg_rent': round(c['rent'] / c['deals']),
        'avg_m2': round(c['m2'] / c['m2d'] * 100) / 100 if c['m2d'] > 0 else None,
    } for k, c in acc.items()]

    sy, sq = map(int, opts['--sales'].split('-'))
    ry, rq = map(int, opts['--rental'].split('-'))
    payload = {
        'source': 'REGA open indicators (MOJ/REGA via Saudi National Open Data)',
        'attribution': 'civillizard/Saudi-Real-Estate-Data — KSA Open Data License',
        'sales_period': {'year': sy, 'quarter': sq},
        'rental_period': {'year': ry, 'quarter': rq},
        'sales': sales, 'rentals': rentals,
    }
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, separators=(',', ':'))
    print(f'wrote {out} sales={len(sales)} rentals={len(rentals)}')


if __name__ == '__main__':
    main()
