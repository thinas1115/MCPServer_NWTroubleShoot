# server.py
import os
import json
import time
from typing import Optional, List, Dict, Any

import requests
from fastmcp import FastMCP

mcp = FastMCP("mcp-awx", version="1.0.0")

# ---- AWX helpers ------------------------------------------------------------
def _hdrs() -> Dict[str, str]:
    token = os.environ.get("AWX_TOKEN", "")
    if not token:
        raise RuntimeError("AWX_TOKEN is not set")
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

def _url(path: str) -> str:
    base = os.environ.get("AWX_BASE", "http://127.0.0.1:8043")
    return f"{base.rstrip('/')}{path}"

def _job_status(job_id: int) -> Dict[str, Any]:
    r = requests.get(_url(f"/api/v2/jobs/{job_id}/"), headers=_hdrs(), timeout=20, verify=False)
    r.raise_for_status()
    return r.json()

# ---- tools ------------------------------------------------------------------
@mcp.tool
def awx_health() -> dict:
    """AWX /api/v2/ping の疎通確認"""
    try:
        r = requests.get(_url("/api/v2/ping/"), headers=_hdrs(), timeout=10, verify=False)
        ok = (r.status_code == 200)
        return {"ok": ok, "status": r.json() if ok else r.text}
    except Exception as e:
        return {"ok": False, "error": str(e)}

@mcp.tool
def vyos_show(
    template_id: int,
    show_cmds: List[str],
    limit: Optional[str] = None,
    inventory: Optional[str] = None,
    save_local: bool = False,
    save_artifacts: bool = True,
    timeout_sec: int = 300,
    poll_interval_sec: float = 2.0,
) -> dict:
    """
    AWXのJob Templateを起動し、VyOSのshowコマンドを実行してArtifactsを返す。
    - template_id: AWX Job Template ID（例: 42）
    - show_cmds: 実行する show コマンド配列
    - limit: "clab-lab1-r1,clab-lab1-r3" など
    - inventory: 必要ならインベントリID/URL
    """
    if not show_cmds:
        raise ValueError("show_cmds must not be empty")

    payload = {
        "extra_vars": {
            "show_cmds": show_cmds,
            "save_local": save_local,
            "save_artifacts": save_artifacts,
            "limit": limit or "all",
        }
    }
    if inventory:
        payload["inventory"] = inventory

    # launch
    r = requests.post(_url(f"/api/v2/job_templates/{template_id}/launch/"),
                      headers=_hdrs(), data=json.dumps(payload),
                      timeout=30, verify=False)
    r.raise_for_status()
    job_id = r.json().get("job")
    if not job_id:
        raise RuntimeError(f"Launch response missing job id: {r.text}")

    # poll
    deadline = time.time() + timeout_sec
    status = None
    while time.time() < deadline:
        j = _job_status(job_id)
        status = j.get("status")
        if status in ("successful", "failed", "error", "canceled"):
            artifacts = j.get("artifacts") or {}
            return {
                "job_id": job_id,
                "status": status,
                "artifacts": artifacts,
                "stdout_url": f"{os.environ.get('AWX_BASE','http://127.0.0.1:8043')}/#/jobs/playbook/{job_id}/output",
            }
        time.sleep(poll_interval_sec)

    # timeout
    j = _job_status(job_id)
    return {"job_id": job_id, "status": j.get("status"), "timeout": True}
