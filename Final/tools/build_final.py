#!/usr/bin/env python3
"""Task 099: build Final/ (engine). Stage data and texts are in stages.py.

Usage:  python3 Final/tools/build_final.py [--pin <commit>] [--srv <dir>] [--dry]

What it does (deterministic; rerunning rebuilds everything except Final/tools):
  * copies repository files from the PINNED commit (git show), never from the working tree
    (exceptions are listed in WORKTREE_EXCEPTIONS and flagged in the README / MANIFEST);
  * copies server files from the raw copy ~/Final_raw/server_run3 (default ~/Final_raw/server_run3, the complete raw copy; --srv ~/server_pull/run3 for the interim one);
  * stage scripts are the version that was IN FORCE when the stage ran: the newest commit whose
    commit time is <= the modification time of the stage's reference log (inferred, see README);
  * gzip for files > 20 MB, for big result formats (sdf/spef/def) and for annotate logs;
  * refuses (error, build stops) any path matching the confidentiality deny-list;
  * writes the index tables (INDEX.md, scripts/MANIFEST.md, docs/INDEX.md, tools/keys.tsv).
"""
import os, sys, re, gzip, hashlib, shutil, subprocess, fnmatch, argparse, datetime, io

HERE = os.path.dirname(os.path.abspath(__file__))
FINAL = os.path.dirname(HERE)
REPO = os.path.dirname(FINAL)

sys.path.insert(0, HERE)
import stages as ST          # noqa: E402

LIMIT_GZ = 20 * 1024 * 1024          # task rule 2: > 20 MB must be gzip-compressed
LIMIT_HARD = 50 * 1024 * 1024        # nothing above this in git
LIMIT_TOTAL = 400 * 1024 * 1024      # stop and tell the user
BIGFMT = ('.sdf', '.spef', '.def', '.gds', '.v')   # compressed when > 1 MB
DENY = re.compile(r'(DRC_TS18SL|ANTENNA_TS18SL|LVS_TS18SL|(^|/)scr(/|$)|tsl18fs120|scl18fs120|'
                  r'\.ndm(/|$)|\.dlib|(^|/)blocks(/|$)|\.lib$|\.db$|\.gds(\.gz)?$|\.def(\.gz)?$|(^|/)svdb(/|$)|'
                  r'(^|/)icv_run_|\.tf$|\.svf$)')
WORKTREE_EXCEPTIONS = {
    'scripts/run_gls.sh': 'untracked in git at the pinned commit (copied from the working tree)',
    'scripts/test_run_gls.sh': 'untracked in git at the pinned commit (copied from the working tree)',
    'docs/planning/tasks/099-final-folder.md': 'staged (git add) but not committed at the pinned commit',
    'pnr_v2/RUN3_RUNBOOK.md': 'modified after the pinned commit (step 11 commit sentence corrected, 2026-11-11); commit pending',
}

ROWS = {}        # rel path (in Final) -> dict(size, sha, osha, origin)
LOCAL = []       # local-only index rows (name, size, sha256, why)
WARN = []        # things the user must see
STAGE_SCRIPTS = {}   # stage -> list of dict(dest, repo, asrun_hash, asrun_ct, pin_hash, differs, note)


def die(msg):
    print('BUILD ERROR: ' + msg, file=sys.stderr)
    sys.exit(2)


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def git(*a, check=True):
    r = subprocess.run(['git', '-C', REPO] + list(a), capture_output=True)
    if check and r.returncode != 0:
        die('git %s: %s' % (' '.join(a), r.stderr.decode(errors='replace')))
    return r.stdout


class Ctx:
    pin = None
    srv = None
    tree = None          # set of all files at the pin
    logcache = {}


def git_files():
    return [l for l in git('ls-tree', '-r', '--name-only', Ctx.pin).decode().split('\n') if l]


def git_content(path, rev=None):
    if rev is None and path in WORKTREE_EXCEPTIONS:
        with open(os.path.join(REPO, path), 'rb') as f:
            return f.read()
    return git('show', '%s:%s' % (rev or Ctx.pin, path))


def origin(path):
    return 'worktree:' + path if path in WORKTREE_EXCEPTIONS else 'git:%s:%s' % (Ctx.pin[:7], path)


