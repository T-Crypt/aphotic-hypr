#!/usr/bin/env bash
# aphotic report — engagement report scaffolding for the exploit-reporting sublayer.
# @cmd: report
# @cmd.desc: Scaffold and render pentest/CTF engagement reports
# @cmd.group: LIFECYCLE
# @cmd.opt: new <name>     | Create a new engagement directory with a report template
# @cmd.opt: list           | List existing engagements
# @cmd.opt: render <name>  | Render an engagement's report.md to PDF via pandoc
#
# Directory convention: ~/aphotic-engagements/<name>/report.md plus an
# evidence/ subdirectory for screenshots and other artifacts. Treated as
# first-class (not an afterthought) per the exploit-reporting sublayer --
# every other exploit-* sublayer produces findings; this is where they go.

_aphotic_engagements_dir="${HOME}/aphotic-engagements"

_aphotic_report_template() {
    local name="$1"
    cat <<EOF
# Engagement Report: ${name}

- **Date:** $(date -Iseconds)
- **Scope:** _systems/networks explicitly authorized for this engagement_
- **Authorization:** _reference to the signed engagement letter / rules of engagement_

## Summary

_One paragraph: what was tested, what was found, overall risk._

## Findings

### Finding 1: _title_

- **Severity:** _informational / low / medium / high / critical_
- **Description:**
- **Evidence:** see \`evidence/\`
- **Reproduction steps:**
- **Remediation:**

## Timeline

| Date | Activity |
|------|----------|
|      |          |

## Appendix

- Tooling used:
- Raw output references:
EOF
}

_aphotic_report_new() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        aphotic_err "usage: aphotic report new <name>"
        return 1
    fi

    local dest="${_aphotic_engagements_dir}/${name}"
    if [[ -e "$dest" ]]; then
        aphotic_err "engagement '${name}' already exists at ${dest}"
        return 1
    fi

    mkdir -p "${dest}/evidence"
    _aphotic_report_template "$name" > "${dest}/report.md"

    aphotic_ok "engagement scaffolded: ${dest}"
    aphotic_log "report template: ${dest}/report.md"
    aphotic_log "put screenshots/artifacts in: ${dest}/evidence/"
}

_aphotic_report_list() {
    if [[ ! -d "$_aphotic_engagements_dir" ]] || [[ -z "$(ls -A "$_aphotic_engagements_dir" 2>/dev/null)" ]]; then
        aphotic_log "no engagements yet — run 'aphotic report new <name>' first"
        return 0
    fi
    printf '  %-28s %s\n' "NAME" "REPORT"
    for dir in "$_aphotic_engagements_dir"/*/; do
        [[ -d "$dir" ]] || continue
        local name has_report
        name="$(basename "$dir")"
        has_report="missing"
        [[ -f "${dir}report.md" ]] && has_report="report.md"
        printf '  %-28s %s\n' "$name" "$has_report"
    done
}

_aphotic_report_render() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        aphotic_err "usage: aphotic report render <name>"
        return 1
    fi

    local dest="${_aphotic_engagements_dir}/${name}"
    local src="${dest}/report.md"
    if [[ ! -f "$src" ]]; then
        aphotic_err "no report.md for engagement '${name}' (see 'aphotic report list')"
        return 1
    fi

    aphotic_require pandoc || {
        aphotic_err "pandoc not found -- install the exploit-reporting layer (pandoc-cli) first"
        return 1
    }

    local out="${dest}/report.pdf"
    pandoc "$src" -o "$out"
    aphotic_ok "rendered: ${out}"
}

aphotic_cmd_report() {
    local sub="${1:-}"
    shift || true
    case "$sub" in
        new)    _aphotic_report_new "$@" ;;
        list)   _aphotic_report_list "$@" ;;
        render) _aphotic_report_render "$@" ;;
        ""|-h|--help)
            cat <<EOF
Usage: aphotic report <new|list|render> [args]

  new <name>      Create a new engagement (${_aphotic_engagements_dir}/<name>/report.md + evidence/)
  list            List existing engagements
  render <name>   Render an engagement's report.md to PDF via pandoc
EOF
            ;;
        *)
            aphotic_err "unknown report subcommand: ${sub}"
            return 1
            ;;
    esac
}
