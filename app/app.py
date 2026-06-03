import os
import json
import time
import logging
import requests
import redis
from functools import wraps
from flask import Flask, jsonify, request
from jose import jwt, JWTError
import mysql.connector

# =============================================================================
# LOGGING — Structured JSON
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# =============================================================================
# CONFIGURATION — All values from environment variables
# Injected by user_data.sh from Terraform templatefile()
# Nothing hardcoded here ever
# =============================================================================
AWS_REGION           = os.environ["AWS_REGION"]
COGNITO_USER_POOL_ID = os.environ["COGNITO_USER_POOL_ID"]
COGNITO_CLIENT_ID    = os.environ["COGNITO_CLIENT_ID"]
REDIS_HOST           = os.environ["REDIS_HOST"]
REDIS_PORT           = 6379

COGNITO_KEYS_URL = (
    f"https://cognito-idp.{AWS_REGION}.amazonaws.com/"
    f"{COGNITO_USER_POOL_ID}/.well-known/jwks.json"
)

# =============================================================================
# REDIS CLIENT
# decode_responses=True — returns strings not bytes
# socket_connect_timeout=5 — don't hang forever if Redis is down
# =============================================================================
cache = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    decode_responses=True,
    socket_connect_timeout=5
)

# =============================================================================
# DATABASE CONNECTION
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
# DATABASE INITIALISATION
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
                status      ENUM('pending','confirmed','in_progress','completed','cancelled')
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
# JWT VALIDATION
# Public keys fetched once and cached in memory for 1 hour.
# Matching by kid (key ID in token header) — more efficient than trying all keys.
# =============================================================================
_jwks_cache = {"keys": None, "fetched_at": 0}
JWKS_TTL = 3600

def _get_jwks():
    if _jwks_cache["keys"] is None or time.time() - _jwks_cache["fetched_at"] > JWKS_TTL:
        try:
            _jwks_cache["keys"] = requests.get(COGNITO_KEYS_URL, timeout=5).json()["keys"]
            _jwks_cache["fetched_at"] = time.time()
        except Exception as e:
            logger.error(f"Failed to fetch Cognito public keys: {str(e)}")
    return _jwks_cache["keys"]

def validate_token(token):
    keys = _get_jwks()
    if not keys:
        return None
    try:
        header = jwt.get_unverified_header(token)
        key = next((k for k in keys if k["kid"] == header["kid"]), None)
        if not key:
            raise JWTError("Unknown signing key")
        claims = jwt.decode(token, key, algorithms=["RS256"], audience=COGNITO_CLIENT_ID)
        return claims
    except JWTError as e:
        logger.warning(f"JWT validation failed: {str(e)}")
        return None

# =============================================================================
# AUTH DECORATORS
# require_auth  — any logged-in user (customer or admin)
# require_admin — admins group only
# Both attach user info to request object for use inside route handlers.
# =============================================================================
def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing or invalid token"}), 401
        token = auth_header.split(" ")[1]
        claims = validate_token(token)
        if not claims:
            return jsonify({"error": "Invalid or expired token"}), 401
        request.user_id    = claims["sub"]
        request.user_email = claims.get("email", "")
        request.user_group = claims.get("cognito:groups", ["customers"])[0]
        return f(*args, **kwargs)
    return decorated

