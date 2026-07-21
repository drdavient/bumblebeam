"""Bumblebeam App Shelf — a tiny catalog for sideloading APKs onto LAN devices.

Scans APKS_DIR for *.apk, reads each one's label / version / minSdk with
pyaxmlparser, and renders a touch-friendly download page. Anything dropped into
the folder (e.g. via the Filebrowser manager) appears automatically. Optional
per-file overrides live in catalog.json: {"file.apk": {"label": "...", "note": "..."}}.

Fire tablet target: Fire OS 5 (5th gen) is Android 5.1 = API 22, so an APK installs
only when its minSdkVersion <= 22. The page flags each app accordingly.
"""
import io
import json
import os
import zipfile
from html import escape

from flask import Flask, Response, abort, send_file
from pyaxmlparser import APK
from waitress import serve

APKS_DIR = os.environ.get("APKS_DIR", "/apks")
PORT = int(os.environ.get("PORT", "8000"))
FIRE_MAX_SDK = 22  # Fire OS 5 / 5th-gen tablets are Android 5.1 (API 22)
FIRE_ABIS = {"armeabi-v7a", "armeabi"}  # Fire 7 5th-gen is 32-bit ARM

app = Flask(__name__)
_cache = {}  # filename -> (mtime, meta dict)


def _overrides():
    path = os.path.join(APKS_DIR, "catalog.json")
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def _parse(path):
    """Best-effort metadata for one APK. Never raises."""
    meta = {
        "label": os.path.basename(path).rsplit(".apk", 1)[0],
        "package": "",
        "version": "",
        "min_sdk": None,
        "abis": [],  # empty => no native libs (pure-Java, runs on any CPU)
        "icon": False,
    }
    try:
        apk = APK(path)
        meta["label"] = apk.application or apk.get_app_name() or meta["label"]
        meta["package"] = apk.package or ""
        meta["version"] = apk.version_name or ""
        try:
            meta["min_sdk"] = int(apk.get_min_sdk_version())
        except (TypeError, ValueError):
            meta["min_sdk"] = None
        icon_path = apk.get_app_icon()
        meta["icon"] = bool(icon_path and icon_path.lower().endswith(("png", "jpg", "jpeg", "webp")))
    except Exception:  # noqa: BLE001 — a bad APK must not break the whole page
        pass
    # ABIs from lib/<abi>/ entries — reliable and independent of the parser above.
    try:
        with zipfile.ZipFile(path) as z:
            abis = {n.split("/")[1] for n in z.namelist()
                    if n.startswith("lib/") and n.count("/") >= 2 and n.split("/")[1]}
        meta["abis"] = sorted(abis)
    except Exception:  # noqa: BLE001
        pass
    return meta


def _meta(filename):
    path = os.path.join(APKS_DIR, filename)
    mtime = os.path.getmtime(path)
    cached = _cache.get(filename)
    if cached and cached[0] == mtime:
        meta = cached[1]
    else:
        meta = _parse(path)
        meta["size"] = os.path.getsize(path)
        _cache[filename] = (mtime, meta)
    return dict(meta)


def _apks():
    try:
        files = [f for f in os.listdir(APKS_DIR) if f.lower().endswith(".apk")]
    except OSError:
        files = []
    ov = _overrides()
    items = []
    for f in sorted(files):
        m = _meta(f)
        m["file"] = f
        o = ov.get(f, {})
        if o.get("label"):
            m["label"] = o["label"]
        m["note"] = o.get("note", "")
        sdk_ok = m["min_sdk"] is None or m["min_sdk"] <= FIRE_MAX_SDK
        abi_ok = not m["abis"] or bool(set(m["abis"]) & FIRE_ABIS)
        m["fire_ok"] = sdk_ok and abi_ok
        if not sdk_ok:
            m["fire_reason"] = "needs newer Android"
        elif not abi_ok:
            m["fire_reason"] = "wrong CPU (needs 32-bit ARM)"
        else:
            m["fire_reason"] = ""
        items.append(m)
    items.sort(key=lambda m: m["label"].lower())
    return items


