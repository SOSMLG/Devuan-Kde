#!/usr/bin/env bash
# extract-packages.sh — shared helpers for pulling the package-name list out
# of the toolkit's scripts. Sourced by tests/apt-checks.sh.
#
# The scripts use these install idioms:
#   * install_pkgs "Description" PKG1 PKG2 ...     (label + args)
#   * priv apt-get install -y PKG1 PKG2 ...        (real apt lines)
#   * priv env DEBIAN_FRONTEND=… apt-get install -y PKG
#   * purge_if_installed "Description" PKG...     (also names real packages)
#   * CORE_ADDONS=( PKG1 PKG2 ... )                (bash array, 48-plasmaAddons)
#   * pkg PKG [critical|optional]                 (verifySetup asserts these)
#
# Any of those may span backslash-continuation lines. This extractor joins
# continuations first, then keeps only tokens shaped like real package names
# (lowercase letter, [a-z0-9+.-], >=2 chars) — description labels, flags,
# paths and shell syntax are all rejected by that shape check.
#
# Two ways this kind of extractor has historically gone wrong, both handled:
#
#  1. A help string that *quotes* a command is not a command.
#        log_info "  Run: apt-get install smartmontools (then re-run …)"
#     A naive /apt-get[ ]+install/ match treats that as a real install site
#     and harvests `re-run`, `this`, `for`, `the` as package names. So an
#     install keyword only counts when it is *not* inside a quoted string —
#     quote parity over the preceding text is the precise test, and it needs
#     no word allowlist (an allowlist regex that permitted one intervening
#     word silently rejected `if priv apt-get install`, the commonest shape
#     in this repo).
#
#  2. Quoted prose after a real package list is not a package list. emit()
#     stops at the first quote so a trailing "— takes a while" can't leak in.
#
# Deliberately NOT an install site: install_deb_file's paths. Those are
# downloaded .deb files, not archive package names — checking them would
# fail forever for a reason that has nothing to do with a typo.
extract_packages_from() {
	local f
	for f in "$@"; do
		[ -f "$f" ] || continue
		# 1. Join backslash-continuation lines so each logical install
		#    statement is on a single line (POSIX-safe sed loop).
		sed -e ':a' -e '/\\$/ { N; s/\\\n/ /g; ba }' "$f" | awk '
            BEGIN { SQ = sprintf("%c", 39); CUT = "[\"" SQ "]" }
            # Reject a keyword that sits inside a quoted string: unbalanced
            # quotes before it mean it is prose, not code.
            function in_string(pre,   i, c, inq, ins) {
                inq = 0; ins = 0
                for (i = 1; i <= length(pre); i++) {
                    c = substr(pre, i, 1)
                    if (c == "\"") inq = !inq
                    else if (c == SQ) ins = !ins
                }
                return inq || ins
            }
            # Emit only real-looking package names, stopping at the first
            # quote so trailing prose cannot be harvested.
            function emit(str,   out, n, i, w) {
                sub(CUT ".*$", "", str)
                n = split(str, out, /[ \t]+/)
                for (i = 1; i <= n; i++) {
                    w = out[i]
                    if (w ~ /^[a-z][a-z0-9+.-]*$/ && length(w) >= 2) print w
                }
            }
            # Drop a leading human label in either quote style, whatever case
            # it starts with.
            function strip_label(arg) {
                if (match(arg, /^"[^"]*"/) || match(arg, /^'"[^']*'"'"'"'"'/)) {
                    arg = substr(arg, RLENGTH + 1)
                }
                return arg
            }
            BEGIN { in_array = 0; array_ok = 0 }
            {
                line = $0
                sub(/#.*/, "", line)          # trailing comment
                sub(/[|;&].*$/, "", line)      # stop at shell operators

                # ── NAME=( … ) arrays of packages ─────────────────────────
                # Only arrays whose name looks intentional are read, so we do
                # not harvest from every stray list in the codebase.
                if (line ~ /^[A-Za-z_][A-Za-z0-9_]*=\(/ && !in_array) {
                    in_array = 1
                    array_ok = (line ~ /(ADDONS|_PKGS|PACKAGES|APPS)/)
                    rest = line
                    sub(/^[A-Za-z_][A-Za-z0-9_]*=\(/, "", rest)
                    sub(/\).*$/, "", rest)
                    if (array_ok) emit(rest)
                    next
                }
                if (in_array) {
                    if (line ~ /\)/) {
                        rest = line
                        sub(/\).*$/, "", rest)
                        if (array_ok) emit(rest)
                        in_array = 0; array_ok = 0
                    } else if (array_ok) {
                        # Skip `"id|Label"` rows: those are Flatpak records,
                        # whose id half is a valid package *shape* but not an
                        # archive package.
                        if (line !~ /"/) emit(line)
                    }
                    next
                }

                # ── install_pkgs "label" PKG... / purge_if_installed ─────
                if (line ~ /(install_pkgs|purge_if_installed)[ \t]/) {
                    pre = line
                    sub(/.*(install_pkgs|purge_if_installed)[ \t].*$/, "", pre)
                    if (in_string(pre)) next
                    arg = line
                    sub(/.*(install_pkgs|purge_if_installed)[ \t]*/, "", arg)
                    emit(strip_label(arg))
                    next
                }

                # ── apt-get / apt install PKG... ─────────────────────────
                if (line ~ /apt(-get)?[ \t]+install[ \t]/) {
                    pre = line
                    sub(/apt(-get)?[ \t]+install[ \t].*$/, "", pre)
                    if (in_string(pre)) next   # keyword is prose, not a command
                    arg = line
                    sub(/.*apt(-get)?[ \t]+install[ \t]*/, "", arg)
                    emit(arg)
                    next
                }

                # ── pkg <name> [critical|optional] ───────────────────────
                # verifySetup.sh asserts these SHOULD be installed, so they
                # are real requirements and belong in the existence check.
                # Drop the severity word — `optional` is itself a valid
                # package *shape*, so it would otherwise be checked as one.
                if (line ~ /(^|[;&|(])[ \t]*pkg[ \t]+[a-z]/) {
                    arg = line
                    sub(/.*pkg[ \t]+/, "", arg)
                    sub(/[ \t]+(critical|optional)[ \t]*$/, "", arg)
                    emit(arg)
                }
            }
        ' 2>/dev/null
	done
}