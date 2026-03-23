#!/usr/bin/env python3
"""Build all-project vulnerable/patch dataset from Real_Vul_data.csv (local git first, API fallback)."""

from __future__ import annotations

import argparse
import base64
import csv
import json
import os
import re
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import pandas as pd
try:
    from dotenv import load_dotenv
except Exception:  # pragma: no cover
    def load_dotenv(*args, **kwargs):  # type: ignore
        return False

PROJECT_REPOS = {
    "FFmpeg": "FFmpeg/FFmpeg",
    "ImageMagick": "ImageMagick/ImageMagick",
    "jasper": "jasper-software/jasper",
    "krb5": "krb5/krb5",
    "openssl": "openssl/openssl",
    "php-src": "php/php-src",
    "qemu": "qemu/qemu",
    "tcpdump": "the-tcpdump-group/tcpdump",
    "linux": "torvalds/linux",
    "Chrome": "chromium/chromium",
}

LOCAL_REPO_DIRS = {
    "FFmpeg": "FFmpeg",
    "ImageMagick": "ImageMagick",
    "jasper": "jasper",
    "krb5": "krb5",
    "openssl": "openssl",
    "php-src": "php-src",
    "qemu": "qemu",
    "tcpdump": "tcpdump",
    "linux": "linux",
    "Chrome": "chromium",
}

LOCAL_REPO_BASE = Path("dataset_pipeline/cache/repositories")

CODE_EXTENSIONS = (".c", ".cc", ".cpp", ".cxx", ".h", ".hpp")

REAL_VUL_COLUMNS = [
    "file_name",
    "unique_id",
    "target",
    "vulnerable_line_numbers",
    "project",
    "commit_hash",
    "dataset_type",
    "processed_func",
    "patched_code_source",
]

LOG_COLUMNS = [
    "file_name",
    "commit_hash",
    "status",
    "function_name",
    "candidate_count",
    "touched_candidate_count",
    "patched_file_path",
    "repo_full_name",
]

HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@.*$")


@dataclass(frozen=True)
class FunctionSpan:
    name: str
    start: int
    end: int


@dataclass(frozen=True)
class Candidate:
    path: str
    span: FunctionSpan
    code: str
    touched_by_hunk: bool


@dataclass(frozen=True)
class CommitContext:
    repo_full_name: Optional[str]
    commit_index: Optional[Dict[str, List[Candidate]]]
    source: str  # local | api | none


def normalize_commit_hash(raw: str) -> str:
    token = (raw or "").strip().split("?")[0]
    m = re.search(r"\b[0-9a-fA-F]{40}\b", token)
    return m.group(0) if m else token


def parse_functions_with_ctags(code: str) -> List[FunctionSpan]:
    total_lines = max(1, len(code.splitlines()))
    with tempfile.NamedTemporaryFile("w", suffix=".c", delete=False, encoding="utf-8") as tmp:
        tmp.write(code)
        tmp_path = Path(tmp.name)
    try:
        res = subprocess.run(
            [
                "ctags",
                "--output-format=json",
                "--fields=+neK",
                "--kinds-C=f",
                "-f",
                "-",
                str(tmp_path),
            ],
            capture_output=True,
            text=True,
        )
        if res.returncode != 0:
            return []
        funcs = []
        for line in res.stdout.splitlines():
            try:
                tag = json.loads(line)
            except json.JSONDecodeError:
                continue
            if tag.get("_type") != "tag" or tag.get("kind") != "function":
                continue
            if "name" not in tag or "line" not in tag:
                continue
            start = int(tag["line"])
            end = int(tag.get("end", total_lines))
            if end < start:
                end = total_lines
            funcs.append(FunctionSpan(str(tag["name"]), start, end))
        return funcs
    finally:
        tmp_path.unlink(missing_ok=True)


def extract_code_by_span(code: str, span: FunctionSpan) -> str:
    lines = code.splitlines(keepends=True)
    s, e = max(1, span.start), min(len(lines), span.end)
    return "" if s > e else "".join(lines[s - 1 : e])


