import os
import platform
import uuid
import logging

import dotenv
from flask import Flask, jsonify, redirect, request
from jose import jwt

from application.auth import handle_auth

from application.core.logging_config import clear_request_id, set_request_id, setup_logging

setup_logging()
logger = logging.getLogger(__name__)

from application.api import api  # noqa: E402
from application.api.answer import answer  # noqa: E402
from application.api.internal.routes import internal  # noqa: E402
from application.api.user.routes import user  # noqa: E402
from application.api.connector.routes import connector  # noqa: E402
from application.celery_init import celery  # noqa: E402
from application.core.service_checks import (  # noqa: E402
    log_startup_diagnostics,
    required_service_checks,
    run_startup_dependency_checks,
    summarize_checks,
)
from application.core.settings import settings  # noqa: E402


if platform.system() == "Windows":
    import pathlib

    pathlib.PosixPath = pathlib.WindowsPath
dotenv.load_dotenv()

app = Flask(__name__)
app.register_blueprint(user)
app.register_blueprint(answer)
app.register_blueprint(internal)
app.register_blueprint(connector)
app.config.update(
    UPLOAD_FOLDER="inputs",
    CELERY_BROKER_URL=settings.CELERY_BROKER_URL,
    CELERY_RESULT_BACKEND=settings.CELERY_RESULT_BACKEND,
    MONGO_URI=settings.MONGO_URI,
)
celery.config_from_object("application.celeryconfig")
api.init_app(app)
log_startup_diagnostics(logger)
run_startup_dependency_checks(logger)

if settings.AUTH_TYPE in ("simple_jwt", "session_jwt") and not settings.JWT_SECRET_KEY:
    key_file = ".jwt_secret_key"
    try:
        with open(key_file, "r") as f:
            settings.JWT_SECRET_KEY = f.read().strip()
    except FileNotFoundError:
        new_key = os.urandom(32).hex()
        with open(key_file, "w") as f:
            f.write(new_key)
        settings.JWT_SECRET_KEY = new_key
    except Exception as e:
        raise RuntimeError(f"Failed to setup JWT_SECRET_KEY: {e}")
SIMPLE_JWT_TOKEN = None
if settings.AUTH_TYPE == "simple_jwt":
    payload = {"sub": "local"}
    SIMPLE_JWT_TOKEN = jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm="HS256")
    print(f"Generated Simple JWT Token: {SIMPLE_JWT_TOKEN}")


@app.route("/")
def home():
    if request.remote_addr in ("0.0.0.0", "127.0.0.1", "localhost", "172.18.0.1"):
        return redirect("http://localhost:5173")
    else:
        return "Welcome to DocsGPT Backend!"


@app.route("/api/config")
def get_config():
    response = {
        "auth_type": settings.AUTH_TYPE,
        "requires_auth": settings.AUTH_TYPE in ["simple_jwt", "session_jwt"],
    }
    return jsonify(response)


@app.route("/api/health")
def healthcheck():
    return jsonify({"status": "ok", "service": "backend"})


@app.route("/api/ready")
def readiness_check():
    checks = required_service_checks()
    all_ok, payload = summarize_checks(checks)
    status_code = 200 if all_ok else 503
    return jsonify({"status": "ready" if all_ok else "degraded", "checks": payload}), status_code


@app.route("/api/generate_token")
def generate_token():
    if settings.AUTH_TYPE == "session_jwt":
        new_user_id = str(uuid.uuid4())
        token = jwt.encode({"sub": new_user_id}, settings.JWT_SECRET_KEY, algorithm="HS256")
        return jsonify({"token": token})
    return jsonify({"error": "Token generation not allowed in current auth mode"}), 400


@app.before_request
def authenticate_request():
    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    set_request_id(request_id)
    request.request_id = request_id
    if request.method == "OPTIONS":
        return "", 200
    decoded_token = handle_auth(request)
    if not decoded_token:
        request.decoded_token = None
    elif "error" in decoded_token:
        return jsonify(decoded_token), 401
    else:
        request.decoded_token = decoded_token


@app.after_request
def after_request(response):
    response.headers.add("X-Request-ID", getattr(request, "request_id", "-"))
    response.headers.add("Access-Control-Allow-Origin", "*")
    response.headers.add("Access-Control-Allow-Headers", "Content-Type, Authorization")
    response.headers.add("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    logger.info(
        "request completed",
        extra={
            "status_code": response.status_code,
            "method": request.method,
            "path": request.path,
        },
    )
    return response


@app.teardown_request
def teardown_request(_exc):
    clear_request_id()


if __name__ == "__main__":
    app.run(debug=settings.FLASK_DEBUG_MODE, port=7091)
