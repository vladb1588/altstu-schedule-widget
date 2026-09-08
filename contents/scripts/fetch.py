#!/usr/bin/env python3
"""
Fetch + parse the AltSTU mobile schedule page (altstu.ru/m/s/<id>/) for groups.

Usage:
    fetch.py <id> [<id> ...]                      # HTTP fetch, fall back to cache
    fetch.py --localdir ~/rasp <id> [<id> ...]    # read <dir>/<id>.html instead of HTTP
    fetch.py --mock <id> [<id> ...]               # emit sample data

Output: one line of JSON:
{
  "generatedAt": "...",
  "groups": {
    "<id>": {
      "groupId", "source", "fetchedAt", "weekType", "stale", "error",
      "days": [ { "weekday", "date": "YYYY-MM-DD"|"", "week": int,
                  "lessons": [ { "index", "start", "end", "subject",
                                 "type", "typeFull", "room", "teacher",
                                 "position", "parity", "subgroup",
                                 "once": bool, "exam": bool } ] } ]
    }
  }
}
"""

import sys
import os
import re
import json
import html as _html
import datetime
import urllib.request

PARSER_READY = True

BASE = "https://www.altstu.ru/m/s/{}/"
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
TIMEOUT = 15
CACHE_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "altstu-schedule",
)

PAIR_INDEX = {"08:15": 1, "09:55": 2, "11:35": 3, "13:35": 4,
              "15:15": 5, "17:05": 6, "18:45": 7, "20:25": 8}
TYPE_FULL = {
    "л.": "лекция",
    "пр.": "практика",
    "лаб.": "лаб. работа",
    "л.р.": "лаб. работа",
    "л.т.": "лекция (теор.)",
    "сем.": "семинар",
    "конс.": "консультация",
}


def now_iso():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def cache_path(gid):
    return os.path.join(CACHE_DIR, "%s.json" % gid)


def load_cache(gid):
    try:
        with open(cache_path(gid), encoding="utf-8") as fh:
            data = json.load(fh)
        data["stale"] = True
        return data
    except Exception:
        return None


def save_cache(gid, data):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = cache_path(gid) + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False)
        os.replace(tmp, cache_path(gid))
    except Exception:
        pass


