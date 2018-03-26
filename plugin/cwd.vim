if exists('g:loaded_cwd')
    finish
endif
let g:loaded_cwd = 1

" https://github.com/airblade/vim-rooter

" Integrate this: {{{1

if has('vim_starting') && $PWD is# $HOME
    " Why a timer?{{{
    "
    "     $ cd
    "     $ grep -noH pat *
    "     $ vim -q <(!!)
    "
    "             The path to the matches would be prefixed with `~/.vim`, instead of `~`.
    "}}}
    " call timer_start(0, {-> execute('cd $HOME/.vim')})
endif

nno  <silent><unique>  d.  :<c-u>call <sid>cd_to_project_root(0)<cr>
nno  <silent><unique>  d:  :<c-u>call <sid>cd_to_project_root(1)<cr>

fu! s:cd_to_project_root(locally) abort
    let dir = expand('%:p')

    let known_dirs = [ 'autoload',
    \                  'colors',
    \                  'compiler',
    \                  'doc',
    \                  'ftdetect',
    \                  'ftplugin',
    \                  'indent',
    \                  'plugin',
    \                  'syntax',
    \                  'CODE' ]

    let guard = 0
    while guard <= 100
        let dir = fnamemodify(dir, ':h')
        if index(known_dirs, fnamemodify(dir, ':t')) >= 0
            let dir = fnamemodify(dir, ':h:t') is# 'after'
                  \ ?     fnamemodify(dir, ':h:h')
                  \ :     fnamemodify(dir, ':h')
            break
        endif
        let guard += 1
    endwhile
    if dir isnot# '/' && isdirectory(dir)
        exe (a:locally ? 'l' : '').'cd '.dir
    endif
    pwd
endfu

nno  <silent><unique>  d~  :<c-u>call <sid>reset_working_directory()<cr>

fu! s:reset_working_directory() abort
    let orig = win_getid()
    sil tabdo windo cd $HOME/.vim
    call win_gotoid(orig)
    call timer_start(0, {-> execute('pwd', '')})
endfu

" Command {{{1

com! Cwd  call cwd#cd_to_project_root()

" Autocmd {{{1

augroup my_cwd
    au!
    au VimEnter,BufEnter  *  Cwd
    au BufWritePost       *  call setbufvar('%', 'rootDir', '') | Cwd
augroup END

" Settings {{{1

let g:cwd_use_lcd = 0

let g:cwd_patterns = ['.git', '.git/', '_darcs/', '.hg/', '.bzr/', '.svn/']

let g:cwd_targets = '/,*'

let g:cwd_change_directory_for_non_project_files = ''

let g:cwd_silent_chdir = 0

let g:cwd_resolve_links = 0

fu! Find_root_directory() abort "{{{1
" For third-parties.  Not used by plugin.
    let s:fd = expand('%:p')

    if empty(s:fd)
        let s:fd = getcwd()
    endif

    if g:cwd_resolve_links
        let s:fd = resolve(s:fd)
    endif

    if !s:change_directory_for_buffer()
        return ''
    endif

    return s:root_directory()
endfu

