#!/bin/bash
# A stand-in for the claude command, used only by scripts/screenshots.sh. It speaks Claude Code's real
# stream-json protocol (the lines Meraline decodes and answers), but its MCP servers and its answers are
# scripted, so the README pictures show neutral demo servers rather than the machine's own servers,
# paths, and files. Meraline itself never runs it.
#
#   demo-agent.sh mcp list     the demo servers, in the format of `claude mcp list`
#   demo-agent.sh --print …    reads one user message on stdin and plays a scripted run. A message that
#                              mentions a changelog gets a question with two choices; anything else
#                              searches two MCP servers, answers, and asks to write notes.md.

if [ "$1" = "mcp" ] && [ "$2" = "list" ]; then
    cat <<'LIST'
Checking MCP server health…

github: https://api.githubcopilot.com/mcp/ - ✔ Connected
linear: https://mcp.linear.app/mcp - ✔ Connected
filesystem: npx -y @modelcontextprotocol/server-filesystem ~/Documents - ✔ Connected
LIST
    exit 0
fi

IFS= read -r message
emit() { printf '%s\n' "$1"; }
thinking() { emit '{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}}'; }
tool() { emit "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_$1\",\"name\":\"$2\",\"input\":$3}]}}"; }
text() { emit "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"$1\"}}}"; }
# Asks Meraline and waits for its answer on stdin, as claude does with --permission-prompt-tool stdio.
ask() { emit "{\"type\":\"control_request\",\"request_id\":\"$1\",\"request\":$2}"; IFS= read -r -t 900 answer; }
finish() { emit '{"type":"result","subtype":"success","is_error":false,"result":"done"}'; exit 0; }

emit '{"type":"system","subtype":"init","tools":[]}'
thinking
sleep 0.8

case "$message" in
    *changelog*)
        ask req-release '{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Which release is this changelog entry for?","header":"Release","options":[{"label":"1.3.0","description":"New features, nothing breaks"},{"label":"2.0.0","description":"Includes breaking changes"}],"multiSelect":false}]}}'
        text "Got it. Drafting the entry now."
        finish
        ;;
    *)
        tool 1 mcp__github__search_issues '{"query":"menu bar icon","state":"open"}'
        sleep 0.8
        tool 2 mcp__linear__search_issues '{"query":"menu bar icon"}'
        sleep 0.8
        for chunk in \
            "Three open issues mention the menu bar icon:" \
            "\\n\\n- **#41** It disappears after the Mac wakes from sleep." \
            "\\n- **#38** Add a monochrome variant for tinted menu bars." \
            "\\n- **#35** Hide it in full-screen apps (also tracked in Linear as MER-112)." \
            "\\n\\nI'll save this summary to notes.md."; do
            text "$chunk"
            sleep 0.15
        done
        ask req-write "{\"subtype\":\"can_use_tool\",\"tool_name\":\"Write\",\"display_name\":\"Write\",\"input\":{\"file_path\":\"$PWD/notes.md\",\"content\":\"# Menu bar icon\\n\"},\"description\":\"notes.md\",\"tool_use_id\":\"toolu_3\"}"
        case "$answer" in
            *'"allow"'*) text "\\n\\nSaved to notes.md." ;;
            *) text "\\n\\nOkay, I won't save it." ;;
        esac
        finish
        ;;
esac
