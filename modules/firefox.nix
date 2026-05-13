{ ... }:
{
  programs.firefox = {
    enable = true;
    profiles.default = {
      name = "Default";
      isDefault = true;
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "ui.systemUsesDarkTheme" = true;
        "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
        "browser.theme.content-theme" = 0;
        "browser.theme.toolbar-theme" = 0;
        "browser.startup.homepage" = "https://www.google.com";
        "browser.startup.page" = 1;
        "browser.urlbar.placeholderName" = "Google";
        "browser.urlbar.quicksuggest.enabled" = false;
        "widget.macos.native-context-menus" = true;
        "widget.macos.respect-system-appearance" = true;
      };
      extraConfig = ''
        user_pref("extensions.autoDisableScopes", 0);
        user_pref("extensions.enabledScopes", 15);
      '';
    };
    policies = {
      Extensions = {
        Install = [
          "https://addons.mozilla.org/firefox/downloads/latest/vimium-ff/latest.xpi"
          "https://addons.mozilla.org/firefox/downloads/latest/raindropio/latest.xpi"
          "https://addons.mozilla.org/firefox/downloads/latest/tabliss/latest.xpi"
        ];
        Locked = [
          "446900e4-71c2-419f-a6a7-df9c091e268b"
          "uBlock0@raymondhill.net"
          "{d7742d87-e61d-4b78-b8a1-b469842139fa}"
          "bb52ecc6-b340-49f6-9342-9740e0f00ec1"
          "087cab65-8b44-4606-a66d-15598ed2bc5a"
        ];
      };
      ExtensionSettings = {
        "446900e4-71c2-419f-a6a7-df9c091e268b".default_area = "navbar";
        "uBlock0@raymondhill.net".default_area = "navbar";
        "{d7742d87-e61d-4b78-b8a1-b469842139fa}".default_area = "navbar";
        "bb52ecc6-b340-49f6-9342-9740e0f00ec1".default_area = "navbar";
        "087cab65-8b44-4606-a66d-15598ed2bc5a".default_area = "navbar";
      };
    };
  };
}
