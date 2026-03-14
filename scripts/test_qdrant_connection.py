#!/usr/bin/env python3
"""
Minimal Qdrant connectivity test for debugging without using the DocsGPT UI.

Usage:
  From repo root (loads .env from repo):
    python scripts/test_qdrant_connection.py

  With explicit URL:
    QDRANT_URL=http://qdrant:6333 python scripts/test_qdrant_connection.py

  On a server/container, ensure QDRANT_URL (and optionally QDRANT_API_KEY,
  QDRANT_COLLECTION_NAME) are set in the environment or in a .env file.

Exits 0 on success, 1 on connection/config error. No application imports;
only qdrant_client and python-dotenv are required.
"""

import os
import sys
from pathlib import Path

# Load .env from repo root when run as scripts/test_qdrant_connection.py
try:
    from dotenv import load_dotenv
    repo_root = Path(__file__).resolve().parent.parent
    load_dotenv(repo_root / ".env")
    load_dotenv()  # override with cwd .env if present
except ImportError:
    pass  # rely on env vars only

QDRANT_URL = os.environ.get("QDRANT_URL")
QDRANT_API_KEY = os.environ.get("QDRANT_API_KEY") or None
QDRANT_COLLECTION_NAME = os.environ.get("QDRANT_COLLECTION_NAME", "docsgpt")


def main() -> int:
    if not QDRANT_URL:
        print("Error: QDRANT_URL is not set. Set it in .env or the environment.", file=sys.stderr)
        return 1

    try:
        from qdrant_client import QdrantClient
    except ImportError:
        print("Error: qdrant-client is not installed. Install with: pip install qdrant-client", file=sys.stderr)
        return 1

    print(f"Connecting to Qdrant at {QDRANT_URL} ...")
    try:
        client = QdrantClient(url=QDRANT_URL, api_key=QDRANT_API_KEY, timeout=10.0)
        collections = client.get_collections()
        names = [c.name for c in collections.collections]
        print(f"OK. Connected. Collections: {names or '(none)'}")

        if QDRANT_COLLECTION_NAME and QDRANT_COLLECTION_NAME not in names:
            print(f"Note: configured collection '{QDRANT_COLLECTION_NAME}' does not exist yet (will be created on first use).")
        elif QDRANT_COLLECTION_NAME and QDRANT_COLLECTION_NAME in names:
            info = client.get_collection(QDRANT_COLLECTION_NAME)
            print(f"Collection '{QDRANT_COLLECTION_NAME}': points_count={info.points_count}")
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