def git_hist(path):
    """newest-first list of (hash, committer time, subject) of the commits touching path, up to the pin"""
    if path not in Ctx.logcache:
        out = git('log', '--format=%H%x09%ct%x09%s', Ctx.pin, '--', path).decode().strip().split('\n')
        Ctx.logcache[path] = [tuple(l.split('\t', 2)) for l in out if l]
    return [(h, int(ct), s) for h, ct, s in Ctx.logcache[path]]


def is_denied(rel):
    return DENY.search(rel) is not None


def emit(rel, data, origin, compress=None):
    """write bytes into Final/rel (gzip when needed); record the row; return the stored rel path"""
    if is_denied(rel):
        die('confidentiality deny-list matches %r (origin %s)' % (rel, origin))
    osha = sha256_bytes(data)
    big = len(data) > LIMIT_GZ
    if compress is None:
        compress = big or (rel.endswith(BIGFMT) and len(data) > (1 << 20)) or \
            ('annotate' in os.path.basename(rel) and len(data) > (1 << 20))
    if compress and not rel.endswith('.gz'):
        buf = io.BytesIO()
        with gzip.GzipFile(filename='', mode='wb', fileobj=buf, mtime=0, compresslevel=9) as g:
            g.write(data)
        data2 = buf.getvalue()
        rel2 = rel + '.gz'
    else:
        data2, rel2 = data, rel
    if len(data2) > LIMIT_HARD:
        die('%s is %d bytes after compression (> 50 MB)' % (rel2, len(data2)))
    path = os.path.join(FINAL, rel2)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data2)
    ROWS[rel2] = dict(size=len(data2), sha=sha256_bytes(data2), osha=(osha if rel2 != rel else ''),
                      origin=origin)
    return rel2


def emit_srv(rel, src, compress=None, origin_prefix='srv:'):
    with open(src, 'rb') as f:
        data = f.read()
    return emit(rel, data, origin_prefix + os.path.relpath(src, Ctx.srv), compress)


def srv_path(sub):
    return os.path.join(Ctx.srv, sub)


def srv_walk(sub, excl_dirs=(), excl_files=()):
    base = srv_path(sub)
    if os.path.isfile(base):
        return [base]
    if not os.path.isdir(base):
        return []
    out = []
    for root, dirs, files in os.walk(base):
        dirs[:] = sorted(d for d in dirs if d not in excl_dirs)
        for fn in sorted(files):
            if any(fnmatch.fnmatch(fn, p) for p in excl_files):
                continue
            out.append(os.path.join(root, fn))
    return out


def copy_srv_dir(sub, dest, excl_dirs=(), excl_files=(), only=None, compress=None):
    n = 0
    base = srv_path(sub)
    for p in srv_walk(sub, excl_dirs, excl_files):
        rel = os.path.relpath(p, base)
        if only and not any(fnmatch.fnmatch(os.path.basename(p), o) for o in only):
            continue
        emit_srv(os.path.join(dest, rel), p, compress)
        n += 1
    if n == 0:
        WARN.append('NOTHING copied from server path %s (missing?)' % sub)
    return n


def mtime(sub):
    p = srv_path(sub)
    return int(os.path.getmtime(p)) if os.path.exists(p) else None


def ref_time(refs):
    ts = [mtime(r) for r in refs]
    ts = [t for t in ts if t]
    return max(ts) if ts else None


def fmt_t(ct):
    return datetime.datetime.fromtimestamp(ct).strftime('%Y-%m-%d %H:%M')


def copy_git_scripts(stage, items, dest_dir, ref):
    """items: list of repo paths; the as-run version is picked by commit time <= ref"""
    rows = []
    for rp in items:
        hist = git_hist(rp) if rp in Ctx.tree else []
        if rp in WORKTREE_EXCEPTIONS:
            with open(os.path.join(REPO, rp), 'rb') as f:
                data = f.read()
            rel = emit(os.path.join(dest_dir, os.path.basename(rp)), data, 'worktree:' + rp)
            rows.append(dict(dest=rel, repo=rp, ash='(working tree)', act=0, phash='-', differs='',
                             note=WORKTREE_EXCEPTIONS[rp]))
            continue
        if rp not in Ctx.tree:
            die('stage %s: %s is not in the pinned commit' % (stage, rp))
        phash = hist[0][0]
        pick, note = hist[0], ''
        if ref:
            cand = [h for h in hist if h[1] <= ref]
            if cand:
                pick = cand[0]
            else:
                pick = hist[-1]
                note = 'FIRST COMMIT IS NEWER THAN THE RUN (oldest version used)'
        data = git_content(rp, pick[0])
        differs = 'yes' if pick[0] != phash else 'no'
        rel = emit(os.path.join(dest_dir, os.path.basename(rp)), data,
                   'git:%s:%s' % (pick[0][:7], rp))
        rows.append(dict(dest=rel, repo=rp, ash=pick[0][:7], act=pick[1], phash=phash[:7],
                         differs=differs, note=note, subj=pick[2]))
    STAGE_SCRIPTS.setdefault(stage, []).extend(rows)
    return rows


