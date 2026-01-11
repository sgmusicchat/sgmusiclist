"""
r/sgmusicchat - Python/FastAPI Service
Purpose: Internal API for scraper orchestration and WAP workflows
Architecture: Gutsy Startup - boring tech, blazing fast
"""

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import Optional, List, Dict
import config
from services.scheduler import start_scheduler, stop_scheduler, get_scheduled_jobs
from scrapers.mock_scraper import generate_mock_events, generate_bad_event_for_quarantine_testing
from services.bronze_writer import write_to_bronze
from services.silver_processor import process_bronze_to_silver
from services.wap_executor import (
    run_audit,
    run_publish,
    auto_publish_workflow,
    get_wap_metrics
)

# Initialize FastAPI
app = FastAPI(
    title="r/sgmusicchat Python API",
    description="Internal API for scraper orchestration and WAP workflows",
    version="1.0.0"
)

# ============================================================================
# Pydantic Models (Request/Response schemas)
# ============================================================================

class MockScraperRequest(BaseModel):
    count: int = 10
    include_bad_events: bool = False


class ProcessBronzeRequest(BaseModel):
    bronze_id: int
    scraper_source: str = "scraper"


class PublishRequest(BaseModel):
    batch_size: int = 500


# ============================================================================
# FastAPI Lifecycle Events
# ============================================================================

@app.on_event("startup")
async def startup_event():
    """Start background scheduler on FastAPI startup"""
    print("\n🚀 FastAPI Starting Up...")
    start_scheduler()


@app.on_event("shutdown")
async def shutdown_event():
    """Stop background scheduler on FastAPI shutdown"""
    print("\n🛑 FastAPI Shutting Down...")
    stop_scheduler()


# ============================================================================
# Health Check Endpoints
# ============================================================================

@app.get("/api/v1/health")
async def health_check():
    """
    Health check endpoint
    Returns: System health status
    """
    try:
        # Test database connection
        from config import get_db_cursor, DB_NAME_SILVER
        with get_db_cursor(DB_NAME_SILVER) as cursor:
            cursor.execute("SELECT 1 AS test")
            result = cursor.fetchone()

        db_status = "connected" if result else "disconnected"
    except Exception as e:
        db_status = f"error: {str(e)}"

    return {
        "status": "healthy",
        "service": "rsgmusicchat_python_api",
        "database": db_status,
        "scheduler": "enabled" if config.ENABLE_SCHEDULER else "disabled",
        "environment": config.FASTAPI_ENV
    }


@app.get("/api/v1/metrics")
async def get_metrics():
    """
    Get system metrics (event counts by status)
    Returns: Dictionary of event counts
    """
    try:
        metrics = get_wap_metrics()
        return {
            "status": "success",
            "metrics": metrics
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# Scraper Orchestration Endpoints
# ============================================================================

@app.post("/api/v1/scrapers/mock/run")
async def run_mock_scraper(request: MockScraperRequest):
    """
    Trigger mock scraper and process to Silver
    Args: count (number of events), include_bad_events (for quarantine testing)
    Returns: Scraper results
    """
    try:
        # Generate mock events
        events = generate_mock_events(count=request.count)

        # Optionally add bad event for quarantine testing
        if request.include_bad_events:
            bad_event = generate_bad_event_for_quarantine_testing()
            events.append(bad_event)

        # Write to Bronze
        bronze_id = write_to_bronze(events, scraper_source="mock_scraper")

        # Process to Silver
        processed, new = process_bronze_to_silver(bronze_id, scraper_source="scraper")

        return {
            "status": "success",
            "bronze_id": bronze_id,
            "events_generated": len(events),
            "events_processed": processed,
            "new_events": new,
            "updated_events": processed - new
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/scrapers/process-bronze")
async def process_bronze(request: ProcessBronzeRequest):
    """
    Process existing Bronze record to Silver
    Args: bronze_id, scraper_source
    Returns: Processing results
    """
    try:
        processed, new = process_bronze_to_silver(
            bronze_id=request.bronze_id,
            scraper_source=request.scraper_source
        )

        return {
            "status": "success",
            "bronze_id": request.bronze_id,
            "events_processed": processed,
            "new_events": new,
            "updated_events": processed - new
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# WAP Workflow Endpoints
# ============================================================================

@app.post("/api/v1/wap/audit")
async def wap_audit():
    """
    Run aggressive audit (auto-quarantines bad records)
    Returns: Audit results
    """
    try:
        error_count, quarantined_count, error_summary = run_audit()

        return {
            "status": "success" if error_count == 0 else "failed",
            "error_count": error_count,
            "quarantined_count": quarantined_count,
            "error_summary": error_summary,
            "audit_passed": error_count == 0
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/wap/publish")
async def wap_publish(request: PublishRequest):
    """
    Run WAP publish workflow (audit + publish)
    Args: batch_size
    Returns: Publish results
    """
    try:
        result = auto_publish_workflow(batch_size=request.batch_size)

        return {
            "status": result['status'],
            "error_count": result['error_count'],
            "quarantined_count": result['quarantined_count'],
            "published_count": result['published_count'],
            "message": result['message']
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# Scheduler Management Endpoints
# ============================================================================

@app.get("/api/v1/scheduler/jobs")
async def get_jobs():
    """
    Get list of scheduled jobs
    Returns: List of job information
    """
    try:
        jobs = get_scheduled_jobs()
        return {
            "status": "success",
            "jobs": jobs
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# Root Endpoint
# ============================================================================

@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "service": "r/sgmusicchat Python API",
        "version": "1.0.0",
        "description": "Internal API for scraper orchestration and WAP workflows",
        "endpoints": {
            "health": "/api/v1/health",
            "metrics": "/api/v1/metrics",
            "mock_scraper": "POST /api/v1/scrapers/mock/run",
            "wap_audit": "POST /api/v1/wap/audit",
            "wap_publish": "POST /api/v1/wap/publish",
            "scheduler_jobs": "/api/v1/scheduler/jobs"
        },
        "docs": "/docs"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,  # Auto-reload on code changes (dev only)
        log_level=config.LOG_LEVEL.lower()
    )
