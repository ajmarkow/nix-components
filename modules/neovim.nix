{ pkgs, ... }:
{
  programs.nixvim = {
    enable = true;
    vimAlias = true;

    # Global settings
    globals = {
      mapleader = " "; # Set space as leader key
      maplocalleader = " ";
      # Disable netrw so oil can take over directory buffers (e.g. when using `nvim .`)
      loaded_netrw = 1;
      loaded_netrwPlugin = 1;
    };

    # General options
    opts = {
      background = "dark";
      autoindent = true; # Auto indent
      smartindent = true;
      number = true; # Show line numbers
      relativenumber = false; # Show relative line numbers
      tabstop = 2; # Tab width
      shiftwidth = 2; # Indent width
      expandtab = true; # Use spaces instead of tabs
      wrap = false; # Don't wrap lines
      termguicolors = true; # Enable 24-bit RGB colors
      clipboard = "unnamedplus"; # Use system clipboard
      autochdir = true; # Auto change directory to the current file's directory
      signcolumn = "yes";
      cursorline = true;
      guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor,sm:block-blinkwait175-blinkoff150-blinkon175";
      guifont = "Fira Code";
      syntax = "on";
    };

    # Colorscheme
    colorschemes.catppuccin = {
      enable = true;
      settings = {
        flavour = "frappe";
        transparent_background = false;
        term_colors = true;
        integrations = {
          lualine = true;
          blink_cmp = true;
          indent_blankline = true;
          which_key = true;
          neotree = true;
          lsp_trouble = true;
        };
      };
    };

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

    # Plugins
    plugins = {
      # wakatime
      wakatime.enable = true;

      # LSP Configuration
      lsp = {
        enable = true;
        servers = {
          # Nix LSP
          nil_ls = {
            enable = true;
            settings = {
              formatting.command = [ "${pkgs.nixfmt}/bin/nixfmt" ];
              completion = true;
              hover = true;
              validate = true;
            };
          };
          # YAML LSP
          yamlls = {
            enable = true;
            settings = {
              schemas = {
                "https://raw.githubusercontent.com/espanso/espanso/dev/schemas/match.schema.json" = "base.yml";
              };
              completion = true;
              hover = true;
              validate = true;
            };
          };
          # TypeScript/JavaScript LSP
          ts_ls.enable = true;
          # Python LSP
          pylsp.enable = true;
          # Lua LSP
          lua_ls.enable = true;
          # Go LSP
          gopls.enable = true;
          # Ruby LSP
          ruby_lsp.enable = true;
        };
      };
      nvim-autopairs = {
        enable = true;
        lazyLoad.enable = true;
      };
      # blankline for indentation guides
      indent-blankline = {
        enable = true;
        lazyLoad.enable = true;
      };
      # oil for file and folder management
      oil = {
        enable = true;
        lazyLoad.enable = true;
      };

      # nvim-lint: async linter (vale, shellcheck, sqlfluff)
      lint = {
        enable = true;
        lazyLoad.enable = true;
        lintersByFt = {
          markdown = [ "markdownlint" ];
          sh = [ "shellcheck" ];
          bash = [ "shellcheck" ];
          sql = [ "sqlfluff" ];
        };
      };

      # File explorer (neo-tree: https://github.com/nvim-neo-tree/neo-tree.nvim)
      neo-tree = {
        enable = true;
        lazyLoad.enable = true;
        settings = {
          window = {
            position = "left";
          };
          filesystem = {
            hijack_netrw_behavior = "disabled";
            follow_current_file = {
              enabled = true;
              leave_dirs_open = true; # Keep auto-expanded dirs open when following file
            };
          };
          log_to_file = false;
        };
      };

      # Trouble for better error rendering
      trouble = {
        enable = true;
        lazyLoad.enable = true;
        settings = {
          warn_no_results = false; # Don't show warning when no diagnostics
        };
      };

      # Edgy for window layouts (https://github.com/folke/edgy.nvim)
      edgy = {
        enable = true;
        settings = {
          left = [
            {
              title = "Files";
              ft = "neo-tree";
              filter = ''
                function(buf)
                  return vim.b[buf].neo_tree_source == "filesystem"
                end
              '';
            }
            {
              title = "Issues";
              ft = "Trouble";
              pinned = true;
              open = "Trouble diagnostics toggle filter.buf=0";
            }
          ];
        };
      };


      # Which-key - show keybindings in popup
      which-key.enable = true;

      # Icons (required by telescope and neo-tree)
      web-devicons.enable = true;

      # Git integration
      gitsigns = {
        enable = true;
        lazyLoad.enable = true;
      };

      # Status line
      lualine = {
        enable = true;
        settings = {
          options = {
            globalstatus = true;
          };
        };
      };

      # snacks.nvim - required by claudecode.nvim for terminal support
      snacks.enable = true;

      # Auto-completion (blink-cmp - performant completion backend)
      cmp.enable = false;
      "blink-cmp" = {
        enable = true;
        lazyLoad.enable = true;
        setupLspCapabilities = true;
        settings = {
          sources = {
            default = [
              "lsp"
              "path"
            ];
          };
          keymap = {
            preset = "default";
          };
        };
      };
    };

    # Open oil when starting with a directory (e.g. `nvim .`)
    autoCmd = [
      {
        event = "VimEnter";
        pattern = "*";
        callback = {
          __raw = ''
            function()
              local path = vim.fn.argv(0)
              if path ~= "" and vim.fn.isdirectory(path) == 1 then
                require("oil").open(path)
              end
            end
          '';
        };
        once = true;
      }
    ];

    # Key mappings
    keymaps = [
      # Which-key - show keybindings
      {
        key = "?";
        action = "<cmd>lua require('which-key').show()<cr>";
        options.desc = "Show keybindings (which-key)";
      }
      # Pulse command palette
      {
        key = "<leader>pc";
        action = "<cmd>Pulse<cr>";
        options.desc = "Pulse command palette";
      }
      # Pulse search
      {
        key = "<leader>ps";
        action = "<cmd>Pulse fuzzy_search<cr>";
        options.desc = "Pulse fuzzy search";
      }
      # File explorer
      {
        key = "<leader>e";
        action = ":Neotree toggle<CR>";
        options.desc = "Toggle file explorer";
      }
      # Save file
      {
        key = "<leader>w";
        action = ":w<CR>";
        options.desc = "Save file";
      }
      # Quit
      {
        key = "<leader>q";
        action = ":q<CR>";
        options.desc = "Quit";
      }
      # Format
      {
        key = "<leader>f";
        action = "<cmd>Format<cr>";
        options.desc = "Format file";
      }
      # Claude Code
      {
        key = "<leader>ac";
        action = "<cmd>ClaudeCode<cr>";
        options.desc = "Toggle Claude Code";
      }
      {
        key = "<leader>af";
        action = "<cmd>ClaudeCodeFocus<cr>";
        options.desc = "Focus Claude Code";
      }
      {
        key = "<leader>ar";
        action = "<cmd>ClaudeCode --resume<cr>";
        options.desc = "Resume Claude session";
      }
      {
        key = "<leader>as";
        action = "<cmd>ClaudeCodeSend<cr>";
        mode = "v";
        options.desc = "Send selection to Claude";
      }
      {
        key = "<leader>ab";
        action = "<cmd>ClaudeCodeAdd %<cr>";
        options.desc = "Add current buffer to Claude";
      }
      {
        key = "<leader>aa";
        action = "<cmd>ClaudeCodeDiffAccept<cr>";
        options.desc = "Accept Claude diff";
      }
      {
        key = "<leader>ad";
        action = "<cmd>ClaudeCodeDiffDeny<cr>";
        options.desc = "Deny Claude diff";
      }
    ];
  };
}
