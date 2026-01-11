"""
WAP (Write-Audit-Publish) Executor Service
Purpose: Execute aggressive audit and publish workflows
Calls: sp_audit_pending_events(), sp_publish_to_gold()
"""

from typing import Dict, Tuple
from config import get_db_cursor, DB_NAME_SILVER


def run_audit() -> Tuple[int, int, str]:
    """
    Execute sp_audit_pending_events (aggressive rejection version)

    Returns:
        Tuple of (error_count, quarantined_count, error_summary)
    """
    with get_db_cursor(DB_NAME_SILVER) as cursor:
        sql = """
            CALL sp_audit_pending_events(@error_count, @quarantined_count, @error_summary)
        """
        cursor.execute(sql)

        # Fetch output parameters
        cursor.execute("SELECT @error_count AS error_count, @quarantined_count AS quarantined_count, @error_summary AS error_summary")
        result = cursor.fetchone()

        error_count = result['error_count'] or 0
        quarantined_count = result['quarantined_count'] or 0
        error_summary = result['error_summary'] or ""

        if error_count > 0:
            print(f"❌ Audit FAILED: {error_summary}")
        elif quarantined_count > 0:
            print(f"⚠️  Audit PASSED (but {quarantined_count} events auto-quarantined)")
        else:
            print(f"✅ Audit PASSED: All pending events are clean")

        return (error_count, quarantined_count, error_summary)


def run_publish(batch_size: int = 500) -> Tuple[int, str]:
    """
    Execute sp_publish_to_gold (with pre-aggregations)

    Args:
        batch_size: Maximum events to publish in one batch

    Returns:
        Tuple of (published_count, result_message)
    """
    with get_db_cursor(DB_NAME_SILVER) as cursor:
        sql = """
            CALL sp_publish_to_gold(%s, @published_count, @result_message)
        """
        cursor.execute(sql, (batch_size,))

        # Consume any result sets from the stored procedure
        cursor.fetchall()

        # Fetch output parameters
        cursor.execute("SELECT @published_count AS published_count, @result_message AS result_message")
        result = cursor.fetchone()

        published_count = result['published_count'] or 0
        result_message = result['result_message'] or ""

        if "SUCCESS" in result_message:
            print(f"✅ {result_message}")
        elif "FAILED" in result_message:
            print(f"❌ {result_message}")
        else:
            print(f"⚠️  {result_message}")

        return (published_count, result_message)


def auto_publish_workflow(batch_size: int = 500) -> Dict:
    """
    Automated WAP workflow: Audit → Publish
    This is the main function called by the scheduler

    Args:
        batch_size: Maximum events to publish in one batch

    Returns:
        Dictionary with workflow results
    """
    print("\n" + "="*60)
    print("🚀 Starting Auto-Publish WAP Workflow")
    print("="*60)

    # Step 1: Audit (auto-quarantines bad records)
    print("\n[1/2] Running aggressive audit...")
    error_count, quarantined_count, error_summary = run_audit()

    # Step 2: Publish if audit passes
    if error_count == 0:
        print("\n[2/2] Publishing to Gold layer...")
        published_count, result_message = run_publish(batch_size)

        workflow_result = {
            "status": "success",
            "error_count": error_count,
            "quarantined_count": quarantined_count,
            "published_count": published_count,
            "message": result_message
        }
    else:
        print(f"\n[2/2] SKIPPED: Audit failed with {error_count} errors")
        print(f"Error details: {error_summary}")

        workflow_result = {
            "status": "failed",
            "error_count": error_count,
            "quarantined_count": quarantined_count,
            "published_count": 0,
            "message": f"Audit failed: {error_summary}"
        }

    print("\n" + "="*60)
    print(f"✨ Workflow completed: {workflow_result['status'].upper()}")
    print("="*60 + "\n")

    return workflow_result


def get_wap_metrics() -> Dict:
    """
    Get current WAP workflow metrics

    Returns:
        Dictionary with event counts by status
    """
    with get_db_cursor(DB_NAME_SILVER) as cursor:
        # Count events by status
        sql = """
            SELECT
                status,
                COUNT(*) AS count
            FROM silver_events
            GROUP BY status
        """
        cursor.execute(sql)
        results = cursor.fetchall()

        metrics = {row['status']: row['count'] for row in results}

        # Add Gold layer count
        cursor.execute("SELECT COUNT(*) AS count FROM rsgmusicchat_gold.gold_events")
        gold_count = cursor.fetchone()['count']
        metrics['gold'] = gold_count

        return metrics


if __name__ == "__main__":
    # Test WAP executor
    print("Testing WAP Executor...")

    # Get current metrics
    print("\n📊 Current Metrics:")
    metrics = get_wap_metrics()
    for status, count in metrics.items():
        print(f"  {status}: {count}")

    # Run auto-publish workflow
    result = auto_publish_workflow(batch_size=100)
    print(f"\nWorkflow Result: {result}")
