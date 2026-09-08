{
  config,
  lib,
  pkgs,
  catppuccinObsidianSource,
  ...
}:

let
  cfg = config.nix-components.obsidianGui;
  obsidianDir = "${cfg.vaultPath}/.obsidian";
  secretsFile =
    if pkgs.stdenv.isDarwin then
      "/etc/nix-darwin/secrets/agent-dropbox.env"
    else
      "/etc/nixos/secrets/agent-dropbox.env";
  registryFile =
    if pkgs.stdenv.isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/obsidian/obsidian.json"
    else
      "${config.home.homeDirectory}/.config/obsidian/obsidian.json";
  vaultId = builtins.substring 0 16 (builtins.hashString "sha256" cfg.vaultPath);

  fetchObsidianPlugin =
    {
      id,
      repo,
      version,
      mainJsHash,
      manifestHash,
      stylesHash,
    }:
    pkgs.runCommand "obsidian-plugin-${id}-${version}" { } ''
      mkdir -p "$out"
      cp ${
        pkgs.fetchurl {
          url = "https://github.com/${repo}/releases/download/${version}/main.js";
          hash = mainJsHash;
        }
      } "$out/main.js"
      cp ${
        pkgs.fetchurl {
          url = "https://github.com/${repo}/releases/download/${version}/manifest.json";
          hash = manifestHash;
        }
      } "$out/manifest.json"
      cp ${
        pkgs.fetchurl {
          url = "https://github.com/${repo}/releases/download/${version}/styles.css";
          hash = stylesHash;
        }
      } "$out/styles.css"
    '';

  plugins = {
    omnisearch = fetchObsidianPlugin {
      id = "omnisearch";
      repo = "scambier/obsidian-omnisearch";
      version = "1.31.0";
      mainJsHash = "sha256-nyRWcF0IQPPMz2Ko6Zpv2viQGTmTbkTU3Sf8ay1SLzE=";
      manifestHash = "sha256-JrH/wlCx2QYF9gwTL3g+MUjdOZ5br1hiBAZx2GKUvIU=";
      stylesHash = "sha256-xqVrGhj/hn8S67s6E5BgoklwQoHhtEkAP/SHlpYhouY=";
    };
    remotely-save = fetchObsidianPlugin {
      id = "remotely-save";
      repo = "remotely-save/remotely-save";
      version = "0.5.25";
      mainJsHash = "sha256-s6+9J/FRiLl4RhjJWGB4abqkNNwKvPByd0+ZNiwR+gQ=";
      manifestHash = "sha256-cdnAthYAPzppaIDnqogpblsxVVdX6TOhLSkAuWxMqpA=";
      stylesHash = "sha256-h1hOfVOMpYxSevuyYlsJ6igryue/eEt8zjPKkung37M=";
    };
    obsidian-icon-folder = fetchObsidianPlugin {
      id = "obsidian-icon-folder";
      repo = "FlorianWoelki/obsidian-icon-folder";
      version = "2.14.7";
      mainJsHash = "sha256-raCwCXBlVsmBAflTpqh/XK/TABCF31k9O+KO7uohggE=";
      manifestHash = "sha256-9SShjWnpkKJEFzo1lWgcOaILy8ncGLWa9R5FZg/vXKI=";
      stylesHash = "sha256-Vv/rg0n0r5fauKFPytywAZ07N7EW16NKoh6VjphFWok=";
    };
    obsidian-style-settings = fetchObsidianPlugin {
      id = "obsidian-style-settings";
      repo = "mgmeyers/obsidian-style-settings";
      version = "1.0.9";
      mainJsHash = "sha256-GCirqs2rTFV4twWmJcWFswUS+O+tTHz8WhjnDMNVdGg=";
      manifestHash = "sha256-nP/cIM8qoTVIIOAFC2lLD5tXZEbj1dRKNq6LAYflv7g=";
      stylesHash = "sha256-7nk30r5QZTqJzLMK5fBXKyNQfVt/EyjQBScaNjB1v9g=";
    };
  };

  corePlugins = pkgs.writeText "obsidian-core-plugins.json" (
    builtins.toJSON [
      "backlink"
      "bookmarks"
      "command-palette"
      "file-explorer"
      "graph"
      "note-composer"
      "outgoing-link"
      "outline"
      "switcher"
      "global-search"
      "slash-command"
      "sync"
    ]
  );
  communityPlugins = pkgs.writeText "obsidian-community-plugins.json" (
    builtins.toJSON (builtins.attrNames plugins)
  );
  appearance = pkgs.writeText "obsidian-appearance.json" (
    builtins.toJSON {
      cssTheme = "Catppuccin";
      enabledCssSnippets = [ ];
    }
  );
  styleSettings = pkgs.writeText "obsidian-style-settings.json" (
    builtins.toJSON {
      "catppuccin-theme-settings@@catppuccin-theme-dark" = "ctp-frappe";
    }
  );
  remotelySaveTemplate = pkgs.writeText "remotely-save-settings.json" (
    builtins.toJSON {
      serviceType = "s3";
      password = "";
      vaultRandomID = "nix-managed-agentic-vault";
      autoRunEveryMilliseconds = 120000;
      syncOnSaveAfterMilliseconds = 2000;
      obfuscateSettingFile = false;
      s3 = {
        s3Endpoint = "https://s3.amazonaws.com";
        s3Region = "us-east-1";
        s3AccessKeyID = "";
        s3SecretAccessKey = "";
        s3BucketName = "aj-agent-dropbox";
        remotePrefix = "obsidian-vault/";
        forcePathStyle = false;
      };
    }
  );

  pluginCopies = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (id: source: ''
      run mkdir -p "${obsidianDir}/plugins/${id}"
      run install -m644 "${source}/main.js" "${obsidianDir}/plugins/${id}/main.js"
      run install -m644 "${source}/manifest.json" "${obsidianDir}/plugins/${id}/manifest.json"
      run install -m644 "${source}/styles.css" "${obsidianDir}/plugins/${id}/styles.css"
    '') plugins
  );
