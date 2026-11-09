"""Open the session DB writable once so Hermes applies pending schema
migrations at boot (volumes from older releases otherwise make read-only
commands like `hermes sessions list` fail until something writes).
No-op on an up-to-date or missing DB."""

import os
import sys
from pathlib import Path

db_path = Path(os.environ.get("HERMES_HOME", "/opt/data/data_dir")) / "state.db"
if not db_path.exists():
    sys.exit(0)

from hermes_state import SessionDB  # noqa: E402

db = SessionDB(db_path)
close = getattr(db, "close", None)
if callable(close):
    close()
print("[akash] session database is up to date", flush=True)
