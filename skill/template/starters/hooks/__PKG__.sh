#!/usr/bin/env bash
# __PKG__ — <one line on what this refuses, or does, and when>
#
# <Why it exists. The reasoning that is not obvious from the code: what went
# wrong without it, what was tried first and did not work, what would break if
# someone "simplified" it. That paragraph is the reason this file is worth
# keeping.>
#
# Hook events and what they can do are in the kit's reference/hook-events.md.
set -uo pipefail

JQ=$(command -v jq) || exit 0   # no jq: fail open rather than break every call
input=$(cat)

# Deny, rather than ask. In auto mode an "ask" decision is resolved by the same
# classifier that approves ordinary tool calls, so it never reaches the user.
# Only deny is beyond its reach. See reference/hook-events.md.
exit 0
