"""Save a site -> profile choice into the learned block of ~/.finicky.js.
Usage: learn.py <host> <profile>   or   learn.py --forget <host>"""
import json, os, re, sys

forget = sys.argv[1] == "--forget"
host = sys.argv[2] if forget else sys.argv[1]
path = os.path.expanduser("~/.finicky.js")
src = open(path).read()
pattern = re.compile(r"(// learned:start\nconst learned = )(\{.*?\})(;\n// learned:end)", re.S)
m = pattern.search(src)
if not m:
    sys.exit("learned block not found in ~/.finicky.js")
learned = json.loads(m.group(2))
if forget:
    learned.pop(host, None)
else:
    learned[host] = sys.argv[2]
block = json.dumps(dict(sorted(learned.items())), indent=2)
# Write in place: replacing the file breaks Finicky's file watcher.
with open(path, "w") as f:
    f.write(src[: m.start(2)] + block + src[m.end(2) :])
