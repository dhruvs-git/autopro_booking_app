import os
import json
import logging
import boto3
from flask import Flask, jsonify, request
from datetime import datetime
import mysql.connector

# =============================================================================
# LOGGING
# Structured JSON logging — every request logged to CloudWatch (Day 6)
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# =============================================================================
# DATABASE CONNECTION
# Reads credentials from environment variables.
# user_data.sh fetched these from Secrets Manager and wrote to /etc/autoserve/db.env
# systemd loads db.env before starting Flask via EnvironmentFile=
# No credentials anywhere in this file.
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
# Creates the bookings table if it doesn't exist.
# Runs once on startup.
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
# ALB hits this every 30 seconds.
# Returns 200 = instance is healthy, keep sending traffic.
# Returns anything else = instance is unhealthy, stop sending traffic.
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
# Body: { "user_id", "vehicle", "service", "date", "time_slot" }
# =============================================================================
@app.route("/bookings", methods=["POST"])
def create_booking():
    try:
        data = request.get_json()

        required = ["user_id", "vehicle", "service", "date", "time_slot"]
        for field in required:
            if field not in data:
                return jsonify({"error": f"Missing field: {field}"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO bookings (user_id, vehicle, service, date, time_slot)
            VALUES (%s, %s, %s, %s, %s)
        """, (
            data["user_id"],
            data["vehicle"],
            data["service"],
            data["date"],
            data["time_slot"]
        ))
        conn.commit()
        booking_id = cursor.lastrowid
        cursor.close()
        conn.close()

        logger.info(f"Booking created: {booking_id} for user: {data['user_id']}")

        return jsonify({
            "message": "Booking created successfully",
            "booking_id": booking_id
        }), 201

    except Exception as e:
        logger.error(f"Create booking failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# GET BOOKINGS
# GET /bookings?user_id=xxx
# Customers see only their own bookings.
# Admins pass user_id=all to see everything (Cognito group check Day 3)
# =============================================================================
@app.route("/bookings", methods=["GET"])
def get_bookings():
    try:
        user_id = request.args.get("user_id")

        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        if user_id == "all":
            cursor.execute("SELECT * FROM bookings ORDER BY created_at DESC")
        else:
            cursor.execute(
                "SELECT * FROM bookings WHERE user_id = %s ORDER BY created_at DESC",
                (user_id,)
            )

        bookings = cursor.fetchall()
        cursor.close()
        conn.close()

        # Convert date and datetime objects to strings for JSON serialisation
        for b in bookings:
            for key, value in b.items():
                if hasattr(value, 'isoformat'):
                    b[key] = value.isoformat()

        return jsonify({"bookings": bookings}), 200

    except Exception as e:
        logger.error(f"Get bookings failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# GET SINGLE BOOKING
# GET /bookings/<id>
# =============================================================================
@app.route("/bookings/<int:booking_id>", methods=["GET"])
def get_booking(booking_id):
    try:
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

        for key, value in booking.items():
            if hasattr(value, 'isoformat'):
                booking[key] = value.isoformat()

        return jsonify({"booking": booking}), 200

    except Exception as e:
        logger.error(f"Get booking failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# UPDATE BOOKING STATUS
# PUT /bookings/<id>/status
# Body: { "status": "confirmed" }
# Admin only — Cognito group check added Day 3
# =============================================================================
@app.route("/bookings/<int:booking_id>/status", methods=["PUT"])
def update_booking_status(booking_id):
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

        logger.info(f"Booking {booking_id} status updated to {data['status']}")
        return jsonify({"message": "Status updated successfully"}), 200

    except Exception as e:
        logger.error(f"Update status failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# CANCEL BOOKING
# DELETE /bookings/<id>
# =============================================================================
@app.route("/bookings/<int:booking_id>", methods=["DELETE"])
def cancel_booking(booking_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "UPDATE bookings SET status = %s WHERE id = %s",
                ("cancelled", booking_id)
            )
            conn.commit()
            rowcount = cursor.rowcount
        finally:
            cursor.close()
            conn.close()

        if rowcount == 0:
            return jsonify({"error": "Booking not found"}), 404

        logger.info(f"Booking {booking_id} cancelled")
        return jsonify({"message": "Booking cancelled"}), 200

    except Exception as e:
        logger.error(f"Cancel booking failed: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500

# =============================================================================
# ENTRY POINT
# host="0.0.0.0" means Flask accepts connections from any IP —
# required so ALB can reach it inside the VPC.
# Debug=False — never run debug mode in production.
# =============================================================================
if __name__ == "__main__":
    logger.info("Starting AutoServe Pro")
    init_db()
    app.run(host="0.0.0.0", port=5000, debug=False)