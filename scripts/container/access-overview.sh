#!/usr/bin/env bash
# Print a Markdown overview of the access the privileged CLIs in the sandbox container
# have right now: which identity each one is logged in as, what that identity may do,
# and which SSH targets accept a connection.
#
# Covers glab, gh, aws, az, oci and every non-wildcard Host in ~/.ssh/config. A tool that
# is not configured is reported as such; the script never fails on one tool.
#
# Nothing here reads a secret value. Token, key and credential values stay unprinted.
#
# Runs inside the container. From the host, `just access-overview` runs it there and
# writes the report to docs/host/access-overview.md (gitignored).
set -uo pipefail

export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True

# Everything printed below goes through prettier, which pads the table columns. stdout is
# closed at the end so prettier sees EOF, then waited for so its output is complete.
exec > >(prettier --parser markdown)
prettier_pid=$!

h1() { printf '\n## %s\n\n' "$1"; }
h2() { printf '\n### %s\n\n' "$1"; }
row() { local cells; printf -v cells ' | %s' "$@"; printf '%s |\n' "${cells# }"; }

printf '# Container access overview\n\n'
printf 'Generated %s on %s as %s.\n' "$(date -Is)" "$(hostname)" "$(id -un)"

# ===== Source control =====
h1 "Source control"

