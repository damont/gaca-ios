"""A stand-in Hermes gateway for testing the app end to end without a real agent.

Speaks just enough of the Hermes api_server protocol that gaca-api's Hermes adapter
drives it like the real thing: POST /v1/runs, GET /v1/runs/{id}/events (SSE with
tool.started / tool.completed / message.delta / run.completed), plus the read-only
profile endpoints (skills, toolsets, jobs, health, model options).

Run it with gaca-api's environment (it only needs starlette + uvicorn):

    uv run --project ../gaca/gaca-api python tools/fake_hermes.py --port 18642

Replies are scripted from the message text:
  * contains "page"  → also links the artifact named by FAKE_ARTIFACT_ID, if set
  * contains "fail"  → the run fails
  * contains "slow"  → long pauses, so the live "Using …" row stays up
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import time
import uuid

import uvicorn
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, StreamingResponse
from starlette.routing import Route

RUNS: dict[str, dict] = {}


def _text_of(payload: dict) -> str:
    raw = payload.get("input")
    if isinstance(raw, str):
        return raw
    parts = []
    for turn in raw or []:
        for part in turn.get("content") or []:
            if part.get("type") == "text":
                parts.append(part.get("text", ""))
            elif part.get("type") == "image_url":
                parts.append("[photo]")
    return " ".join(parts)


async def start_run(request: Request) -> JSONResponse:
    payload = await request.json()
    run_id = f"run_{uuid.uuid4().hex[:12]}"
    RUNS[run_id] = {"text": _text_of(payload), "history": len(payload.get("conversation_history") or [])}
    return JSONResponse({"run_id": run_id, "status": "started"}, status_code=202)


def _reply_for(text: str) -> tuple[list[tuple[str, float]], str, bool]:
    """(tools with how long each takes, reply text, failed?)"""
    lower = text.lower()
    slow = "slow" in lower
    if "fail" in lower:
        return [("terminal", 0.6)], "", True
    tools = [("web_search", 2.5 if slow else 0.8), ("terminal", 2.0 if slow else 0.5), ("terminal", 0.4)]
    reply = (
        "Here's what I found:\n\n"
        "- **9:30** Infra standup (Zoom)\n"
        "- **12:00** Lunch with Sam, Tartine\n"
        "- **3:00** Dentist — 1450 Market St\n\n"
        f"You asked: _{text.strip()[:80] or '(a photo)'}_. Want me to prep anything? "
        "Run `docker image prune` if the disk fills up again."
    )
    artifact = os.environ.get("FAKE_ARTIFACT_ID")
    if "page" in lower and artifact:
        reply += f"\n\nI made you a page: [Disk usage](gaca://artifact/{artifact})"
    return tools, reply, False


async def run_events(request: Request) -> StreamingResponse:
    run_id = request.path_params["run_id"]
    run = RUNS.get(run_id, {"text": ""})

    async def stream():
        def frame(event: str, **fields) -> str:
            return "data: " + json.dumps({"event": event, "run_id": run_id, "timestamp": time.time(), **fields}) + "\n\n"

        tools, reply, failed = _reply_for(run["text"])
        for tool, seconds in tools:
            yield frame("tool.started", tool=tool, preview=f"{tool}(…)")
            await asyncio.sleep(seconds)
            yield frame("tool.completed", tool=tool, duration=seconds, error=False)
        if failed:
            yield frame("run.failed", error="The fake agent was asked to fail.")
            return
        for word in reply.split(" "):
            yield frame("message.delta", delta=word + " ")
            await asyncio.sleep(0.03)
        yield frame("run.completed", output=reply, usage={"input_tokens": 10, "output_tokens": 50, "total_tokens": 60})

    return StreamingResponse(stream(), media_type="text/event-stream")


async def run_status(request: Request) -> JSONResponse:
    return JSONResponse({"run_id": request.path_params["run_id"], "status": "completed"})


async def skills(_: Request) -> JSONResponse:
    return JSONResponse({"object": "list", "data": [
        {"name": "disk-report", "description": "Breaks down disk usage by directory and flags what's growing.", "category": "system"},
        {"name": "docker-cleanup", "description": "Prunes unused images, volumes and build cache.", "category": "system"},
        {"name": "cron-jobs", "description": "Creates, pauses and edits scheduled jobs.", "category": "scheduling"},
        {"name": "web-search", "description": "Searches the web.", "category": None},
    ]})


async def health(_: Request) -> JSONResponse:
    return JSONResponse({"status": "ok", "version": "fake-0.1", "platforms": {"telegram": {"state": "connected"}}})


async def model_options(_: Request) -> JSONResponse:
    return JSONResponse({"model": "fake-model", "provider": "fake", "providers": [{"name": "Fake AI", "is_current": True}]})


async def toolsets(_: Request) -> JSONResponse:
    return JSONResponse({"data": [
        {"name": "terminal", "label": "Terminal", "enabled": True},
        {"name": "web", "label": "Web", "enabled": True},
    ]})


async def jobs(_: Request) -> JSONResponse:
    return JSONResponse({"jobs": [
        {"id": "j1", "name": "Weekly Docker prune", "schedule": {"kind": "cron", "expr": "0 3 * * 0"}, "enabled": True,
         "next_run_at": "2026-10-11T03:00:00+00:00", "last_status": "ok", "no_agent": True},
        {"id": "j2", "name": "Disk check", "schedule": {"kind": "cron", "expr": "0 * * * *"}, "enabled": False,
         "last_status": "ok"},
    ]})


app = Starlette(routes=[
    Route("/v1/runs", start_run, methods=["POST"]),
    Route("/v1/runs/{run_id}/events", run_events),
    Route("/v1/runs/{run_id}", run_status),
    Route("/v1/skills", skills),
    Route("/v1/toolsets", toolsets),
    Route("/health/detailed", health),
    Route("/api/model/options", model_options),
    Route("/api/jobs", jobs),
])

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18642)
    args = parser.parse_args()
    uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="warning")
