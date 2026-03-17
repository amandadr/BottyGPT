import contextvars
import json
import logging
import os
from datetime import UTC, datetime
from logging.config import dictConfig

from flask import has_request_context, request

request_id_var: contextvars.ContextVar[str] = contextvars.ContextVar("request_id", default="-")


def set_request_id(request_id: str) -> None:
    request_id_var.set(request_id)


def clear_request_id() -> None:
    request_id_var.set("-")


class RequestContextFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get()
        record.service = os.getenv("DOCSGPT_SERVICE_NAME", "docsgpt-backend")
        return True


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(UTC).isoformat(),
            "severity": record.levelname,
            "level": record.levelname,
            "logger": record.name,
            "service": getattr(record, "service", "docsgpt-backend"),
            "request_id": getattr(record, "request_id", "-"),
            "message": record.getMessage(),
        }
        if has_request_context():
            payload["method"] = request.method
            payload["path"] = request.path
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=True)


def setup_logging() -> None:
    dictConfig(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "filters": {"request_context": {"()": "application.core.logging_config.RequestContextFilter"}},
            "formatters": {"structured": {"()": "application.core.logging_config.JsonFormatter"}},
            "handlers": {
                "console": {
                    "class": "logging.StreamHandler",
                    "stream": "ext://sys.stdout",
                    "formatter": "structured",
                    "filters": ["request_context"],
                }
            },
            "root": {
                "level": os.getenv("LOG_LEVEL", "INFO"),
                "handlers": ["console"],
            },
        }
    )
