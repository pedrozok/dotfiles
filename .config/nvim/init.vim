call plug#begin('~/.vim/plugged')
    " Defaults
    Plug 'tpope/vim-sensible'
    " Themes
    Plug 'joshdick/onedark.vim'
    Plug 'morhetz/gruvbox'
    Plug 'nanotech/jellybeans.vim'
    Plug 'overcache/NeoSolarized'
    " Fuzzy file search
    Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
    Plug 'junegunn/fzf.vim'
    " Explorer
    Plug 'preservim/nerdtree'
    " Conquer of completion
    Plug 'neoclide/coc.nvim', {'branch': 'release'}
    " Airline
    Plug 'vim-airline/vim-airline'
    Plug 'vim-airline/vim-airline-themes'
    " Git
    Plug 'APZelos/blamer.nvim'
    " Other utilities
    Plug 'preservim/nerdcommenter'
    Plug 'christoomey/vim-tmux-navigator'
    Plug 'tpope/vim-surround'
call plug#end()

" neovim settings
set nocompatible
"set background=dark " Solarized theme
"let g:neosolarized_contrast = "high"
"colorscheme NeoSolarized
colorscheme onedark
syntax enable                           " Enables syntax highlighing
set backspace=indent,eol,start
set noswapfile
set hidden                              " Required to keep multiple buffers open multiple buffers
set nowrap                              " Display long lines as just one line
set encoding=utf-8                      " The encoding displayed
set fileencoding=utf-8                  " The encoding written to file
set ruler                               " Show the cursor position all the time
set mouse=a                             " Enable your mouse
set splitbelow                          " Horizontal splits will automatically be below
set splitright                          " Vertical splits will automatically be to the right
set t_Co=256                            " Support 256 colors
set number                              " Line numbers
set cursorline                          " Enable highlighting of the current line
set nobackup                            " This is recommended by coc
set nowritebackup                       " This is recommended by coc
set updatetime=300                      " Faster completion
set timeoutlen=500                      " By default timeoutlen is 1000 ms
set tabstop=2                           " number of visual spaces per TAB
set softtabstop=2                       " number of spaces in tab when editing
set shiftwidth=2                        " number of spaces to use for autoindent
set expandtab                           " tabs are space
set autoindent
set copyindent                          " copy indent from the previous line
set termguicolors
if system('uname -s') == "Darwin\n"
  set clipboard=unnamed "OSX
else
  set clipboard=unnamedplus "Linux
endif
" set clipboard=unnamedplus             " Copy paste between vim and everything else
set ignorecase                          " ignore case when searching
set smartcase                           " ignore case if search pattern is lower case
set laststatus=2
au! BufWritePost $MYVIMRC source %      " auto source when writing to init.vm alternatively you can run :source $MYVIMRC

" neovide font
set guifont=Monaco:h12
let &t_SI = "\e[6 q"                    " Make cursor a line in insert
let &t_EI = "\e[2 q"                    " Make cursor a line in insert

" fzf
set rtp+=/opt/homebrew/opt/fzf


filetype plugin on

let g:blamer_enabled = 1

let g:airline_theme='dark'

" NERDTree configs
let g:NERDTreeIgnore = ['^node_modules$', '\.pyc$', '__pycache__']
let NERDTreeShowHidden=1

" Coc config
let g:coc_global_extensions = [
  \ 'coc-snippets',
  \ 'coc-pairs',
  \ 'coc-tsserver',
  \ 'coc-eslint', 
  \ 'coc-prettier', 
  \ 'coc-json', 
  \ ]

" Keymaps
map <Esc><Esc> :w<CR>
" Shift up, Shift down, line up/down
nnoremap <S-Up> :m-2<CR>
nnoremap <S-Down> :m+<CR>
inoremap <S-Up> <Esc>:m-2<CR>
inoremap <S-Down> <Esc>:m+<CR>
" Nerdtree
nnoremap <leader>n :NERDTreeFocus<CR>
nnoremap <C-n> :NERDTree<CR>
nnoremap <C-t> :NERDTreeToggle<CR>
nnoremap <C-f> :NERDTreeFind<CR>
" File searching/browsing
nmap <C-p> :FZF<CR>
nnoremap <c-g> :Rg<cr>
" Window splitting shortcuts
" Navigate splits with ctrl-(j/k/l/h)
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>
" Tab management
nnoremap H gT
nnoremap L gt
" accept autocomplete
"inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm() : "\<CR>"
inoremap <silent><expr> <TAB>
      \ coc#pum#visible() ? coc#pum#next(1) :
      \ CheckBackspace() ? "\<Tab>" :
      \ coc#refresh()
inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

" Make <CR> to accept selected completion item or notify coc.nvim to format
" <C-g>u breaks current undo, please make your own choice
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm()
                              \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"


function! CheckBackspace() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction


" Use <c-space> to trigger completion
if has('nvim')
  inoremap <silent><expr> <c-space> coc#refresh()
else
  inoremap <silent><expr> <c-@> coc#refresh()
endif

" Experimental stuf
command! -nargs=0 Prettier :CocCommand prettier.formatFile
