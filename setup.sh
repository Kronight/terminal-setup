#!/bin/bash
#
# terminal-setup — One-script terminal environment setup
#
# Platforms: macOS, Debian/Ubuntu, Windows (via WSL)
#
# Stack: Ghostty + (Fish or Zsh) + Starship + Nerd Font (Maple Mono NF CN)
# Tools: bat, eza, fd, ripgrep, zoxide, fzf
# Theme: Catppuccin Mocha (Starship)
#
# Usage:
#   ./setup.sh              # interactive shell choice
#   ./setup.sh --fish       # use Fish
#   ./setup.sh --zsh        # use Zsh (with fish-like plugins)
#   ./setup.sh --dry-run    # preview what would be done (no changes)
#

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Dry-run support ────────────────────────────────────────────────
DRY_RUN=false

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# run_cmd: execute a command, or just print it in dry-run mode
run_cmd() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

# ─── Parse Arguments ────────────────────────────────────────────────
SHELL_CHOICE=""
for arg in "$@"; do
    case "$arg" in
        --fish)    SHELL_CHOICE="fish" ;;
        --zsh)     SHELL_CHOICE="zsh" ;;
        --dry-run) DRY_RUN=true ;;
        *)         warn "Unknown option: $arg (ignored)" ;;
    esac
done

if $DRY_RUN; then
    echo ""
    echo -e "${YELLOW}${BOLD}  ⚠  DRY-RUN MODE — no changes will be made${NC}"
    echo ""
fi

# ─── OS Detection ───────────────────────────────────────────────────
# Possible values: macos, debian, wsl, unsupported
detect_os() {
    local uname_out
    uname_out="$(uname -s)"

    case "$uname_out" in
        Darwin)
            echo "macos"
            ;;
        Linux)
            # Check if running inside WSL
            if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
                echo "wsl"
            elif [[ -f /etc/debian_version ]] || grep -qi 'debian\|ubuntu' /etc/os-release 2>/dev/null; then
                echo "debian"
            else
                echo "unsupported"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows-native"
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

OS="$(detect_os)"

case "$OS" in
    macos)
        info "Detected ${BOLD}macOS${NC}"
        ;;
    debian)
        info "Detected ${BOLD}Debian/Ubuntu Linux${NC}"
        ;;
    wsl)
        info "Detected ${BOLD}Windows WSL${NC} (Debian/Ubuntu layer)"
        ;;
    windows-native)
        error "Native Windows (MINGW/MSYS/Cygwin) is not supported.\n  Please install WSL: https://learn.microsoft.com/en-us/windows/wsl/install\n  Then run this script inside WSL."
        ;;
    *)
        error "Unsupported OS: $(uname -s)\n  This script supports macOS, Debian/Ubuntu, and Windows WSL."
        ;;
esac

# ─── Shell Choice ────────────────────────────────────────────────────
if [[ -z "$SHELL_CHOICE" ]]; then
    echo ""
    echo -e "${BOLD}Which shell do you want to use?${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} ${BOLD}Fish${NC}  — Modern shell, amazing defaults, not POSIX"
    echo -e "  ${GREEN}2)${NC} ${BOLD}Zsh${NC}   — POSIX-compatible, fish-like with plugins"
    echo ""
    while true; do
        read -rp "Choose [1/2]: " choice
        case "$choice" in
            1|fish) SHELL_CHOICE="fish"; break ;;
            2|zsh)  SHELL_CHOICE="zsh"; break ;;
            *) echo "Please enter 1 or 2." ;;
        esac
    done
fi

echo ""
info "Setting up with ${BOLD}${SHELL_CHOICE}${NC} on ${BOLD}${OS}${NC}"

# ─── Config Directory ───────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"

# If running via curl pipe (no local configs dir), clone the repo first
if [[ ! -d "$CONFIGS_DIR" ]]; then
    info "Config files not found locally, cloning repo..."
    TMPDIR_CLONE="$(mktemp -d)"
    git clone --depth 1 https://github.com/Kronight/terminal-setup.git "$TMPDIR_CLONE/terminal-setup"
    SCRIPT_DIR="$TMPDIR_CLONE/terminal-setup"
    CONFIGS_DIR="$SCRIPT_DIR/configs"
