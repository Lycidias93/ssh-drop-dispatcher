#!/usr/bin/env python3
"""Conservative, PR-scoped Codex review request gate.

Usage: python3 tools/codex-review-once.py --pr NUMBER --head FULL_SHA [--send]
The caller must hold the exclusive RepoWork PR-review action claim for --send.
No automatic retry after a provider error or an ambiguous POST outcome.
"""
import argparse
import json
import re
import subprocess
import sys

REPO = "Lycidias93/ssh-drop-dispatcher"
BOT = "chatgpt-codex-connector"
SHA = re.compile(r"[0-9a-f]{40}\Z")
MENTION = re.compile(r"(?m)^\s*@codex\s+review(?:\s|$)", re.IGNORECASE)


class GateError(Exception):
    pass


def gh_api(endpoint, *, paginate=False, body=None):
    args = ["gh", "api", endpoint]
    if paginate:
        args.extend(["--paginate", "--jq", ".[]"])
    if body is not None:
        args.extend(["--method", "POST", "-f", "body=" + body])
    proc = subprocess.run(args, capture_output=True, text=True, check=False)
    if proc.returncode:
        raise GateError("GitHub request failed: " + endpoint + " (no request retry)")
    if paginate:
        # GitHub CLI 2.46 supports --paginate/--jq but not --slurp.
        # .[] emits one compact JSON object per line across all pages.
        try:
            rows = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
        except json.JSONDecodeError as exc:
            raise GateError("GitHub pagination malformed: " + endpoint) from exc
        if any(not isinstance(row, dict) for row in rows):
            raise GateError("GitHub pagination malformed: " + endpoint)
        return rows
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise GateError("GitHub response malformed: " + endpoint) from exc


def evidence(pr):
    prefix = "repos/" + REPO
    discussions = gh_api(f"{prefix}/issues/{pr}/comments?per_page=100", paginate=True)
    reviews = gh_api(f"{prefix}/pulls/{pr}/reviews?per_page=100", paginate=True)
    for review in reviews:
        if not isinstance(review, dict):
            raise GateError("Invalid review entry")
        login = str((review.get("user") or {}).get("login") or "").lower()
        if login.startswith(BOT):
            return "codex_review_exists"
    for comment in discussions:
        if not isinstance(comment, dict):
            raise GateError("Invalid conversation entry")
        body = str(comment.get("body") or "")
        login = str((comment.get("user") or {}).get("login") or "").lower()
        if MENTION.search(body):
            return "review_request_exists"
        if login.startswith(BOT) and ("codex-review-state:" in body or
                                      "usage limits for code reviews" in body.lower()):
            return "provider_response_exists"
    return None


def run(pr, head, send=False):
    if not SHA.fullmatch(head):
        raise GateError("Exact 40-character lower-case head SHA required")
    info = gh_api(f"repos/{REPO}/pulls/{pr}")
    if not isinstance(info, dict) or info.get("number") != pr:
        raise GateError("PR identity not verified")
    if info.get("state") != "open":
        return "SKIP closed_pr"
    if (info.get("head") or {}).get("sha") != head:
        raise GateError("PR head changed: request blocked")
    if info.get("draft"):
        return "SKIP draft_pr"
    existing = evidence(pr)
    if existing:
        return "SKIP " + existing
    if not send:
        return "REQUIRED no_prior_request_or_review"
    account = gh_api("user")
    if (account.get("login") or "").lower() != REPO.split("/")[0].lower():
        raise GateError("Authenticated GitHub owner mismatch")
    body = f"@codex review\nreview_head_sha={head}\n\nOne initial review for this PR; further automatic requests disabled."
    result = gh_api(f"repos/{REPO}/issues/{pr}/comments", body=body)
    request_id = result.get("id") if isinstance(result, dict) else None
    if not isinstance(request_id, int):
        raise GateError("Post response had no request ID; inspect GitHub before retry")
    comments = gh_api(f"repos/{REPO}/issues/{pr}/comments?per_page=100", paginate=True)
    if not any(isinstance(c, dict) and c.get("id") == request_id and
               c.get("body") == body for c in comments):
        raise GateError("Posted request not yet visible in exact readback; do not retry")
    return "SENT id=" + str(request_id)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--send", action="store_true", help="Post at most one initial request")
    args = parser.parse_args()
    if args.pr <= 0:
        parser.error("--pr must be positive")
    try:
        outcome = run(args.pr, args.head, send=args.send)
    except GateError as exc:
        print("RESULT: CODEX_REVIEW_ONCE_STOP reason=" + str(exc), file=sys.stderr)
        return 1
    print(f"RESULT: CODEX_REVIEW_ONCE_{outcome} pr={args.pr} head={args.head}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