def require_admin(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing or invalid token"}), 401
        token = auth_header.split(" ")[1]
        claims = validate_token(token)
        if not claims:
            return jsonify({"error": "Invalid or expired token"}), 401
        if "admins" not in claims.get("cognito:groups", []):
            return jsonify({"error": "Admin access required"}), 403
        request.user_id    = claims["sub"]
        request.user_email = claims.get("email", "")
        request.user_group = "admins"
        return f(*args, **kwargs)
    return decorated

# =============================================================================
# HEALTH CHECK
# ALB hits this every 30 seconds — no auth required.
# Checks both DB and Redis so a failed Redis also marks the instance unhealthy.
# =============================================================================
@app.route("/health", methods=["GET"])
def health():
    health_status = {"status": "healthy", "database": "unknown", "cache": "unknown"}

    try:
        conn = get_db_connection()
        conn.close()
        health_status["database"] = "connected"
    except Exception as e:
        health_status["database"] = "disconnected"
        health_status["status"]   = "unhealthy"
        logger.error(f"DB health check failed: {str(e)}")

    try:
        cache.ping()
        health_status["cache"] = "connected"
    except Exception as e:
        health_status["cache"] = "disconnected"
        health_status["status"] = "unhealthy"
        logger.error(f"Redis health check failed: {str(e)}")

    status_code = 200 if health_status["status"] == "healthy" else 500
    return jsonify(health_status), status_code

# =============================================================================
# CREATE BOOKING
# POST /bookings — any authenticated user
# user_id always from JWT sub — never from request body
# =============================================================================
@app.route("/bookings", methods=["POST"])
@require_auth
def create_booking():
    try:
        data = request.get_json()
        required = ["vehicle", "service", "date", "time_slot"]
        for field in required:
            if field not in data:
                return jsonify({"error": f"Missing field: {field}"}), 400

        conn   = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute("""
                INSERT INTO bookings (user_id, vehicle, service, date, time_slot)
                VALUES (%s, %s, %s, %s, %s)
            """, (
                request.user_id,
                data["vehicle"],
                data["service"],
                data["date"],
                data["time_slot"]
            ))
            conn.commit()
            booking_id = cursor.lastrowid
        finally:
            cursor.close()
            conn.close()

        cache.delete("admin:all_bookings")
        cache.delete(f"user:{request.user_id}:bookings")

        logger.info(f"Booking {booking_id} created for user {request.user_id}")
        return jsonify({"message": "Booking created successfully", "booking_id": booking_id}), 201

    except Exception as e:
        logger.error(f"Create booking failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# GET BOOKINGS
# GET /bookings — customers see only their own, cached per user
# =============================================================================
@app.route("/bookings", methods=["GET"])
@require_auth
def get_bookings():
    try:
        cache_key = f"user:{request.user_id}:bookings"
        cached = cache.get(cache_key)
        if cached:
            logger.info(f"Cache hit for {cache_key}")
            return jsonify({"bookings": json.loads(cached), "source": "cache"}), 200

        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute(
                "SELECT * FROM bookings WHERE user_id = %s ORDER BY created_at DESC",
                (request.user_id,)
            )
            bookings = cursor.fetchall()
        finally:
            cursor.close()
            conn.close()

        for b in bookings:
            for key, value in b.items():
                if hasattr(value, "isoformat"):
                    b[key] = value.isoformat()

        cache.setex(cache_key, 60, json.dumps(bookings))
        logger.info(f"Cache miss for {cache_key} — fetched from RDS")
        return jsonify({"bookings": bookings, "source": "database"}), 200

    except Exception as e:
        logger.error(f"Get bookings failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# GET SINGLE BOOKING
# GET /bookings/<id> — customer can only see their own booking
# =============================================================================
@app.route("/bookings/<int:booking_id>", methods=["GET"])
@require_auth
def get_booking(booking_id):
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute(
                "SELECT * FROM bookings WHERE id = %s AND user_id = %s",
                (booking_id, request.user_id)
            )
            booking = cursor.fetchone()
        finally:
            cursor.close()
            conn.close()

        if not booking:
            return jsonify({"error": "Booking not found"}), 404

        for key, value in booking.items():
            if hasattr(value, "isoformat"):
                booking[key] = value.isoformat()

        return jsonify({"booking": booking}), 200

    except Exception as e:
        logger.error(f"Get booking failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# ADMIN — GET ALL BOOKINGS
# GET /admin/bookings — admins only, cached separately
# =============================================================================
@app.route("/admin/bookings", methods=["GET"])
@require_admin
def admin_get_all_bookings():
    try:
        cache_key = "admin:all_bookings"
        cached = cache.get(cache_key)
        if cached:
            logger.info("Cache hit for admin:all_bookings")
            return jsonify({"bookings": json.loads(cached), "source": "cache"}), 200

        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute("SELECT * FROM bookings ORDER BY created_at DESC")
            bookings = cursor.fetchall()
        finally:
            cursor.close()
            conn.close()

        for b in bookings:
            for key, value in b.items():
                if hasattr(value, "isoformat"):
                    b[key] = value.isoformat()

        cache.setex(cache_key, 60, json.dumps(bookings))
        logger.info("Cache miss for admin:all_bookings — fetched from RDS")
        return jsonify({"bookings": bookings, "source": "database"}), 200

    except Exception as e:
        logger.error(f"Admin get bookings failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# ADMIN — UPDATE BOOKING STATUS
# PUT /admin/bookings/<id>/status — admins only
# =============================================================================
@app.route("/admin/bookings/<int:booking_id>/status", methods=["PUT"])
@require_admin
def update_booking_status(booking_id):
    try:
        data = request.get_json()
        valid_statuses = ["pending", "confirmed", "in_progress", "completed", "cancelled"]
        if "status" not in data or data["status"] not in valid_statuses:
            return jsonify({"error": f"Status must be one of: {valid_statuses}"}), 400

        conn   = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "UPDATE bookings SET status = %s WHERE id = %s",
                (data["status"], booking_id)
            )
            conn.commit()
            rows_affected = cursor.rowcount
        finally:
            cursor.close()
            conn.close()

        if rows_affected == 0:
            return jsonify({"error": "Booking not found"}), 404

        cache.delete("admin:all_bookings")
        logger.info(f"Booking {booking_id} status updated to {data['status']} by admin {request.user_id}")
        return jsonify({"message": "Status updated successfully"}), 200

    except Exception as e:
        logger.error(f"Update status failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# CANCEL BOOKING
# DELETE /bookings/<id> — customer can only cancel their own booking
# =============================================================================
@app.route("/bookings/<int:booking_id>", methods=["DELETE"])
@require_auth
def cancel_booking(booking_id):
    try:
        conn   = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "UPDATE bookings SET status = %s WHERE id = %s AND user_id = %s",
                ("cancelled", booking_id, request.user_id)
            )
            conn.commit()
            rows_affected = cursor.rowcount
        finally:
            cursor.close()
            conn.close()

        if rows_affected == 0:
            return jsonify({"error": "Booking not found"}), 404

        cache.delete(f"user:{request.user_id}:bookings")
        cache.delete("admin:all_bookings")

        logger.info(f"Booking {booking_id} cancelled by user {request.user_id}")
        return jsonify({"message": "Booking cancelled"}), 200

    except Exception as e:
        logger.error(f"Cancel booking failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# ENTRY POINT
# =============================================================================
if __name__ == "__main__":
    logger.info("Starting AutoServe Pro")
    init_db()
    app.run(host="0.0.0.0", port=5000, debug=False)
