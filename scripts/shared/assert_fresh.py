"""
assert_fresh() - shared freshness-enforcement mechanism (2026-09-08 rebuild).

Python counterpart to assert_fresh.R - same interface and semantics
deliberately, since this project's Python and R scripts both need it and
don't share a module system across repos (see this project's own
standalone-script convention). Keep the two in sync by hand; they're small
and simple on purpose so that's a realistic thing to actually do, unlike the
duplicated business logic elsewhere in this codebase that's caused drift
before.

See assert_fresh.R's header for the full rationale (the 2026-09-07 incident,
the "safe auto-fix" vs "stop and ask" split, and why version-stamp files are
written as a side effect of this function rather than trusted as ground
truth).
"""
import hashlib
import os


def _file_state(path):
    if not os.path.exists(path):
        return None
    mtime = os.path.getmtime(path)
    with open(path, "rb") as f:
        md5 = hashlib.md5(f.read()).hexdigest()
    return {"mtime": mtime, "md5": md5}


def assert_fresh(artifact_path, source_paths, mode="auto", fix_fn=None,
                  fix_hint=None, stamp_path=None, label=None):
    """
    artifact_path: file that must be fresh.
    source_paths: list of path(s) the artifact must not predate.
    mode: "auto" (safe, deterministic regeneration - runs fix_fn() itself) or
          "stop" (judgment-sensitive or explicitly not-casual-to-rerun -
          raises with fix_hint, never runs anything).
    fix_fn: zero-arg callable, required for mode="auto".
    fix_hint: human-readable exact command, used in the error for mode="stop".
    stamp_path: optional - where to write a version-stamp file on success.
    label: optional short name for messages; defaults to the basename.

    Returns True if the artifact was already fresh, False if mode="auto" and
    a fix was applied. Raises RuntimeError for mode="stop" staleness, a
    broken fix_fn(), or a missing source.
    """
    if isinstance(source_paths, str):
        source_paths = [source_paths]
    label = label or os.path.basename(artifact_path)

    missing_sources = [p for p in source_paths if not os.path.exists(p)]
    if missing_sources:
        raise RuntimeError(
            f"assert_fresh({label}): source file(s) do not exist, cannot check freshness: "
            + ", ".join(missing_sources)
        )

    def check_stale():
        art = _file_state(artifact_path)
        if art is None:
            return True
        newest_source_mtime = max(_file_state(p)["mtime"] for p in source_paths)
        return art["mtime"] < newest_source_mtime

    stale = check_stale()

    if stale and mode == "stop":
        newest_source = max(source_paths, key=lambda p: _file_state(p)["mtime"])
        raise RuntimeError(
            f"assert_fresh({label}): STALE - this predates its source ({newest_source}) "
            "and this project's convention is to never auto-regenerate this one "
            "(judgment-sensitive or explicitly not-casual-to-rerun). Run this first, "
            "then re-run whatever you were doing:\n\n    "
            + (fix_hint or "(no fix_hint provided - see the artifact's own build script)")
            + "\n"
        )

    if stale and mode == "auto":
        if fix_fn is None:
            raise RuntimeError(f"assert_fresh({label}): STALE and mode='auto' but no fix_fn provided.")
        print(f"assert_fresh({label}): stale, auto-fixing...")
        fix_fn()
        if check_stale():
            raise RuntimeError(
                f"assert_fresh({label}): still stale after fix_fn() ran - the regeneration "
                "itself is broken, not a freshness gap. Investigate fix_fn(), don't retry."
            )
        print(f"assert_fresh({label}): refreshed from "
              + ", ".join(os.path.basename(p) for p in source_paths) + ".")

    if not stale:
        print(f"assert_fresh({label}): fresh, no action needed.")

    if stamp_path:
        art = _file_state(artifact_path)
        import datetime
        lines = [
            f"stamped_at: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            f"artifact_path: {artifact_path}",
            f"artifact_mtime: {datetime.datetime.fromtimestamp(art['mtime']).strftime('%Y-%m-%d %H:%M:%S')}",
            f"artifact_md5: {art['md5']}",
            f"checked_against_sources: {'; '.join(source_paths)}",
        ]
        with open(stamp_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

    return not stale
