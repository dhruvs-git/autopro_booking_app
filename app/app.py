import os
import json
import time
import logging
import requests
import redis
from functools import wraps
from flask import Flask, jsonify, request
from datetime import datetime
from jose import jwt, JWTError
import mysql.connector

# =============================================================================
# LOGGING
# Structured JSON logging — every request logged to CloudWatch
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# =============================================================================
# CONFIG
# All values written to /etc/autoserve/*.env by user_data.sh at EC2 startup.
# systemd loads both env files before starting Flask.
# Nothing is hardcoded here.
# =============================================================================
AWS_REGION           = os.environ["AWS_REGION"]
COGNITO_USER_POOL_ID = os.environ["COGNITO_USER_POOL_ID"]
COGNITO_CLIENT_ID    = os.environ["COGNITO_CLIENT_ID"]
REDIS_HOST           = os.environ["REDIS_HOST"]

# =============================================================================
# REDIS CLIENT
# decode_responses=True means Redis returns str, not bytes.
# =============================================================================
cache = redis.Redis(host=REDIS_HOST, port=6379, db=0, decode_responses=True)

# =============================================================================
# DATABASE CONNECTION
# Credentials read from /etc/autoserve/db.env — fetched from Secrets Manager
# by user_data.sh at startup. No credentials anywhere in this file.
# =============================================================================
def get_db_connection():
    return mysql.connector.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ["DB_PORT"]),
        database=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"]
    )

# =============================================================================
# JWT VALIDATION
# Cognito signs JWTs with RSA keys. The public keys are at a well-known URL.
# We fetch them once and cache in memory — no HTTP call on every request.
# On each request: extract kid from token header → find matching key → verify.
# =============================================================================
_jwks_cache = {"keys": None, "fetched_at": 0}
JWKS_TTL = 3600  # refresh public keys every hour

def _get_jwks():
    if _jwks_cache["keys"] is None or time.time() - _jwks_cache["fetched_at"] > JWKS_TTL:
        url = (
            f"https://cognito-idp.{AWS_REGION}.amazonaws.com"
            f"/{COGNITO_USER_POOL_ID}/.well-known/jwks.json"
        )
        _jwks_cache["keys"] = requests.get(url, timeout=5).json()["keys"]
        _jwks_cache["fetched_at"] = time.time()
    return _jwks_cache["keys"]

def verify_token(token):
    keys = _get_jwks()
    header = jwt.get_unverified_header(token)
    key = next((k for k in keys if k["kid"] == header["kid"]), None)
    if not key:
        raise JWTError("Unknown signing key")
    return jwt.decode(token, key, algorithms=["RS256"], audience=COGNITO_CLIENT_ID)

def _get_bearer_token():
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    return auth.split(" ", 1)[1]

# =============================================================================
# AUTH DECORATORS
# @require_auth  — any logged-in user. Injects claims into the route.
# @require_admin — admins group only. Returns 403 for everyone else.
# =============================================================================
def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = _get_bearer_token()
        if not token:
            return jsonify({"error": "Missing authorization token"}), 401
        try:
            claims = verify_token(token)
        except JWTError:
            return jsonify({"error": "Invalid or expired token"}), 401
        return f(claims, *args, **kwargs)
    return decorated

