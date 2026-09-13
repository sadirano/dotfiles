"""PreToolUse guard: refuse image-name process kills that can take down Claude sessions.

Every Claude session on this machine runs as x.exe -> claude.exe -> cmd.exe -> shell,
so killing by image name (not PID) kills every open session at once.

The kill is allowed only after the user types the phrase below in a prompt of
the same session. Tool results and model text never count.
"""
import json
import re
import sys

PHRASE = "allow broad kill"

NAMES = (
    r"(?:x|cmd|pwsh|powershell|node|claude|bash|sh|conhost|windowsterminal|"
    r"openconsole|wt|explorer)(?:\.exe)?"
)
# A wildcard name ("c*", "*") can match any of the above.
TARGET = rf"""["']?(?:{NAMES}|[^\s"']*\*[^\s"']*)["']?(?=[\s;|&)"']|$)"""

PATTERNS = [
    # taskkill /IM name, //IM, -im
    rf"taskkill\b[^\n;|&]*?(?:/{{1,2}}|-)im\s+{TARGET}",
    # taskkill /FI "IMAGENAME eq name"
    rf"taskkill\b[^\n;|&]*?imagename\s+eq\s+{TARGET}",
    # Stop-Process -Name / -ProcessName (also via spps / kill aliases)
    rf"(?:stop-process|spps|kill)\b[^\n;|&]*?-(?:process)?name\s+{TARGET}",
    # Get-Process name | Stop-Process
    rf"(?:get-process|gps|ps)\s+(?:-(?:process)?name\s+)?{TARGET}[^\n;]*\|\s*(?:stop-process|spps|kill)\b",
    # wmic process where name='cmd.exe' delete|call terminate
    rf"wmic\b[^\n]*?name\s*=\s*{TARGET}[^\n]*?(?:delete|terminate)",
    # CIM/WMI Terminate filtered by name
    rf"win32_process[^\n]*?name\s*=\s*{TARGET}[^\n]*?terminate",
    # pkill / killall by name
    rf"(?:pkill|killall)\b[^\n;|&]*?\s{TARGET}",
]
COMPILED = [re.compile(p, re.IGNORECASE) for p in PATTERNS]


def user_typed_texts(transcript_path):
    """Yield text the human typed in this session (not tool results, not meta)."""
    try:
        with open(transcript_path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("type") != "user" or d.get("isMeta") or d.get("isSidechain"):
                    continue
                msg = d.get("message")
                if not isinstance(msg, dict) or msg.get("role") != "user":
                    continue
                content = msg.get("content")
                if isinstance(content, str):
                    yield content
                elif isinstance(content, list):
                    if any(b.get("type") == "tool_result" for b in content if isinstance(b, dict)):
                        continue
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "text":
                            yield b.get("text", "")
    except OSError:
        return


def strip_injected(text):
    return re.sub(r"<system-reminder>.*?</system-reminder>", "", text, flags=re.DOTALL)


def main():
    # The payload is UTF-8; sys.stdin would decode it with the console codepage.
    try:
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8", errors="replace"))
    except ValueError:
        return 0
    if not isinstance(payload, dict):
        return 0
    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command") or ""
    if not isinstance(command, str) or not any(p.search(command) for p in COMPILED):
        return 0

    transcript = payload.get("transcript_path") or ""
    # A subagent's prompt is written by the model, so it can never authorize.
    authorized = bool(transcript) and "subagents" not in transcript.replace("\\", "/").split("/")
    if authorized:
        authorized = any(PHRASE in strip_injected(t).lower() for t in user_typed_texts(transcript))
    if authorized:
        return 0

    reason = (
        "Blocked: this kills processes by image name. Every Claude session on this "
        "machine runs under x.exe -> claude.exe -> cmd.exe, so it would close ALL open "
        "sessions (this happened on 2026-09-13). Kill the specific PID you started "
        "instead. If a broad kill is truly needed, ask the user; it is allowed only "
        "after they type '" + PHRASE + "' in this session."
    )
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
