from __future__ import annotations

from typing import Optional

from flask import Request


def _first_forwarded_value(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    # Proxies may send comma-separated lists; the first is the original client-facing value.
    return value.split(",")[0].strip() or None


def get_public_base_url(req: Request, fallback_base_url: str) -> str:
    """
    Build a public-facing base URL (scheme://host[:port]) for links returned to clients.

    Prefers reverse-proxy headers when present; otherwise falls back to Flask's view of the
    request, and finally to `fallback_base_url` (typically `settings.API_URL`).
    """

    forwarded_proto = _first_forwarded_value(req.headers.get("X-Forwarded-Proto"))
    forwarded_host = _first_forwarded_value(req.headers.get("X-Forwarded-Host"))
    host = forwarded_host or req.headers.get("Host")
    scheme = forwarded_proto or req.scheme

    if host and scheme:
        return f"{scheme}://{host}".rstrip("/")

    return (req.url_root or fallback_base_url).rstrip("/")

