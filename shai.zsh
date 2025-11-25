# SHAI - Shell AI
# A ZSH plugin for AI-powered terminal assistance
# https://github.com/gevorggalstyan/shai
#
# MIT License - Copyright (c) 2024
# See LICENSE file for full license text

# Mode state
typeset -g SHAI_MODE=${SHAI_MODE:-shell}
typeset -g SHAI_DEPS_OK=1
typeset -g SHAI_SAVED_HIGHLIGHTERS=()
typeset -g SHAI_HIGHLIGHTING_DISABLED=0
typeset -g SHAI_HIGHLIGHTERS_WAS_SET=0
typeset -g SHAI_HIGHLIGHT_STYLES_WAS_SET=0
typeset -g SHAI_AUTOSUGGEST_WAS_SET=0
typeset -gA SHAI_SAVED_HIGHLIGHT_STYLES
typeset -g SHAI_SAVED_AUTOSUGGEST_STYLE=""
typeset -g SHAI_AUTOSUGGEST_SUSPENDED=0

# Model catalog - can be overridden by setting SHAI_MODEL_CHOICES before sourcing
# Format: "provider:model-id"
if (( ! ${+SHAI_MODEL_CHOICES} )); then
  typeset -ga SHAI_MODEL_CHOICES=(
    "anthropic:claude-sonnet-4-5"
    "anthropic:claude-opus-4-5"
    "openai:gpt-5.1"
    "openai:gpt-5.1-codex"
    "google:gemini-2.5-pro"
  )
fi

# Short names for prompt display - can be overridden
if (( ! ${+SHAI_MODEL_SHORT_NAMES} )); then
  typeset -gA SHAI_MODEL_SHORT_NAMES=(
    "claude-sonnet-4-5" "son4.5"
    "claude-opus-4-5" "opus4.5"
    "gpt-5.1" "gpt5.1"
    "gpt-5.1-codex" "cdx5.1"
    "gemini-2.5-pro" "gem2.5"
  )
fi
typeset -g SHAI_MODEL_INDEX=${SHAI_MODEL_INDEX:-1}
typeset -g SHAI_MODEL_STATE_FILE="$HOME/.config/shai/model_choice"