def copy_git_pinned(items, dest_dir, keep_tree=True):
    """pinned copies (docs): items are repo paths; destination keeps the basename"""
    n = 0
    for rp in items:
        if rp in WORKTREE_EXCEPTIONS:
            with open(os.path.join(REPO, rp), 'rb') as f:
                data = f.read()
            origin = 'worktree:' + rp
        else:
            if rp not in Ctx.tree:
                die('%s is not in the pinned commit' % rp)
            data = git_content(rp)
            origin = 'git:%s:%s' % (Ctx.pin[:7], rp)
        emit(os.path.join(dest_dir, os.path.basename(rp)) if not keep_tree else os.path.join(dest_dir, rp),
             data, origin)
        n += 1
    return n


def expand(patterns):
    out = []
    for p in patterns:
        if any(c in p for c in '*?['):
            m = sorted(f for f in Ctx.tree if fnmatch.fnmatch(f, p))
            if not m:
                die('pattern %s matches nothing at the pin' % p)
            out.extend(m)
        else:
            out.append(p)
    seen, res = set(), []
    for o in out:
        if o not in seen:
            seen.add(o)
            res.append(o)
    return res


# ----------------------------------------------------------------------------------- local only
def local_index(sub, why):
    """index (name, size, sha256) of server files that stay local; nothing is copied"""
    for p in srv_walk(sub):
        LOCAL.append(dict(name=os.path.relpath(p, Ctx.srv), size=os.path.getsize(p),
                          sha=sha256_file(p), why=why))


def tree_hash(sub):
    """aggregate for a directory tree that stays local: file count, bytes, sha256 over the sorted 'sha  relpath' lines"""
    base = srv_path(sub)
    lines, tot = [], 0
    for root, dirs, files in os.walk(base):
        dirs.sort()
        for fn in sorted(files):
            p = os.path.join(root, fn)
            if os.path.islink(p):
                continue
            tot += os.path.getsize(p)
            lines.append('%s  %s' % (sha256_file(p), os.path.relpath(p, base)))
    return len(lines), tot, sha256_bytes('\n'.join(sorted(lines, key=lambda l: l.split('  ', 1)[1])).encode())


def local_index_tree(sub, why):
    n, tot, h = tree_hash(sub)
    LOCAL.append(dict(name=sub + '/ (%d files, tree sha256 = sha256 of the sorted "sha256  relpath" lines)' % n,
                      size=tot, sha=h, why=why))




# ----------------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pin', default=None)
    ap.add_argument('--srv', default=os.path.expanduser('~/Final_raw/server_run3'))
    ap.add_argument('--keep', action='store_true', help='do not delete the generated folders first')
    a = ap.parse_args()
    Ctx.pin = git('rev-parse', a.pin or ST.PIN_DEFAULT).decode().strip()
    Ctx.srv = a.srv
    if not os.path.isdir(Ctx.srv):
        die('server copy %s does not exist' % Ctx.srv)
    Ctx.tree = set(git_files())

    if not a.keep:
        for d in sorted(os.listdir(FINAL)):
            p = os.path.join(FINAL, d)
            if d == 'tools':
                continue
            shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)

    ST.build(sys.modules[__name__])      # stage folders, scripts/, docs/
    ST.write_indexes(sys.modules[__name__])
    tot = sum(r['size'] for r in ROWS.values())
    print('files in git: %d, bytes: %d (%.1f MB)' % (len(ROWS), tot, tot / 1048576))
    for w in WARN:
        print('WARNING: ' + w)
    if tot > LIMIT_TOTAL:
        print('STOP: total over 400 MB -- tell the user before committing anything')
        sys.exit(3)


if __name__ == '__main__':
    main()