def _human(size):
    mb = size / (1024 * 1024)
    return f"{mb:.0f} MB" if mb >= 1 else f"{size / 1024:.0f} KB"


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Bumblebeam App Shelf</title>
<style>
* {{ box-sizing: border-box; }}
body {{ margin: 0; font-family: -apple-system, Roboto, "Segoe UI", Arial, sans-serif;
  background: #10131a; color: #eef1f6; -webkit-text-size-adjust: 100%; }}
header {{ padding: 20px 16px 8px; }}
h1 {{ font-size: 22px; margin: 0 0 4px; }}
.sub {{ color: #9aa4b2; font-size: 14px; line-height: 1.4; }}
.help {{ background: #1b2130; border: 1px solid #2a3245; border-radius: 10px;
  margin: 12px 16px; padding: 12px 14px; font-size: 13px; color: #c7cfdd; line-height: 1.5; }}
.help b {{ color: #fff; }}
.list {{ padding: 4px 12px 40px; }}
.card {{ display: flex; align-items: center; background: #1b2130; border: 1px solid #2a3245;
  border-radius: 12px; padding: 12px; margin: 10px 4px; }}
.icon {{ width: 56px; height: 56px; border-radius: 12px; margin-right: 14px; flex: 0 0 auto;
  background: #2a3245; display: flex; align-items: center; justify-content: center;
  font-size: 28px; overflow: hidden; }}
.icon img {{ width: 100%; height: 100%; object-fit: cover; }}
.meta {{ flex: 1 1 auto; min-width: 0; }}
.name {{ font-size: 17px; font-weight: 600; }}
.info {{ color: #9aa4b2; font-size: 13px; margin-top: 2px; }}
.note {{ color: #c7cfdd; font-size: 12px; margin-top: 3px; font-style: italic; }}
.badge {{ display: inline-block; font-size: 11px; padding: 1px 7px; border-radius: 20px;
  margin-left: 6px; vertical-align: middle; }}
.ok {{ background: #10391f; color: #6ee7a0; border: 1px solid #1c5c34; }}
.warn {{ background: #3a2a10; color: #f0c274; border: 1px solid #6b4d18; }}
.get {{ flex: 0 0 auto; margin-left: 10px; text-decoration: none; background: #3b6ef5;
  color: #fff; font-weight: 600; font-size: 15px; padding: 12px 16px; border-radius: 10px; }}
.get:active {{ background: #2f59cc; }}
.empty {{ color: #9aa4b2; padding: 30px 20px; text-align: center; }}
footer {{ color: #6b7484; font-size: 12px; text-align: center; padding: 20px; }}
</style>
</head>
<body>
<header>
  <h1>&#128241; Bumblebeam App Shelf</h1>
  <div class="sub">Tap <b>Get</b> to download an app, then open it to install.</div>
</header>
<div class="help">
  <b>First time on a Fire tablet?</b> Turn on installs first:
  Settings &rarr; Security &amp; Privacy &rarr; <b>Apps from Unknown Sources</b> (or
  "Install unknown apps" &rarr; Silk Browser). Then tap Get, open the downloaded file,
  and choose Install. A <span class="badge ok">Fire&nbsp;5&nbsp;OK</span> tag means it
  should install on a 5th-gen Fire.
</div>
<div class="list">
{cards}
</div>
<footer>{count} app(s) &middot; served from Bumblebeam</footer>
</body>
</html>"""


def _card(m):
    icon = (
        f'<img src="/icon/{escape(m["file"])}" alt="">'
        if m["icon"]
        else "&#127918;"
    )
    badge = (
        '<span class="badge ok">Fire 5 OK</span>'
        if m["fire_ok"]
        else f'<span class="badge warn">{escape(m.get("fire_reason") or "not for Fire 5")}</span>'
    )
    ver = f'v{escape(m["version"])}' if m["version"] else ""
    sdk = f'min Android API {m["min_sdk"]}' if m["min_sdk"] else ""
    info = " &middot; ".join(x for x in [ver, _human(m["size"]), sdk] if x)
    note = f'<div class="note">{escape(m["note"])}</div>' if m.get("note") else ""
    return f"""  <div class="card">
    <div class="icon">{icon}</div>
    <div class="meta">
      <div class="name">{escape(m["label"])}{badge}</div>
      <div class="info">{info}</div>{note}
    </div>
    <a class="get" href="/apk/{escape(m["file"])}">Get</a>
  </div>"""


@app.route("/")
def index():
    items = _apks()
    if items:
        cards = "\n".join(_card(m) for m in items)
    else:
        cards = '<div class="empty">No apps yet. Add APK files with the manager, then refresh.</div>'
    html = PAGE.format(cards=cards, count=len(items))
    return Response(html, mimetype="text/html")


@app.route("/apk/<path:filename>")
def download(filename):
    if "/" in filename or "\\" in filename or not filename.lower().endswith(".apk"):
        abort(404)
    path = os.path.join(APKS_DIR, filename)
    if not os.path.isfile(path):
        abort(404)
    return send_file(
        path,
        mimetype="application/vnd.android.package-archive",
        as_attachment=True,
        download_name=filename,
    )


@app.route("/icon/<path:filename>")
def icon(filename):
    if "/" in filename or "\\" in filename or not filename.lower().endswith(".apk"):
        abort(404)
    path = os.path.join(APKS_DIR, filename)
    if not os.path.isfile(path):
        abort(404)
    try:
        apk = APK(path)
        ip = apk.get_app_icon()
        if not ip:
            abort(404)
        with zipfile.ZipFile(path) as z:
            data = z.read(ip)
        ext = ip.rsplit(".", 1)[-1].lower()
        mime = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp"}.get(ext)
        if not mime:
            abort(404)
        return send_file(io.BytesIO(data), mimetype=mime)
    except Exception:  # noqa: BLE001
        abort(404)


@app.route("/healthz")
def healthz():
    return "ok"


if __name__ == "__main__":
    serve(app, host="0.0.0.0", port=PORT)