fi

# ═══════════════════════════════════════════════════════════════════════
# Helper Functions (cross-platform)
# ═══════════════════════════════════════════════════════════════════════

# Install a package using the appropriate package manager
pkg_install() {
    local pkg="$1"
    case "$OS" in
        macos)
            if brew list "$pkg" &>/dev/null; then
                success "$pkg already installed"
                return 0
            fi
            info "Installing $pkg..."
            run_cmd brew install "$pkg"
            ;;
        debian|wsl)
            if dpkg -s "$pkg" &>/dev/null 2>&1; then
                success "$pkg already installed"
                return 0
            fi
            info "Installing $pkg..."
            run_cmd sudo apt-get install -y "$pkg"
            ;;
    esac
    success "$pkg installed"
}

# Check if a command exists
has_cmd() {
    command -v "$1" &>/dev/null
}

# ─── Step 1: Package Manager ────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  📦 Step 1/7: Package Manager${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

case "$OS" in
    macos)
        if ! has_cmd brew; then
            info "Installing Homebrew..."
            run_cmd /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Auto-detect Homebrew prefix (Apple Silicon vs Intel)
            if ! $DRY_RUN; then
                if [[ -d /opt/homebrew ]]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [[ -d /usr/local/Homebrew ]]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
            fi
            success "Homebrew installed"
        else
            success "Homebrew already installed"
        fi
        ;;
    debian|wsl)
        info "Updating apt package index..."
        run_cmd sudo apt-get update
        # Ensure basic build tools are available
        pkg_install "curl"
        pkg_install "git"
        pkg_install "wget"
        pkg_install "unzip"
        pkg_install "build-essential"
        success "apt package manager ready"
        ;;
esac

# ─── Step 2: Terminal Emulator ───────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  👻 Step 2/7: Terminal Emulator${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

case "$OS" in
    macos)
        if [[ ! -d "/Applications/Ghostty.app" ]]; then
            info "Installing Ghostty..."
            run_cmd brew install --cask ghostty
            success "Ghostty installed"
        else
            success "Ghostty already installed"
        fi
        ;;
    debian)
        # Ghostty on Linux: check if already installed, otherwise try snap/flatpak or skip
        if has_cmd ghostty; then
            success "Ghostty already installed"
        else
            warn "Ghostty is not easily available on Linux via apt."
            echo -e "  Options to install Ghostty on Linux:"
            echo -e "    • Snap:    ${BOLD}sudo snap install ghostty${NC}"
            echo -e "    • Build:   ${BOLD}https://ghostty.org/docs/install/build${NC}"
            echo -e "    • Or use any other terminal (kitty, alacritty, etc.)"
            echo ""
            info "Skipping Ghostty installation — install it manually if desired."
        fi
        ;;
    wsl)
        info "WSL detected — terminal emulator runs on the Windows side."
        echo -e "  Install Ghostty for Windows: ${BOLD}https://ghostty.org${NC}"
        echo -e "  Or use Windows Terminal, which works great with WSL."
        info "Skipping terminal emulator installation."
        ;;
esac

# ─── Step 3: Nerd Font (Maple Mono NF CN) ───────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  🔤 Step 3/7: Nerd Font (Maple Mono NF CN)${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

# Determine font directory based on OS
case "$OS" in
    macos)
        FONT_DIR="$HOME/Library/Fonts"
        ;;
    debian|wsl)
        FONT_DIR="$HOME/.local/share/fonts"
        ;;
esac

MAPLE_FONTS=(
    "MapleMono-NF-CN-Regular.ttf"
    "MapleMono-NF-CN-Bold.ttf"
    "MapleMono-NF-CN-Italic.ttf"
    "MapleMono-NF-CN-BoldItalic.ttf"
)

# Font source: bundled in repo (fonts/) — no download needed
# Note: SCRIPT_DIR already points at the repo (or the temp clone) from Step 0 — do not recompute
FONT_SRC_DIR="$SCRIPT_DIR/fonts"

FONT_INSTALLED=true
for font in "${MAPLE_FONTS[@]}"; do
    [[ ! -f "$FONT_DIR/$font" ]] && FONT_INSTALLED=false && break
