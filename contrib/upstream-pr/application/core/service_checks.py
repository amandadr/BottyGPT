"""Dependency checks for Redis, Mongo, and Qdrant (when enabled). Used by /api/ready and healthcheck CLI."""

from dataclasses import dataclass
from typing import Dict, Tuple
from urllib.parse import urlparse

import redis
from pymongo import MongoClient
from qdrant_client import QdrantClient

from application.core.settings import settings


@dataclass
class CheckResult:
    """Result of a single dependency check."""

    ok: bool
    detail: str


def _check_redis(url: str) -> CheckResult:
    """Ping Redis at the given URL."""
    try:
        client = redis.Redis.from_url(url, socket_connect_timeout=2, socket_timeout=2)
        if client.ping():
            return CheckResult(ok=True, detail="redis ping successful")
        return CheckResult(ok=False, detail="redis ping failed")
    except Exception as exc:
        return CheckResult(ok=False, detail=f"redis connection failed: {exc}")


def _check_mongo(uri: str) -> CheckResult:
    """Ping MongoDB at the given URI."""
    client = None
    try:
        client = MongoClient(uri, serverSelectionTimeoutMS=2000)
        client.admin.command("ping")
        return CheckResult(ok=True, detail="mongo ping successful")
    except Exception as exc:
        return CheckResult(ok=False, detail=f"mongo connection failed: {exc}")
    finally:
        if client is not None:
            client.close()


def _check_qdrant(url: str) -> CheckResult:
    """Check Qdrant API at the given URL."""
    try:
        client = QdrantClient(url=url, api_key=settings.QDRANT_API_KEY, timeout=2.0)
        client.get_collections()
        return CheckResult(ok=True, detail="qdrant API reachable")
    except Exception as exc:
        return CheckResult(ok=False, detail=f"qdrant connection failed: {exc}")


def _is_qdrant_enabled() -> bool:
    return settings.VECTOR_STORE.lower() == "qdrant"


def _normalize_host(value: str) -> str:
    """Extract hostname from URL for display."""
    parsed = urlparse(value)
    return parsed.hostname or value


def required_service_checks() -> Dict[str, CheckResult]:
    """Run checks for Redis, Mongo, and Qdrant (if vector store is qdrant)."""
    checks: Dict[str, CheckResult] = {
        "redis": _check_redis(settings.CELERY_BROKER_URL),
        "mongo": _check_mongo(settings.MONGO_URI),
    }
    if _is_qdrant_enabled():
        qdrant_url = settings.QDRANT_URL or "http://qdrant:6333"
        checks["qdrant"] = _check_qdrant(qdrant_url)
    return checks


def summarize_checks(checks: Dict[str, CheckResult]) -> Tuple[bool, Dict[str, dict]]:
    """Convert check results to a payload and overall ok flag."""
    all_ok = all(result.ok for result in checks.values())
    payload = {
        name: {"ok": result.ok, "detail": result.detail} for name, result in checks.items()
    }
    return all_ok, payload
