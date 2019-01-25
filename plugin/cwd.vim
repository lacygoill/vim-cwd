if exists('g:loaded_cwd')
    finish
endif
let g:loaded_cwd = 1

" Read This:{{{
"
" The concept of working directory is local to a window.
"
" `:pwd` and `getcwd()`  give the local working directory if  there's one in the
" current window, or the global one otherwise
"
" `getcwd(-1)` gives the global directory, and `getcwd(winnr())` the local one.
"}}}

" Inspiration: https://github.com/airblade/vim-rooter

" TODO:
" Study this plugin:
" https://github.com/mattn/vim-findroot/blob/master/plugin/findroot.vim

" Autocmd {{{1

augroup my_cwd
    au!
    au VimEnter,BufEnter  *  call s:cd_root()
augroup END

" Interface {{{1
fu! s:cd_root() abort "{{{2
    let s:bufname = expand('%:p')

    if empty(s:bufname)
        let s:bufname = getcwd(winnr())
    endif

    " Resolve symbolic links before searching for the project root.
    " This is useful when  editing a file within a project  from a symbolic link
    " outside.
    let s:bufname = resolve(s:bufname)

    if s:is_special()
        return
    endif

    let root_dir = s:get_root_dir()
    if empty(root_dir)
        " Do NOT use `$HOME` as a default root directory!{{{
        "
        " Vim would be stuck for too much time after pressing:
        "
        "     :fin * C-d
        "
        " because there are a lot of files in our home.
        "}}}
        call s:change_directory($HOME.'/.vim')
    else
        " If we're in  `~/wiki/foo/bar.md`, we want the working  directory to be
        " `~/wiki/foo`, and not `~/wiki`. So, we may need to add a path component.
        if s:root_dir_is_just_below(root_dir)
            let root_dir .= '/'.expand('%:p:h:t')
        endif
        call s:change_directory(root_dir)
    endif
endfu
" }}}1
" Core {{{1
fu! s:get_root_dir() abort "{{{2
    let root_dir = getbufvar('%', 'root_dir')
    if empty(root_dir)
        for pat in ['.git/', '_darcs/', '.hg/', '.bzr/', '.svn/']
            let root_dir = s:find_root_dir(pat)
            if !empty(root_dir)
                break
            endif
        endfor
        if !empty(root_dir)
            " cache the result
            call setbufvar('%', 'root_dir', root_dir)
        endif
    endif
    return root_dir
endfu

fu! s:find_root_dir(pat) abort "{{{2
    let fd_dir = isdirectory(s:bufname) ? s:bufname : fnamemodify(s:bufname, ':h')
    let fd_dir_escaped = escape(fd_dir, ' ')

    if s:is_directory(a:pat)
        let match = finddir(a:pat, fd_dir_escaped.';')
    else
        let [_suffixesadd, &suffixesadd] = [&suffixesadd, '']
        let match = findfile(a:pat, fd_dir_escaped.';')
        let &suffixesadd = _suffixesadd
    endif

    if empty(match)
        return ''
    endif

    if s:is_directory(a:pat)
        " If the directory we found (`match`) is  part of the file's path, it is
        " the project root and we return it.
        " Otherwise,  the directory  we found  is contained  within the  project
        " root, so return its parent i.e. the project root.
        let fd_match = fnamemodify(match, ':p:h')
        return stridx(fd_dir, fd_match) == 0
            \ ?     fd_match
            \ :     fnamemodify(match, ':p:h:h')
    else
        return fnamemodify(match, ':p:h')
    endif
endfu

fu! s:change_directory(directory) abort "{{{2
    if a:directory isnot# getcwd(winnr())
        exe 'lcd '.fnameescape(a:directory)
    endif
endfu

" }}}1
" Utilities {{{1
fu! s:is_directory(pat) abort "{{{2
    return stridx(a:pat, '/') !=# -1
endfu

fu! s:is_special() abort "{{{2
    return !isdirectory(s:bufname) && !empty(&buftype)
endfu

fu! s:root_dir_is_just_below(root_dir) abort "{{{2
    return a:root_dir is# $HOME.'/wiki' && expand('%:p:h') isnot# $HOME.'/wiki'
    "                                      ├──────────────────────────────────┘{{{
    "                                      └ don't add any path component, if we're in `~/wiki/foo.md`;
    "                                        only if we're in `~/wiki/foo/bar.md`
    "                                        Otherwise, we would end up with:
    "
    "                                            let root_dir = `~/wiki/wiki`, which doesn't exist.
    "}}}
endfu