def extract_code_by_span_with_repair(code: str, span: FunctionSpan) -> str:
    """Extract function code by ctags span, with conservative repair when span starts too early."""
    lines = code.splitlines(keepends=True)
    if not lines:
        return ""

    s, e = max(1, span.start), min(len(lines), span.end)
    if s > e:
        return ""

    raw = "".join(lines[s - 1 : e])
    name_pat = re.compile(rf"\b{re.escape(span.name)}\s*\(")

    # Fast path: current span already starts around the expected function header.
    head_sample = "".join(lines[s - 1 : min(len(lines), s + 2)])
    if name_pat.search(head_sample):
        return raw

    # Repair path: locate the real header nearby and re-compute function end by brace balance.
    search_s = max(1, s - 8)
    search_e = min(len(lines), e + 120)
    header_line = None
    for i in range(search_s, search_e + 1):
        t = lines[i - 1].strip()
        if not t or t.startswith("#"):
            continue
        if name_pat.search(lines[i - 1]):
            header_line = i
            break

    if header_line is None:
        return raw

    depth = 0
    seen_open = False
    for i in range(header_line, min(len(lines), header_line + 4000) + 1):
        line = lines[i - 1]
        for ch in line:
            if ch == "{":
                depth += 1
                seen_open = True
            elif ch == "}" and seen_open:
                depth -= 1
                if depth == 0:
                    return "".join(lines[header_line - 1 : i])

    # Fallback if braces are unusual (macro-heavy code etc.)
    return "".join(lines[header_line - 1 : e]) if header_line <= e else raw


def parse_hunk_ranges(patch: str) -> List[Tuple[int, int]]:
    ranges: List[Tuple[int, int]] = []
    for line in patch.splitlines():
        hm = HUNK_RE.match(line)
        if not hm:
            continue
        start = int(hm.group(1))
        count = int(hm.group(2) or 1)
        if count <= 0:
            continue
        ranges.append((start, start + count - 1))
    return ranges


def overlaps(span: FunctionSpan, ranges: List[Tuple[int, int]]) -> bool:
    return any(not (span.end < rs or re_ < span.start) for rs, re_ in ranges)


class GitHubClient:
    def __init__(self, token: str):
        self.token = token
        self.commit_cache: Dict[Tuple[str, str], Optional[dict]] = {}
        self.blob_cache: Dict[Tuple[str, str], Optional[str]] = {}

    def _request_json(self, url: str) -> Optional[dict]:
        req = urllib.request.Request(url)
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode("utf-8", errors="ignore"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code == 422:
                # Common for missing/invalid commit SHA on /commits/{sha}
                # and some search validation failures. Treat as not-found.
                return None
            raise
        except urllib.error.URLError as e:
            raise RuntimeError(f"GitHub API unreachable: {e.reason}") from e

    def get_commit(self, repo_full_name: str, commit_hash: str) -> Optional[dict]:
        key = (repo_full_name, commit_hash)
        if key in self.commit_cache:
            return self.commit_cache[key]
        url = f"https://api.github.com/repos/{repo_full_name}/commits/{commit_hash}"
        data = self._request_json(url)
        self.commit_cache[key] = data
        return data

    def get_blob_text(self, repo_full_name: str, blob_sha: str) -> Optional[str]:
        key = (repo_full_name, blob_sha)
        if key in self.blob_cache:
            return self.blob_cache[key]
        url = f"https://api.github.com/repos/{repo_full_name}/git/blobs/{blob_sha}"
        data = self._request_json(url)
        if not data or "content" not in data:
            self.blob_cache[key] = None
            return None
        content = data["content"].replace("\n", "")
        try:
            text = base64.b64decode(content).decode("utf-8", errors="ignore")
        except Exception:
            text = None
        self.blob_cache[key] = text
        return text


def resolve_commit(client: GitHubClient, default_repo: str, commit_hash: str) -> Tuple[Optional[str], Optional[dict]]:
    commit = client.get_commit(default_repo, commit_hash)
    return (default_repo, commit) if commit else (None, None)


def local_repo_path_for_project(project: str) -> Optional[Path]:
    name = LOCAL_REPO_DIRS.get(project)
    if not name:
        return None
    p = LOCAL_REPO_BASE / name
    return p if (p / ".git").exists() else None


def run_git(repo_path: Path, args: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo_path), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="ignore",
    )


