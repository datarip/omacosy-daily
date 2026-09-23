# omacosy — everything the setup needs, installable via `brew bundle`

# The window manager: install.sh --omniwm | --aerospace sets
# HOMEBREW_OMACOSY_WM, and AeroSpace is the default. The other one installs
# on first use: omacosy-wm-switch omniwm | aerospace
wm = ENV.fetch("HOMEBREW_OMACOSY_WM", "aerospace")
if wm == "omniwm"
  cask "omniwm"
else
  tap "nikitabobko/tap"
  cask "aerospace"
end

# Window management + bar + borders
cask "karabiner-elements"  # Caps Lock -> Super
cask "ghostty"             # default terminal + floating TUI host (btop)
cask "raycast"             # Super+Space launcher (the binding assumes it)

# CLI stack
brew "fzf"
brew "eza"
brew "zoxide"
brew "ripgrep"
brew "bat"
brew "lazygit"
brew "btop"
brew "starship"
brew "jq"

# yazi and its preview helpers are opt-in: ./install.sh --yazi, or
# --yazi-full for video and raw-photo previews and the symbols font

cask "font-jetbrains-mono-nerd-font"
