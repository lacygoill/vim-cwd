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
" Similar Plugin: https://github.com/mattn/vim-findroot/blob/master/plugin/findroot.vim

" Init {{{1

let s:ROOT_MARKER = [
    \ '.bzr/',
    \ '.git/',
    \ '.gitignore',
    \ '.hg/',
    \ '.svn/',
    \ 'Rakefile',
    \ '_darcs/',
    \ ]

" Autocmd {{{1

augroup my_cwd
    au!
    au BufEnter * call s:cd_root()
augroup END

" Interface {{{1
fu! s:cd_root() abort "{{{2
    " Why `resolve()`?{{{
    "
    " Useful when editing a file within a project from a symbolic link outside.
    "}}}
    let s:bufname = resolve(expand('%:p'))
    if empty(s:bufname)
        return
    endif

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
            let dir_just_below = matchstr(expand('%:p'), '\m\C^' . root_dir . '/\zs[^/]*')
            let root_dir ..= '/' . dir_just_below
        endif
        call s:change_directory(root_dir)
    endif
endfu
" }}}1
" Core {{{1
fu! s:get_root_dir() abort "{{{2
    let root_dir = getbufvar('%', 'root_dir', '')
    if empty(root_dir)
        for pat in s:ROOT_MARKER
            let root_dir = s:find_root_for_this_marker(pat)
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

fu! s:find_root_for_this_marker(pat) abort "{{{2
    let dir = isdirectory(s:bufname) ? s:bufname : fnamemodify(s:bufname, ':h')
    let dir_escaped = escape(dir, ' ')

    " `.git/`
    if s:is_directory(a:pat)
        let match = finddir(a:pat, dir_escaped.';')
    " `Rakefile`
    else
        let sua_save = &suffixesadd
        let &suffixesadd = ''
        let match = findfile(a:pat, dir_escaped.';')
        let &suffixesadd = sua_save
    endif

    if empty(match)
        return ''
    endif
    " `match` should be sth like:{{{
    "
    "    - /path/to/.git/
    "    - /path/to/Rakefile
    "    ...
    "}}}

    " `.git/`
    if s:is_directory(a:pat)
        " Why `return full_match` ?{{{
        "
        " If our current file is under the directory where what we found (`match`) is:
        "
        "     /path/to/.git/my/file
        "     ├───────────┘
        "     └ `match`
        "
        " We don't want `/path/to` to be the root of our project.
        " Instead we prefer `/path/to/.git`.
        " So, we return the latter.
        "
        " It makes  more sense. If we're  working in  a file under  `.git/`, and
        " we're looking for some info, we probably want our search to be limited
        " to only the  files in `.git/`, and  not also include the  files of the
        " working tree.
        "}}}
        " Why `:p:h`?  Isn't `:p` enough?{{{
        "
        " `:p` will add a trailing slash, wich may interfere:
        "
        "                                                  v
        "     let full_match = '~/.vim/plugged/vim-cwd/.git/'
        "     let dir = '~/.vim/plugged/vim-cwd/.git'
        "     echo stridx(dir, full_match)
        "     -1~
        "
        " `:h` will remove this trailing slash:
        "
        "     let full_match = '~/.vim/plugged/vim-cwd/.git'
        "     let dir = '~/.vim/plugged/vim-cwd/.git'
        "     echo stridx(dir, full_match)
        "     0~
        "}}}
        let full_match = fnamemodify(match, ':p:h')
        if stridx(dir, full_match) == 0
            return full_match
        " Otherwise, what we found is contained right below the project root, so
        " we return its parent.
        else
            return fnamemodify(match, ':p:h:h')
        endif
    " `Rakefile`
    else
        return fnamemodify(match, ':p:h')
    endif
endfu

fu! s:change_directory(directory) abort "{{{2
    " Why `isdirectory(a:directory)`?{{{
    "
    "     :sp ~/wiki/non_existing_dir/file.md
    "     E344: Can't find directory "/home/user/wiki/non_existing_dir" in cdpath~
    "     E472: Command failed~
    "}}}
    if isdirectory(a:directory) && a:directory isnot# getcwd(winnr())
        exe 'lcd '.fnameescape(a:directory)
    endif
endfu
" }}}1
" Utilities {{{1
fu! s:is_directory(pat) abort "{{{2
    return stridx(a:pat, '/') != -1
endfu

fu! s:is_special() abort "{{{2
    " Why `isdirectory()`?{{{
    "
    " If we're moving in the filesystem with dirvish, or a similar plugin, while
    " working on  a project, we want  the cwd to  stay the same, and  not change
    " every time we go up/down into a directory to see its contents.
    "}}}
    return !empty(&buftype) && !isdirectory(s:bufname)
endfu

fu! s:root_dir_is_just_below(root_dir) abort "{{{2
    return a:root_dir is# $HOME.'/wiki' && expand('%:p:h') isnot# $HOME.'/wiki'
    "                                      ├──────────────────────────────────┘
    "                                      └ don't add any path component, if we're in `~/wiki/foo.md`{{{
    " Only if we're in `~/wiki/foo/bar.md`
    " Otherwise, we would end up with `let root_dir = ~/wiki/wiki`, which
    " doesn't exist.
    "}}}
endfu