def local_has_commit(repo_path: Path, commit_hash: str) -> bool:
    res = run_git(repo_path, ["cat-file", "-e", f"{commit_hash}^{{commit}}"])
    return res.returncode == 0


def local_get_commit_patch(repo_path: Path, commit_hash: str) -> Optional[str]:
    res = run_git(repo_path, ["show", "--format=", "--no-color", "--unified=0", commit_hash])
    return res.stdout if res.returncode == 0 else None


def local_get_file_text_at_commit(repo_path: Path, commit_hash: str, file_path: str) -> Optional[str]:
    res = run_git(repo_path, ["show", f"{commit_hash}:{file_path}"])
    return res.stdout if res.returncode == 0 else None


def iter_file_patches_from_git_show(diff_text: str) -> List[Tuple[str, str]]:
    sections: List[List[str]] = []
    cur: List[str] = []
    for line in diff_text.splitlines():
        if line.startswith("diff --git "):
            if cur:
                sections.append(cur)
            cur = [line]
        elif cur:
            cur.append(line)
    if cur:
        sections.append(cur)

    out: List[Tuple[str, str]] = []
    for sec in sections:
        path = ""
        for line in sec:
            if line.startswith("+++ "):
                p = line[4:].strip()
                if p.startswith("b/"):
                    p = p[2:]
                path = p
                break
        if not path or path == "/dev/null" or not path.endswith(CODE_EXTENSIONS):
            continue
        out.append((path, "\n".join(sec)))
    return out


def build_commit_index_from_local(
    repo_path: Path,
    commit_hash: str,
) -> Optional[Dict[str, List[Candidate]]]:
    diff_text = local_get_commit_patch(repo_path, commit_hash)
    if diff_text is None:
        return None

    by_name: Dict[str, List[Candidate]] = defaultdict(list)
    for path, patch in iter_file_patches_from_git_show(diff_text):
        content = local_get_file_text_at_commit(repo_path, commit_hash, path)
        if not content:
            continue

        hunk_ranges = parse_hunk_ranges(patch)
        funcs = parse_functions_with_ctags(content)
        for span in funcs:
            code = extract_code_by_span_with_repair(content, span)
            if not code.strip():
                continue
            by_name[span.name].append(
                Candidate(
                    path=path,
                    span=span,
                    code=code,
                    touched_by_hunk=overlaps(span, hunk_ranges),
                )
            )
    return by_name


def build_commit_index_from_api(
    client: GitHubClient, repo_full_name: str, commit_payload: dict
) -> Dict[str, List[Candidate]]:
    by_name: Dict[str, List[Candidate]] = defaultdict(list)
    for f in commit_payload.get("files", []):
        path = str(f.get("filename", ""))
        if not path or not path.endswith(CODE_EXTENSIONS):
            continue
        blob_sha = f.get("sha")
        patch = str(f.get("patch", "") or "")
        if not blob_sha or not patch:
            continue
        content = client.get_blob_text(repo_full_name, blob_sha)
        if not content:
            continue

        hunk_ranges = parse_hunk_ranges(patch)
        funcs = parse_functions_with_ctags(content)
        for span in funcs:
            code = extract_code_by_span_with_repair(content, span)
            if not code.strip():
                continue
            by_name[span.name].append(
                Candidate(
                    path=path,
                    span=span,
                    code=code,
                    touched_by_hunk=overlaps(span, hunk_ranges),
                )
            )
    return by_name


