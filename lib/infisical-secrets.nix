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
      local auth_dir client_id_file client_secret_file client_id client_secret token login_output
      auth_dir="$HOME/.config/infisical"
      client_id_file="$auth_dir/universal-auth-client-id"
      client_secret_file="$auth_dir/universal-auth-client-secret"

      if [ -s "$client_id_file" ] && [ -s "$client_secret_file" ]; then
        client_id=$(<"$client_id_file")
        client_secret=$(<"$client_secret_file")
        if ! token=$( \
          INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="$client_id" \
          INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="$client_secret" \
          infisical login --method=universal-auth --plain --silent 2>&1
        ); then
          die "Infisical Universal Auth failed. Check the stored machine identity credentials."
        fi
        unset client_id client_secret
        export INFISICAL_TOKEN="$token"
        unset token
        return
      fi

      if [ -n "''${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:-}" ] \
        && [ -n "''${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET:-}" ]; then
        if ! token=$(infisical login --method=universal-auth --plain --silent 2>&1); then
          die "Infisical Universal Auth failed. Check the machine identity environment variables."
        fi
        export INFISICAL_TOKEN="$token"
        unset token
        return
      fi

      if [ -n "''${INFISICAL_TOKEN:-}" ] || [ -n "''${INFISICAL_UNIVERSAL_AUTH_ACCESS_TOKEN:-}" ]; then
        return
      fi

      if [ -s "$HOME/.config/infisical-token" ]; then
        INFISICAL_TOKEN=$(<"$HOME/.config/infisical-token")
        export INFISICAL_TOKEN
        return
      fi

      if ! login_output=$(infisical login --plain --silent 2>&1); then
        die "Infisical login failed. Run .#infisical-login or authenticate with the Infisical CLI."
      fi
      export INFISICAL_TOKEN="$login_output"
      unset login_output
    }

    fetch_path() {
      local path=$1 label=$2 key blob value parsed_file
      parsed_file="$stage/exported-secrets"
      if ! infisical export --silent --format=json \
        --projectId "$project_id" --env "$environment" --path "$path" \
        >"$payload_file" 2>&1; then
        die "Infisical export failed for $label. Check authentication and project access."
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
      done <"$parsed_file"

      : >"$payload_file"
      : >"$parsed_file"
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

    resolve_auth
    fetch_path / "shared path /"
    fetch_path "$host_folder" "host path $host_folder"

    ${renderCalls}

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
      for item in "''${rendered[@]}"; do
        file="''${item%%:*}"
        printf 'would write %s/%s\n' "$secrets_dir" "$file"
      done
      printf '%s files ready; %s skipped; nothing written\n' "''${#rendered[@]}" "''${#skipped[@]}"
      exit 0
    fi

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

    printf '%s files rendered; %s skipped\n' "''${#rendered[@]}" "''${#skipped[@]}"
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
      exec bash -c ${lib.escapeShellArg rebuildCommand}
    '';
  };

  loginPackage = pkgs.writeShellApplication {
    name = "infisical-login-setup";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      auth_dir="$HOME/.config/infisical"
      install -d -m 700 "$auth_dir"
      read -r -p "Universal Auth Client ID: " client_id
      read -r -s -p "Universal Auth Client Secret: " client_secret
      printf '\n'
      [ -n "$client_id" ] || { printf 'error: client ID must not be empty\n' >&2; exit 1; }
      [ -n "$client_secret" ] || { printf 'error: client secret must not be empty\n' >&2; exit 1; }
      printf '%s' "$client_id" | install -m 600 /dev/stdin "$auth_dir/universal-auth-client-id"
      printf '%s' "$client_secret" | install -m 600 /dev/stdin "$auth_dir/universal-auth-client-secret"
      unset client_id client_secret
      printf 'Stored machine identity credentials in %s. Re-run this command to rotate them.\n' "$auth_dir"
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
