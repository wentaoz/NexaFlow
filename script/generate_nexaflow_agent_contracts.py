#!/usr/bin/env python3
"""Generate standard NexaFlow agent contract files from registry.json."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "agents" / "nexaflow" / "registry.json"
AGENT_ROOT = ROOT / "agents" / "nexaflow"


def main() -> None:
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    for agent in registry["agents"]:
        name = agent["name"]
        folder = AGENT_ROOT / name
        folder.mkdir(parents=True, exist_ok=True)

        input_json = {
            "agent": name,
            "task": "Describe the user task here.",
            "businessContext": {
                "businessSpace": "",
                "country": "",
                "timezone": "",
                "productType": ""
            },
            "dataContext": {
                "selectedReports": [],
                "periodPolicy": "",
                "sourceLimitations": []
            },
            "evidenceContext": {
                "knowledge": [],
                "projectEvidence": [],
                "externalEvidence": [],
                "calculationEvidence": []
            },
            "constraints": {
                "readOnly": True,
                "doNotExposeSecrets": True,
                "businessSpaceIsolation": True
            }
        }
        (folder / "input.json").write_text(json.dumps(input_json, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        handoff = f"""# {name} Handoff

## Task

`<task>`

## Inputs Received

- Business context:
- Data context:
- Evidence context:
- User question or report scope:

## Work Performed

- Agent responsibility: {agent.get("responsibility", "")}
- Skills used: {", ".join(agent.get("skills", []))}

## Output

- Primary deliverables: {", ".join(agent.get("outputs", []))}
- Known limitations:
- Follow-up agent:

## Safety

- No secrets included.
- No live NexaFlow App action executed.
- Business-space isolation preserved.
"""
        (folder / "handoff.md").write_text(handoff, encoding="utf-8")

        acceptance = f"""# {name} Acceptance Criteria

- The output matches the agent responsibility: {agent.get("responsibility", "")}
- The response names which Skill(s) were used or should be used.
- The output is scoped to the provided business space.
- Secrets, tokens, and credentials are not included.
- Evidence limitations are visible.
- The output can be handed to the next agent or user without hidden assumptions.
- If the task cannot be completed, the blocker and safe next step are explicit.
"""
        (folder / "acceptance.md").write_text(acceptance, encoding="utf-8")


if __name__ == "__main__":
    main()
