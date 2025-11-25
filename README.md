```
  ███████╗██╗  ██╗ █████╗ ██╗
  ██╔════╝██║  ██║██╔══██╗██║
  ███████╗███████║███████║██║
  ╚════██║██╔══██║██╔══██║██║
  ███████║██║  ██║██║  ██║██║
  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝
     ★ Shell AI Assistant ★
```

# SHAI - Shell AI

A ZSH plugin that adds an AI-powered chat mode to your terminal. Toggle between normal shell mode and AI mode with a single keystroke.

## Features

- **Dual Mode**: Switch between shell and AI mode instantly
- **Multiple Models**: Cycle through different AI models (Claude, GPT, Gemini)
- **Persistent Sessions**: Conversations persist within a terminal session
- **Shared Server**: Multiple terminals share a single OpenCode server
- **Clean Integration**: Disables syntax highlighting in AI mode for cleaner input

## Requirements

- **ZSH** (5.0+)
- **[OpenCode](https://github.com/opencode-ai/opencode)** - AI backend server
- **jq** - JSON processor

## Installation

### Dependencies

```bash
# Install OpenCode
brew install opencode

# Install jq
# macOS
brew install jq

# Debian/Ubuntu
sudo apt install jq

# Fedora
sudo dnf install jq

# Arch
sudo pacman -S jq
```

### Plugin Installation

#### Manual

```bash
# Clone the repository
git clone https://github.com/gevorggalstyan/shai.git ~/.zsh/shai

# Add to your .zshrc
echo 'source ~/.zsh/shai/shai.plugin.zsh' >> ~/.zshrc

# Reload
source ~/.zshrc
```

#### Oh My Zsh

```bash
git clone https://github.com/gevorggalstyan/shai.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/shai
```

Add `shai` to your plugins in `~/.zshrc`:
```zsh
plugins=(... shai)
```

#### Zinit

```zsh
zinit light gevorggalstyan/shai
```

#### Antigen

```zsh
antigen bundle gevorggalstyan/shai
```

## Usage

### Keybindings

| Key | Action |
|-----|--------|
| `Ctrl+]` | Toggle AI/Shell mode |
| `Ctrl+N` | Next model (AI mode) / Next history (Shell mode) |
| `Ctrl+P` | Previous model (AI mode) / Previous history (Shell mode) |
| `Ctrl+X` | Start new conversation (AI mode only) |

### Basic Usage

1. Press `Ctrl+]` to enter AI mode (prompt changes to show model name)
2. Type your question and press Enter
3. Press `Ctrl+]` again to return to shell mode

### Example

```
➜ ~ %                          # Normal shell mode
★ sonnet ~ %                   # AI mode (press Ctrl+])
★ sonnet ~ % How do I find large files?
★ ★ ★
You can use the find command:
  find / -type f -size +100M 2>/dev/null
★ ★ ★
★ sonnet ~ %                   # Ready for next question
```

## Configuration

### Custom Models

Set your preferred models before sourcing the plugin:

```zsh
# In ~/.zshrc, BEFORE sourcing shai
typeset -ga SHAI_MODEL_CHOICES=(
  "anthropic:claude-sonnet-4-5"
  "anthropic:claude-opus-4-5"
  "openai:gpt-5.1"
  "openai:gpt-5.1-codex"
  "google:gemini-2.5-pro"
)

typeset -gA SHAI_MODEL_SHORT_NAMES=(
  "claude-sonnet-4-5" "son4.5"
  "claude-opus-4-5" "opus4.5"
  "gpt-5.1" "gpt5.1"
  "gpt-5.1-codex" "cdx5.1"
  "gemini-2.5-pro" "gem2.5"
)

source ~/.zsh/shai/shai.plugin.zsh
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SHAI_SERVER_PORT` | `4096` | Starting port for OpenCode server |
| `SHAI_MODEL_INDEX` | `1` | Default model (1-indexed) |

## How It Works

1. When you enter AI mode, SHAI ensures an OpenCode server is running
2. Multiple terminal sessions share the same server (reference counted)
3. The server is automatically killed when the last terminal exits
4. Each terminal maintains its own conversation session

## Troubleshooting

### Server won't start

```bash
# Kill any orphaned servers
shai-kill-all-servers

# Check if port is in use
lsof -i :4096
```

### Dependencies missing

The plugin will show an error with installation instructions if `opencode` or `jq` are not found.

### Reset everything

```bash
# Kill servers and clear state
shai-kill-all-servers
rm -f /tmp/shai_*
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
