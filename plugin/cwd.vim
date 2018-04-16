if exists('g:loaded_cwd')
    finish
endif
let g:loaded_cwd = 1

" https://github.com/airblade/vim-rooter

" TODO:
" :tabedit $MYVIMRC
" :fin * C-d
" Why do these suggestions use full paths?:
"
"         /home/user/.vim/plugged/
"         /home/user/.vim/plugin/
"         /home/user/.vim/pythonx/
"         /home/user/.vim/tags
"
" All the other ones don't.
" Also, why does it occur only when we do `:set path=.,**` but not `set path=.`?
"
" Theory:
" Maybe it's because there's a `tags` file in the working directory.
" And a `plugin/` directory, which begins with the letter `p`.
" So, there may be some kind of ambiguity with all suggestions coming from
" the directory of the current file, when their name is begin with `t` or `p`.

" TODO:
" Study which  path we can write  in a file in  a project, which will  work with
" `gf`. I mean, what's the impact of 'path'? How short can we write a path?

" TODO:
" `latex/`, `terminal/`, `vim/`, ... should  be automatically set as the working
" directory when we're reading our notes or working on our exercises.

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

com! Cwd  call s:cd_to_project_root()

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

let g:cwd_silent_chdir = 1

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

fu! s:cd_to_project_root() abort "{{{1
    let s:fd = expand('%:p')

    if empty(s:fd)
        let s:fd = getcwd()
    endif

    if g:cwd_resolve_links
        let s:fd = resolve(s:fd)
    endif

    if !s:change_directory_for_buffer()
        return
    endif

    let root_dir = s:root_directory()
    if empty(root_dir)
        " Test against 1 for backwards compatibility
        if g:cwd_change_directory_for_non_project_files ==# 1 ||
        \ g:cwd_change_directory_for_non_project_files is? 'current'
            if expand('%') isnot# ''
                call s:change_directory(fnamemodify(s:fd, ':h'))
            endif
        elseif g:cwd_change_directory_for_non_project_files is? 'home'
            call s:change_directory($HOME)
        endif
    else
        call s:change_directory(root_dir)
    endif
endfu

fu! s:change_directory(directory) abort "{{{1
    if a:directory isnot# getcwd()
        let cmd = g:cwd_use_lcd ==# 1 ? 'lcd' : 'cd'
        exe cmd.' '.fnameescape(a:directory)
        if !g:cwd_silent_chdir
            echo 'cwd: '.a:directory
        endif
        sil do <nomodeline> User CwdChDir
    endif
endfu

fu! s:change_directory_for_buffer() abort "{{{1
    let patterns = split(g:cwd_targets, ',')

    if isdirectory(s:fd)
        return index(patterns, '/') !=# -1
    endif

    if filereadable(s:fd) && empty(&buftype)
        for p in patterns
            if p isnot# '/' && s:fd =~# glob2regpat(p)
                return 1
            endif
        endfor
    endif

    return 0
endfu

fu! s:find_ancestor(pattern) abort "{{{1
    let fd_dir = isdirectory(s:fd) ? s:fd : fnamemodify(s:fd, ':h')

    if s:is_directory(a:pattern)
        let match = finddir(a:pattern, fnameescape(fd_dir).';')
    else
        let [_suffixesadd, &suffixesadd] = [&suffixesadd, '']
        let match = findfile(a:pattern, fnameescape(fd_dir).';')
        let &suffixesadd = _suffixesadd
    endif

    if empty(match)
        return ''
    endif

    return s:is_directory(a:pattern)
    \ ?        fnamemodify(match, ':p:h:h')
    \ :        fnamemodify(match, ':p:h')
endfu

fu! s:is_directory(pattern) abort "{{{1
    return stridx(a:pattern, '/') !=# -1
endfu

fu! s:root_directory() abort "{{{1
    let root_dir = getbufvar('%', 'rootDir')
    if empty(root_dir)
        let root_dir = s:search_for_root_directory()
        if !empty(root_dir)
            call setbufvar('%', 'rootDir', root_dir)
        endif
    endif
    return root_dir
endfu

fu! s:search_for_root_directory() abort "{{{1
    for pattern in g:cwd_patterns
        let result = s:find_ancestor(pattern)
        if !empty(result)
            return result
        endif
    endfor
    return ''
endfu

