# SHAI - Shell AI
# A ZSH plugin for AI-powered terminal assistance
# https://github.com/gevorggalstyan/shai
#
# Version: 1.0.0
# MIT License - Copyright (c) 2024
# See LICENSE file for full license text
#
# USAGE:
#   Ctrl+]  - Toggle between shell and AI mode
#   Ctrl+N  - Next model (in AI mode) / Next history (in shell mode)
#   Ctrl+P  - Previous model (in AI mode) / Previous history (in shell mode)
#   Ctrl+X  - Start new conversation (in AI mode only)
#
# DEPENDENCIES:
#   - opencode: npm install -g opencode-ai
#   - jq: brew install jq (macOS) / apt install jq (Debian)

# =============================================================================
# MODEL CONFIGURATION - Edit this section to customize your models
# =============================================================================
# Format: "provider:model-id:shortname"
#
# - provider:  anthropic, openai, google, etc.
# - model-id:  the model identifier for that provider
# - shortname: displayed in your prompt (e.g., "★ son4.5 ~ %") - can be anything you like
#
# Browse available models at https://models.dev
# Models must also be supported by OpenCode: https://github.com/opencode-ai/opencode

typeset -ga SHAI_MODELS=(
  "anthropic:claude-sonnet-4-5:son4.5"
  "anthropic:claude-opus-4-5:ops4.5"
  "openai:gpt-5.2:gpt5.2"
  "openai:gpt-5-pro:gpt5.2pro"
  "openai:gpt-5.1-codex:cdx5.1"
  "google:gemini-3-pro-preview:gem3p"
  "google:gemini-3-flash-preview:gem3f"
  "opencode:big-pickle:glm4.6"
  "opencode:grok-code:grk1f"
)

# =============================================================================
# END OF MODEL CONFIGURATION - No need to edit below this line
# =============================================================================

# -----------------------------------------------------------------------------
# Helper functions to parse model entries
# -----------------------------------------------------------------------------
shai-get-provider()  { local IFS=':'; local parts=(${=SHAI_MODELS[$1]}); echo "$parts[1]"; }
shai-get-model()     { local IFS=':'; local parts=(${=SHAI_MODELS[$1]}); echo "$parts[2]"; }
shai-get-shortname() { local IFS=':'; local parts=(${=SHAI_MODELS[$1]}); echo "$parts[3]"; }

# =============================================================================
# MODE STATE
# =============================================================================
# Track current mode (shell or ai) and related state variables

typeset -g SHAI_MODE=${SHAI_MODE:-shell}           # Current mode: 'shell' or 'ai'
typeset -g SHAI_DEPS_OK=1                          # Whether dependencies are installed
typeset -g SHAI_SAVED_HIGHLIGHTERS=()              # Backup of ZSH_HIGHLIGHT_HIGHLIGHTERS
typeset -g SHAI_HIGHLIGHTING_DISABLED=0            # Whether we disabled highlighting
typeset -g SHAI_HIGHLIGHTERS_WAS_SET=0             # Whether highlighters were set before
typeset -g SHAI_HIGHLIGHT_STYLES_WAS_SET=0         # Whether highlight styles were set before
typeset -g SHAI_AUTOSUGGEST_WAS_SET=0              # Whether autosuggest was set before
typeset -gA SHAI_SAVED_HIGHLIGHT_STYLES            # Backup of ZSH_HIGHLIGHT_STYLES
typeset -g SHAI_SAVED_AUTOSUGGEST_STYLE=""         # Backup of autosuggest style
typeset -g SHAI_AUTOSUGGEST_SUSPENDED=0            # Whether autosuggest is suspended

typeset -g SHAI_MODEL_INDEX=${SHAI_MODEL_INDEX:-1}              # Current model (1-indexed)
typeset -g SHAI_MODEL_STATE_FILE="$HOME/.config/shai/model_choice"  # Persist model choice