done

if $FONT_INSTALLED; then
    success "Maple Mono NF CN fonts already installed"
else
    info "Installing Maple Mono NF CN fonts from repo..."
    run_cmd mkdir -p "$FONT_DIR"
    for font in "${MAPLE_FONTS[@]}"; do
        if [[ -f "$FONT_SRC_DIR/$font" ]]; then
            run_cmd cp "$FONT_SRC_DIR/$font" "$FONT_DIR/$font"
        else
            warn "Font not found in repo: $font — skipping"
        fi
    done
    # Rebuild font cache on Linux
    if [[ "$OS" == "debian" || "$OS" == "wsl" ]]; then
        if has_cmd fc-cache; then
            run_cmd fc-cache -fv "$FONT_DIR"
        fi
    fi
    success "Maple Mono NF CN fonts installed"
fi

# ─── Step 4: Shell ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
if [[ "$SHELL_CHOICE" == "fish" ]]; then
    echo -e "${BOLD}  🐟 Step 4/7: Fish Shell${NC}"
else
    echo -e "${BOLD}  🐚 Step 4/7: Zsh + Fish-like Plugins${NC}"
fi
echo -e "${BOLD}══════════════════════════════════════════${NC}"

install_shell_macos() {
    if [[ "$SHELL_CHOICE" == "fish" ]]; then
        if ! has_cmd fish; then
            info "Installing Fish..."
            run_cmd brew install fish
            success "Fish installed"
        else
            success "Fish already installed"
        fi

        FISH_PATH="$(command -v fish || true)"
        if [[ -z "$FISH_PATH" ]]; then
            warn "fish not available (dry-run?) — skipping /etc/shells and default shell change"
        else
            if ! grep -qxF "$FISH_PATH" /etc/shells 2>/dev/null; then
                if $DRY_RUN; then
                    echo -e "${YELLOW}[DRY-RUN]${NC} add $FISH_PATH to /etc/shells"
                else
                    info "Adding Fish to /etc/shells (may need sudo)..."
                    echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
                fi
            fi

            if [[ "$SHELL" != "$FISH_PATH" ]]; then
                info "Setting Fish as default shell..."
                run_cmd chsh -s "$FISH_PATH"
                success "Default shell changed to Fish"
            else
                success "Fish is already the default shell"
            fi
        fi
    else
        # Zsh is pre-installed on macOS, just install the plugins
        local plugins=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions)
        for plugin in "${plugins[@]}"; do
            if brew list "$plugin" &>/dev/null; then
                success "$plugin already installed"
            else
                info "Installing $plugin..."
                run_cmd brew install "$plugin"
                success "$plugin installed"
            fi
        done

        ZSH_PATH="$(command -v zsh || true)"
        if [[ -z "$ZSH_PATH" ]]; then
            warn "zsh not available (dry-run?) — skipping default shell change"
        elif [[ "$SHELL" != "$ZSH_PATH" ]]; then
            info "Setting Zsh as default shell..."
            run_cmd chsh -s "$ZSH_PATH"
            success "Default shell changed to Zsh"
        else
            success "Zsh is already the default shell"
        fi
    fi
}

