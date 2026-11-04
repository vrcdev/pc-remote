"""PC Remote server (stdlib only). Run: python server.py

Endpoints (all need header  X-Token: <token.txt>):
  GET    /ping
  GET    /commands               -> {"commands": {name: [steps]}}
  PUT    /commands/<name>        body {"steps": [...]}  (create / replace)
  DELETE /commands/<name>
  POST   /run/<name>             run a saved command
  POST   /exec                   body {"steps": [...]}  run steps ad hoc

Step types: url, run, kill, hotkey, shell, type, sleep, media, power
"""
import ctypes, hmac, json, os, subprocess, threading, time
from ctypes import wintypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, unquote

HERE = os.path.dirname(os.path.abspath(__file__))
CFG_PATH = os.path.join(HERE, "commands.json")
LOCK = threading.Lock()
TOKEN = open(os.path.join(HERE, "token.txt")).read().strip()


def load():
    with open(CFG_PATH, encoding="utf-8") as f:
        return json.load(f)


def save(cfg):
    tmp = CFG_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    os.replace(tmp, CFG_PATH)


# ---------- input helpers ----------
u32 = ctypes.windll.user32
VK = {"ctrl": 0x11, "shift": 0x10, "alt": 0x12, "win": 0x5B, "enter": 0x0D,
      "esc": 0x1B, "tab": 0x09, "space": 0x20, "backspace": 0x08, "delete": 0x2E,
      "up": 0x26, "down": 0x28, "left": 0x25, "right": 0x27}
VK.update({f"f{i}": 0x6F + i for i in range(1, 25)})
VK.update({chr(c).lower(): c for c in range(0x41, 0x5B)})
VK.update({str(d): 0x30 + d for d in range(10)})
MEDIA = {"play_pause": 0xB3, "next": 0xB0, "prev": 0xB1, "stop": 0xB2,
         "mute": 0xAD, "vol_up": 0xAF, "vol_down": 0xAE}


def hotkey(combo):
    keys = [VK[k.strip().lower()] for k in combo.split("+")]
    for k in keys:
        u32.keybd_event(k, 0, 0, 0)
    for k in reversed(keys):
        u32.keybd_event(k, 0, 2, 0)


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD),
                ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_void_p)]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
                ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_void_p)]


class _U(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("u", _U)]


def type_text(text):
    data = text.encode("utf-16-le")
    for i in range(0, len(data), 2):
        unit = int.from_bytes(data[i:i + 2], "little")
        for flags in (0x4, 0x4 | 0x2):  # UNICODE down, UNICODE up
            inp = INPUT(type=1)
            inp.u.ki = KEYBDINPUT(0, unit, flags, 0, None)
            u32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))
        time.sleep(0.005)


def power(action):
    if action == "lock":
        u32.LockWorkStation()
    elif action == "sleep":
        subprocess.Popen(["rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0"])
    elif action == "shutdown":
        subprocess.Popen(["shutdown", "/s", "/t", "0"])
    elif action == "restart":
        subprocess.Popen(["shutdown", "/r", "/t", "0"])
    else:
        raise ValueError("power: lock | sleep | shutdown | restart")


TYPES = {"url", "run", "kill", "hotkey", "shell", "type", "sleep", "media", "power"}


def do(step):
    t, v = step["type"], str(step.get("value", ""))
    ev = os.path.expandvars(v)
    if t == "url":
        os.startfile(ev)
    elif t == "run":
        subprocess.Popen([ev, *step.get("args", [])], close_fds=True)
    elif t == "kill":
        subprocess.run(["taskkill", "/F", "/IM", ev], capture_output=True)
    elif t == "hotkey":
        hotkey(v)
    elif t == "shell":
        subprocess.Popen(["powershell", "-NoProfile", "-Command", v], creationflags=0x08000000)
    elif t == "type":
        type_text(v)
    elif t == "sleep":
        time.sleep(min(float(v), 30000) / 1000)
    elif t == "media":
        name, _, n = v.partition("*")
        for _ in range(int(n or 1)):
            u32.keybd_event(MEDIA[name.strip()], 0, 0, 0)
            u32.keybd_event(MEDIA[name.strip()], 0, 2, 0)
    elif t == "power":
        power(v.strip().lower())
    else:
        raise ValueError(f"unknown step type {t}")


def validate(steps):
    if not isinstance(steps, list) or not steps:
        raise ValueError("steps must be a non-empty list")
    for s in steps:
        if s.get("type") not in TYPES:
            raise ValueError(f"bad step type: {s.get('type')}")


def run_steps(steps):
    for s in steps:
        do(s)


class H(BaseHTTPRequestHandler):
    def reply(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def route(self, method):
        if not hmac.compare_digest(self.headers.get("X-Token", ""), TOKEN):
            return self.reply(401, {"error": "bad token"})
        parts = urlparse(self.path).path.strip("/").split("/", 1)
        head = parts[0]
        name = unquote(parts[1]).strip() if len(parts) > 1 else ""
        try:
            if head == "ping":
                return self.reply(200, {"ok": True, "host": os.environ.get("COMPUTERNAME", "pc")})
            if head == "commands":
                if method == "GET" and not name:
                    return self.reply(200, {"commands": load()["commands"]})
                if not name:
                    return self.reply(400, {"error": "name required"})
                with LOCK:
                    cfg = load()
                    if method == "PUT":
                        steps = self.body().get("steps")
                        validate(steps)
                        cfg["commands"][name] = steps
                    elif method == "DELETE":
                        cfg["commands"].pop(name, None)
                    else:
                        return self.reply(405, {"error": "method"})
                    save(cfg)
                return self.reply(200, {"ok": True})
            if head == "run" and method in ("GET", "POST"):
                steps = {k.lower(): v for k, v in load()["commands"].items()}.get(name.lower())
                if not steps:
                    return self.reply(404, {"error": f"no command named '{name}'"})
                run_steps(steps)
                return self.reply(200, {"ok": True})
            if head == "exec" and method == "POST":
                steps = self.body().get("steps")
                validate(steps)
                run_steps(steps)
                return self.reply(200, {"ok": True})
            return self.reply(404, {"error": "unknown route"})
        except Exception as e:
            return self.reply(500, {"error": str(e)})

    def do_GET(self): self.route("GET")
    def do_POST(self): self.route("POST")
    def do_PUT(self): self.route("PUT")
    def do_DELETE(self): self.route("DELETE")

    def log_message(self, fmt, *a):
        print(self.address_string(), fmt % a)


if __name__ == "__main__":
    cfg = load()
    srv = ThreadingHTTPServer((cfg["bind"], cfg["port"]), H)
    print(f"listening on {cfg['bind']}:{cfg['port']}")
    srv.serve_forever()
