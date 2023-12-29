alias viedit="vim ~/.config/nvim/init.vim"
alias zshedit="vim ~/.zshrc"
alias brewdeps="brew deps --installed --tree"
alias gitclean="gco master && ggpull && git fetch && git branch | grep -v "master" | xargs git branch -D" # checkout to master, pull master, fetch and remove all other local branches except master
alias brew='env PATH="${PATH//$(pyenv root)\/shims:/}" brew' # Fix brew error due to pyenv
alias mvim='/Applications/MacVim.app/Contents/bin/gvim'