def append_pair_rows(
    rows: List[dict],
    vul_row: dict,
    patch_unique_id: str,
    patch_code: str,
    patched_code_source: str,
) -> None:
    rows.append(
        {
            "file_name": vul_row["file_name"],
            "unique_id": vul_row["unique_id"],
            "target": 1,
            "vulnerable_line_numbers": vul_row["vulnerable_line_numbers"],
            "project": vul_row["project"],
            "commit_hash": vul_row["commit_hash"],
            "dataset_type": vul_row["dataset_type"],
            "processed_func": vul_row["processed_func"],
            "patched_code_source": patched_code_source,
        }
    )
    rows.append(
        {
            "file_name": f"{patch_unique_id}.c",
            "unique_id": patch_unique_id,
            "target": 0,
            "vulnerable_line_numbers": "",
            "project": vul_row["project"],
            "commit_hash": vul_row["commit_hash"],
            "dataset_type": vul_row["dataset_type"],
            "processed_func": patch_code,
            "patched_code_source": patched_code_source,
        }
    )


def append_log(logs: List[dict], file_id: str, commit_hash: str, status: str, **kwargs: Any) -> None:
    row = {"file_name": file_id, "commit_hash": commit_hash, "status": status}
    row.update(kwargs)
    logs.append(row)


def load_vul_function(
    vul_code: str,
    file_id: str,
    raw_commit: str,
    stats: Counter,
    logs: List[dict],
) -> Optional[Tuple[str, str]]:
    if not vul_code.strip():
        stats["skip_vul_func_empty"] += 1
        append_log(logs, file_id, raw_commit, "vul_func_empty")
        return None

    vul_funcs = parse_functions_with_ctags(vul_code)
    if not vul_funcs:
        stats["skip_name_extract_failed"] += 1
        append_log(logs, file_id, raw_commit, "name_extract_failed")
        return None

    vul_func_name = vul_funcs[0].name
    return vul_code, vul_func_name


def get_commit_context(
    client: GitHubClient,
    project: str,
    default_repo: str,
    commit_hash: str,
    cache: Dict[Tuple[str, str], CommitContext],
) -> CommitContext:
    key = (project, commit_hash)
    cached = cache.get(key)
    if cached is not None:
        return cached

    repo_path = local_repo_path_for_project(project)
    if repo_path and local_has_commit(repo_path, commit_hash):
        local_index = build_commit_index_from_local(repo_path, commit_hash)
        if local_index is not None:
            ctx = CommitContext(
                repo_full_name=f"local:{repo_path.name}",
                commit_index=local_index,
                source="local",
            )
            cache[key] = ctx
            return ctx

    repo_full_name, commit_payload = resolve_commit(client, default_repo, commit_hash)
    if not repo_full_name or not commit_payload:
        ctx = CommitContext(
            repo_full_name=None,
            commit_index=None,
            source="none",
        )
    else:
        commit_index = build_commit_index_from_api(client, repo_full_name, commit_payload)
        ctx = CommitContext(
            repo_full_name=repo_full_name,
            commit_index=commit_index,
            source="api",
        )
    cache[key] = ctx
    return ctx


