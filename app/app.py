import os
import json
import time
import logging
import requests
import redis
import boto3
import watchtower
from functools import wraps
from flask import Flask, Blueprint, jsonify, request
from jose import jwt, JWTError
import mysql.connector

# =============================================================================
# LOGGING — Structured JSON to stdout + CloudWatch Logs
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
)
logger = logging.getLogger(__name__)

_project   = os.environ.get("PROJECT_NAME", "autoserve")
_env       = os.environ.get("ENVIRONMENT", "dev")
_region    = os.environ.get("AWS_REGION", "ca-central-1")

try:
    logger.addHandler(watchtower.CloudWatchLogHandler(
        log_group=f"/{_project}-{_env}/flask",
        boto3_client=boto3.client("logs", region_name=_region)
    ))
except Exception:
    pass

app = Flask(__name__)
api = Blueprint("api", __name__, url_prefix="/api")

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
SQS_QUEUE_URL        = os.environ["SQS_QUEUE_URL"]

sqs_client     = boto3.client("sqs",         region_name=AWS_REGION)
cognito_client = boto3.client("cognito-idp", region_name=AWS_REGION)

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
                user_email  VARCHAR(255) NOT NULL DEFAULT '',
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
        try:
            cursor.execute("ALTER TABLE bookings ADD COLUMN user_email VARCHAR(255) NOT NULL DEFAULT '' AFTER user_id")
            conn.commit()
        except Exception:
            pass  # column already exists
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
# ALB hits /health directly — must stay at root, NOT under /api blueprint.
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

    return jsonify(health_status), 200

# =============================================================================
# AUTH — LOGIN
# POST /api/auth/login
# =============================================================================
@api.route("/auth/login", methods=["POST"])
def login():
    try:
        data = request.get_json()
        if not data.get("email") or not data.get("password"):
            return jsonify({"error": "Email and password required"}), 400

        response = cognito_client.initiate_auth(
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={
                "USERNAME": data["email"],
                "PASSWORD": data["password"]
            },
            ClientId=COGNITO_CLIENT_ID
        )

        tokens = response["AuthenticationResult"]
        claims = validate_token(tokens["AccessToken"])
        groups = claims.get("cognito:groups", []) if claims else []
        group  = "admins" if "admins" in groups else "customers"

        return jsonify({
            "access_token":  tokens["AccessToken"],
            "id_token":      tokens["IdToken"],
            "refresh_token": tokens["RefreshToken"],
            "group":         group
        }), 200

    except cognito_client.exceptions.NotAuthorizedException:
        return jsonify({"error": "Invalid email or password"}), 401

    except cognito_client.exceptions.UserNotConfirmedException:
        return jsonify({"error": "Please verify your email first"}), 401

    except Exception as e:
        logger.error(f"Login failed: {str(e)}")
        return jsonify({"error": "Login failed"}), 500

# =============================================================================
# AUTH — SIGNUP
# POST /api/auth/signup
# Creates user in Cognito — sends verification email
# User is added to customers group after they confirm (see /auth/confirm)
# =============================================================================
@api.route("/auth/signup", methods=["POST"])
def signup():
    try:
        data = request.get_json()
        if not data.get("email") or not data.get("password"):
            return jsonify({"error": "Email and password required"}), 400

        cognito_client.sign_up(
            ClientId=COGNITO_CLIENT_ID,
            Username=data["email"],
            Password=data["password"],
            UserAttributes=[{"Name": "email", "Value": data["email"]}]
        )

        logger.info(f"New user signed up: {data['email']}")
        return jsonify({"message": "Account created. Check your email for a verification code."}), 201

    except cognito_client.exceptions.UsernameExistsException:
        return jsonify({"error": "Email already registered"}), 409

    except cognito_client.exceptions.InvalidPasswordException as e:
        return jsonify({"error": str(e)}), 400

    except Exception as e:
        logger.error(f"Signup failed: {str(e)}")
        return jsonify({"error": "Signup failed"}), 500

# =============================================================================
# AUTH — CONFIRM
# POST /api/auth/confirm
# Verifies email with the 6-digit code Cognito sent.
# Adds user to the customers group after confirmed — so they can access /bookings.
# =============================================================================
@api.route("/auth/resend", methods=["POST"])
def resend_confirmation():
    try:
        data = request.get_json()
        if not data.get("email"):
            return jsonify({"error": "Email required"}), 400

        cognito_client.resend_confirmation_code(
            ClientId=COGNITO_CLIENT_ID,
            Username=data["email"]
        )

        return jsonify({"message": "A new verification code has been sent to your email."}), 200

    except cognito_client.exceptions.UserNotFoundException:
        return jsonify({"error": "No account found with this email"}), 404

    except cognito_client.exceptions.InvalidParameterException:
        return jsonify({"error": "Already confirmed — you can sign in"}), 400

    except Exception as e:
        logger.error(f"Resend confirmation failed: {str(e)}")
        return jsonify({"error": "Failed to resend code"}), 500


