{ pkgs, ... }:
{
  programs.nixvim = {
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

      };
      # blankline for indentation guides
      indent-blankline = {
        enable = true;

      };
      # oil for file and folder management
      oil = {
        enable = true;

      };

      # nvim-lint: async linter (vale, shellcheck, sqlfluff)
      lint = {
        enable = true;

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
  };
}
