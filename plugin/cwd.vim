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

" https://github.com/airblade/vim-rooter

" TODO:
" Study this plugin:
" https://github.com/mattn/vim-findroot/blob/master/plugin/findroot.vim

" TODO:
" Study which  path we can write  in a file in  a project, which will  work with
" `gf`. I mean, what's the impact of 'path'? How short can we write a path?

" Autocmd {{{1

augroup my_cwd
    au!
    au BufEnter  *  call s:cd_root()
    " au VimEnter,BufEnter  *  call s:cd_root()
    " au BufWritePost       *  call setbufvar('%', 'rootDir', '') | call s:cd_root()
augroup END

" Settings {{{1

let g:cwd_patterns = ['.git', '.git/', '_darcs/', '.hg/', '.bzr/', '.svn/']

fu! s:cd_root() abort "{{{1
    let s:fd = expand('%:p')

    if empty(s:fd)
        let s:fd = getcwd(winnr())
    endif

    " Resolve symbolic links before searching for the project root.
    " This is useful when  editing a file within a project  from a symbolic link
    " outside.
    let s:fd = resolve(s:fd)

    if s:is_special()
        return
    endif

    let root_dir = s:root_directory()
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

fu! s:root_dir_is_just_below(root_dir) abort "{{{1
    return a:root_dir is# $HOME.'/wiki' && expand('%:p:h') isnot# $HOME.'/wiki'
    "                                      ├──────────────────────────────────┘{{{
    "                                      └ don't add any path component, if we're in `~/wiki/foo.md`;
    "                                        only if we're in `~/wiki/foo/bar.md`
    "                                        Otherwise, we would end up with:
    "
    "                                            let root_dir = `~/wiki/wiki`, which doesn't exist.
    "}}}
endfu

fu! s:change_directory(directory) abort "{{{1
    if a:directory isnot# getcwd(winnr())
        exe 'lcd '.fnameescape(a:directory)
    endif
endfu

fu! s:find_ancestor(pattern) abort "{{{1
    let fd_dir = isdirectory(s:fd) ? s:fd : fnamemodify(s:fd, ':h')
    let fd_dir_escaped = escape(fd_dir, ' ')

    if s:is_directory(a:pattern)
        let match = finddir(a:pattern, fd_dir_escaped.';')
    else
        let [_suffixesadd, &suffixesadd] = [&suffixesadd, '']
        let match = findfile(a:pattern, fd_dir_escaped.';')
        let &suffixesadd = _suffixesadd
    endif

    if empty(match)
        return ''
    endif

    if s:is_directory(a:pattern)
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

fu! s:is_directory(pattern) abort "{{{1
    return stridx(a:pattern, '/') !=# -1
endfu

fu! s:is_special() abort "{{{1
    return !isdirectory(s:fd) && !empty(&buftype)
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