install_shell_linux() {
    if [[ "$SHELL_CHOICE" == "fish" ]]; then
        if ! has_cmd fish; then
            # Fish PPA for latest version on Ubuntu/Debian
            if [[ -f /etc/lsb-release ]] && grep -qi ubuntu /etc/lsb-release 2>/dev/null; then
                info "Adding Fish PPA for latest version..."
                run_cmd sudo apt-add-repository -y ppa:fish-shell/release-3
                run_cmd sudo apt-get update
            fi
            info "Installing Fish..."
            run_cmd sudo apt-get install -y fish
            success "Fish installed"
        else
            success "Fish already installed"
        fi

        FISH_PATH="$(command -v fish || true)"
        if [[ -z "$FISH_PATH" ]]; then
            warn "fish not available (dry-run?) — skipping /etc/shells and default shell change"
        else
            if ! grep -qxF "$FISH_PATH" /etc/shells 2>/dev/null; then
                if $DRY_RUN; then
                    echo -e "${YELLOW}[DRY-RUN]${NC} add $FISH_PATH to /etc/shells"
                else
                    info "Adding Fish to /etc/shells..."
                    echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
                fi
            fi

            if [[ "$SHELL" != "$FISH_PATH" ]]; then
                info "Setting Fish as default shell..."
                run_cmd chsh -s "$FISH_PATH"
                success "Default shell changed to Fish"
            else
                success "Fish is already the default shell"
            fi
        fi
    else
        # Install Zsh if not present
        if ! has_cmd zsh; then
            info "Installing Zsh..."
            run_cmd sudo apt-get install -y zsh
            success "Zsh installed"
        else
            success "Zsh already installed"
        fi

        # Install Zsh plugins from apt or git clone
        local ZSH_PLUGINS_DIR="/usr/share"

        # zsh-autosuggestions
        if [[ -f "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
            success "zsh-autosuggestions already installed"
        elif dpkg -s zsh-autosuggestions &>/dev/null 2>&1; then
            success "zsh-autosuggestions already installed"
        else
            info "Installing zsh-autosuggestions..."
            run_cmd sudo apt-get install -y zsh-autosuggestions 2>/dev/null || {
                info "apt package not available, cloning from git..."
                run_cmd sudo git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGINS_DIR/zsh-autosuggestions"
            }
            success "zsh-autosuggestions installed"
        fi

        # zsh-syntax-highlighting
        if [[ -f "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
            success "zsh-syntax-highlighting already installed"
        elif dpkg -s zsh-syntax-highlighting &>/dev/null 2>&1; then
            success "zsh-syntax-highlighting already installed"
        else
            info "Installing zsh-syntax-highlighting..."
            run_cmd sudo apt-get install -y zsh-syntax-highlighting 2>/dev/null || {
                info "apt package not available, cloning from git..."
                run_cmd sudo git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting"
            }
            success "zsh-syntax-highlighting installed"
        fi

        # zsh-completions
        if [[ -d "$ZSH_PLUGINS_DIR/zsh-completions" ]] || dpkg -s zsh-completions &>/dev/null 2>&1; then
            success "zsh-completions already installed"
        else
            info "Installing zsh-completions..."
            run_cmd sudo apt-get install -y zsh-completions 2>/dev/null || {
                info "apt package not available, cloning from git..."
                run_cmd sudo git clone https://github.com/zsh-users/zsh-completions "$ZSH_PLUGINS_DIR/zsh-completions"
            }
            success "zsh-completions installed"
        fi

        ZSH_PATH="$(command -v zsh || true)"
        if [[ -z "$ZSH_PATH" ]]; then
            warn "zsh not available (dry-run?) — skipping default shell change"
        elif [[ "$SHELL" != "$ZSH_PATH" ]]; then
            info "Setting Zsh as default shell..."
            run_cmd chsh -s "$ZSH_PATH"
            success "Default shell changed to Zsh"
        else
            success "Zsh is already the default shell"
        fi
    fi
}

case "$OS" in
    macos)  install_shell_macos ;;
    debian|wsl) install_shell_linux ;;
esac

# ─── Step 5: CLI Tools ──────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  🛠  Step 5/7: CLI Tools${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

install_cli_tools_macos() {
    local TOOLS=(bat eza fd ripgrep zoxide fzf)
    for tool in "${TOOLS[@]}"; do
        if brew list "$tool" &>/dev/null; then
            success "$tool already installed"
        else
            info "Installing $tool..."
            run_cmd brew install "$tool"
            success "$tool installed"
        fi
    done
}

install_cli_tools_linux() {
    # Tools available directly from apt (on modern Debian/Ubuntu)
    local APT_TOOLS=(bat fd-find ripgrep fzf)

    for tool in "${APT_TOOLS[@]}"; do
        if dpkg -s "$tool" &>/dev/null 2>&1; then
            success "$tool already installed"
        else
            info "Installing $tool..."
            run_cmd sudo apt-get install -y "$tool"
            success "$tool installed"
        fi
    done

    # zoxide — not in apt on older Debian/Ubuntu, use bundled installer as fallback
    if has_cmd zoxide; then
        success "zoxide already installed"
    else
        info "Installing zoxide..."
        if run_cmd sudo apt-get install -y zoxide 2>/dev/null; then
            success "zoxide installed via apt"
        elif has_cmd snap && run_cmd sudo snap install zoxide 2>/dev/null; then
            success "zoxide installed via snap"
        else
            info "zoxide not in apt/snap, using bundled installer..."
            run_cmd bash "$SCRIPT_DIR/scripts/install-zoxide.sh"
            success "zoxide installed via bundled script"
        fi
    fi

    # bat is installed as 'batcat' on Debian/Ubuntu — create symlink
    if has_cmd batcat && ! has_cmd bat; then
        info "Creating symlink: batcat → bat"
        run_cmd mkdir -p "$HOME/.local/bin"
        run_cmd ln -sf "$(which batcat)" "$HOME/.local/bin/bat"
        success "bat symlink created"
    fi

    # fd is installed as 'fdfind' on Debian/Ubuntu — create symlink
    if has_cmd fdfind && ! has_cmd fd; then
        info "Creating symlink: fdfind → fd"
        run_cmd mkdir -p "$HOME/.local/bin"
        run_cmd ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
        success "fd symlink created"
    fi

    # eza — apt only (packaged on modern Debian/Ubuntu)
    if has_cmd eza; then
        success "eza already installed"
    else
        info "Installing eza..."
        if run_cmd sudo apt-get install -y eza 2>/dev/null; then
            success "eza installed via apt"
        else
            warn "eza not available via apt — skipping (install manually: https://github.com/eza-community/eza)"
        fi
    fi

    # Ensure ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

case "$OS" in
    macos)      install_cli_tools_macos ;;
    debian|wsl) install_cli_tools_linux ;;
esac

# ─── Step 6: Starship Prompt ────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  🚀 Step 6/7: Starship Prompt${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

if has_cmd starship; then
    success "Starship already installed"
else
    case "$OS" in
        macos)
            info "Installing Starship..."
            run_cmd brew install starship
            ;;
        debian|wsl)
            info "Installing Starship..."
            # starship is not in Debian/Ubuntu apt repos — use official GitHub release binary
            # (the starship.rs installer script may fail on some WSL setups)
            starship_arch=""
            case "$(uname -m)" in
                x86_64)  starship_arch="x86_64" ;;
                aarch64) starship_arch="aarch64" ;;
                *) error "Unsupported arch for Starship: $(uname -m)" ;;
            esac
            if $DRY_RUN; then
                echo -e "${YELLOW}[DRY-RUN]${NC} Download starship from GitHub releases"
            else
                starship_tmp="$(mktemp -d)"
                curl -fsSL "https://github.com/starship/starship/releases/latest/download/starship-${starship_arch}-unknown-linux-musl.tar.gz" \
                    | tar xz -C "$starship_tmp" \
                    && sudo cp "$starship_tmp/starship" /usr/local/bin/starship \
                    && sudo chmod +x /usr/local/bin/starship
                rm -rf "$starship_tmp"
            fi
            ;;
    esac
    success "Starship installed"
