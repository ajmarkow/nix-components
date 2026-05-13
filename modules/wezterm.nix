{ ... }:
{
  # Set Wezterm Config
  programs.wezterm = {
    enable = true;
    extraConfig = ''
      -- Pull in the wezterm API
      local wezterm = require('wezterm')
      local smart_splits = wezterm.plugin.require('https://github.com/mrjones2014/smart-splits.nvim')
      local config = wezterm.config_builder()

      -- Set custom keybindings (merged with smart-splits keys below)
      local mykeys = {
          {key = 'k', mods = 'SUPER', action = wezterm.action.ActivateCommandPalette},
          {key = 'x', mods = 'SUPER|SHIFT|CTRL|OPT', action = wezterm.action.CloseCurrentPane { confirm = true }}
      }
      -- Make sure confirm is always required for pane close
      config.skip_close_confirmation_for_processes_named = {}

      -- Set fontsize and other formatting
      local myfontsize = 14
      local ajrows = 8
      local preferred_font = wezterm.font_with_fallback({'Fira Code'})
      config.color_scheme = 'Catppuccin Frappe'
      config.font = preferred_font
      config.font_size = myfontsize

      -- Command palette settings
      config.command_palette_rows = ajrows
      config.command_palette_font = preferred_font
      config.command_palette_font_size = 16
      config.command_palette_bg_color = "#181818"

      -- Enable kitty keyboard protocol so WezTerm can disambiguate ESC from Alt+key sequences.
      -- Without this, vi mode escape detection is unreliable.
      config.enable_kitty_keyboard = true

      -- Tab bar settings
      config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
      config.window_frame = {font = preferred_font, font_size = 16}
      config.hide_tab_bar_if_only_one_tab = false
      config.show_new_tab_button_in_tab_bar = false
      config.show_close_tab_button_in_tabs = false

      -- Apply smart-splits: Hyper (⌘⌃⌥⇧)+h/j/k/l to move, Alt+h/j/k/l to resize (Hyper matches Hyperkey / SUPER|SHIFT|CTRL|OPT)
      smart_splits.apply_to_config(config, {
        modifiers = {
          move = {
            wezterm = 'SUPER|SHIFT|CTRL|OPT',
            neovim = 'SUPER|SHIFT|CTRL|OPT',
          },
        },
      })

      -- Merge our custom keys with smart-splits keys
      for _, key in ipairs(mykeys) do table.insert(config.keys, key) end

      return config
    '';
  };
}
