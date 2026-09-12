{ pkgs, ... }:
{
  programs.nixvim = {
    # Pulse - single command palette with prefix-based pickers
    # https://github.com/willyelm/pulse.nvim
    extraPlugins = [
      (pkgs.vimUtils.buildVimPlugin {
        name = "pulse.nvim";
        src = pkgs.fetchFromGitHub {
          owner = "willyelm";
          repo = "pulse.nvim";
          rev = "v0.1.12";
          hash = "sha256-GaN28qk9NGJiskVCEGnuQnke17bD1Sr2O+XgDxfNDWA=";
        };
      })
      (pkgs.vimUtils.buildVimPlugin {
        name = "claudecode.nvim";
        src = pkgs.fetchFromGitHub {
          owner = "coder";
          repo = "claudecode.nvim";
          rev = "432121f0f5b9bda041030d1e9e83b7ba3a93dd8f";
          hash = "sha256-r8hAUpSsr8zNm+av8Mu5oILaTfEsXEnJmkzRmvi9pF8=";
        };
      })
    ];

    extraConfigLua = ''
      require("pulse").setup({
        cmdline = false,
        initial_mode = "insert",
        position = "top",
        width = 0.50,
        height = 0.75,
        border = "rounded",
      })
      require("claudecode").setup({})
      require("which-key").setup({})
      vim.api.nvim_create_user_command('Format', function()
        vim.lsp.buf.format()
      end, {})
      local npairs = require'nvim-autopairs'
      local Rule = require("nvim-autopairs.rule")

      -- Auto-pair "= " with ";" in Nix files, but not on comment lines
      npairs.add_rule(
        Rule("= ", ";", "nix")
          :with_pair(function(info)
            local line = info.line:sub(1, info.col - 1)
            if line:match('^%s*#') then
              return false
            end
            local rest_of_line = info.line:sub(info.col)
            return rest_of_line:match('^%s*$') ~= nil
          end)
          :set_end_pair_length(1)
      )
    '';
  };
}