fi

# ─── Step 7: Config Files ───────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  📦 Step 7/7: Deploying Configs${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"

# --- Ghostty config ---
deploy_ghostty_config() {
    local ghostty_config_dir
    case "$OS" in
        macos)
            ghostty_config_dir="$HOME/Library/Application Support/com.mitchellh.ghostty"
            ;;
        debian)
            ghostty_config_dir="$HOME/.config/ghostty"
            ;;
        wsl)
            info "Ghostty config: configure on the Windows side if using Ghostty for Windows."
            info "Deploying Linux-side config to ~/.config/ghostty/ for reference."
            ghostty_config_dir="$HOME/.config/ghostty"
            ;;
    esac

    run_cmd mkdir -p "$ghostty_config_dir"
    if [[ -f "$ghostty_config_dir/config" ]] || [[ -f "$ghostty_config_dir/config.ghostty" ]]; then
        local existing
        existing="$(ls "$ghostty_config_dir"/config* 2>/dev/null | head -1)"
        run_cmd cp "$existing" "${existing}.bak.$(date +%s)"
        warn "Backed up existing Ghostty config"
    fi

    # macOS uses config.ghostty, Linux uses config
    case "$OS" in
        macos)
            run_cmd cp "$CONFIGS_DIR/ghostty.config" "$ghostty_config_dir/config.ghostty"
            ;;
        debian|wsl)
            run_cmd cp "$CONFIGS_DIR/ghostty.config" "$ghostty_config_dir/config"
            ;;
    esac
    success "Ghostty config deployed"
}