def require_admin(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = _get_bearer_token()
        if not token:
            return jsonify({"error": "Missing authorization token"}), 401
        try:
            claims = verify_token(token)
        except JWTError:
            return jsonify({"error": "Invalid or expired token"}), 401
        if "admins" not in claims.get("cognito:groups", []):
            return jsonify({"error": "Admin access required"}), 403
        return f(claims, *args, **kwargs)
    return decorated

# =============================================================================
# CACHE HELPERS
# All Redis calls are wrapped in try/except — if Redis is down the app
# keeps working, it just skips caching.
# =============================================================================
CACHE_TTL = 60  # seconds

def cache_get(key):
    try:
        val = cache.get(key)
        return json.loads(val) if val else None
    except Exception:
        return None

def cache_set(key, value):
    try:
        cache.setex(key, CACHE_TTL, json.dumps(value))
    except Exception:
        pass

def cache_delete(*keys):
    try:
        cache.delete(*keys)
    except Exception:
        pass

# =============================================================================
# DATABASE INITIALISATION
# Creates the bookings table if it does not exist. Runs once on startup.
# =============================================================================
def init_db():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS bookings (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                user_id     VARCHAR(255) NOT NULL,
                vehicle     VARCHAR(255) NOT NULL,
                service     VARCHAR(255) NOT NULL,
                date        DATE NOT NULL,
                time_slot   VARCHAR(50) NOT NULL,
                status      ENUM('pending', 'confirmed', 'in_progress', 'completed', 'cancelled')
                            DEFAULT 'pending',
                created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        cursor.close()
        conn.close()
        logger.info("Database initialised successfully")
    except Exception as e:
        logger.error(f"Database initialisation failed: {str(e)}")

# =============================================================================
# HEALTH CHECK
# ALB hits this every 30 seconds — no auth required.
# =============================================================================
@app.route("/health", methods=["GET"])
def health():
    try:
        conn = get_db_connection()
        conn.close()
        return jsonify({"status": "healthy", "database": "connected"}), 200
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({"status": "unhealthy", "error": str(e)}), 500

# =============================================================================
# CREATE BOOKING
# POST /bookings
# Body: { "vehicle", "service", "date", "time_slot" }
# user_id is taken from the JWT sub claim — never from the request body.
# =============================================================================
@app.route("/bookings", methods=["POST"])
@require_auth
def create_booking(claims):
    try:
        data = request.get_json()
        required = ["vehicle", "service", "date", "time_slot"]
        for field in required:
            if field not in data:
                return jsonify({"error": f"Missing field: {field}"}), 400

        user_id = claims["sub"]

        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute("""
                INSERT INTO bookings (user_id, vehicle, service, date, time_slot)
                VALUES (%s, %s, %s, %s, %s)
            """, (user_id, data["vehicle"], data["service"], data["date"], data["time_slot"]))
            conn.commit()
            booking_id = cursor.lastrowid
        finally:
            cursor.close()
            conn.close()

        cache_delete(f"bookings:{user_id}")
        logger.info(f"Booking created: {booking_id} for user: {user_id}")
        return jsonify({"message": "Booking created successfully", "booking_id": booking_id}), 201

    except Exception as e:
        logger.error(f"Create booking failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# GET BOOKINGS
# GET /bookings        — returns the caller's own bookings
# GET /bookings?all=true — admins only, returns all bookings
# =============================================================================
@app.route("/bookings", methods=["GET"])
@require_auth
def get_bookings(claims):
    try:
        user_id  = claims["sub"]
        groups   = claims.get("cognito:groups", [])
        show_all = request.args.get("all") == "true" and "admins" in groups

        cache_key = "bookings:all" if show_all else f"bookings:{user_id}"
        cached = cache_get(cache_key)
        if cached is not None:
            return jsonify({"bookings": cached, "source": "cache"}), 200

        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        try:
            if show_all:
                cursor.execute("SELECT * FROM bookings ORDER BY created_at DESC")
            else:
                cursor.execute(
                    "SELECT * FROM bookings WHERE user_id = %s ORDER BY created_at DESC",
                    (user_id,)
                )
            bookings = cursor.fetchall()
        finally:
            cursor.close()
            conn.close()

        for b in bookings:
            for key, value in b.items():
                if hasattr(value, 'isoformat'):
                    b[key] = value.isoformat()

        cache_set(cache_key, bookings)
        return jsonify({"bookings": bookings, "source": "db"}), 200

    except Exception as e:
        logger.error(f"Get bookings failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# GET SINGLE BOOKING
# GET /bookings/<id>
# Customers can only fetch their own booking. Admins can fetch any.
# =============================================================================
@app.route("/bookings/<int:booking_id>", methods=["GET"])
@require_auth
def get_booking(claims, booking_id):
    try:
        cached = cache_get(f"booking:{booking_id}")
        if cached is not None:
            groups = claims.get("cognito:groups", [])
            if "admins" not in groups and cached["user_id"] != claims["sub"]:
                return jsonify({"error": "Access denied"}), 403
            return jsonify({"booking": cached, "source": "cache"}), 200

        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute("SELECT * FROM bookings WHERE id = %s", (booking_id,))
            booking = cursor.fetchone()
        finally:
            cursor.close()
            conn.close()

        if not booking:
            return jsonify({"error": "Booking not found"}), 404

        groups = claims.get("cognito:groups", [])
        if "admins" not in groups and booking["user_id"] != claims["sub"]:
            return jsonify({"error": "Access denied"}), 403

        for key, value in booking.items():
            if hasattr(value, 'isoformat'):
                booking[key] = value.isoformat()

        cache_set(f"booking:{booking_id}", booking)
        return jsonify({"booking": booking, "source": "db"}), 200

    except Exception as e:
        logger.error(f"Get booking failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# UPDATE BOOKING STATUS
# PUT /bookings/<id>/status
# Body: { "status": "confirmed" }
# Admin only.
# =============================================================================
@app.route("/bookings/<int:booking_id>/status", methods=["PUT"])
@require_admin
def update_booking_status(claims, booking_id):
    try:
        data = request.get_json()
        valid_statuses = ["pending", "confirmed", "in_progress", "completed", "cancelled"]
        if "status" not in data or data["status"] not in valid_statuses:
            return jsonify({"error": f"Status must be one of: {valid_statuses}"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "UPDATE bookings SET status = %s WHERE id = %s",
                (data["status"], booking_id)
            )
            conn.commit()
            rowcount = cursor.rowcount
        finally:
            cursor.close()
            conn.close()

        if rowcount == 0:
            return jsonify({"error": "Booking not found"}), 404

        cache_delete(f"booking:{booking_id}", "bookings:all")
        logger.info(f"Booking {booking_id} status updated to {data['status']}")
        return jsonify({"message": "Status updated successfully"}), 200

    except Exception as e:
        logger.error(f"Update status failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# CANCEL BOOKING
# DELETE /bookings/<id>
# Booking owner or admin can cancel.
# =============================================================================
@app.route("/bookings/<int:booking_id>", methods=["DELETE"])
@require_auth
def cancel_booking(claims, booking_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute("SELECT user_id FROM bookings WHERE id = %s", (booking_id,))
            booking = cursor.fetchone()

            if not booking:
                return jsonify({"error": "Booking not found"}), 404

            groups = claims.get("cognito:groups", [])
            if "admins" not in groups and booking["user_id"] != claims["sub"]:
                return jsonify({"error": "Access denied"}), 403

            cursor.execute(
                "UPDATE bookings SET status = %s WHERE id = %s",
                ("cancelled", booking_id)
            )
            conn.commit()
        finally:
            cursor.close()
            conn.close()

        cache_delete(f"booking:{booking_id}", f"bookings:{booking['user_id']}", "bookings:all")
        logger.info(f"Booking {booking_id} cancelled")
        return jsonify({"message": "Booking cancelled"}), 200

    except Exception as e:
        logger.error(f"Cancel booking failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# ENTRY POINT
# host="0.0.0.0" — Flask accepts connections from any IP (required for ALB).
# debug=False     — never run debug mode in production.
# =============================================================================
if __name__ == "__main__":
    logger.info("Starting AutoServe Pro")
    init_db()
    app.run(host="0.0.0.0", port=5000, debug=False)
