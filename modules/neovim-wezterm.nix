{ ... }:
{
  programs.nixvim = {
    # Wezterm Integration - seamless pane navigation between Neovim and Wezterm
    # Requires matching keybindings in Wezterm (smart_splits.apply_to_config)
    # Do not lazy-load: plugin sets IS_NVIM for Wezterm to detect Neovim panes
    plugins.smart-splits = {
      enable = true;
      lazyLoad.enable = false;
      settings = {
        multiplexer_integration = "wezterm";
        at_edge = "wrap";
      };
    };

    keymaps = [
      # Smart-splits: move between Neovim/Wezterm panes (Hyper = ⌘⌃⌥⇧ + h/j/k/l; matches Wezterm SUPER|SHIFT|CTRL|OPT)
      {
        key = "<C-S-A-D-h>";
        action = "<cmd>lua require('smart-splits').move_cursor_left()<cr>";
        mode = "n";
        options.desc = "Smart-splits: move left";
      }
      {
        key = "<C-S-A-D-j>";
        action = "<cmd>lua require('smart-splits').move_cursor_down()<cr>";
        mode = "n";
        options.desc = "Smart-splits: move down";
      }
      {
        key = "<C-S-A-D-k>";
        action = "<cmd>lua require('smart-splits').move_cursor_up()<cr>";
        mode = "n";
        options.desc = "Smart-splits: move up";
      }
      {
        key = "<C-S-A-D-l>";
        action = "<cmd>lua require('smart-splits').move_cursor_right()<cr>";
        mode = "n";
        options.desc = "Smart-splits: move right";
      }
      {
        key = "<C-\\>";
        action = "<cmd>lua require('smart-splits').move_cursor_previous()<cr>";
        mode = "n";
        options.desc = "Smart-splits: move to previous pane";
      }
      # Smart-splits: resize panes (Alt+h/j/k/l)
      {
        key = "<A-h>";
        action = "<cmd>lua require('smart-splits').resize_left()<cr>";
        mode = "n";
        options.desc = "Smart-splits: resize left";
      }
      {
        key = "<A-j>";
        action = "<cmd>lua require('smart-splits').resize_down()<cr>";
        mode = "n";
        options.desc = "Smart-splits: resize down";
      }
      {
        key = "<A-k>";
        action = "<cmd>lua require('smart-splits').resize_up()<cr>";
        mode = "n";
        options.desc = "Smart-splits: resize up";
      }
      {
        key = "<A-l>";
        action = "<cmd>lua require('smart-splits').resize_right()<cr>";
        mode = "n";
        options.desc = "Smart-splits: resize right";
      }
    ];
  };
}
