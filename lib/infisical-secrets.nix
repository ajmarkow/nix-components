{
  pkgs,
  projectId,
  hostFolder,
  secretsDir,
  manifest,
  environment ? "prod",
  rebuildCommand ? null,
}:
let
  inherit (pkgs) lib;

  validEntry =
    entry:
    entry ? file
    && entry ? keys
    && entry ? template
    && builtins.isString entry.file
    && builtins.baseNameOf entry.file == entry.file
    && entry.file != "."
    && entry.file != ".."
    && builtins.match "[a-zA-Z0-9._-]+" entry.file != null
    && builtins.isList entry.keys
    && entry.keys != [ ]
    && builtins.all (
      key: builtins.isString key && builtins.match "[a-zA-Z_][a-zA-Z0-9_]*" key != null
    ) entry.keys
    && builtins.isString entry.template
    && (!(entry ? owner) || entry.owner == null || builtins.isString entry.owner);

  checkedManifest =
    if projectId == "" then
      throw "mkSecretsApp: projectId must not be empty"
    else if !(lib.hasPrefix "/" hostFolder) || hostFolder == "/" then
      throw "mkSecretsApp: hostFolder must be an absolute, host-specific path"
    else if !(lib.hasPrefix "/" secretsDir) then
      throw "mkSecretsApp: secretsDir must be absolute"
    else if manifest == [ ] then
      throw "mkSecretsApp: manifest must not be empty"
    else if !(builtins.all validEntry manifest) then
      throw "mkSecretsApp: each manifest entry needs a safe file name, non-empty keys, and a template"
    else
      manifest;

  manifestNames = map (entry: entry.file) checkedManifest;
  duplicateNames = lib.filter (
    name: builtins.length (lib.filter (candidate: candidate == name) manifestNames) > 1
  ) (lib.unique manifestNames);

  finalManifest =
    if duplicateNames != [ ] then
      throw "mkSecretsApp: duplicate manifest files: ${lib.concatStringsSep ", " duplicateNames}"
    else
      checkedManifest;

  renderCall =
    entry:
    let
      templateFile = pkgs.writeText "infisical-secret-template-${entry.file}" entry.template;
      owner = if (entry.owner or null) == null then "" else entry.owner;
    in
    ''
      render_file ${
        lib.escapeShellArgs [
          entry.file
          owner
          (lib.concatStringsSep " " entry.keys)
          templateFile
        ]
      }
    '';

  renderCalls = lib.concatMapStrings renderCall finalManifest;
  needsTraversal = builtins.any (entry: (entry.owner or null) != "root") finalManifest;

  commonScript = ''
    set -euo pipefail

    project_id=${lib.escapeShellArg projectId}
    environment=${lib.escapeShellArg environment}
    host_folder=${lib.escapeShellArg hostFolder}
    secrets_dir=${lib.escapeShellArg secretsDir}
    dry_run=false
    only=""

    die() {
      printf 'error: %s\n' "$*" >&2
      exit 1
    }

    warn() {
      printf 'warn: %s\n' "$*" >&2
    }

    step() {
      printf '==> %s\n' "$*"
    }

    note() {
      printf '    %s\n' "$*"
    }

    usage() {
      printf '%s\n' \
        'Usage: nix run .#secrets -- [--dry-run] [--only file-a,file-b]' \
        "" \
        '  --dry-run       Validate available keys and list files. Write nothing.' \
        '  --only <files>  Render only these comma-separated manifest file names.' \
        '  -h, --help      Show this text.' \
        "" \
        'Secret values are never printed.'
    }

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --dry-run)
          dry_run=true
          shift
          ;;
        --only)
          [ -n "''${2:-}" ] || die "--only needs a value"
          only=$2
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage >&2
          die "unknown argument: $1"
          ;;
      esac
    done

    stage=$(mktemp -d)
    payload_file=$(mktemp)
    trap 'rm -rf "$stage" "$payload_file"' EXIT
    chmod 700 "$stage"

    resolve_auth() {
      local auth_dir client_id_file client_secret_file client_id client_secret token
      auth_dir="$HOME/.config/infisical"
      client_id_file="$auth_dir/universal-auth-client-id"
      client_secret_file="$auth_dir/universal-auth-client-secret"

      if [ -s "$client_id_file" ] && [ -s "$client_secret_file" ]; then
        note "Using stored Universal Auth credentials"
        client_id=$(<"$client_id_file")
        client_secret=$(<"$client_secret_file")
        if ! token=$( \
          INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="$client_id" \
          INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="$client_secret" \
          timeout 30s infisical login --method=universal-auth --plain --silent 2>&1
        ); then
          die "Infisical Universal Auth failed or timed out after 30 seconds. Check the stored machine identity credentials and network access."
        fi
        unset client_id client_secret
        [ -n "$token" ] || die "Infisical Universal Auth returned an empty access token."
        export INFISICAL_TOKEN="$token"
        unset token
        note "Authentication succeeded"
        return
      fi

      if [ -n "''${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:-}" ] \
        && [ -n "''${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET:-}" ]; then
        note "Using Universal Auth environment variables"
        if ! token=$(timeout 30s infisical login --method=universal-auth --plain --silent 2>&1); then
          die "Infisical Universal Auth failed or timed out after 30 seconds. Check the machine identity environment variables and network access."
        fi
        [ -n "$token" ] || die "Infisical Universal Auth returned an empty access token."
        export INFISICAL_TOKEN="$token"
        unset token
        note "Authentication succeeded"
        return
      fi

      if [ -n "''${INFISICAL_TOKEN:-}" ] || [ -n "''${INFISICAL_UNIVERSAL_AUTH_ACCESS_TOKEN:-}" ]; then
        note "Using an existing Infisical access token"
        return
      fi

      if [ -s "$HOME/.config/infisical-token" ]; then
        note "Using the legacy Infisical token file"
        INFISICAL_TOKEN=$(<"$HOME/.config/infisical-token")
        export INFISICAL_TOKEN
        return
      fi

      die "No Infisical credentials found. Run 'nix run .#infisical-login' as your normal user."
    }

    fetch_path() {
      local path=$1 label=$2 key blob value parsed_file count=0
      parsed_file="$stage/exported-secrets"
      note "Fetching $label"
      if ! timeout 30s infisical export --silent --format=json \
        --projectId "$project_id" --env "$environment" --path "$path" \
        >"$payload_file" 2>&1; then
        die "Infisical export failed or timed out after 30 seconds for $label. Check authentication, network access, and project permissions."
      fi

      if ! jq -r 'if type == "array" then .[] else empty end | "\(.key) \(.value | @base64)"' \
        "$payload_file" >"$parsed_file" 2>/dev/null; then
        die "Infisical returned an invalid response for $label."
      fi

      while IFS=' ' read -r key blob; do
        [ -n "$key" ] || continue
        if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
          warn "$label contains a key that is not a shell variable; skipped its name"
          continue
        fi
        value=$(printf '%s' "$blob" | base64 --decode)
        printf -v "$key" '%s' "$value"
        # The validated Infisical key is the variable name to export.
        # shellcheck disable=SC2163
        export "$key"
        unset value
        ((count += 1))
      done <"$parsed_file"

      : >"$payload_file"
      : >"$parsed_file"
      note "$label: $count keys available"
    }

    selected() {
      local file=$1
      [ -z "$only" ] || [[ ",$only," == *",$file,"* ]]
    }

    rendered=()
    skipped=()

    render_file() {
      local file=$1 owner=$2 key_list=$3 template_file=$4 key substitution_vars="" missing=false
      local -a keys
      selected "$file" || return
      read -r -a keys <<<"$key_list"

      for key in "''${keys[@]}"; do
        if [ -z "''${!key:-}" ]; then
          warn "$file: missing Infisical key $key; leaving the host copy unchanged"
          missing=true
        fi
        substitution_vars+="\$$key "
      done
      if $missing; then
        skipped+=("$file")
        return
      fi

      envsubst "$substitution_vars" <"$template_file" >"$stage/$file"
      chmod 600 "$stage/$file"
      rendered+=("$file:$owner")
    }

    step "Authenticate with Infisical"
    resolve_auth
    step "Fetch secrets"
    fetch_path / "shared path /"
    fetch_path "$host_folder" "host path $host_folder"

    step "Render secret files"
    ${renderCalls}
    note "''${#rendered[@]} files ready; ''${#skipped[@]} skipped"

    if [ -n "$only" ]; then
      IFS=',' read -r -a requested <<<"$only"
      for requested_file in "''${requested[@]}"; do
        case "$requested_file" in
          ${lib.concatStringsSep "|" manifestNames}) ;;
          *) die "--only names a file outside the manifest: $requested_file" ;;
        esac
      done
    fi

    if $dry_run; then
      step "Dry run"
      for item in "''${rendered[@]}"; do
        file="''${item%%:*}"
        printf 'would write %s/%s\n' "$secrets_dir" "$file"
      done
      note "Nothing was written"
      exit 0
    fi

    step "Install secret files"
    caller_uid="''${SUDO_UID:-$(id -u)}"
    caller_gid="''${SUDO_GID:-$(id -g)}"
    dir_mode=${if needsTraversal then "751" else "700"}
    sudo install -d -m "$dir_mode" -o 0 -g "$caller_gid" "$secrets_dir"

    for item in "''${rendered[@]}"; do
      file="''${item%%:*}"
      owner="''${item#*:}"
      if [ -z "$owner" ]; then
        uid=$caller_uid
        gid=$caller_gid
      else
        if ! uid=$(id -u "$owner" 2>/dev/null) || ! gid=$(id -g "$owner" 2>/dev/null); then
          warn "$file: owner $owner does not exist; leaving the host copy unchanged"
          continue
        fi
      fi
      sudo install -m 600 -o "$uid" -g "$gid" "$stage/$file" "$secrets_dir/$file"
      printf 'wrote %s\n' "$file"
    done

    note "''${#rendered[@]} files rendered; ''${#skipped[@]} skipped"
  '';

  runtimeInputs = [
    pkgs.coreutils
    pkgs.gettext
    pkgs.infisical
    pkgs.jq
  ];

  secretsPackage = pkgs.writeShellApplication {
    name = "secrets";
    inherit runtimeInputs;
    text = commonScript;
  };

  rebuildPackage = pkgs.writeShellApplication {
    name = "rebuild";
    runtimeInputs = runtimeInputs ++ [ pkgs.bash ];
    text = ''
      ${commonScript}
      step "Rebuild host configuration"
      exec bash -c ${lib.escapeShellArg rebuildCommand}
    '';
  };

  loginPackage = pkgs.writeShellApplication {
    name = "infisical-login-setup";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail

      auth_dir="$HOME/.config/infisical"
      install -d -m 700 "$auth_dir"
      umask 077

      printf '==> Store Infisical Universal Auth credentials\n'
      read -r -p "Universal Auth Client ID: " client_id
      read -r -s -p "Universal Auth Client Secret: " client_secret
      printf '\n'
      [ -n "$client_id" ] || { printf 'error: client ID must not be empty\n' >&2; exit 1; }
      [ -n "$client_secret" ] || { printf 'error: client secret must not be empty\n' >&2; exit 1; }

      client_id_tmp=$(mktemp "$auth_dir/.universal-auth-client-id.XXXXXX")
      client_secret_tmp=$(mktemp "$auth_dir/.universal-auth-client-secret.XXXXXX")
      trap 'rm -f "$client_id_tmp" "$client_secret_tmp"' EXIT

      printf '%s' "$client_id" >"$client_id_tmp"
      printf '%s' "$client_secret" >"$client_secret_tmp"
      chmod 600 "$client_id_tmp" "$client_secret_tmp"
      mv -f "$client_id_tmp" "$auth_dir/universal-auth-client-id"
      mv -f "$client_secret_tmp" "$auth_dir/universal-auth-client-secret"
      trap - EXIT
      unset client_id client_secret
      printf '    Credentials stored in %s with mode 600.\n' "$auth_dir"
      printf '    Run this command again to rotate them.\n'
    '';
  };

  mkApp = package: {
    type = "app";
    program = lib.getExe package;
  };
in
{
  secrets = mkApp secretsPackage;
  infisical-login = mkApp loginPackage;
}
// lib.optionalAttrs (rebuildCommand != null) {
  rebuild = mkApp rebuildPackage;
}
