"""Import one audited, self-contained bundle without checking out historical code.

Fill the four capitalized placeholders from the reviewed local audit before upload.
This script and the bundle are removed from the resulting tree. The workflow
is left byte-for-byte unchanged for the authenticated plugin to remove next:
GITHUB_TOKEN does not grant permission to modify workflow files.
"""

from __future__ import annotations

import collections
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


PUBLISH_BASE_SHA = "a7b47f9f26321de6dff079e9e8ec3ee0b337d1b8"
HISTORY_TIP = "bd0a42f8448b9860709e12e42d3c635ea2f7945b"
HISTORY_COUNT = "77"
BUNDLE_SHA256 = "0e4968866531cee0d22d0de7279d359efe30779ff4d1e94eec79e538b3184513"

REPOSITORY = "ShenTenghui/shuiyu-core"
BRANCH = "refs/heads/main"
BUNDLE_REF = "refs/heads/main"
TEMP_REF = "refs/heads/history-import-temp"
BUNDLE_PATH = ".github/history-import/shuiyu-core.bundle"
SCRIPT_PATH = ".github/history-import/import_history.py"
WORKFLOW_PATH = ".github/workflows/import-history.yml"
TEMPORARY_PATHS = {BUNDLE_PATH, SCRIPT_PATH, WORKFLOW_PATH}
REMOVABLE_PATHS = {BUNDLE_PATH, SCRIPT_PATH}
EXPECTED_APPLICATION_FILES = 42


def fail(message: str) -> None:
    raise SystemExit(message)