# -----------------------------------------------------------------------------
# Load saved model choice from disk
# -----------------------------------------------------------------------------
shai-load-model-state() {
  [[ -f $SHAI_MODEL_STATE_FILE ]] || return
  local saved_index=$(<"$SHAI_MODEL_STATE_FILE")
  # Validate: must be a number within range
  if [[ $saved_index =~ ^[0-9]+$ ]] && (( saved_index >= 1 && saved_index <= ${#SHAI_MODELS[@]} )); then
    SHAI_MODEL_INDEX=$saved_index
  fi
}

# -----------------------------------------------------------------------------
# Save current model choice to disk
# -----------------------------------------------------------------------------
shai-save-model-state() {
  mkdir -p "${SHAI_MODEL_STATE_FILE:h}" 2>/dev/null
  echo "$SHAI_MODEL_INDEX" > "$SHAI_MODEL_STATE_FILE" 2>/dev/null
}

# Load saved model on startup
shai-load-model-state

# =============================================================================
# PROMPT CONFIGURATION
# =============================================================================
# Dynamic prompt that shows current mode and model

setopt PROMPT_SUBST  # Enable prompt substitution

# -----------------------------------------------------------------------------
# Update the prompt based on current mode
# Shell mode: green arrow
# AI mode: yellow star with model name
# -----------------------------------------------------------------------------
shai-update-prompt() {
  if [[ $SHAI_MODE == ai ]]; then
    local short_name=$(shai-get-shortname $SHAI_MODEL_INDEX)
    PROMPT="%F{yellow}★ ${short_name}%f %1~ %# "
  else
    PROMPT='%F{green}➜%f %1~ %# '
  fi
}

# Initialize prompt on load
shai-update-prompt

# =============================================================================
# SYNTAX HIGHLIGHTING MANAGEMENT
# =============================================================================
# Disable syntax highlighting in AI mode to avoid confusing colors on natural
# language input, then restore it when returning to shell mode.

# -----------------------------------------------------------------------------
# Disable all syntax highlighting (zsh-syntax-highlighting plugin)
# Saves current state so it can be restored later
# -----------------------------------------------------------------------------
shai-disable-highlighting() {
  # Prevent double-disable
  if (( SHAI_HIGHLIGHTING_DISABLED == 1 )); then
    return
  fi

  # Save and clear ZSH_HIGHLIGHT_HIGHLIGHTERS
  if typeset -p ZSH_HIGHLIGHT_HIGHLIGHTERS >/dev/null 2>&1; then
    SHAI_HIGHLIGHTERS_WAS_SET=1
    SHAI_SAVED_HIGHLIGHTERS=("${ZSH_HIGHLIGHT_HIGHLIGHTERS[@]}")
    ZSH_HIGHLIGHT_HIGHLIGHTERS=()
  else
    SHAI_HIGHLIGHTERS_WAS_SET=0
  fi

  # Save and clear ZSH_HIGHLIGHT_STYLES
  if typeset -p ZSH_HIGHLIGHT_STYLES >/dev/null 2>&1; then
    SHAI_HIGHLIGHT_STYLES_WAS_SET=1
    SHAI_SAVED_HIGHLIGHT_STYLES=("${(@kv)ZSH_HIGHLIGHT_STYLES}")
    typeset -gA ZSH_HIGHLIGHT_STYLES
    ZSH_HIGHLIGHT_STYLES=()
  else
    SHAI_HIGHLIGHT_STYLES_WAS_SET=0
  fi

  # Save and disable autosuggest highlighting
  if typeset -p ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE >/dev/null 2>&1; then
    SHAI_AUTOSUGGEST_WAS_SET=1
    SHAI_SAVED_AUTOSUGGEST_STYLE=$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='none'
  else
    SHAI_AUTOSUGGEST_WAS_SET=0
  fi

  # Clear any existing region highlights
  typeset -ga region_highlight
  region_highlight=()
  SHAI_HIGHLIGHTING_DISABLED=1
}

# -----------------------------------------------------------------------------
# Restore syntax highlighting to previous state
# -----------------------------------------------------------------------------
shai-restore-highlighting() {
  # Prevent double-restore
  if (( SHAI_HIGHLIGHTING_DISABLED == 0 )); then
    return
  fi

  # Restore ZSH_HIGHLIGHT_HIGHLIGHTERS
  if (( SHAI_HIGHLIGHTERS_WAS_SET == 1 )); then
    ZSH_HIGHLIGHT_HIGHLIGHTERS=("${SHAI_SAVED_HIGHLIGHTERS[@]}")
  else
    unset ZSH_HIGHLIGHT_HIGHLIGHTERS
  fi

  # Restore ZSH_HIGHLIGHT_STYLES
  if (( SHAI_HIGHLIGHT_STYLES_WAS_SET == 1 )); then
    typeset -gA ZSH_HIGHLIGHT_STYLES
    ZSH_HIGHLIGHT_STYLES=("${(@kv)SHAI_SAVED_HIGHLIGHT_STYLES}")
  else
    unset ZSH_HIGHLIGHT_STYLES
  fi

  # Restore autosuggest style
  if (( SHAI_AUTOSUGGEST_WAS_SET == 1 )); then
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE=$SHAI_SAVED_AUTOSUGGEST_STYLE
  else
    unset ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE
  fi

  # Clear region highlights
  typeset -ga region_highlight
  region_highlight=()
  SHAI_HIGHLIGHTING_DISABLED=0
}

# =============================================================================
# AUTOSUGGEST MANAGEMENT
# =============================================================================
# Suspend zsh-autosuggestions in AI mode to prevent shell command suggestions
# from appearing while typing natural language prompts.

# -----------------------------------------------------------------------------
# Suspend autosuggest widget
# -----------------------------------------------------------------------------
shai-suspend-autosuggest() {
  if (( SHAI_AUTOSUGGEST_SUSPENDED == 1 )); then
    return
  fi
  # Only run if we're in a ZLE context
  zle >/dev/null 2>&1 || return

  # Try different widget names (varies by plugin version)
  if (( $+widgets[autosuggest-disable] )); then
    zle autosuggest-disable
    SHAI_AUTOSUGGEST_SUSPENDED=1
    return
  fi

  if (( $+widgets[autosuggest-stop] )); then
    zle autosuggest-stop
    SHAI_AUTOSUGGEST_SUSPENDED=1
  fi
}

# -----------------------------------------------------------------------------
# Resume autosuggest widget
# -----------------------------------------------------------------------------
shai-resume-autosuggest() {
  if (( SHAI_AUTOSUGGEST_SUSPENDED == 0 )); then
    return
  fi
  zle >/dev/null 2>&1 || return

  if (( $+widgets[autosuggest-enable] )); then
    zle autosuggest-enable
  elif (( $+widgets[autosuggest-start] )); then
    zle autosuggest-start
  fi

  SHAI_AUTOSUGGEST_SUSPENDED=0
}

# =============================================================================
# MODE TOGGLE
# =============================================================================
# Switch between shell mode (normal terminal) and AI mode (chat with LLM)

# -----------------------------------------------------------------------------
# Toggle between shell and AI mode (bound to Ctrl+])
# -----------------------------------------------------------------------------
shai-mode() {
  if [[ $SHAI_MODE == ai ]]; then
    # Switch to shell mode
    SHAI_MODE=shell
    shai-restore-highlighting
    shai-resume-autosuggest
  else
    # Switch to AI mode
    SHAI_MODE=ai
    shai-disable-highlighting
    shai-suspend-autosuggest

    # Check for required dependencies
    local missing_deps=()
    command -v opencode >/dev/null 2>&1 || missing_deps+=("opencode")
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")

    if (( ${#missing_deps[@]} > 0 )); then
      SHAI_DEPS_OK=0
      SHAI_DEPS_MISSING="${(j:,:)missing_deps}"
    else
      SHAI_DEPS_OK=1
      SHAI_DEPS_MISSING=""
    fi
  fi

  shai-update-prompt
  zle && zle reset-prompt
}
zle -N shai-mode  # Register as ZLE widget

# =============================================================================
# MODEL CYCLING
# =============================================================================
# Cycle through available models with Ctrl+N (next) and Ctrl+P (previous)
# In shell mode, these keys retain their default behavior (history navigation)

# -----------------------------------------------------------------------------
# Next model (Ctrl+N in AI mode, down-history in shell mode)
# -----------------------------------------------------------------------------
shai-model-next() {
  if [[ $SHAI_MODE == ai ]]; then
    # Cycle to next model (wraps around)
    SHAI_MODEL_INDEX=$(( (SHAI_MODEL_INDEX % ${#SHAI_MODELS[@]}) + 1 ))
    shai-save-model-state
    shai-update-prompt
    # Clear session when changing models (different context)
    SHAI_SESSION_ID=""
    rm -f "$SHAI_SESSION_FILE" 2>/dev/null
    zle && zle reset-prompt
  else
    # Default behavior in shell mode
    zle down-line-or-history
  fi
}
zle -N shai-model-next

# -----------------------------------------------------------------------------
# Previous model (Ctrl+P in AI mode, up-history in shell mode)
# -----------------------------------------------------------------------------
shai-model-prev() {
  if [[ $SHAI_MODE == ai ]]; then
    # Cycle to previous model (wraps around)
    SHAI_MODEL_INDEX=$(( SHAI_MODEL_INDEX - 1 ))
    (( SHAI_MODEL_INDEX < 1 )) && SHAI_MODEL_INDEX=${#SHAI_MODELS[@]}
    shai-save-model-state
    shai-update-prompt
    # Clear session when changing models
    SHAI_SESSION_ID=""
    rm -f "$SHAI_SESSION_FILE" 2>/dev/null
    zle && zle reset-prompt
  else
    # Default behavior in shell mode
    zle up-line-or-history
  fi
}
zle -N shai-model-prev

# =============================================================================
# SESSION MANAGEMENT
# =============================================================================
# Each conversation with the AI is a "session". Reset to start fresh.

# -----------------------------------------------------------------------------
# Start a new conversation (Ctrl+X in AI mode only)
# -----------------------------------------------------------------------------
shai-new-session() {
  if [[ $SHAI_MODE == ai ]]; then
    SHAI_SESSION_ID=""
    rm -f "$SHAI_SESSION_FILE" 2>/dev/null
    print "Session cleared. Next message starts a new conversation."
    zle && zle reset-prompt
  fi
}
zle -N shai-new-session

# =============================================================================
# KEYBINDINGS
# =============================================================================

bindkey '^]' shai-mode              # Ctrl + ] : toggle mode
bindkey '^N' shai-model-next        # Ctrl + N : next model / next history
bindkey '^P' shai-model-prev        # Ctrl + P : previous model / prev history
bindkey '^X' shai-new-session       # Ctrl + X : new conversation

# =============================================================================
# OPENCODE SERVER INTEGRATION
# =============================================================================
# SHAI uses OpenCode as the backend server for AI interactions.
# The server is shared across multiple terminal sessions using reference counting.
# When the last terminal exits, the server is automatically killed.

# Server configuration
typeset -g SHAI_TMPDIR="${TMPDIR:-/tmp}"                              # Temp directory (cross-platform)
typeset -g SHAI_SERVER_PORT=${SHAI_SERVER_PORT:-4096}                 # Starting port for server
typeset -g SHAI_SERVER_URL="http://localhost:$SHAI_SERVER_PORT"       # Server URL
typeset -g SHAI_SERVER_PID_FILE="$SHAI_TMPDIR/shai_server.pid"        # Server process ID
typeset -g SHAI_SERVER_PORT_FILE="$SHAI_TMPDIR/shai_server.port"      # Actual port used
typeset -g SHAI_SESSION_ID=""                                          # Current chat session ID
typeset -g SHAI_SESSION_FILE="$SHAI_TMPDIR/shai_session_$$"           # Session file (per-shell)
typeset -g SHAI_SERVER_REFCOUNT_FILE="$SHAI_TMPDIR/shai_server.refcount"  # Number of shells using server
typeset -g SHAI_SERVER_LOCK_FILE="$SHAI_TMPDIR/shai_server.lock"      # Mutex for refcount operations
typeset -g SHAI_REGISTERED_WITH_SERVER=0                               # Whether this shell is registered

# Load existing session if available (for shell restarts)
if [[ -f $SHAI_SESSION_FILE ]]; then
  SHAI_SESSION_ID=$(<"$SHAI_SESSION_FILE")
fi

# =============================================================================
# LOCKING MECHANISM
# =============================================================================
# File-based mutex using mkdir (atomic operation) to safely coordinate
# multiple shells accessing the shared server.

# -----------------------------------------------------------------------------
# Acquire exclusive lock with timeout
# Uses mkdir as an atomic test-and-set operation
# Returns: 0 on success, 1 on failure
# -----------------------------------------------------------------------------
shai-acquire-lock() {
  local max_attempts=50  # 5 seconds max (50 * 0.1s)
  local attempt=0

  while ! mkdir "$SHAI_SERVER_LOCK_FILE" 2>/dev/null; do
    (( attempt++ ))
    if (( attempt >= max_attempts )); then
      # Lock appears stale - force remove and retry once
      rmdir "$SHAI_SERVER_LOCK_FILE" 2>/dev/null
      if ! mkdir "$SHAI_SERVER_LOCK_FILE" 2>/dev/null; then
        return 1  # Still can't acquire
      fi
      break
    fi
    sleep 0.1
  done
  return 0
}

# -----------------------------------------------------------------------------
# Release exclusive lock
# -----------------------------------------------------------------------------
shai-release-lock() {
  rmdir "$SHAI_SERVER_LOCK_FILE" 2>/dev/null
}

# =============================================================================
# REFERENCE COUNTING
# =============================================================================
# Track how many shells are using the server. Kill server when count reaches 0.

# -----------------------------------------------------------------------------
# Register this shell as using the server (increment refcount)
# -----------------------------------------------------------------------------
shai-register-shell() {
  [[ $SHAI_REGISTERED_WITH_SERVER -eq 1 ]] && return  # Already registered

  shai-acquire-lock || return 1

  local count=0
  [[ -f $SHAI_SERVER_REFCOUNT_FILE ]] && count=$(<"$SHAI_SERVER_REFCOUNT_FILE")
  echo $(( count + 1 )) > "$SHAI_SERVER_REFCOUNT_FILE"
  SHAI_REGISTERED_WITH_SERVER=1

  shai-release-lock
}

# -----------------------------------------------------------------------------
# Unregister this shell (decrement refcount, kill server if last)
# -----------------------------------------------------------------------------
shai-unregister-shell() {
  [[ $SHAI_REGISTERED_WITH_SERVER -eq 0 ]] && return  # Not registered

  shai-acquire-lock || return 1

  local count=1
  [[ -f $SHAI_SERVER_REFCOUNT_FILE ]] && count=$(<"$SHAI_SERVER_REFCOUNT_FILE")
  count=$(( count - 1 ))

  if (( count <= 0 )); then
    # Last shell using the server - kill it
    rm -f "$SHAI_SERVER_REFCOUNT_FILE"
    shai-kill-server
  else
    echo $count > "$SHAI_SERVER_REFCOUNT_FILE"
  fi

  SHAI_REGISTERED_WITH_SERVER=0
  shai-release-lock
}

# =============================================================================
# SERVER LIFECYCLE
# =============================================================================

# -----------------------------------------------------------------------------
# Kill the OpenCode server gracefully, then forcefully if needed
# -----------------------------------------------------------------------------
shai-kill-server() {
  if [[ -f $SHAI_SERVER_PID_FILE ]]; then
    local pid=$(<"$SHAI_SERVER_PID_FILE")
    if kill -0 $pid 2>/dev/null; then
      # Send SIGTERM first
      kill $pid 2>/dev/null
      # Wait up to 1 second for graceful shutdown
      local wait_count=0
      while kill -0 $pid 2>/dev/null && (( wait_count < 10 )); do
        sleep 0.1
        (( wait_count++ ))
      done
      # Force kill if still running
      kill -0 $pid 2>/dev/null && kill -9 $pid 2>/dev/null
    fi
    rm -f "$SHAI_SERVER_PID_FILE" "$SHAI_SERVER_PORT_FILE" 2>/dev/null
  fi
}

# -----------------------------------------------------------------------------
# Cleanup function called when shell exits
# -----------------------------------------------------------------------------
shai-cleanup() {
  shai-unregister-shell
  rm -f "$SHAI_SESSION_FILE" 2>/dev/null
}

# Register cleanup handlers
trap shai-cleanup EXIT
autoload -Uz add-zsh-hook
add-zsh-hook zshexit shai-cleanup

# -----------------------------------------------------------------------------
# Manual cleanup: kill all orphaned opencode servers
# Use this if servers get stuck: run `shai-kill-all-servers` in terminal
# -----------------------------------------------------------------------------
shai-kill-all-servers() {
  print "Killing all opencode servers..."
  local pids=$(pgrep -f "opencode serve" 2>/dev/null)
  if [[ -n $pids ]]; then
    echo $pids | xargs kill 2>/dev/null
    sleep 0.5
    # Force kill any remaining
    pgrep -f "opencode serve" 2>/dev/null | xargs kill -9 2>/dev/null
    print "Killed opencode servers"
  else
    print "No opencode servers found"
  fi
  # Clean up all state files
  rm -f "$SHAI_SERVER_PID_FILE" "$SHAI_SERVER_PORT_FILE" "$SHAI_SERVER_REFCOUNT_FILE" 2>/dev/null
  rmdir "$SHAI_SERVER_LOCK_FILE" 2>/dev/null
  SHAI_REGISTERED_WITH_SERVER=0
}

# =============================================================================
# SERVER STARTUP
# =============================================================================

# -----------------------------------------------------------------------------
# Ensure OpenCode server is running, start if needed
# Uses double-fork daemonization to fully detach from terminal
# (prevents "Closing this window will terminate..." popup on macOS)
# -----------------------------------------------------------------------------
shai-ensure-server() {
  # Load saved port from previous run
  if [[ -f $SHAI_SERVER_PORT_FILE ]]; then
    SHAI_SERVER_PORT=$(<"$SHAI_SERVER_PORT_FILE")
    SHAI_SERVER_URL="http://localhost:$SHAI_SERVER_PORT"
  fi

  # Check if server is already running and responding
  if [[ -f $SHAI_SERVER_PID_FILE ]]; then
    local pid=$(<"$SHAI_SERVER_PID_FILE")
    if kill -0 $pid 2>/dev/null; then
      # Process exists, verify server is actually responding
      if curl -s -f "$SHAI_SERVER_URL/session" --connect-timeout 2 -m 2 >/dev/null 2>&1; then
        shai-register-shell
        return 0
      fi
    fi
  fi

  # Find an available port (try 10 ports starting from configured port)
  local port=$SHAI_SERVER_PORT
  local max_port=$((port + 10))

  while (( port < max_port )); do
    # Use /dev/tcp for fast port checking (zsh built-in)
    if ! (echo >/dev/tcp/localhost/$port) 2>/dev/null; then
      # Port is available, start server
      setopt local_options no_notify no_monitor

      # Remove stale PID file first
      rm -f "$SHAI_SERVER_PID_FILE"

      # Double-fork daemonization pattern:
      # Fork 1: Creates intermediate process (exits immediately)
      # Fork 2: Creates daemon (parent is init/launchd, fully detached)
      # This prevents the terminal from "owning" the server process
      (
        (
          opencode serve --port=$port >/dev/null 2>&1 </dev/null &
          echo $! > "$SHAI_SERVER_PID_FILE"
        ) &
      ) &

      # Wait for PID file to be written (max 1 second)
      local wait_count=0
      while [[ ! -f $SHAI_SERVER_PID_FILE ]] && (( wait_count < 50 )); do
        sleep 0.02
        (( wait_count++ ))
      done

      echo $port > "$SHAI_SERVER_PORT_FILE"
      SHAI_SERVER_PORT=$port
      SHAI_SERVER_URL="http://localhost:$port"

      # Wait for server to be ready (max 5 seconds)
      local max_attempts=25
      local attempt=0
      while (( attempt < max_attempts )); do
        if curl -s -f "$SHAI_SERVER_URL/session" --connect-timeout 1 -m 1 >/dev/null 2>&1; then
          shai-register-shell
          return 0
        fi
        sleep 0.2
        (( attempt++ ))
      done

      # Server started but not responding
      break
    fi

    (( port++ ))
  done

  print "Error: Could not start OpenCode server (tried ports 4096-$((max_port-1)))"
  return 1
}

# =============================================================================
# MESSAGE SENDING
# =============================================================================

# -----------------------------------------------------------------------------
# Send a message to the AI and display the response
# Handles session creation, spinner display, and error handling
# -----------------------------------------------------------------------------
shai-send-message() {
  local message=$1

  # Ensure server is running
  shai-ensure-server || return 1

  # Create a new session if we don't have one
  if [[ -z $SHAI_SESSION_ID ]]; then
    SHAI_SESSION_ID=$(curl -s -X POST "$SHAI_SERVER_URL/session" \
      -H "Content-Type: application/json" \
      -d '{"title":"SHAI Terminal"}' \
      --connect-timeout 5 \
      --max-time 10 | jq -r '.id')

    if [[ -z $SHAI_SESSION_ID || $SHAI_SESSION_ID == "null" ]]; then
      print "Error: Failed to create session"
      return 1
    fi

    # Persist session ID for potential shell restart
    echo "$SHAI_SESSION_ID" > "$SHAI_SESSION_FILE"
  fi

  # Get provider and model from current selection
  local provider=$(shai-get-provider $SHAI_MODEL_INDEX)
  local model=$(shai-get-model $SHAI_MODEL_INDEX)

  # Build JSON payload for the API
  local tmpfile=$(mktemp -t shai.XXXXXX)
  local json_payload=$(jq -n \
    --arg text "$message" \
    --arg provider "$provider" \
    --arg model "$model" \
    '{
      parts: [{type: "text", text: $text}],
      model: {providerID: $provider, modelID: $model}
    }')

  # Start animated spinner in background
  local spinner_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spinner_pid
  local curl_pid
  {
    setopt local_options no_monitor
    (
      while true; do
        for char in "${spinner_chars[@]}"; do
          printf "\r\033[33m%s\033[0m " "$char"
          sleep 0.1
        done
      done
    ) &
    spinner_pid=$!
  }

  # Handle Ctrl+C to cancel the request
  local cleanup_done=0
  TRAPINT() {
    if (( cleanup_done == 0 )); then
      cleanup_done=1
      kill $spinner_pid 2>/dev/null
      wait $spinner_pid 2>/dev/null
      [[ -n $curl_pid ]] && kill $curl_pid 2>/dev/null
      printf "\r  \r"
      print "\n\033[33mRequest cancelled\033[0m"
      rm -f "$tmpfile" 2>/dev/null
      return 130
    fi
  }

  # Send request (in background so Ctrl+C can interrupt)
  curl -sS -X POST "$SHAI_SERVER_URL/session/$SHAI_SESSION_ID/message" \
    -H "Content-Type: application/json" \
    -d "$json_payload" \
    --connect-timeout 5 \
    --max-time 300 \
    --no-buffer > "$tmpfile" 2>&1 &
  curl_pid=$!

  # Wait for request to complete
  wait $curl_pid 2>/dev/null
  local curl_status=$?

  # Stop spinner
  kill $spinner_pid 2>/dev/null
  wait $spinner_pid 2>/dev/null
  printf "\r  \r"

  # Remove interrupt handler
  unfunction TRAPINT 2>/dev/null

  # Check if cancelled
  if (( cleanup_done == 1 )); then
    return 130
  fi

  # Process and display response
  if (( curl_status != 0 )); then
    # Curl failed
    local raw_error=$(<"$tmpfile")
    [[ -z $raw_error ]] && raw_error="Curl exited with status $curl_status and no output."
    print "Request failed (curl exit $curl_status):"
    print "$raw_error"
  else
    # Extract text response from JSON
    local text_tmpfile=$(mktemp -t shai.XXXXXX)
    jq -r '.parts[] | select((.text? // "") != "") | .text' "$tmpfile" 2>/dev/null > "$text_tmpfile"

    if [[ -s $text_tmpfile ]]; then
      # Display response with decorative separators
      print "\033[33m★ ★ ★\033[0m"
      cat "$text_tmpfile"
      # Ensure trailing newline (prevents prompt overlap)
      [[ $(tail -c 1 "$text_tmpfile" | wc -l) -eq 0 ]] && printf '\n'
      print "\033[33m★ ★ ★\033[0m"
      rm -f "$text_tmpfile"
    else
      rm -f "$text_tmpfile"
      # Try to extract error message from various possible locations
      local error_msg
      error_msg=$(jq -r '.error
        // (.errors[]? | .message)
        // .message
        // .info.error.data.message
        // .info.error.name
        // empty' "$tmpfile" 2>/dev/null)
      if [[ -n $error_msg && $error_msg != "null" ]]; then
        print "Error: $error_msg"
      else
        # Unknown response format - show raw payload for debugging
        local raw_payload=$(<"$tmpfile")
        if [[ -n $raw_payload ]]; then
          print "No assistant text in response."
          print "Raw payload:"
          print "$raw_payload"
        else
          print "No response received (the request may have timed out or failed)"
        fi
      fi
    fi
  fi

  rm -f "$tmpfile"
}

# =============================================================================
# INPUT HANDLING
# =============================================================================
# Intercept Enter key to route input to either shell or AI

# -----------------------------------------------------------------------------
# Custom accept-line handler
# In AI mode: send input to AI
# In shell mode: execute as normal command
# -----------------------------------------------------------------------------
shai-accept-line() {
  if [[ $SHAI_MODE == ai ]]; then
    # Check dependencies before processing
    if (( SHAI_DEPS_OK == 0 )); then
      zle redisplay
      print
      print -P "%F{red}Error: Missing dependencies: $SHAI_DEPS_MISSING%f"
      print "Please install:"
      if [[ $SHAI_DEPS_MISSING == *"opencode"* ]]; then
        print "  - opencode: npm install -g opencode-ai"
      fi
      if [[ $SHAI_DEPS_MISSING == *"jq"* ]]; then
        print "  - jq: brew install jq (macOS) / apt install jq (Debian) / dnf install jq (Fedora)"
      fi
      BUFFER=""
      zle && zle reset-prompt
      return 1
    fi

    local cmd=$BUFFER
    zle redisplay
    print

    # Ignore empty input
    if [[ -z ${cmd//[[:space:]]/} ]]; then
      BUFFER=""
      zle && zle reset-prompt
      return 0
    fi

    # Send to AI
    shai-send-message "$cmd"

    # Clear input buffer
    BUFFER=""
    zle && zle reset-prompt
  else
    # Normal shell behavior
    zle .accept-line
  fi
}

# -----------------------------------------------------------------------------
# Wrap the accept-line widget to use our custom handler
# Done on first prompt to ensure proper initialization order
# -----------------------------------------------------------------------------
shai-wrap-accept-line() {
  zle -la accept-line &>/dev/null || return
  # Save original widget
  builtin zle -A accept-line shai-original-accept-line
  # Replace with our handler
  zle -N accept-line shai-accept-line
}

# Hook to wrap on first prompt
add-zsh-hook precmd shai-wrap-accept-line
