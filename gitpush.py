#!/usr/bin/env python3
"""gitpush.py - menu push GitHub untuk Termux (token terenkripsi).

Jalankan dari dalam folder repo:  python gitpush.py
Butuh:  pkg install python git python-cryptography

Token disimpan terenkripsi (password -> scrypt -> Fernet) di .git/gitpush.cred
dan TIDAK PERNAH ikut ter-push karena folder .git tidak dikirim ke GitHub.
"""
import base64
import fnmatch
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from getpass import getpass

CRED_NAME = "gitpush.cred"
LOCK_FILE = ".pushlock"
PERMANENT = ["tokengit.txt", LOCK_FILE]  # kunci bawaan, tidak bisa di-unlock
ORIG = os.getcwd()
ROOT = None
creds = {"user": None, "token": None}


# ---------------------------------------------------------------- util git
def git(args, env=None):
    return subprocess.run(["git"] + args, capture_output=True, text=True,
                          cwd=ROOT, env=env)


def find_root():
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def to_rel(p):
    ab = os.path.abspath(os.path.join(ORIG, p))
    return os.path.relpath(ab, ROOT).replace(os.sep, "/")


def cred_path():
    r = git(["rev-parse", "--absolute-git-dir"])
    return os.path.join(r.stdout.strip(), CRED_NAME)


def chunks(seq, n=200):
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


# ------------------------------------------------------------------ lock
def load_locks():
    p = os.path.join(ROOT, LOCK_FILE)
    if not os.path.exists(p):
        return []
    with open(p) as f:
        return [l.strip() for l in f if l.strip() and not l.startswith("#")]


def save_locks(locks):
    with open(os.path.join(ROOT, LOCK_FILE), "w") as f:
        f.write("\n".join(sorted(set(locks))) + "\n")


def ensure_default_locks():
    locks = load_locks()
    missing = [d for d in PERMANENT if d not in locks]
    if missing:
        save_locks(locks + missing)


def match(rp, pat):
    if pat.endswith("/"):
        return rp.startswith(pat)
    if fnmatch.fnmatch(rp, pat) or fnmatch.fnmatch(os.path.basename(rp), pat):
        return True
    return rp.startswith(pat + "/")


def is_locked(rp):
    for pat in load_locks():
        if match(rp, pat):
            return pat
    return None


def lock_menu():
    ensure_default_locks()
    while True:
        locks = load_locks()
        print("\n--- Lock File ---")
        for i, l in enumerate(locks, 1):
            tag = " (permanen)" if l in PERMANENT else ""
            print(f" {i}. {l}{tag}")
        print(" 1) Lock   2) Unlock satu   3) Unlock semua   4) Kembali")
        c = input("> ").strip()
        if c == "1":
            p = input("File / pola / folder (mis. config.py, *.env, secret/): ").strip()
            if not p:
                continue
            if os.path.exists(os.path.join(ORIG, p)):
                r = to_rel(p)
                if os.path.isdir(os.path.join(ORIG, p)) and not r.endswith("/"):
                    r += "/"
                p = r
            save_locks(locks + [p])
            print(f"[OK] Terkunci: {p}")
        elif c == "2":
            n = input("Nomor yang di-unlock: ").strip()
            if n.isdigit() and 1 <= int(n) <= len(locks):
                x = locks[int(n) - 1]
                if x in PERMANENT:
                    print("[!] Kunci permanen tidak bisa di-unlock.")
                else:
                    locks.pop(int(n) - 1)
                    save_locks(locks)
                    print(f"[OK] Unlock: {x}")
            else:
                print("[!] Nomor tidak valid.")
        elif c == "3":
            if input("Unlock semua kunci buatan Anda? (y/n): ").lower() == "y":
                save_locks([l for l in locks if l in PERMANENT])
                print("[OK] Semua unlock (kecuali permanen).")
        elif c == "4":
            return


# ---------------------------------------------------------------- enkripsi
def fernet(password, salt):
    try:
        from cryptography.fernet import Fernet
        from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
    except ImportError:
        print("[!] Library 'cryptography' belum ada. Jalankan: pkg install python-cryptography")
        return None
    kdf = Scrypt(salt=salt, length=32, n=2 ** 15, r=8, p=1)
    return Fernet(base64.urlsafe_b64encode(kdf.derive(password.encode())))


def save_cred(user, token, password):
    salt = os.urandom(16)
    f = fernet(password, salt)
    if not f:
        return False
    blob = f.encrypt(json.dumps({"user": user, "token": token}).encode())
    data = {"v": 1, "salt": base64.b64encode(salt).decode(), "data": blob.decode()}
    fd = os.open(cred_path(), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh)
    os.chmod(cred_path(), 0o600)
    return True


