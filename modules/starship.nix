{ ... }:
{
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      scan_timeout = 10000;
      add_newline = true;
      character = {
        success_symbol = "[---➔](bold green)";
        error_symbol = "[ ⍉ ](bold red) ";
      };
      line_break = {
        disabled = true;
      };
      package = {
        disabled = true;
      };
      cmd_duration = {
        min_time = 10000;
        format = "took [$duration]($style) ";
      };
      battery = {
        charging_symbol = "⚡️ ";
        discharging_symbol = "💀 ";
        display = [
          {
            threshold = 20;
            style = "bold red";
          }
        ];
      };
      status = {
        style = "bg:red";
        symbol = "💣 ";
        format = "[\\[$symbol$status\\]]($style) ";
        disabled = false;
      };
    };
  };
}