# ----- GitLab (glab) -----
# Identity comes from /user. Scopes come from /personal_access_tokens/self, which a
# fine-grained token can only read when it holds "Personal Access Token: Read".
h2 "GitLab (glab)"
mapfile -t glab_hosts < <(yq -r '.hosts | keys | .[]' ~/.config/glab-cli/config.yml 2>/dev/null)
if [[ ${#glab_hosts[@]} -eq 0 ]]; then
    echo "Not configured (no hosts in ~/.config/glab-cli/config.yml)."
else
    row "Host" "User" "Admin" "Token" "Scopes" "Expires"
    row "---" "---" "---" "---" "---" "---"
    for host in "${glab_hosts[@]}"; do
        user_json="$(glab api --hostname "$host" user 2>/dev/null)" || user_json='{}'
        tok_json="$(glab api --hostname "$host" personal_access_tokens/self 2>/dev/null)" || tok_json='{}'
        row "$host" \
            "$(jq -r '.username // "login failed"' <<<"$user_json")" \
            "$(jq -r '.is_admin // false' <<<"$user_json")" \
            "$(jq -r '.name // "not readable with this token"' <<<"$tok_json")" \
            "$(jq -r '.scopes // [] | join(", ")' <<<"$tok_json")" \
            "$(jq -r '.expires_at // ""' <<<"$tok_json")"
    done
fi

# ----- GitHub (gh) -----
h2 "GitHub (gh)"
if gh auth status >/dev/null 2>&1; then
    # gh prints the scopes itself; the token line is dropped.
    gh auth status 2>&1 | grep -v -i 'token:' | sed 's/^/    /'
else
    echo "Not logged in."
fi

# ===== Cloud platforms =====
h1 "Cloud platforms"

# ----- AWS -----
# One row per profile in ~/.aws/config and ~/.aws/credentials, plus the environment when
# AWS_ACCESS_KEY_ID is set. sts get-caller-identity works with any valid credential.
h2 "AWS (aws)"
mapfile -t aws_profiles < <(aws configure list-profiles 2>/dev/null)
[[ -n ${AWS_ACCESS_KEY_ID:-} ]] && aws_profiles+=("(environment)")
if [[ ${#aws_profiles[@]} -eq 0 ]]; then
    echo "Not configured (no profiles in ~/.aws, no AWS_ACCESS_KEY_ID)."
else
    row "Profile" "Account" "Identity" "Region"
    row "---" "---" "---" "---"
    for profile in "${aws_profiles[@]}"; do
        opts=()
        [[ $profile != "(environment)" ]] && opts=(--profile "$profile")
        ident="$(aws sts get-caller-identity --output json "${opts[@]}" 2>/dev/null)" || ident='{}'
        row "$profile" \
            "$(jq -r '.Account // "credentials rejected"' <<<"$ident")" \
            "$(jq -r '.Arn // ""' <<<"$ident")" \
            "$(aws configure get region "${opts[@]}" 2>/dev/null || true)"
    done
fi

# ----- Azure -----
# One row per subscription the login can see, then the role assignments of the signed-in
# identity per subscription, which is where the permissions live.
h2 "Azure (az)"
subs="$(az account list -o json 2>/dev/null)" || subs='[]'
if [[ "$(jq 'length' <<<"$subs")" -eq 0 ]]; then
    echo "Not logged in (run \`az login\`)."
else
    row "Subscription" "Id" "State" "User" "Default"
    row "---" "---" "---" "---" "---"
    jq -r '.[] | [.name, .id, .state, .user.name, .isDefault] | join("|")' <<<"$subs" \
        | while IFS='|' read -r name id state user def; do row "$name" "$id" "$state" "$user" "$def"; done
    printf '\n#### Role assignments\n\n'
    row "Subscription" "Role" "Scope"
    row "---" "---" "---"
    jq -r '.[] | [.id, .user.name] | join("|")' <<<"$subs" | while IFS='|' read -r id user; do
        az role assignment list --all --assignee "$user" --subscription "$id" -o json 2>/dev/null \
            | jq -r --arg s "$id" '.[] | [$s, .roleDefinitionName, .scope] | join("|")' \
            | while IFS='|' read -r s role scope; do row "$s" "$role" "$scope"; done
    done
fi

# ----- Oracle Cloud -----
# One row per profile in ~/.oci/config. OCI grants permissions to groups through
# policies, so the groups and the tenancy-level policy statements are the overview.
h2 "Oracle Cloud (oci)"
mapfile -t oci_profiles < <(awk -F'[][]' '/^\[/{print $2}' ~/.oci/config 2>/dev/null)
if [[ ${#oci_profiles[@]} -eq 0 ]]; then
    echo "Not configured (no profiles in ~/.oci/config)."
else
    row "Profile" "Tenancy" "Home region" "User" "State" "Groups"
    row "---" "---" "---" "---" "---" "---"
    for profile in "${oci_profiles[@]}"; do
        user_id="$(awk -v p="$profile" -F= '$0=="["p"]"{f=1;next} /^\[/{f=0} f&&$1=="user"{print $2}' ~/.oci/config)"
        tenancy_id="$(awk -v p="$profile" -F= '$0=="["p"]"{f=1;next} /^\[/{f=0} f&&$1=="tenancy"{print $2}' ~/.oci/config)"
        user="$(oci --profile "$profile" iam user get --user-id "$user_id" 2>/dev/null)" || user='{}'
        tenancy="$(oci --profile "$profile" iam tenancy get --tenancy-id "$tenancy_id" 2>/dev/null)" || tenancy='{}'
        groups="$(oci --profile "$profile" iam user list-groups --user-id "$user_id" 2>/dev/null)" || groups='{}'
        row "$profile" \
            "$(jq -r '.data.name // ""' <<<"$tenancy")" \
            "$(jq -r '.data["home-region-key"] // ""' <<<"$tenancy")" \
            "$(jq -r '.data.name // "credentials rejected"' <<<"$user")" \
            "$(jq -r '.data["lifecycle-state"] // ""' <<<"$user")" \
            "$(jq -r '[.data[]?.name] | join(", ")' <<<"$groups")"
    done
    printf '\n#### Tenancy policies\n\n'
    for profile in "${oci_profiles[@]}"; do
        tenancy_id="$(awk -v p="$profile" -F= '$0=="["p"]"{f=1;next} /^\[/{f=0} f&&$1=="tenancy"{print $2}' ~/.oci/config)"
        oci --profile "$profile" iam policy list --compartment-id "$tenancy_id" 2>/dev/null \
            | jq -r --arg p "$profile" '.data[] | "- \($p) / \(.name): " + (.statements | join("; "))'
    done
fi

# ----- SSH -----
# Every non-wildcard Host in ~/.ssh/config and its Include files. BatchMode stops any
# prompt; -n and no command make git servers print their greeting and shells exit at once.
#
# ssh -G reports the container user name both for a host without a User line and for one
# that names it. The first are the git servers, where that name is meaningless, so such a
# host is tried as git first and as the configured user when git is rejected.
probe() {
    local out rc
    out="$(timeout 20 ssh -n -T -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=accept-new "$1@$2" 2>&1 | tr -d '\r')"
    rc=${PIPESTATUS[0]}
    case "$out" in
        *"Welcome to GitLab, @"*) result="git access as ${out#*@}"; result="${result%%!*}" ;;
        *"successfully authenticated"*) result="git access as ${out#Hi }"; result="${result%%!*}" ;;
        *"Permission denied"*) result="reachable, key rejected" ;;
        *"Could not resolve"*) result="unreachable, name does not resolve" ;;
        *"timed out"*|*"Connection refused"*|*"No route to host"*) result="unreachable, ${out##*: }" ;;
        *) [[ $rc -eq 0 ]] && result="shell access" || result="failed (rc=$rc)" ;;
    esac
}
h1 "SSH targets"
row "Host" "Target" "User" "Result"
row "---" "---" "---" "---"
mapfile -t ssh_hosts < <(
    cat ~/.ssh/config ~/.ssh/config.d/* 2>/dev/null \
        | awk '$1=="Host" {for (i=2;i<=NF;i++) if ($i !~ /[*?!]/) print $i}' | sort -u
)
me="$(id -un)"
for host in "${ssh_hosts[@]}"; do
    hostname="$(ssh -G "$host" 2>/dev/null | awk '$1=="hostname"{print $2}')"
    port="$(ssh -G "$host" 2>/dev/null | awk '$1=="port"{print $2}')"
    user="$(ssh -G "$host" 2>/dev/null | awk '$1=="user"{print $2}')"
    if [[ $user == "$me" ]]; then
        probe git "$host"
        if [[ $result == "reachable, key rejected" ]]; then probe "$user" "$host"; else user=git; fi
    else
        probe "$user" "$host"
    fi
    row "$host" "$hostname:$port" "$user" "$result"
done

# A commented-out Host block is one edit away from being live, so it is listed with the
# key it names and whether that key is in the container. Nothing is probed. The block
# ends at the first line that is not a comment or names the next Host.
printf '\n#### Disabled hosts\n\n'
mapfile -t disabled < <(
    cat ~/.ssh/config ~/.ssh/config.d/* 2>/dev/null | awk '
        function flush() { if (h != "") print h "|" hn "|" u "|" k "|" pt; h = "" }
        /^[[:space:]]*#[[:space:]]*Host[[:space:]]/ { flush(); h = $3; hn = ""; u = ""; k = ""; pt = "22"; next }
        !/^[[:space:]]*#/ { flush(); next }
        h != "" && tolower($2) == "hostname" { hn = $3 }
        h != "" && tolower($2) == "user" { u = $3 }
        h != "" && tolower($2) == "identityfile" { k = $3 }
        h != "" && tolower($2) == "port" { pt = $3 }
        END { flush() }'
)
if [[ ${#disabled[@]} -eq 0 ]]; then
    echo "None."
else
    echo "These blocks are commented out. Uncommenting one enables the access it describes."
    echo
    row "Host" "Target" "User" "Key" "Key in container"
    row "---" "---" "---" "---" "---"
    for line in "${disabled[@]}"; do
        IFS='|' read -r host hostname user key port <<<"$line"
        present="no"; [[ -n $key && -f ${key/#\~/$HOME} ]] && present="yes"
        row "$host" "$hostname:$port" "$user" "$key" "$present"
    done
fi

exec >&-
wait "$prettier_pid"