@api.route("/auth/confirm", methods=["POST"])
def confirm_signup():
    try:
        data = request.get_json()
        if not data.get("email") or not data.get("code"):
            return jsonify({"error": "Email and code required"}), 400

        cognito_client.confirm_sign_up(
            ClientId=COGNITO_CLIENT_ID,
            Username=data["email"],
            ConfirmationCode=data["code"]
        )

        try:
            existing = cognito_client.admin_list_groups_for_user(
                UserPoolId=COGNITO_USER_POOL_ID,
                Username=data["email"]
            )
            existing_groups = [g["GroupName"] for g in existing.get("Groups", [])]
            if "admins" not in existing_groups:
                cognito_client.admin_add_user_to_group(
                    UserPoolId=COGNITO_USER_POOL_ID,
                    Username=data["email"],
                    GroupName="customers"
                )
                logger.info(f"User confirmed and added to customers group: {data['email']}")
            else:
                logger.info(f"User {data['email']} is already an admin — skipping customers group assignment")
        except Exception as e:
            logger.error(f"Group assignment failed (user still confirmed): {str(e)}")
        return jsonify({"message": "Email verified. You can now sign in."}), 200

    except cognito_client.exceptions.CodeMismatchException:
        return jsonify({"error": "Invalid verification code"}), 400

    except cognito_client.exceptions.ExpiredCodeException:
        return jsonify({"error": "Code expired — sign up again to get a new one"}), 400

    except cognito_client.exceptions.NotAuthorizedException:
        return jsonify({"error": "Already confirmed — you can sign in"}), 400

    except Exception as e:
        logger.error(f"Confirm signup failed: {str(e)}")
        return jsonify({"error": "Verification failed"}), 500

# =============================================================================
# CREATE BOOKING
# POST /api/bookings — any authenticated user
# user_id always from JWT sub — never from request body
# =============================================================================
@api.route("/bookings", methods=["POST"])
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
                INSERT INTO bookings (user_id, user_email, vehicle, service, date, time_slot)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (
                request.user_id,
                request.user_email,
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

        try:
            sqs_client.send_message(
                QueueUrl    = SQS_QUEUE_URL,
                MessageBody = json.dumps({
                    "booking_id": booking_id,
                    "user_email": request.user_email,
                    "vehicle":    data["vehicle"],
                    "service":    data["service"],
                    "date":       data["date"],
                    "time_slot":  data["time_slot"]
                })
            )
            logger.info(f"Booking event queued for booking {booking_id}")
        except Exception as e:
            logger.error(f"Failed to queue booking event: {str(e)}")

        logger.info(f"Booking {booking_id} created for user {request.user_id}")
        return jsonify({"message": "Booking created successfully", "booking_id": booking_id}), 201

    except Exception as e:
        logger.error(f"Create booking failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# GET BOOKINGS
# GET /api/bookings — customers see only their own, cached per user
# =============================================================================
@api.route("/bookings", methods=["GET"])
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
# GET /api/bookings/<id> — customer can only see their own booking
# =============================================================================
@api.route("/bookings/<int:booking_id>", methods=["GET"])
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
# GET /api/admin/bookings — admins only, cached separately
# =============================================================================
@api.route("/admin/bookings", methods=["GET"])
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
# PUT /api/admin/bookings/<id>/status — admins only
# =============================================================================
@api.route("/admin/bookings/<int:booking_id>/status", methods=["PUT"])
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
# DELETE /api/bookings/<id> — customer can only cancel their own booking
# =============================================================================
@api.route("/bookings/<int:booking_id>", methods=["DELETE"])
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

@api.route("/auth/account", methods=["DELETE"])
@require_auth
def delete_account():
    try:
        cognito_client.admin_delete_user(
            UserPoolId=COGNITO_USER_POOL_ID,
            Username=request.user_email
        )
        logger.info(f"Account deleted: {request.user_email}")
        return jsonify({"message": "Account deleted successfully"}), 200

    except Exception as e:
        logger.error(f"Account deletion failed: {str(e)}")
        return jsonify({"error": "Failed to delete account"}), 500


app.register_blueprint(api)

# =============================================================================
# ENTRY POINT
# =============================================================================
if __name__ == "__main__":
    logger.info("Starting AutoServe Pro")
    init_db()
    app.run(host="0.0.0.0", port=5000, debug=False)
