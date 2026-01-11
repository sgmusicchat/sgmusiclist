"""
Configuration module for r/sgmusicchat Python/FastAPI service
Purpose: Database connections, environment variables
"""

import os
from dotenv import load_dotenv
import MySQLdb
from contextlib import contextmanager

# Load environment variables from .env file
load_dotenv()

# Database configuration
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_USER = os.getenv("DB_USER", "rsguser")
DB_PASSWORD = os.getenv("DB_PASSWORD", "rsgpass")

# Database names
DB_NAME_BRONZE = os.getenv("DB_NAME_BRONZE", "rsgmusicchat_bronze")
DB_NAME_SILVER = os.getenv("DB_NAME_SILVER", "rsgmusicchat_silver")
DB_NAME_GOLD = os.getenv("DB_NAME_GOLD", "rsgmusicchat_gold")

# Scheduler configuration
ENABLE_SCHEDULER = os.getenv("ENABLE_SCHEDULER", "true").lower() == "true"
AUTO_PUBLISH_INTERVAL = int(os.getenv("AUTO_PUBLISH_INTERVAL", "60"))  # minutes
MOCK_SCRAPER_HOUR = int(os.getenv("MOCK_SCRAPER_HOUR", "6"))  # Daily at 6 AM

# FastAPI configuration
FASTAPI_ENV = os.getenv("FASTAPI_ENV", "development")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")


def get_db_connection(database_name):
    """
    Create MySQL database connection

    Args:
        database_name: Name of database (bronze, silver, or gold)

    Returns:
        MySQLdb connection object
    """
    return MySQLdb.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        passwd=DB_PASSWORD,
        db=database_name,
        charset='utf8mb4',
        autocommit=False  # Manual transaction control for WAP workflow
    )


@contextmanager
def get_db_cursor(database_name):
    """
    Context manager for database operations
    Ensures proper connection cleanup

    Usage:
        with get_db_cursor('rsgmusicchat_silver') as cursor:
            cursor.execute("SELECT ...")
            results = cursor.fetchall()
    """
    conn = get_db_connection(database_name)
    cursor = conn.cursor(MySQLdb.cursors.DictCursor)
    try:
        yield cursor
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        cursor.close()
        conn.close()