def build_dataset(
    realvul_csv: Path,
    output_csv: Path,
    match_log_csv: Path,
    github_token: str,
) -> Counter:
    client = GitHubClient(github_token)
    df = pd.read_csv(realvul_csv, dtype=str).fillna("")
    vul_df = df[df["target"].str.strip() == "1"]

    stats = Counter()
    rows: List[dict] = []
    logs: List[dict] = []
    commit_index_cache: Dict[Tuple[str, str], CommitContext] = {}

    for _, rec in vul_df.iterrows():
        stats["vul_samples_total"] += 1
        file_id = rec["file_name"].strip()
        project = rec["project"].strip()
        if project not in PROJECT_REPOS:
            stats["skip_unknown_project"] += 1
            append_log(logs, file_id, rec.get("commit_hash", ""), "unknown_project", project=project)
            continue

        try:
            orig_uid = int(str(rec["unique_id"]).strip())
        except Exception:
            stats["skip_bad_unique_id"] += 1
            append_log(logs, file_id, rec.get("commit_hash", ""), "bad_unique_id")
            continue
        patch_unique_id = str(-(orig_uid))

        raw_commit = rec["commit_hash"].strip()
        commit_hash = normalize_commit_hash(raw_commit)
        dataset_type = "train_val"
        vuln_lines_raw = rec.get("vulnerable_line_numbers", "").strip()
        vul_code = rec.get("processed_func", "")
        default_repo = PROJECT_REPOS[project]

        row_payload = {
            "file_name": file_id,
            "unique_id": str(orig_uid),
            "vulnerable_line_numbers": vuln_lines_raw,
            "project": project,
            "commit_hash": commit_hash,
            "dataset_type": dataset_type,
            "processed_func": vul_code,
        }

        vul_info = load_vul_function(vul_code, file_id, raw_commit, stats, logs)
        if vul_info is None:
            continue
        _, vul_func_name = vul_info

        ctx = get_commit_context(client, project, default_repo, commit_hash, commit_index_cache)
        if ctx.source == "local":
            stats["resolved_from_local_commit"] += 1
        elif ctx.source == "api":
            stats["resolved_from_api_commit"] += 1
        if not ctx.repo_full_name or ctx.commit_index is None:
            stats["skip_commit_not_found"] += 1
            append_log(
                logs,
                file_id,
                raw_commit,
                "commit_not_found",
                function_name=vul_func_name,
            )
            continue

        candidates = list(ctx.commit_index.get(vul_func_name, []))
        if not candidates:
            stats["skip_no_name_match"] += 1
            append_log(
                logs,
                file_id,
                commit_hash,
                "no_name_match",
                function_name=vul_func_name,
                repo_full_name=ctx.repo_full_name,
            )
            continue

        disambiguated_by_hunk = 0
        if len(candidates) > 1:
            touched = [c for c in candidates if c.touched_by_hunk]
            if len(touched) == 1:
                candidates = touched
                disambiguated_by_hunk = 1
                stats["resolved_by_hunk"] += 1
            else:
                stats["skip_multi_match"] += 1
                append_log(
                    logs,
                    file_id,
                    commit_hash,
                    "multi_match",
                    function_name=vul_func_name,
                    candidate_count=len(candidates),
                    touched_candidate_count=len(touched),
                    repo_full_name=ctx.repo_full_name,
                )
                continue

        chosen = candidates[0]
        append_pair_rows(rows, row_payload, patch_unique_id, chosen.code, ctx.source)
        stats["matched_pairs"] += 1
        append_log(
            logs,
            file_id,
            commit_hash,
            "matched",
            function_name=vul_func_name,
            candidate_count=len(candidates),
            touched_candidate_count=int(chosen.touched_by_hunk),
            patched_file_path=chosen.path,
            repo_full_name=ctx.repo_full_name,
        )

    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with output_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=REAL_VUL_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    with match_log_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=LOG_COLUMNS)
        writer.writeheader()
        writer.writerows(logs)

    stats["output_rows"] = len(rows)
    stats["matched_rows"] = len(rows)
    return stats


def parse_args() -> argparse.Namespace:
    load_dotenv()
    parser = argparse.ArgumentParser(description="Build all-project vulnerable/patch CSV from Real_Vul_data.csv")
    parser.add_argument(
        "--realvul-csv",
        default="dataset_pipeline/output/realvul.old/Real_Vul_data.csv",
    )
    parser.add_argument(
        "--output-csv",
        default="dataset_pipeline/output/realvul.old/all_projects_vul_patch_dataset.csv",
    )
    parser.add_argument(
        "--match-log-csv",
        default="dataset_pipeline/output/realvul.old/all_projects_vul_patch_match_log.csv",
    )
    parser.add_argument("--github-token", default=os.environ.get("GITHUB_TOKEN", ""))
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    try:
        stats = build_dataset(
            realvul_csv=Path(args.realvul_csv),
            output_csv=Path(args.output_csv),
            match_log_csv=Path(args.match_log_csv),
            github_token=args.github_token,
        )
    except RuntimeError as e:
        print(f"[ERROR] {e}")
        print("Hint: Check network/DNS access and GITHUB_TOKEN.")
        raise SystemExit(1)
    print("=== Local-first/API-fallback vul/patch dataset build done ===")
    for k in sorted(stats):
        print(f"{k}: {stats[k]}")


if __name__ == "__main__":
    main()