in
{
  options.nix-components.obsidianGui.vaultPath = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/Vaults/Agentic";
    description = "Path to the S3-synced Agentic Obsidian vault.";
  };

  config.home = {
    packages = [ pkgs.obsidian ];

    activation = {
      obsidianGuiFiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "${obsidianDir}/themes/Catppuccin"
        run install -m644 "${corePlugins}" "${obsidianDir}/core-plugins.json"
        run install -m644 "${communityPlugins}" "${obsidianDir}/community-plugins.json"
        run install -m644 "${appearance}" "${obsidianDir}/appearance.json"
        ${pluginCopies}
        run install -m644 "${styleSettings}" "${obsidianDir}/plugins/obsidian-style-settings/data.json"
        run install -m644 "${catppuccinObsidianSource}/manifest.json" "${obsidianDir}/themes/Catppuccin/manifest.json"
        run install -m644 "${catppuccinObsidianSource}/theme.css" "${obsidianDir}/themes/Catppuccin/theme.css"
      '';

      obsidianRemotelySaveSettings = lib.hm.dag.entryAfter [ "obsidianGuiFiles" ] ''
        if [ -r "${secretsFile}" ]; then
          set -a
          . "${secretsFile}"
          set +a
          run ${pkgs.jq}/bin/jq \
            --arg accessKeyId "$AGENT_DROPBOX_ACCESS_KEY_ID" \
            --arg secretAccessKey "$AGENT_DROPBOX_SECRET_ACCESS_KEY" \
            '.s3.s3AccessKeyID = $accessKeyId | .s3.s3SecretAccessKey = $secretAccessKey' \
            "${remotelySaveTemplate}" > "${obsidianDir}/plugins/remotely-save/data.json"
          run chmod 600 "${obsidianDir}/plugins/remotely-save/data.json"
        fi
      '';

      obsidianVaultRegistry = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        registry_file="${registryFile}"
        run mkdir -p "$(dirname "$registry_file")"
        if [ -s "$registry_file" ]; then
          registry_source="$registry_file"
        else
          registry_source="${pkgs.writeText "empty-obsidian-registry.json" "{}"}"
        fi
        tmp_file="$(mktemp)"
        ${pkgs.jq}/bin/jq \
          --arg id "${vaultId}" \
          --arg path "${cfg.vaultPath}" \
          '.vaults //= {} | if any(.vaults[]?; .path == $path) then . else .vaults[$id] = {path: $path, ts: 0, open: false} end' \
          "$registry_source" > "$tmp_file"
        run install -m644 "$tmp_file" "$registry_file"
        rm -f "$tmp_file"
      '';
    };
  };
}
