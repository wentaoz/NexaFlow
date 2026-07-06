#!/usr/bin/env python3
"""Validate NexaFlow Skill / Agent / MCP pack structure."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILLS_ROOT = ROOT / "skills" / "nexaflow"
AGENTS_ROOT = ROOT / "agents" / "nexaflow"
REGISTRY = AGENTS_ROOT / "registry.json"


def fail(message: str, issues: list[str]) -> None:
    issues.append(message)


def validate_skill(skill_dir: Path, issues: list[str]) -> None:
    skill_file = skill_dir / "SKILL.md"
    if not skill_file.exists():
        fail(f"Missing SKILL.md: {skill_dir}", issues)
        return
    text = skill_file.read_text(encoding="utf-8")
    frontmatter = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not frontmatter:
        fail(f"Missing YAML frontmatter: {skill_file}", issues)
        return
    fm = frontmatter.group(1)
    name_match = re.search(r"^name:\s*([a-z0-9-]+)\s*$", fm, re.MULTILINE)
    desc_match = re.search(r"^description:\s*(.+)\s*$", fm, re.MULTILINE)
    if not name_match:
        fail(f"Missing or invalid name: {skill_file}", issues)
    elif name_match.group(1) != skill_dir.name:
        fail(f"Skill folder/name mismatch: {skill_file}", issues)
    if not desc_match or len(desc_match.group(1).strip()) < 40:
        fail(f"Missing or too-short description: {skill_file}", issues)
    lower = text.lower()
    if "## workflow" not in lower:
        fail(f"Missing Workflow section: {skill_file}", issues)
    if not any(marker in lower for marker in ["## output requirements", "## output", "## report usage"]):
        fail(f"Missing output requirements: {skill_file}", issues)
    if not any(marker in lower for marker in ["## boundaries", "## safe sql rules", "## prohibited output"]):
        fail(f"Missing boundaries/safety section: {skill_file}", issues)


def validate_agents(issues: list[str]) -> None:
    if not REGISTRY.exists():
        fail("Missing agents/nexaflow/registry.json", issues)
        return
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    registry_names = {agent["name"] for agent in registry.get("agents", [])}
    folder_names = {path.name for path in AGENTS_ROOT.iterdir() if path.is_dir()}
    missing_from_registry = folder_names - registry_names
    missing_folders = registry_names - folder_names
    for name in sorted(missing_from_registry):
        fail(f"Agent folder missing from registry: {name}", issues)
    for name in sorted(missing_folders):
        fail(f"Registry agent missing folder: {name}", issues)
    for name in sorted(registry_names & folder_names):
        folder = AGENTS_ROOT / name
        for filename in ["AGENT.md", "input.json", "handoff.md", "acceptance.md"]:
            if not (folder / filename).exists():
                fail(f"Missing {filename}: {folder}", issues)
        agent_text = (folder / "AGENT.md").read_text(encoding="utf-8")
        for heading in ["## Responsibility", "## Trigger", "## Inputs", "## Workflow", "## Output", "## Skills"]:
            if heading not in agent_text:
                fail(f"Missing {heading}: {folder / 'AGENT.md'}", issues)


def main() -> int:
    issues: list[str] = []
    for ds_store in SKILLS_ROOT.glob("**/.DS_Store"):
        fail(f"Remove .DS_Store: {ds_store}", issues)
    for skill_dir in sorted(path for path in SKILLS_ROOT.iterdir() if path.is_dir() and not path.name.startswith("_")):
        validate_skill(skill_dir, issues)
    validate_agents(issues)
    if issues:
        print("NexaFlow Skill/Agent validation failed:")
        for issue in issues:
            print(f"- {issue}")
        return 1
    print("NexaFlow Skill/Agent validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