def get_source(gid, localdir):
    if localdir:
        path = os.path.join(os.path.expanduser(localdir), "%s.html" % gid)
        with open(path, "rb") as fh:
            raw = fh.read()
        return raw.decode("utf-8", "replace")
    req = urllib.request.Request(
        BASE.format(gid),
        headers={"User-Agent": UA, "Accept-Language": "ru,en;q=0.8"},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        raw = resp.read()
        ctype = resp.headers.get("Content-Type", "")
    enc = "utf-8"
    m = re.search(r"charset=([\w-]+)", ctype, re.I)
    if m:
        enc = m.group(1)
    try:
        return raw.decode(enc, "replace")
    except LookupError:
        return raw.decode("utf-8", "replace")


def _clean(s):
    s = re.sub(r"<[^>]+>", " ", s)
    s = _html.unescape(s)
    s = s.replace("\xa0", " ").replace(" ", " ").replace(" ", " ")
    s = s.replace(" ", " ").replace(" ", " ")
    return re.sub(r"\s+", " ", s).strip()


_TOKEN = re.compile(
    r'<h4>[^<]*?(\d+)\s*</h4>'
    r'|<div class="block-index">\s*<h2>\s*(\d{2}\.\d{2}\.\d{2})\s*(?:&nbsp;| |\s)\s*'
    r'([^<]+?)\s*</h2>\s*<div class="list-group">(.*?)</div>\s*</div>',
    re.S,
)
_ITEM = re.compile(r'<div class="list-group-item([^"]*)">(.*?)</div>', re.S)


def parse(html_text):
    days = []
    week = 0
    for m in _TOKEN.finditer(html_text):
        if m.group(1):
            week = int(m.group(1))
            continue
        raw_date = m.group(2)
        weekday = _clean(m.group(3))
        # _TOKEN's trailing "</div></div>" swallows the last item's closing tag
        # together with the list-group's — give it back so _ITEM sees every item.
        body = m.group(4) + "</div>"

        iso = ""
        dm = re.match(r"(\d{2})\.(\d{2})\.(\d{2})$", raw_date)
        if dm:
            iso = "20%s-%s-%s" % (dm.group(3), dm.group(2), dm.group(1))

        lessons = []
        for cm in _ITEM.finditer(body):
            cls, inner = cm.group(1), cm.group(2)
            tm = re.search(r"(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})", inner)
            if not tm:
                continue
            start, end = tm.group(1), tm.group(2)

            subj_m = re.search(r"<strong>(.*?)</strong>", inner, re.S)
            subject = _clean(subj_m.group(1)) if subj_m else ""
            rest = inner[subj_m.end():] if subj_m else inner

            ltype, subgroup = "", ""
            pm = re.search(r"\(([^)]*)\)", rest, re.S)
            after = rest
            if pm:
                inside = _clean(pm.group(1))
                after = rest[pm.end():]
                sg = re.search(r"подгруппа\s*([0-9A-Za-zА-Яа-я])", inside)
                if sg:
                    subgroup = sg.group(1)
                ltype = inside.split(",", 1)[0].strip()

            nobrs = [_clean(x) for x in re.findall(r"<nobr>(.*?)</nobr>", after, re.S)]
            room, teacher = "", ""
            if len(nobrs) >= 2:
                room, teacher = nobrs[0], nobrs[1]
            elif len(nobrs) == 1:
                teacher = nobrs[0]

            plain = _clean(re.sub(r"<nobr>.*?</nobr>", "", after, flags=re.S))
            pos_m = re.search(r"-\s*([А-Яа-яёA-Za-z][А-Яа-яёA-Za-z. ]*)\s*$", plain)
            position = pos_m.group(1).strip() if pos_m else ""

            lessons.append({
                "index": PAIR_INDEX.get(start, 0),
                "start": start, "end": end,
                "subject": subject,
                "type": ltype,
                "typeFull": TYPE_FULL.get(ltype, ltype),
                "room": room,
                "teacher": teacher,
                "position": position,
                "parity": "",
                "subgroup": subgroup,
                "once": ("once" in cls) and ("once-exam" not in cls),
                "exam": "once-exam" in cls,
            })

        lessons.sort(key=lambda x: (x["start"], x["subject"]))
        days.append({"weekday": weekday, "date": iso, "week": week,
                     "lessons": lessons})
    days.sort(key=lambda d: d["date"] or "9999-99-99")
    return {"weekType": "", "days": days}


def group_payload(gid, localdir):
    url = BASE.format(gid)
    if not PARSER_READY:
        s = sample_days()
        return {"groupId": gid, "source": url, "fetchedAt": now_iso(),
                "weekType": s["weekType"], "days": s["days"], "stale": True,
                "error": "парсер ещё не подключён"}
    try:
        parsed = parse(get_source(gid, localdir))
        if not parsed["days"]:
            raise ValueError("на странице не найдено ни одного дня "
                             "(возможно, изменилась вёрстка сайта)")
        data = {"groupId": gid, "source": url, "fetchedAt": now_iso(),
                "weekType": parsed.get("weekType", ""),
                "days": parsed["days"], "stale": False, "error": ""}
        save_cache(gid, data)
        return data
    except Exception as exc:
        label = "%s: %s" % (type(exc).__name__, exc)
        cached = load_cache(gid)
        if cached:
            cached["error"] = label + " (показан кэш)"
            return cached
        return {"groupId": gid, "source": url, "fetchedAt": now_iso(),
                "weekType": "", "days": [], "stale": True, "error": label}


def sample_days():
    def L(i, s, e, subj, t, room, teacher, sg="", once=False, exam=False):
        return {"index": i, "start": s, "end": e, "subject": subj, "type": t,
                "typeFull": TYPE_FULL.get(t, t), "room": room, "teacher": teacher,
                "position": "", "parity": "", "subgroup": sg,
                "once": once, "exam": exam}
    d0 = datetime.date.today()
    days = []
    plan = [
        ("Понедельник", [L(3, "11:35", "13:05", "Экономика отрасли", "л.", "437 ГК", "Глазкова Т. А."),
                          L(4, "13:35", "15:05", "Основы компьютерных сетей", "л.", "437 ГК", "Буковский А. С.")]),
        ("Вторник", [L(2, "09:55", "11:25", "Основы компьютерных сетей", "л.т.", "350 ГК", "Буковский А. С.", "Б"),
                      L(3, "11:35", "13:05", "Базы данных", "л.т.", "315 ГК", "Пузоватова Я. Ю.", "А")]),
        ("Среда", [L(5, "15:15", "16:45", "Основы компьютерных сетей", "л.т.", "327 ГК", "Буковский А. С.", "Б")]),
        ("Четверг", [L(2, "09:55", "11:25", "Базы данных", "л.т.", "315 ГК", "Пузоватова Я. Ю.", "А"),
                      L(5, "15:15", "16:45", "Анализ данных и машинное обучение", "л.т.", "350 ГК", "Позднякова В. В.", "Б")]),
        ("Пятница", [L(1, "08:15", "09:45", "Прикладной анализ данных", "л.т.", "", "Ортнер А. А.", "", False, False),
                      L(5, "15:15", "16:45", "ИТ поддержка ИИС", "л.", "203 Л", "Умбетов С. В.", "", True)]),
    ]
    for k, (wd, lessons) in enumerate(plan):
        days.append({"weekday": wd, "date": (d0 + datetime.timedelta(days=k)).isoformat(),
                     "week": 1 + (k // 3), "lessons": lessons})
    return {"weekType": "", "days": days}


def main():
    argv = sys.argv[1:]
    mock = "--mock" in argv
    localdir = ""
    if "--localdir" in argv:
        i = argv.index("--localdir")
        localdir = argv[i + 1] if i + 1 < len(argv) else ""
        del argv[i:i + 2]
    ids = [a for a in argv if not a.startswith("-")]

    groups = {}
    for gid in ids:
        if mock:
            s = sample_days()
            groups[gid] = {"groupId": gid, "source": BASE.format(gid),
                           "fetchedAt": now_iso(), "weekType": s["weekType"],
                           "days": s["days"], "stale": False, "error": ""}
        else:
            groups[gid] = group_payload(gid, localdir)

    sys.stdout.write(json.dumps(
        {"generatedAt": now_iso(), "groups": groups}, ensure_ascii=False))


if __name__ == "__main__":
    main()