deploy_ghostty_config

# --- Starship config ---
run_cmd mkdir -p "$HOME/.config"
if [[ -f "$HOME/.config/starship.toml" ]]; then
    run_cmd cp "$HOME/.config/starship.toml" "$HOME/.config/starship.toml.bak.$(date +%s)"
    warn "Backed up existing starship.toml"
fi
run_cmd cp "$CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml"
success "Starship config deployed"

# --- Shell-specific config ---
if [[ "$SHELL_CHOICE" == "fish" ]]; then
    # Fish config
    FISH_CONFIG_DIR="$HOME/.config/fish"
    run_cmd mkdir -p "$FISH_CONFIG_DIR"

    if [[ -f "$FISH_CONFIG_DIR/config.fish" ]]; then
        run_cmd cp "$FISH_CONFIG_DIR/config.fish" "$FISH_CONFIG_DIR/config.fish.bak.$(date +%s)"
        warn "Backed up existing config.fish"
    fi

    # Deploy platform-appropriate fish config
    if [[ "$OS" == "macos" ]]; then
        run_cmd cp "$CONFIGS_DIR/config.fish" "$FISH_CONFIG_DIR/config.fish"
    else
        # For Linux: use modified config without Homebrew paths
        run_cmd cp "$CONFIGS_DIR/config.fish" "$FISH_CONFIG_DIR/config.fish"
        # Patch: replace Homebrew paths with Linux equivalents
        run_cmd sed -i 's|/opt/homebrew/bin/starship|starship|g' "$FISH_CONFIG_DIR/config.fish"
        run_cmd sed -i 's|fish_add_path /opt/homebrew/bin|# PATH: system paths are used on Linux|g' "$FISH_CONFIG_DIR/config.fish"
        # Fix pnpm path for Linux
        run_cmd sed -i 's|\$HOME/Library/pnpm|\$HOME/.local/share/pnpm|g' "$FISH_CONFIG_DIR/config.fish"
    fi
    success "Fish config deployed"

    # Fish abbreviations (written to config.fish for Fish 3.x & 4.x compat)
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} append Fish abbreviations to $FISH_CONFIG_DIR/config.fish"
    elif ! grep -qF 'abbr -a ls' "$FISH_CONFIG_DIR/config.fish" 2>/dev/null; then
        info "Adding Fish abbreviations to config.fish..."
        cat >> "$FISH_CONFIG_DIR/config.fish" << 'ABBREOF'

# Abbreviations (compatible with Fish 3.x and 4.x)
if status is-interactive
    abbr -a ls "eza --icons --group-directories-first"
    abbr -a ll "eza -la --icons --group-directories-first"
    abbr -a lt "eza --tree --icons --level=2"
    abbr -a cat "bat"
    abbr -a find "fd"
    abbr -a grep "rg"
    abbr -a cd "z"
end
ABBREOF
        success "Fish abbreviations added to config.fish"
    else
        success "Fish abbreviations already present"
    fi

    # Zoxide + fzf init for fish
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} append zoxide + fzf init to $FISH_CONFIG_DIR/config.fish"
    elif ! grep -qF "zoxide" "$FISH_CONFIG_DIR/config.fish" 2>/dev/null; then
        info "Adding zoxide + fzf init to fish config..."
        cat >> "$FISH_CONFIG_DIR/config.fish" << 'FISHEOF'

# zoxide
zoxide init fish | source

# fzf
fzf --fish | source
set -gx FZF_DEFAULT_OPTS '--height 40% --layout=reverse --border'
if command -q fd
    set -gx FZF_DEFAULT_COMMAND 'fd --type f --hidden --follow --exclude .git'
    set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
    set -gx FZF_ALT_C_COMMAND 'fd --type d --hidden --follow --exclude .git'