def load_cred(password):
    """Return dict, atau None jika gagal (password salah / file rusak)."""
    try:
        from cryptography.fernet import InvalidToken
    except ImportError:
        print("[!] Library 'cryptography' belum ada. Jalankan: pkg install python-cryptography")
        return None
    try:
        with open(cred_path()) as fh:
            d = json.load(fh)
        f = fernet(password, base64.b64decode(d["salt"]))
        if not f:
            return None
        return json.loads(f.decrypt(d["data"].encode()))
    except InvalidToken:
        return None
    except Exception as e:
        print(f"[!] File kredensial rusak: {e}")
        return None


def unlock_with_password():
    if not os.path.exists(cred_path()):
        print("[!] Belum ada ID tersimpan. Pakai menu Add ID dulu.")
        return None
    for i in range(3):
        d = load_cred(getpass("Password: "))
        if d:
            return d
        print(f"[!] Password salah ({i + 1}/3)")
    return None


def new_password():
    while True:
        p1 = getpass("Password baru (untuk enkripsi): ")
        if len(p1) < 4:
            print("[!] Minimal 4 karakter.")
            continue
        if p1 == getpass("Ulangi password: "):
            return p1
        print("[!] Tidak sama, ulangi.")


# ----------------------------------------------------------------- connect
def connect():
    d = unlock_with_password()
    if not d:
        if os.path.exists(os.path.join(ROOT, "tokengit.txt")):
            print("[i] tokengit.txt ditemukan. Pindahkan lewat Add ID > Input baru, lalu hapus file itu.")
        return
    req = urllib.request.Request(
        "https://api.github.com/user",
        headers={"Authorization": f"token {d['token']}", "User-Agent": "gitpush"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            login = json.load(r).get("login")
    except Exception as e:
        print(f"[!] Token tidak bisa diverifikasi: {e}")
        return
    creds["user"], creds["token"] = d["user"], d["token"]
    print(f"[OK] Terhubung sebagai {login}")
    if login and login.lower() != d["user"].lower():
        print(f"[!] Username tersimpan ({d['user']}) beda dengan akun token ({login}).")


# ------------------------------------------------------------------ add id
def add_id_new():
    if os.path.exists(cred_path()) and input("ID sudah ada. Timpa? (y/n): ").lower() != "y":
        return
    user = input("Username GitHub: ").strip()
    token = getpass("Token (tidak tampil): ").strip()
    if not user or not token:
        print("[!] Username dan token wajib diisi.")
        return
    if save_cred(user, token, new_password()):
        print("[OK] Tersimpan terenkripsi di .git/" + CRED_NAME)


def add_id_migrate():
    url = git(["remote", "get-url", "origin"]).stdout.strip()
    m = re.match(r"^(https?://)(?:([^:@/]+)(?::([^@/]+))?@)(.+)$", url)
    if not m:
        print("[i] URL origin tidak berisi token, tidak ada yang dimigrasi.")
        return
    scheme, a, b, rest = m.groups()
    if b:
        user, token = a, b
    else:  # format https://TOKEN@github.com/...
        token = a
        user = input("Username GitHub: ").strip()
        if not user:
            return
    if not save_cred(user, token, new_password()):
        return
    r = git(["remote", "set-url", "origin", scheme + rest])
    if r.returncode:
        print("[!] Gagal membersihkan URL:", r.stderr.strip())
        return
    print("[OK] Token terenkripsi & URL origin dibersihkan:")
    print("    ", scheme + rest)
    print("[i] Cek riwayat Termux (~/.bash_history) dan backup lama; token lama bisa tertinggal di sana.")


def add_id_change():
    d = unlock_with_password()
    if not d:
        return
    user = input(f"Username [{d['user']}]: ").strip() or d["user"]
    token = getpass("Token baru (Enter = tetap): ").strip() or d["token"]
    pw = getpass("Password baru (Enter = tetap): ")
    if pw:
        if pw != getpass("Ulangi password: "):
            print("[!] Tidak sama, dibatalkan.")
            return
    else:
        pw = getpass("Konfirmasi password lama: ")
        if not load_cred(pw):
            print("[!] Password lama salah, dibatalkan.")
            return
    if save_cred(user, token, pw):
        print("[OK] Diperbarui.")
        creds["user"] = creds["token"] = None
        print("[i] Silakan Connect ulang.")


def add_id_menu():
    while True:
        print("\n--- Add ID ---")
        print("1. Input baru")
        print("2. Migrasi dari URL lama")
        print("3. Ganti password / token")
        print("4. Kembali")
        c = input("> ").strip()
        if c == "1":
            add_id_new()
        elif c == "2":
            add_id_migrate()
        elif c == "3":
            add_id_change()
        elif c == "4":
            return


# -------------------------------------------------------------------- push
def changed_files():
    r = git(["status", "--porcelain=v1", "-z", "-uall", "--no-renames"])
    out = []
    for ent in r.stdout.split("\0"):
        if len(ent) < 4:
            continue
        xy, path = ent[:2], ent[3:]
        if "D" in xy:
            kind = "hapus"
        elif xy == "??" or "A" in xy:
            kind = "baru"
        else:
            kind = "ubah"
        out.append((path, kind))
    return sorted(out)


def askpass_env():
    fd, path = tempfile.mkstemp(suffix=".sh")
    with os.fdopen(fd, "w") as f:
        f.write('#!/bin/sh\ncase "$1" in\n*sername*) echo "$GP_USER";;\n*) echo "$GP_TOKEN";;\nesac\n')
    os.chmod(path, 0o700)
    env = os.environ.copy()
    env.update(GIT_ASKPASS=path, GIT_TERMINAL_PROMPT="0",
               GP_USER=creds["user"], GP_TOKEN=creds["token"])
    return env, path


def split_locked(items):
    ok, skipped = [], []
    for p, k in items:
        (skipped if is_locked(p) else ok).append((p, k))
    return ok, skipped


def handle_deletes(items):
    dels = [i for i in items if i[1] == "hapus"]
    if not dels:
        return items
    print(f"\n[!] {len(dels)} file akan DIHAPUS dari repo:")
    for p, _ in dels[:10]:
        print("   -", p)
    if len(dels) > 10:
        print(f"   ... dan {len(dels) - 10} lainnya")
    if input("Ikut hapus di GitHub? (y = ikut, n = lewati): ").lower() == "y":
        return items
    return [i for i in items if i[1] != "hapus"]


def commit_and_push(items):
    """Satu commit berisi HANYA file di items, lalu push."""
    if not items:
        print("[i] Tidak ada file untuk di-push.")
        return
    items = handle_deletes(items)
    if not items:
        print("[i] Tidak ada file untuk di-push.")
        return
    msg = input(f"Pesan commit [update {len(items)} file]: ").strip() or f"update {len(items)} file"
    files = [p for p, _ in items]

    git(["reset", "-q"])  # kosongkan staging agar hanya file terpilih yang masuk
    for part in chunks(files):
        r = git(["add", "-A", "--"] + part)
        if r.returncode:
            print("[!] git add gagal:", r.stderr.strip())
            return
    staged = [f for f in git(["diff", "--cached", "--name-only", "-z"]).stdout.split("\0") if f]
    bad = [f for f in staged if is_locked(f)]
    if bad:  # pengaman ganda
        git(["reset", "-q"])
        print("[LOCKED] Dibatalkan, ada file terkunci di staging:", ", ".join(bad))
        return
    if not staged:
        print("[i] Tidak ada perubahan untuk di-commit.")
        return
    ensure_identity()
    r = git(["commit", "-m", msg])
    if r.returncode:
        print("[!] Commit gagal:", (r.stderr or r.stdout).strip())
        return

    url = git(["remote", "get-url", "origin"]).stdout.strip()
    if not url:
        print("[!] Remote 'origin' belum ada. Commit tersimpan lokal.")
        return
    if not url.startswith("http"):
        print("[!] Origin bukan HTTPS; push lewat token tidak bisa dipakai di URL ini.")
        return
    if re.match(r"^https?://[^/]*@", url):
        print("[i] URL origin masih berisi token. Pakai Add ID > Migrasi untuk membersihkannya.")
    env, ap = askpass_env()
    try:
        r = git(["push", "-u", "origin", "HEAD"], env=env)
    finally:
        os.remove(ap)
    out = (r.stdout + r.stderr).strip()
    print("[OK] Push berhasil." if r.returncode == 0 else "[!] Push gagal:")
    print(out)
    if r.returncode and re.search(r"rejected|fetch first|non-fast-forward", out):
        print("[i] Repo di GitHub sudah berisi riwayat lain (bukan repo kosong).")
        print("    Buat repo kosong baru, atau tarik dulu isinya dengan: git pull --rebase origin main")


def ensure_identity():
    """git commit butuh nama & email; tanya sekali jika belum ada."""
    if git(["config", "user.email"]).stdout.strip() and git(["config", "user.name"]).stdout.strip():
        return
    print("\n[i] Identitas git belum diset (dipakai sebagai penulis commit).")
    name = input(f"Nama [{creds['user'] or 'user'}]: ").strip() or (creds["user"] or "user")
    default_mail = f"{creds['user']}@users.noreply.github.com" if creds["user"] else ""
    email = input(f"Email [{default_mail}]: ").strip() or default_mail
    if email:
        git(["config", "user.name", name])
        git(["config", "user.email", email])


def need_connect():
    if not creds["token"]:
        print("[!] Belum connect. Pilih menu 1 dulu.")
        return True
    return False


def parse_choice(s, n):
    idx = set()
    for part in s.replace(" ", "").split(","):
        if re.fullmatch(r"\d+", part):
            idx.add(int(part))
        elif re.fullmatch(r"\d+-\d+", part):
            a, b = map(int, part.split("-"))
            idx.update(range(min(a, b), max(a, b) + 1))
    return sorted(i for i in idx if 1 <= i <= n)


def push_list():
    items = changed_files()
    if not items:
        print("[i] Tidak ada file yang berubah.")
        return
    print("\nFile berubah:")
    for i, (p, k) in enumerate(items, 1):
        lk = "  [LOCKED]" if is_locked(p) else ""
        print(f" {i:>2}. [{k}] {p}{lk}")
    s = input("Pilih nomor (mis. 2 / 1,3 / 2-4, a = semua yang tidak terkunci): ").strip().lower()
    chosen = items if s == "a" else [items[i - 1] for i in parse_choice(s, len(items))]
    ok, skipped = split_locked(chosen)
    for p, _ in skipped:
        print(f"[LOCKED] dilewati: {p}")
    if not ok:
        return
    print(f"\nAkan push {len(ok)} file.")
    if input("Lanjut? (y/n): ").lower() == "y":
        commit_and_push(ok)


def push_all():
    ok, skipped = split_locked(changed_files())
    if not ok and not skipped:
        print("[i] Tidak ada file yang berubah.")
        return
    print(f"\nAkan push {len(ok)} file, {len(skipped)} dilewati karena terkunci.")
    for p, k in ok[:15]:
        print(f"  [{k}] {p}")
    if len(ok) > 15:
        print(f"  ... dan {len(ok) - 15} lainnya")
    if ok and input("Lanjut? (y/n): ").lower() == "y":
        commit_and_push(ok)


def push_folder():
    d = input("Folder: ").strip()
    if not d or not os.path.isdir(os.path.join(ORIG, d)):
        print("[!] Folder tidak ada.")
        return
    rf = to_rel(d).rstrip("/") + "/"
    if rf.startswith("../") or rf == "./":
        print("[!] Folder di luar repo / root repo. Pakai 'Push semua' untuk root.")
        return
    pat = is_locked(rf)
    if pat:
        print(f"[LOCKED] Folder dikunci (pola: {pat}). Dibatalkan.")
        return
    inside = [(p, k) for p, k in changed_files() if p.startswith(rf)]
    if not inside:
        print("[i] Tidak ada perubahan di folder itu (atau sudah ter-ignore/kosong).")
        return
    ok, skipped = split_locked(inside)
    print(f"\n{len(ok)} file akan di-push, {len(skipped)} dilewati karena terkunci.")
    for p, k in ok[:15]:
        print(f"  [{k}] {p}")
    if len(ok) > 15:
        print(f"  ... dan {len(ok) - 15} lainnya")
    if ok and input("Lanjut? (y/n): ").lower() == "y":
        commit_and_push(ok)


def push_menu():
    if need_connect():
        return
    ensure_default_locks()
    while True:
        print("\n--- Push ---")
        print("1. Pilih dari daftar")
        print("2. Push semua (kecuali terkunci)")
        print("3. Push 1 folder")
        print("4. Kembali")
        c = input("> ").strip()
        if c == "1":
            push_list()
        elif c == "2":
            push_all()
        elif c == "3":
            push_folder()
        elif c == "4":
            return


# ------------------------------------------------------------ connect repo
def mask_url(url):
    return re.sub(r"(://)[^/@]*@", r"\1****@", url)


def normalize_repo_url(raw):
    """Return (url_bersih, ada_token). None jika bukan URL repo GitHub yang valid."""
    raw = raw.strip()
    m = re.match(r"^(?:https?://)?(?:([^/@]*)@)?github\.com[/:]([\w.-]+)/([\w.-]+?)(?:\.git)?/?$", raw)
    if not m:
        return None, False
    userinfo, owner, repo = m.groups()
    return f"https://github.com/{owner}/{repo}.git", bool(userinfo) and userinfo != "git"


def ensure_gitignore():
    p = os.path.join(ROOT, ".gitignore")
    wanted = ["tokengit.txt", LOCK_FILE]
    have = open(p).read().splitlines() if os.path.exists(p) else []
    add = [w for w in wanted if w not in have]
    if not add:
        print("[i] .gitignore sudah memuat entri yang diperlukan.")
        return
    with open(p, "a") as f:
        if have and have[-1] != "":
            f.write("\n")
        f.write("\n".join(add) + "\n")
    print(f"[OK] .gitignore diperbarui: {', '.join(add)}")


def connect_repo():
    cur = git(["remote", "get-url", "origin"])
    if cur.returncode == 0:
        print(f"Origin sekarang: {mask_url(cur.stdout.strip())}")
    raw = input("URL repo GitHub (mis. https://github.com/user/repo.git): ").strip()
    url, had_token = normalize_repo_url(raw)
    if not url:
        print("[!] Bukan URL repo GitHub yang valid.")
        return
    if had_token:
        print("[i] URL yang ditempel berisi token; bagian itu dibuang. Token hanya dari Add ID.")
    if cur.returncode == 0:
        if cur.stdout.strip() != url and input("Origin sudah ada. Ganti? (y/n): ").lower() != "y":
            return
        r = git(["remote", "set-url", "origin", url])
    else:
        r = git(["remote", "add", "origin", url])
    if r.returncode:
        print("[!]", r.stderr.strip())
        return
    print(f"[OK] origin -> {url}")

    if not creds["token"]:
        print("[i] Belum connect, jadi akses repo belum dicek. Pilih Connect (menu 1), lalu ulangi menu ini untuk push pertama.")
        return
    env, ap = askpass_env()
    try:
        r = git(["ls-remote", "origin"], env=env)
    finally:
        os.remove(ap)
    if r.returncode:
        print("[!] Repo tidak bisa diakses dengan token ini:")
        print((r.stderr or r.stdout).strip())
        print("    Cek nama repo, dan pastikan token punya izin (Contents: write) ke repo itu.")
        return
    empty = not r.stdout.strip()
    print("[OK] Repo bisa diakses" + (" dan masih kosong." if empty else ", tapi SUDAH berisi commit."))
    if not empty:
        print("[!] Push pertama ke repo berisi riwayat lain bisa ditolak. Lebih aman pakai repo kosong.")

    if input("Buat/lengkapi .gitignore (tokengit.txt, .pushlock)? (y/n): ").lower() == "y":
        ensure_gitignore()
    if input("Lanjut push pertama sekarang? (y/n): ").lower() != "y":
        return
    ensure_default_locks()
    ok, skipped = split_locked(changed_files())
    print(f"\nAkan push {len(ok)} file, {len(skipped)} dilewati karena terkunci.")
    for p, k in ok[:15]:
        print(f"  [{k}] {p}")
    if len(ok) > 15:
        print(f"  ... dan {len(ok) - 15} lainnya")
    if ok and input("Lanjut? (y/n): ").lower() == "y":
        commit_and_push(ok)


# -------------------------------------------------------------------- main
def init_repo_here():
    print(f"[i] {ORIG} belum berupa repo git.")
    if input("Jalankan git init di sini (branch main)? (y/n): ").lower() != "y":
        return False
    r = subprocess.run(["git", "init", "-b", "main"], capture_output=True, text=True, cwd=ORIG)
    if r.returncode:  # git lama tanpa opsi -b
        subprocess.run(["git", "init"], capture_output=True, text=True, cwd=ORIG)
        subprocess.run(["git", "checkout", "-b", "main"], capture_output=True, text=True, cwd=ORIG)
    print("[OK] Repo git dibuat.")
    return True


def main():
    global ROOT
    ROOT = find_root()
    if not ROOT:
        if not init_repo_here():
            sys.exit(1)
        ROOT = find_root()
        if not ROOT:
            print("[!] git init gagal.")
            sys.exit(1)
    while True:
        st = f"terhubung: {creds['user']}" if creds["token"] else "belum connect"
        print(f"\n=== Git Push Termux ({st}) ===")
        print("1. Connect")
        print("2. Add ID")
        print("3. Connect repo (push pertama)")
        print("4. Push")
        print("5. Lock file")
        print("0. Keluar")
        c = input("> ").strip()
        if c == "1":
            connect()
        elif c == "2":
            add_id_menu()
        elif c == "3":
            connect_repo()
        elif c == "4":
            push_menu()
        elif c == "5":
            lock_menu()
        elif c == "0":
            sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("\nKeluar.")
