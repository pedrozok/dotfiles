export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="apple"

plugins=(git)

source $ZSH/oh-my-zsh.sh

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"

export PATH="$HOME/.local/bin:$PATH"

# rupa-z
. /opt/homebrew/etc/profile.d/z.sh


# Machine-specific config lives outside the repo.
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