end
FISHEOF
        success "Zoxide + fzf init added"
    else
        success "Zoxide init already present"
    fi

    # Add ~/.local/bin to fish PATH on Linux
    if [[ "$OS" == "debian" || "$OS" == "wsl" ]]; then
        if $DRY_RUN; then
            echo -e "${YELLOW}[DRY-RUN]${NC} append fish_add_path ~/.local/bin to config.fish"
        elif ! grep -qF '.local/bin' "$FISH_CONFIG_DIR/config.fish" 2>/dev/null; then
            echo '' >> "$FISH_CONFIG_DIR/config.fish"
            echo '# Local bin (Linux)' >> "$FISH_CONFIG_DIR/config.fish"
            echo 'fish_add_path $HOME/.local/bin' >> "$FISH_CONFIG_DIR/config.fish"
        fi
    fi
else
    # Zsh config
    if [[ -f "$HOME/.zshrc" ]]; then
        run_cmd cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%s)"
        warn "Backed up existing .zshrc"
    fi

    if [[ "$OS" == "macos" ]]; then
        run_cmd cp "$CONFIGS_DIR/.zshrc" "$HOME/.zshrc"
    else
        # Deploy and patch for Linux
        run_cmd cp "$CONFIGS_DIR/.zshrc" "$HOME/.zshrc"

        # Patch Homebrew paths → Linux paths
        run_cmd sed -i 's|export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:\$PATH"|# PATH — system paths on Linux\nexport PATH="$HOME/.local/bin:$PATH"|' "$HOME/.zshrc"

        # Patch zsh plugin source paths
        run_cmd sed -i 's|/opt/homebrew/share/zsh-syntax-highlighting/|/usr/share/zsh-syntax-highlighting/|g' "$HOME/.zshrc"
        run_cmd sed -i 's|/opt/homebrew/share/zsh-autosuggestions/|/usr/share/zsh-autosuggestions/|g' "$HOME/.zshrc"
        run_cmd sed -i 's|/opt/homebrew/share/zsh-completions|/usr/share/zsh-completions|g' "$HOME/.zshrc"

        # Patch pnpm path for Linux
        run_cmd sed -i 's|\$HOME/Library/pnpm|\$HOME/.local/share/pnpm|g' "$HOME/.zshrc"
    fi
    success "Zsh config deployed"
fi

# ─── Git config (quality-of-life) ────────────────────────────────────
run_cmd git config --global merge.conflictstyle diff3
run_cmd git config --global diff.colorMoved default
success "Git config applied"

# ─── Done! ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
if $DRY_RUN; then
    echo -e "${YELLOW}${BOLD}  ⚠  DRY-RUN complete — no changes were made${NC}"
else
    echo -e "${GREEN}${BOLD}  ✅ All done!${NC}"
fi
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Platform:${NC} $OS"
echo -e ""
echo -e "  ${BOLD}Your terminal stack:${NC}"
case "$OS" in
    macos)
        echo -e "    👻 Ghostty              — terminal emulator"
        ;;
    debian)
        echo -e "    👻 Ghostty              — terminal (install separately on Linux)"
        ;;
    wsl)
        echo -e "    💻 Windows Terminal      — recommended for WSL"
        ;;
esac
if [[ "$SHELL_CHOICE" == "fish" ]]; then
    echo -e "    🐟 Fish                 — shell"
else
    echo -e "    🐚 Zsh                  — shell (POSIX-compatible)"
    echo -e "    ✨ zsh-autosuggestions   — fish-like suggestions"
    echo -e "    🎨 zsh-syntax-highlight — fish-like highlighting"
fi
echo -e "    🚀 Starship             — prompt (Catppuccin Mocha)"
echo -e "    🔤 Maple Mono NF CN     — nerd font"
echo -e "    📦 bat eza fd rg        — modern coreutils"
echo -e "    📁 zoxide               — smart cd"
echo -e "    🔍 fzf                  — fuzzy finder"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo -e "    1. Restart your terminal (or open ${BOLD}Ghostty${NC})"
echo -e "    2. Try: ${BOLD}Ctrl+R${NC} (fzf history) / ${BOLD}Ctrl+T${NC} (fzf files)"
echo ""
