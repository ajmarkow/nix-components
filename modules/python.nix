{ config, lib, pkgs, ... }:
{
  xdg.configFile."uv/uv.toml".text = ''
    python-preference = "only-managed"
    python-downloads = "automatic"
  '';

  xdg.configFile."direnv/lib/uv.sh".text = ''
    layout_uv() {
      [[ -d .venv ]] || uv venv
      source .venv/bin/activate
    }
  '';
}
