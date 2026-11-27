export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="apple"

plugins=(git)

# Must be set before oh-my-zsh loads, or it pulls and runs upstream code on a timer.
zstyle ':omz:update' mode reminder

[[ -r "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

# Pasted commands can carry comments; a leading space keeps a command out of history.
setopt INTERACTIVE_COMMENTS HIST_IGNORE_SPACE

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_INSECURE_REDIRECT=1
# A cask without a pinned checksum refuses to install; get that app from its vendor instead.
export HOMEBREW_CASK_OPTS=--require-sha
export PIP_REQUIRE_VIRTUALENV=true

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init - zsh)"
command -v rbenv >/dev/null && eval "$(rbenv init - zsh)"

export PATH="$HOME/.local/bin:$PATH"

# rupa-z
[[ -r /opt/homebrew/etc/profile.d/z.sh ]] && . /opt/homebrew/etc/profile.d/z.sh

# jdk 17 | jdk 21. Needs the JDK symlinks in /Library/Java/JavaVirtualMachines (see README).
jdk() {
  local home
  home="$(/usr/libexec/java_home -F -v "$1")" || return 1
  export JAVA_HOME="$home"
  java -version
}

# withsecrets .env.op npm run dev. Secrets stay in memory; nothing starts if they cannot be read.
# In WSL op is the Windows op.exe, which cannot start Linux programs, so it only resolves the values.
withsecrets() {
  local file="$1"; shift
  if command -v op >/dev/null; then
    op run --env-file="$file" -- "$@"
    return
  fi
  local resolved
  resolved="$(op.exe inject < "$file")" || { echo "withsecrets: op.exe failed, nothing was started" >&2; return 1; }
  (
    while IFS='=' read -r key value; do
      [[ -z "$key" || "$key" == \#* ]] && continue
      export "$key=$value"
    done <<< "${resolved//$'\r'/}"
    exec "$@"
  )
}

# Machine-specific config lives outside the repo.
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