def git(*args: str, data: bytes | None = None, env: dict | None = None) -> bytes:
    result = subprocess.run(
        ["git", "-c", "core.hooksPath=/dev/null", *args],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    if result.returncode:
        fail("Git operation failed: " + " ".join(args) + "\n" + result.stderr.decode("utf-8", "replace"))
    return result.stdout


def text(*args: str) -> str:
    return git(*args).decode("utf-8").strip()


def is_ancestor(ancestor: str, descendant: str) -> bool:
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode not in (0, 1):
        fail("Cannot verify commit ancestry.")
    return result.returncode == 0


def remote_main() -> str:
    rows = git("ls-remote", "--exit-code", "origin", BRANCH).splitlines()
    if len(rows) != 1:
        fail("Expected exactly one remote main ref.")
    oid, ref = rows[0].split(b"\t", 1)
    if ref.decode("ascii") != BRANCH:
        fail("Unexpected remote ref.")
    return oid.decode("ascii")


def tree_files(commit: str) -> set[str]:
    return {
        name.decode("utf-8")
        for name in git("ls-tree", "-r", "--name-only", "-z", commit).split(b"\0")
        if name
    }


def verify_self_contained_bundle(bundle: Path) -> None:
    # Prerequisites are '-' header records before the first blank line.
    # A self-contained bundle must contain no such record even if the local
    # checkout happened to satisfy it.
    with bundle.open("rb") as stream:
        signature = stream.readline(1024)
        if signature not in (b"# v2 git bundle\n", b"# v3 git bundle\n"):
            fail("Unsupported bundle signature.")
        for _ in range(1000):
            line = stream.readline(4096)
            if line == b"\n":
                break
            if not line or not line.endswith(b"\n"):
                fail("Malformed bundle header.")
            if line.startswith(b"-"):
                fail("Bundle must be self-contained, with no prerequisites.")
        else:
            fail("Bundle header is unexpectedly large.")
    git("bundle", "verify", str(bundle))
    rows = git("bundle", "list-heads", str(bundle)).splitlines()
    if rows != [(HISTORY_TIP + " " + BUNDLE_REF).encode("ascii")]:
        fail("Bundle must advertise only the audited history ref and tip.")


def metadata_summary(tip: str) -> dict:
    # This fingerprint is reproducible against the local filtered repository.
    # Raw author/committer records include their original epoch and TZ offset;
    # messages are hashed as bytes, without date formatting or re-encoding.
    commits = sorted(git("rev-list", tip).splitlines())
    batch = git("cat-file", "--batch", data=b"\n".join(commits) + b"\n")
    position = 0
    digest = hashlib.sha256()
    authors: collections.Counter[str] = collections.Counter()
    committers: collections.Counter[str] = collections.Counter()
    dates: list[int] = []
    for expected in commits:
        end = batch.index(b"\n", position)
        oid, kind, size_raw = batch[position:end].split()
        if oid != expected or kind != b"commit":
            fail("Unexpected object in historical commit metadata.")
        size = int(size_raw)
        raw = batch[end + 1:end + 1 + size]
        position = end + 1 + size
        if batch[position:position + 1] != b"\n":
            fail("Malformed cat-file output.")
        position += 1
        headers, message = raw.split(b"\n\n", 1)
        author_rows = [row for row in headers.splitlines() if row.startswith(b"author ")]
        committer_rows = [row for row in headers.splitlines() if row.startswith(b"committer ")]
        if len(author_rows) != 1 or len(committer_rows) != 1:
            fail("Historical commit has malformed author or committer metadata.")
        author, committer = author_rows[0], committer_rows[0]
        author_identity, author_epoch, author_tz = author[len(b"author "):].rsplit(b" ", 2)
        committer_identity, committer_epoch, committer_tz = committer[len(b"committer "):].rsplit(b" ", 2)
        if not re.fullmatch(rb"[+-][0-9]{4}", author_tz) or not re.fullmatch(rb"[+-][0-9]{4}", committer_tz):
            fail("Unexpected historical timezone offset.")
        dates.append(int(author_epoch))
        int(committer_epoch)
        authors[author_identity.decode("utf-8")] += 1
        committers[committer_identity.decode("utf-8")] += 1
        for part in (expected, author, committer, message):
            digest.update(str(len(part)).encode("ascii") + b":" + part)
    if position != len(batch) or len(commits) != int(HISTORY_COUNT):
        fail("Unexpected metadata length or historical commit count.")
    return {
        "commit_count": len(commits),
        "raw_author_committer_message_sha256": digest.hexdigest(),
        "authors": dict(authors),
        "committers": dict(committers),
        "earliest_author_epoch": min(dates),
        "latest_author_epoch": max(dates),
    }


def main() -> None:
    for value in (PUBLISH_BASE_SHA, HISTORY_TIP):
        if not re.fullmatch(r"[0-9a-f]{40}", value):
            fail("Replace the audited commit placeholders before running.")
    if not re.fullmatch(r"[0-9a-f]{64}", BUNDLE_SHA256):
        fail("Replace the audited bundle checksum placeholder before running.")
    if not HISTORY_COUNT.isdigit() or int(HISTORY_COUNT) <= 0:
        fail("Replace the audited historical commit count before running.")
    if os.environ.get("GITHUB_REPOSITORY") != REPOSITORY or os.environ.get("GITHUB_REF") != BRANCH:
        fail("This migration is restricted to the intended repository and branch.")
    if os.environ.get("GITHUB_EVENT_NAME") != "push":
        fail("This migration only accepts a push trigger.")
    github_sha = os.environ.get("GITHUB_SHA", "")
    if not re.fullmatch(r"[0-9a-f]{40}", github_sha):
        fail("Missing GitHub event commit.")
    if text("rev-parse", "HEAD") != github_sha or remote_main() != github_sha:
        fail("Remote main or checkout changed; stop without pushing.")
    if not is_ancestor(PUBLISH_BASE_SHA, github_sha):
        fail("Published application commit is not an ancestor of this event.")
    if git("status", "--porcelain", "--untracked-files=all"):
        fail("The fresh checkout must be clean.")
    application_files = tree_files(PUBLISH_BASE_SHA)
    if len(application_files) != EXPECTED_APPLICATION_FILES:
        fail("The audited application snapshot must have exactly 42 files.")
    current_files = tree_files(github_sha)
    if application_files & TEMPORARY_PATHS or current_files != application_files | TEMPORARY_PATHS:
        fail("Only the three audited temporary import files may be added.")
    changed = {
        value.decode("utf-8")
        for value in git("diff", "--name-only", "-z", PUBLISH_BASE_SHA, github_sha).split(b"\0")
        if value
    }
    if changed != TEMPORARY_PATHS:
        fail("The import commit must leave every application file unchanged.")
    bundle = Path(BUNDLE_PATH)
    if not bundle.is_file() or bundle.is_symlink():
        fail("Expected a regular bundle file.")
    with bundle.open("rb") as bundle_stream:
        actual_bundle_hash = hashlib.file_digest(bundle_stream, "sha256").hexdigest()
    if actual_bundle_hash != BUNDLE_SHA256:
        fail("Bundle SHA-256 differs from the reviewed local artifact.")
    verify_self_contained_bundle(bundle)
    existing = subprocess.run(
        ["git", "show-ref", "--verify", "--quiet", TEMP_REF], check=False,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if existing.returncode != 1:
        fail("Temporary history ref already exists or cannot be checked.")
    git("fetch", "--no-tags", "--no-write-fetch-head", "--refmap=", str(bundle.resolve()), BUNDLE_REF + ":" + TEMP_REF)
    if text("rev-parse", TEMP_REF + "^{commit}") != HISTORY_TIP:
        fail("Fetched history tip differs from the audited tip.")
    if text("rev-list", "--count", HISTORY_TIP) != HISTORY_COUNT:
        fail("Fetched history count differs from the audited count.")
    if is_ancestor(HISTORY_TIP, github_sha) or is_ancestor(github_sha, HISTORY_TIP):
        fail("Historical tip is already imported or is not an independent history.")
    metadata = metadata_summary(HISTORY_TIP)
    original_tree = text("rev-parse", PUBLISH_BASE_SHA + "^{tree}")
    with tempfile.TemporaryDirectory(prefix="shuiyu-import-index-", dir=os.environ.get("RUNNER_TEMP")) as index_dir:
        env = os.environ.copy()
        env["GIT_INDEX_FILE"] = str(Path(index_dir) / "index")
        git("read-tree", github_sha, env=env)
        git("update-index", "--force-remove", "--", *sorted(REMOVABLE_PATHS), env=env)
        cleaned_tree = git("write-tree", env=env).decode("ascii").strip()
        workflow_entry = git("ls-tree", "-z", github_sha, "--", WORKFLOW_PATH)
        entry_header, entry_path = workflow_entry.rstrip(b"\0").split(b"\t", 1)
        mode, kind, workflow_blob = entry_header.split()
        if mode != b"100644" or kind != b"blob" or entry_path.decode("utf-8") != WORKFLOW_PATH:
            fail("The retained workflow must be a regular file at the intended path.")
        # Independently construct the expected tree from the original application
        # plus the exact workflow blob. This proves all 42 application entries,
        # their modes, and their blobs remain intact, with only one extra file.
        git("read-tree", PUBLISH_BASE_SHA, env=env)
        git("update-index", "--add", "--cacheinfo", "100644," + workflow_blob.decode("ascii") + "," + WORKFLOW_PATH, env=env)
        expected_merge_tree = git("write-tree", env=env).decode("ascii").strip()
    if cleaned_tree != expected_merge_tree:
        fail("Cleaned tree must equal the published application plus the unchanged import workflow.")
    current_time = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S%z")
    commit_env = os.environ.copy()
    for role in ("AUTHOR", "COMMITTER"):
        commit_env["GIT_" + role + "_NAME"] = "github-actions[bot]"
        commit_env["GIT_" + role + "_EMAIL"] = "41898282+github-actions[bot]@users.noreply.github.com"
        commit_env["GIT_" + role + "_DATE"] = current_time
    message = (
        "Import audited Shuiyu core development history\n\n"
        "Preserve every existing application file and the published commits.\n"
        "Attach only the reviewed core-file history, retaining its original\n"
        "author, committer, dates, and commit messages.\n"
        "Leave the temporary workflow unchanged for authenticated cleanup.\n"
        "History tip: " + HISTORY_TIP + "\n"
        "Bundle SHA-256: " + BUNDLE_SHA256 + "\n"
    )
    merge_sha = git(
        "commit-tree", cleaned_tree, "-p", github_sha, "-p", HISTORY_TIP,
        data=message.encode("utf-8"), env=commit_env,
    ).decode("ascii").strip()
    if text("show", "-s", "--format=%P", merge_sha) != github_sha + " " + HISTORY_TIP:
        fail("Migration commit must have exactly the two intended parents.")
    if text("rev-parse", merge_sha + "^{tree}") != expected_merge_tree or not is_ancestor(PUBLISH_BASE_SHA, merge_sha):
        fail("Migration commit failed application-tree or ancestry verification.")
    if tree_files(merge_sha) != application_files | {WORKFLOW_PATH}:
        fail("Migration tree must contain exactly the application and retained workflow.")
    if remote_main() != github_sha:
        fail("Remote main changed during validation; stop without pushing.")
    # This is deliberately an ordinary fast-forward push, with no force or lease.
    # If main races after the preceding check, Git rejects the unrelated update.
    git("push", "origin", merge_sha + ":" + BRANCH)
    if remote_main() != merge_sha:
        fail("Remote main differs from the migration commit after push.")
    git("update-ref", "-d", TEMP_REF, HISTORY_TIP)
    result = {
        "repository": REPOSITORY,
        "published_base_sha": PUBLISH_BASE_SHA,
        "import_trigger_sha": github_sha,
        "historical_tip": HISTORY_TIP,
        "migration_merge_sha": merge_sha,
        "application_tree": original_tree,
        "migration_tree": expected_merge_tree,
        "application_files": len(application_files),
        "temporary_files_removed_from_tree": sorted(REMOVABLE_PATHS),
        "retained_temporary_workflow": WORKFLOW_PATH,
        "next_step": "Authenticated plugin removes the unchanged import workflow while updating provenance and triggering final CI.",
        "bundle_sha256": BUNDLE_SHA256,
        "historical_metadata": metadata,
        "push_mode": "ordinary fast-forward",
    }
    report = json.dumps(result, ensure_ascii=False, indent=2)
    print(report)
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as summary:
            summary.write("Audited history imported; every application file is unchanged. The temporary workflow awaits authenticated cleanup.\n\n```json\n" + report + "\n```\n")


if __name__ == "__main__":
    main()
