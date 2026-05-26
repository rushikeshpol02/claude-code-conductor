#!/usr/bin/env python3
"""
Phase 3 spawn-fidelity audit hook (simplified — property 1 only).

Verifies declared personas == spawned Agent() calls for Tier 3+ turns.

Per the persona architecture in ~/.claude/CLAUDE.md:
- Tier 3+ tasks MUST declare personas on line 2 of the response
- Phase 3 atomic spawn MUST produce Agent() tool calls matching the declared count

This hook checks PROPERTY (1): count match.
PROPERTY (2) — spawn results actually used in synthesis — is a known open gap.
Citation-pattern checks for property (2) were attempted and failed Standard 7 review
(see plan you-are-an-ai-peppy-gem.md v2 review for findings).

Stop hook contract (Claude Code):
- stdin: JSON {"session_id": "...", "transcript_path": "...", "stop_hook_active": false}
- exit 0: pass, silent
- exit 2: violation; stderr surfaced to Claude as feedback in next turn

Failure handling: ANY parse error / unexpected schema → exit 0 silent.
Hook MUST NOT block the user's workspace on internal errors.
"""

import json
import re
import sys
from pathlib import Path


# Match Tier declaration anchored to start of a line (canonical: line 1).
# Use MULTILINE so ^ matches line starts within the text.
TIER_LINE_RE = re.compile(r'^\[Tier:\s*(Analytical|Deep)\b', re.MULTILINE | re.IGNORECASE)

# Match Personas declaration anchored to start of a line (canonical: line 2).
# Format: "Task: <type> | Personas: <Lead> (lead), <P2>, <P3>"
PERSONAS_LINE_RE = re.compile(
    r'^Task:[ \t]*[^|\n]+\|[ \t]*Personas:[ \t]*([^\n]+?)[ \t]*$',
    re.MULTILINE | re.IGNORECASE
)


def parse_personas(persona_str):
    """Parse 'Architect (lead), Engineer, AI QA / Red Teamer' into a list of names."""
    cleaned = re.sub(r'\s*\(lead\)\s*', '', persona_str, flags=re.IGNORECASE)
    names = [n.strip() for n in cleaned.split(',') if n.strip()]
    return names


def main():
    # Read Stop hook payload
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # malformed input → silent

    transcript_path = payload.get("transcript_path")
    if not transcript_path:
        sys.exit(0)

    tp = Path(transcript_path)
    if not tp.exists() or not tp.is_file():
        sys.exit(0)

    # Read full transcript
    try:
        messages = []
        with tp.open() as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        messages.append(json.loads(line))
                    except json.JSONDecodeError:
                        # Skip malformed lines; don't fail the hook
                        continue
    except Exception:
        sys.exit(0)

    if not messages:
        sys.exit(0)

    # Identify last user message; current turn = everything after
    last_user_idx = -1
    for i, msg in enumerate(messages):
        if msg.get("type") == "user":
            last_user_idx = i

    if last_user_idx == -1:
        sys.exit(0)

    turn_msgs = messages[last_user_idx + 1:]
    if not turn_msgs:
        sys.exit(0)

    # Find the FIRST text block of the FIRST assistant message in the turn.
    # The canonical declaration (Tier on line 1, Personas on line 2) lives here.
    # We deliberately do NOT scan later blocks — that's how false positives on
    # quoted prior-turn text creep in.
    first_text = None
    for msg in turn_msgs:
        if msg.get("type") != "assistant":
            continue
        content = msg.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") != "text":
                continue
            text = block.get("text", "")
            if text:
                first_text = text
                break
        if first_text is not None:
            break

    if not first_text:
        sys.exit(0)

    # Restrict scan to the FIRST ~5 lines of the first text block.
    # The canonical declaration is on lines 1–2; allowing a small buffer for
    # leading whitespace or an occasional preamble while still blocking
    # false positives from quoted text later in the response.
    header_window = "\n".join(first_text.splitlines()[:5])

    tier_match = TIER_LINE_RE.search(header_window)
    if not tier_match:
        sys.exit(0)  # Not Tier 3+; out of scope, silent.

    tier_name = tier_match.group(1)

    personas_match = PERSONAS_LINE_RE.search(header_window)
    if not personas_match:
        # Tier 3+ declared but no `Task: ... | Personas: ...` line.
        # Per CLAUDE.md L13: the second-line declaration is mandatory when
        # the architecture fires. Treat as architecture violation.
        msg = (
            f"Phase 3 spawn-audit FAILED.\n"
            f"Tier {tier_name} declared on line 1 but no `Task: ... | Personas: ...` "
            f"line found in the first 5 lines of the response.\n"
            f"Per CLAUDE.md L13: the second-line declaration is mandatory when "
            f"the architecture fires (Tier 3+ OR Tier 2 + persona task).\n"
            f"Next turn: add the Personas declaration AND spawn the team — "
            f"OR downgrade the tier if architecture wasn't required."
        )
        print(msg, file=sys.stderr)
        sys.exit(2)

    declared_personas = parse_personas(personas_match.group(1))
    if not declared_personas:
        # Personas line present but empty / unparseable → also a violation.
        msg = (
            f"Phase 3 spawn-audit FAILED.\n"
            f"Tier {tier_name} declared with a `Personas:` line, but no persona "
            f"names could be parsed from it.\n"
            f"Expected format: `Task: <type> | Personas: <Lead> (lead), <P2>, <P3>`."
        )
        print(msg, file=sys.stderr)
        sys.exit(2)

    declared_count = len(declared_personas)

    # Count Agent tool calls across the entire turn
    agent_count = 0
    for msg in turn_msgs:
        if msg.get("type") != "assistant":
            continue
        content = msg.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use" and block.get("name") == "Agent":
                agent_count += 1

    if agent_count < declared_count:
        msg = (
            f"Phase 3 spawn-audit FAILED.\n"
            f"Declared {declared_count} personas on line 2: {', '.join(declared_personas)}\n"
            f"Spawned only {agent_count} Agent() tool calls in this turn.\n"
            f"Per CLAUDE.md Phase 3 atomic spawn requirement: spawned count MUST equal declared count.\n"
            f"This is property (1) of the persona architecture — independent subagents.\n"
            f"Next turn: spawn missing personas OR explain why the declared count was inaccurate."
        )
        print(msg, file=sys.stderr)
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()