# Load saved model choice
shai-load-model-state() {
  [[ -f $SHAI_MODEL_STATE_FILE ]] || return
  local saved_index=$(<"$SHAI_MODEL_STATE_FILE")
  if [[ $saved_index =~ ^[0-9]+$ ]] && (( saved_index >= 1 && saved_index <= ${#SHAI_MODEL_CHOICES[@]} )); then
    SHAI_MODEL_INDEX=$saved_index
  fi
}

# Save model choice
shai-save-model-state() {
  mkdir -p "${SHAI_MODEL_STATE_FILE:h}" 2>/dev/null
  echo "$SHAI_MODEL_INDEX" > "$SHAI_MODEL_STATE_FILE" 2>/dev/null
}

# Load on startup
shai-load-model-state

# Prompt setup
setopt PROMPT_SUBST

shai-update-prompt() {
  if [[ $SHAI_MODE == ai ]]; then
    local entry=${SHAI_MODEL_CHOICES[$SHAI_MODEL_INDEX]}
    local model=${entry#*:}
    local short_name=${SHAI_MODEL_SHORT_NAMES[$model]:-$model}
    PROMPT="%F{yellow}★ ${short_name}%f %1~ %# "
  else
    PROMPT='%F{green}➜%f %1~ %# '
  fi
}

# Initialize prompt
shai-update-prompt

# Disable syntax highlighting
shai-disable-highlighting() {
  if (( SHAI_HIGHLIGHTING_DISABLED == 1 )); then
    return
  fi

  if typeset -p ZSH_HIGHLIGHT_HIGHLIGHTERS >/dev/null 2>&1; then
    SHAI_HIGHLIGHTERS_WAS_SET=1
    SHAI_SAVED_HIGHLIGHTERS=("${ZSH_HIGHLIGHT_HIGHLIGHTERS[@]}")
    ZSH_HIGHLIGHT_HIGHLIGHTERS=()
  else
    SHAI_HIGHLIGHTERS_WAS_SET=0
  fi

  if typeset -p ZSH_HIGHLIGHT_STYLES >/dev/null 2>&1; then
    SHAI_HIGHLIGHT_STYLES_WAS_SET=1
    SHAI_SAVED_HIGHLIGHT_STYLES=("${(@kv)ZSH_HIGHLIGHT_STYLES}")
    typeset -gA ZSH_HIGHLIGHT_STYLES
    ZSH_HIGHLIGHT_STYLES=()
  else
    SHAI_HIGHLIGHT_STYLES_WAS_SET=0
  fi

  if typeset -p ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE >/dev/null 2>&1; then
    SHAI_AUTOSUGGEST_WAS_SET=1
    SHAI_SAVED_AUTOSUGGEST_STYLE=$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='none'
  else
    SHAI_AUTOSUGGEST_WAS_SET=0
  fi

  typeset -ga region_highlight
  region_highlight=()
  SHAI_HIGHLIGHTING_DISABLED=1
}

# Restore syntax highlighting
shai-restore-highlighting() {
  if (( SHAI_HIGHLIGHTING_DISABLED == 0 )); then
    return
  fi

  if (( SHAI_HIGHLIGHTERS_WAS_SET == 1 )); then
    ZSH_HIGHLIGHT_HIGHLIGHTERS=("${SHAI_SAVED_HIGHLIGHTERS[@]}")
  else
    unset ZSH_HIGHLIGHT_HIGHLIGHTERS
  fi

  if (( SHAI_HIGHLIGHT_STYLES_WAS_SET == 1 )); then
    typeset -gA ZSH_HIGHLIGHT_STYLES
    ZSH_HIGHLIGHT_STYLES=("${(@kv)SHAI_SAVED_HIGHLIGHT_STYLES}")
  else
    unset ZSH_HIGHLIGHT_STYLES
  fi

  if (( SHAI_AUTOSUGGEST_WAS_SET == 1 )); then
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE=$SHAI_SAVED_AUTOSUGGEST_STYLE
  else
    unset ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE
  fi

  typeset -ga region_highlight
  region_highlight=()
  SHAI_HIGHLIGHTING_DISABLED=0
}

# Suspend autosuggest
shai-suspend-autosuggest() {
  if (( SHAI_AUTOSUGGEST_SUSPENDED == 1 )); then
    return
  fi
  zle >/dev/null 2>&1 || return

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

# Resume autosuggest
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

# Mode toggle function
shai-mode() {
  if [[ $SHAI_MODE == ai ]]; then
    SHAI_MODE=shell
    shai-restore-highlighting
    shai-resume-autosuggest
  else
    SHAI_MODE=ai
    shai-disable-highlighting
    shai-suspend-autosuggest

    # Check dependencies when switching to AI mode
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
zle -N shai-mode

# Model cycling (only in AI mode)
shai-model-next() {
  if [[ $SHAI_MODE == ai ]]; then
    SHAI_MODEL_INDEX=$(( (SHAI_MODEL_INDEX % ${#SHAI_MODEL_CHOICES[@]}) + 1 ))
    shai-save-model-state
    shai-update-prompt
    # Clear session to start fresh with new model
    SHAI_SESSION_ID=""
    rm -f "$SHAI_SESSION_FILE" 2>/dev/null
    zle && zle reset-prompt
  else
    zle down-line-or-history
  fi
}
zle -N shai-model-next

shai-model-prev() {
  if [[ $SHAI_MODE == ai ]]; then
    SHAI_MODEL_INDEX=$(( SHAI_MODEL_INDEX - 1 ))
    (( SHAI_MODEL_INDEX < 1 )) && SHAI_MODEL_INDEX=${#SHAI_MODEL_CHOICES[@]}
    shai-save-model-state
    shai-update-prompt
    # Clear session to start fresh with new model
    SHAI_SESSION_ID=""
    rm -f "$SHAI_SESSION_FILE" 2>/dev/null
    zle && zle reset-prompt
  else
    zle up-line-or-history
  fi
}
zle -N shai-model-prev

# Session reset (only in AI mode)
shai-new-session() {
  if [[ $SHAI_MODE == ai ]]; then
    SHAI_SESSION_ID=""
    rm -f "$SHAI_SESSION_FILE" 2>/dev/null
    print "Session cleared. Next message starts a new conversation."
    zle && zle reset-prompt
  fi
}
zle -N shai-new-session

# Keybindings
bindkey '^]' shai-mode              # Ctrl + ] : toggle mode
bindkey '^N' shai-model-next        # Ctrl + N : next model
bindkey '^P' shai-model-prev        # Ctrl + P : previous model
bindkey '^X' shai-new-session       # Ctrl + X : new session

# --- OpenCode Integration ---

# Server settings
typeset -g SHAI_TMPDIR="${TMPDIR:-/tmp}"
typeset -g SHAI_SERVER_PORT=${SHAI_SERVER_PORT:-4096}
typeset -g SHAI_SERVER_URL="http://localhost:$SHAI_SERVER_PORT"
typeset -g SHAI_SERVER_PID_FILE="$SHAI_TMPDIR/shai_server.pid"
typeset -g SHAI_SERVER_PORT_FILE="$SHAI_TMPDIR/shai_server.port"
typeset -g SHAI_SESSION_ID=""
typeset -g SHAI_SESSION_FILE="$SHAI_TMPDIR/shai_session_$$"
typeset -g SHAI_SERVER_REFCOUNT_FILE="$SHAI_TMPDIR/shai_server.refcount"
typeset -g SHAI_SERVER_LOCK_FILE="$SHAI_TMPDIR/shai_server.lock"
typeset -g SHAI_REGISTERED_WITH_SERVER=0

# Load session if exists
if [[ -f $SHAI_SESSION_FILE ]]; then
  SHAI_SESSION_ID=$(<"$SHAI_SESSION_FILE")
fi

# Acquire lock with timeout (returns 0 on success, 1 on failure)
shai-acquire-lock() {
  local max_attempts=50  # 5 seconds max
  local attempt=0

  while ! mkdir "$SHAI_SERVER_LOCK_FILE" 2>/dev/null; do
    (( attempt++ ))
    if (( attempt >= max_attempts )); then
      # Stale lock - force remove and retry once
      rmdir "$SHAI_SERVER_LOCK_FILE" 2>/dev/null
      if ! mkdir "$SHAI_SERVER_LOCK_FILE" 2>/dev/null; then
        return 1
      fi
      break
    fi
    sleep 0.1
  done
  return 0
}

# Release lock
shai-release-lock() {
  rmdir "$SHAI_SERVER_LOCK_FILE" 2>/dev/null
}

# Register this shell as using the server
shai-register-shell() {
  [[ $SHAI_REGISTERED_WITH_SERVER -eq 1 ]] && return

  shai-acquire-lock || return 1

  # Increment reference count
  local count=0
  [[ -f $SHAI_SERVER_REFCOUNT_FILE ]] && count=$(<"$SHAI_SERVER_REFCOUNT_FILE")
  echo $(( count + 1 )) > "$SHAI_SERVER_REFCOUNT_FILE"
  SHAI_REGISTERED_WITH_SERVER=1

  shai-release-lock
}

# Unregister this shell
shai-unregister-shell() {
  [[ $SHAI_REGISTERED_WITH_SERVER -eq 0 ]] && return

  shai-acquire-lock || return 1

  local count=1
  [[ -f $SHAI_SERVER_REFCOUNT_FILE ]] && count=$(<"$SHAI_SERVER_REFCOUNT_FILE")
  count=$(( count - 1 ))

  if (( count <= 0 )); then
    # Last shell - kill the server
    rm -f "$SHAI_SERVER_REFCOUNT_FILE"
    shai-kill-server
  else
    echo $count > "$SHAI_SERVER_REFCOUNT_FILE"
  fi

  SHAI_REGISTERED_WITH_SERVER=0
  shai-release-lock
}

# Kill the server
shai-kill-server() {
  if [[ -f $SHAI_SERVER_PID_FILE ]]; then
    local pid=$(<"$SHAI_SERVER_PID_FILE")
    if kill -0 $pid 2>/dev/null; then
      kill $pid 2>/dev/null
      local wait_count=0
      while kill -0 $pid 2>/dev/null && (( wait_count < 10 )); do
        sleep 0.1
        (( wait_count++ ))
      done
      kill -0 $pid 2>/dev/null && kill -9 $pid 2>/dev/null
    fi
    rm -f "$SHAI_SERVER_PID_FILE" "$SHAI_SERVER_PORT_FILE" 2>/dev/null
  fi
}

# Cleanup function on exit
shai-cleanup() {
  shai-unregister-shell
  rm -f "$SHAI_SESSION_FILE" 2>/dev/null
}

# Register cleanup on exit
trap shai-cleanup EXIT
autoload -Uz add-zsh-hook
add-zsh-hook zshexit shai-cleanup

# Manual cleanup function to kill all orphaned opencode servers
shai-kill-all-servers() {
  print "Killing all opencode servers..."
  # Find all opencode processes
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
  # Reset local state
  SHAI_REGISTERED_WITH_SERVER=0
}

# Ensure OpenCode server is running
shai-ensure-server() {
  # Check if we have a saved port from previous run
  if [[ -f $SHAI_SERVER_PORT_FILE ]]; then
    SHAI_SERVER_PORT=$(<"$SHAI_SERVER_PORT_FILE")
    SHAI_SERVER_URL="http://localhost:$SHAI_SERVER_PORT"
  fi

  # Check if server is already running and responding
  if [[ -f $SHAI_SERVER_PID_FILE ]]; then
    local pid=$(<"$SHAI_SERVER_PID_FILE")
    if kill -0 $pid 2>/dev/null; then
      # Process exists, check if server is responding
      if curl -s -f "$SHAI_SERVER_URL/session" --connect-timeout 2 -m 2 >/dev/null 2>&1; then
        # Server is running and responding - register and return
        shai-register-shell
        return 0
      fi
    fi
  fi

  # Try to find an available port starting from 4096
  local port=$SHAI_SERVER_PORT
  local max_port=$((port + 10))

  while (( port < max_port )); do
    # Use /dev/tcp for faster port checking
    if ! (echo >/dev/tcp/localhost/$port) 2>/dev/null; then
      # Port is available, start server
      setopt local_options no_notify no_monitor

      # Remove stale PID file to detect when new one is written
      rm -f "$SHAI_SERVER_PID_FILE"

      # Double-fork daemonization to fully detach from terminal
      (
        (
          opencode serve --port=$port >/dev/null 2>&1 </dev/null &
          echo $! > "$SHAI_SERVER_PID_FILE"
        ) &
      ) &

      # Wait for PID file to be written
      local wait_count=0
      while [[ ! -f $SHAI_SERVER_PID_FILE ]] && (( wait_count < 50 )); do
        sleep 0.02
        (( wait_count++ ))
      done

      echo $port > "$SHAI_SERVER_PORT_FILE"

      # Update URL with actual port
      SHAI_SERVER_PORT=$port
      SHAI_SERVER_URL="http://localhost:$port"

      # Wait for server to be ready (max 5 seconds)
      local max_attempts=25
      local attempt=0
      while (( attempt < max_attempts )); do
        if curl -s -f "$SHAI_SERVER_URL/session" --connect-timeout 1 -m 1 >/dev/null 2>&1; then
          # Server is ready - register and return
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

  # Server failed to start
  print "Error: Could not start OpenCode server (tried ports 4096-$((max_port-1)))"
  return 1
}

# Send message to AI
shai-send-message() {
  local message=$1

  # Ensure server is running
  shai-ensure-server || return 1

  # Create session if needed
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

    echo "$SHAI_SESSION_ID" > "$SHAI_SESSION_FILE"
  fi

  # Get provider and model
  local entry=${SHAI_MODEL_CHOICES[$SHAI_MODEL_INDEX]}
  local provider=${entry%%:*}
  local model=${entry#*:}

  # Send message
  local tmpfile=$(mktemp -t shai.XXXXXX)
  local json_payload=$(jq -n \
    --arg text "$message" \
    --arg provider "$provider" \
    --arg model "$model" \
    '{
      parts: [{type: "text", text: $text}],
      model: {providerID: $provider, modelID: $model}
    }')

  # Start spinner in background
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

  # Set up trap to handle Ctrl+C
  local cleanup_done=0
  TRAPINT() {
    if (( cleanup_done == 0 )); then
      cleanup_done=1
      # Kill spinner
      kill $spinner_pid 2>/dev/null
      wait $spinner_pid 2>/dev/null
      # Kill curl if it's running
      [[ -n $curl_pid ]] && kill $curl_pid 2>/dev/null
      printf "\r  \r"
      print "\n\033[33mRequest cancelled\033[0m"
      rm -f "$tmpfile" 2>/dev/null
      return 130
    fi
  }

  # Start curl in background so we can interrupt it
  curl -sS -X POST "$SHAI_SERVER_URL/session/$SHAI_SESSION_ID/message" \
    -H "Content-Type: application/json" \
    -d "$json_payload" \
    --connect-timeout 5 \
    --max-time 300 \
    --no-buffer > "$tmpfile" 2>&1 &
  curl_pid=$!

  # Wait for curl to complete
  wait $curl_pid 2>/dev/null
  local curl_status=$?

  # Stop spinner
  kill $spinner_pid 2>/dev/null
  wait $spinner_pid 2>/dev/null
  printf "\r  \r"

  # Unset trap
  unfunction TRAPINT 2>/dev/null

  # If cancelled, return early
  if (( cleanup_done == 1 )); then
    return 130
  fi

  # Display response
  if (( curl_status != 0 )); then
    local raw_error=$(<"$tmpfile")
    [[ -z $raw_error ]] && raw_error="Curl exited with status $curl_status and no output."
    print "Request failed (curl exit $curl_status):"
    print "$raw_error"
  else
    # Extract text to a temp file first, then cat it to avoid any piping issues
    local text_tmpfile=$(mktemp -t shai.XXXXXX)
    jq -r '.parts[] | select((.text? // "") != "") | .text' "$tmpfile" 2>/dev/null > "$text_tmpfile"
    
    if [[ -s $text_tmpfile ]]; then
      print "\033[33m★ ★ ★\033[0m"
      # Use cat to ensure complete output
      cat "$text_tmpfile"
      # Guarantee a trailing newline so the prompt never overwrites the last line
      [[ $(tail -c 1 "$text_tmpfile" | wc -l) -eq 0 ]] && printf '\n'
      print "\033[33m★ ★ ★\033[0m"
      rm -f "$text_tmpfile"
    else
      rm -f "$text_tmpfile"
      # Show error if present
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

# Accept line handler
shai-accept-line() {
  if [[ $SHAI_MODE == ai ]]; then
    # Check dependencies first
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

    # Empty input
    if [[ -z ${cmd//[[:space:]]/} ]]; then
      BUFFER=""
      zle && zle reset-prompt
      return 0
    fi

    # Send message
    shai-send-message "$cmd"

    # Reset
    BUFFER=""
    zle && zle reset-prompt
  else
    zle .accept-line
  fi
}

# Wrap accept-line widget
shai-wrap-accept-line() {
  zle -la accept-line &>/dev/null || return
  builtin zle -A accept-line shai-original-accept-line
  zle -N accept-line shai-accept-line
}

# Wrap on first prompt
add-zsh-hook precmd shai-wrap-accept-line
