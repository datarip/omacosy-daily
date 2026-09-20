# omacosy — everything the setup needs, installable via `brew bundle`

tap "nikitabobko/tap"        # aerospace

# Window management + bar + borders
# (OmniWM is NOT here: `omacosy-wm-switch omniwm` installs it on first use)
cask "aerospace"
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

# yazi, a terminal file manager, and what it previews with. No keybinding
# opens it yet: run `yazi` in Ghostty.
# fd and ripgrep are its search; the rest decode a file type each, so a
# missing one costs that preview and nothing else:
#   ffmpeg-full    video thumbnails        poppler   PDF
#   imagemagick-full  raw photos, SVG      resvg     SVG
#   sevenzip       archives
# The "-full" builds carry the codecs the plain ones leave out. install.sh
# links them over the plain build when both are installed.
brew "yazi"
brew "fd"
brew "sevenzip"
brew "poppler"
brew "resvg"
brew "ffmpeg-full"
brew "imagemagick-full"

cask "font-jetbrains-mono-nerd-font"
cask "font-symbols-only-nerd-font"   # yazi's file-type icons
