if exists('g:loaded_cwd')
    finish
endif
let g:loaded_cwd = 1

" Inspiration: https://github.com/airblade/vim-rooter
" Similar Plugin: https://github.com/mattn/vim-findroot/blob/master/plugin/findroot.vim

" Init {{{1

const s:ROOT_MARKER =<< trim END
    .bzr/
    .git/
    .gitignore
    .hg/
    .svn/
    Rakefile
    _darcs/
END

const s:BLACKLIST =<< trim END

    git
    gitcommit
END

" Autocmd {{{1

augroup my_cwd | au!
    " `++nested` because: https://github.com/airblade/vim-rooter/commit/eef98131fef264d0f4e4f95c42e0de476c78009c
    au BufEnter * ++nested call s:cd_root()
augroup END

" Interface {{{1
fu s:cd_root() abort "{{{2
    " Changing the cwd automatically can lead to hard-to-debug issues.{{{
    "
    " It  only  makes sense  when  we're  working on  some  project  in a  known
    " programming language.
    "
    " In the  past, we had  several issues because we  changed the cwd  where it
    " didn't make sense; e.g.: https://github.com/justinmk/vim-dirvish/issues/168
    " Another issue was in an unexpected output of ``expand('`shell cmd`')``.
    "
    " I'm tired of finding bugs which no one else finds/can reproduce...
    "}}}
    if s:should_be_ignored() | return | endif

    " Why `resolve()`?{{{
    "
    " Useful when editing a file within a project from a symbolic link outside.
    "}}}
    let s:bufname = expand('<afile>:p')->resolve()
    if empty(s:bufname) | return | endif

    if s:is_special() | return | endif

    let root_dir = s:get_root_dir()
    if empty(root_dir)
        " Why this guard?{{{
        "
        "     $ cd /tmp; echo ''>r.vim; vim -S r.vim /tmp/r.vim
        "     Error detected while processing command line:~
        "     E484: Can't open file r.vim~
        "
        " More generally, any relative file path used in a `+''` command will be
        " completed with Vim's cwd.  If the latter is different than the shell's
        " cwd, this will lead to unexpected results.
        "}}}
        if !has('vim_starting')
            " Do *not* use `$HOME` as a default root directory!{{{
            "
            " Vim would be stuck for too much time after pressing:
            "
            "     :fin * C-d
            "
            " because there are a lot of files in our home.
            "}}}
            call s:set_cwd($HOME .. '/.vim')
        endif
    else
        " If we're in  `~/wiki/foo/bar.md`, we want the working  directory to be
        " `~/wiki/foo`, and not `~/wiki`.  So, we may need to add a path component.
        if s:in_wiki(root_dir)
            let dir_just_below = expand('<afile>:p')
                \ ->matchstr('^\V' .. escape(root_dir, '\') .. '\m/\zs[^/]*')
            let root_dir ..= '/' .. dir_just_below
        endif
        call s:set_cwd(root_dir)
    endif
endfu
" }}}1
" Core {{{1
fu s:get_root_dir() abort "{{{2
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

fu s:find_root_for_this_marker(pat) abort "{{{2
    let dir = isdirectory(s:bufname) ? s:bufname : fnamemodify(s:bufname, ':h')
    let dir_escaped = escape(dir, ' ')

    " `.git/`
    if s:is_directory(a:pat)
        let match = finddir(a:pat, dir_escaped .. ';')
    " `Rakefile`
    else
        let sua_save = &suffixesadd
        let &suffixesadd = ''
        let match = findfile(a:pat, dir_escaped .. ';')
        let &suffixesadd = sua_save
    endif

    if empty(match) | return '' | endif
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
        " It makes  more sense.  If we're  working in a file  under `.git/`, and
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

fu s:set_cwd(directory) abort "{{{2
    " Why `isdirectory(a:directory)`?{{{
    "
    "     :sp ~/wiki/non_existing_dir/file.md
    "     E344: Can't find directory "/home/user/wiki/non_existing_dir" in cdpath~
    "     E472: Command failed~
    "}}}
    if isdirectory(a:directory) && a:directory isnot# winnr()->getcwd()
        exe 'lcd ' .. fnameescape(a:directory)
    endif
endfu
" }}}1
" Utilities {{{1
fu s:should_be_ignored() abort "{{{2
    " Alternatively, you could use a whitelist, which by definition would be more restrictive.{{{
    "
    " Something like that:
    "
    "     return index(s:WHITELIST, &ft) == -1 || ...
    "}}}
    " Why the `filereadable()` condition?{{{
    "
    " If we're editing  a new file, we don't want  any discrepancy between Vim's
    " cwd  and the  shell's one.   Otherwise,  Vim could  write the  file in  an
    " unexpected location:
    "
    "     $ cd /tmp
    "     $ vim x/y.vim
    "     :echo expand('%:p')
    "     x/y.vim~
    "     :w
    "     :echo expand('%:p')
    "     ~/.vim/x/y.vim~
    "     " this is wrong; I would expect the new file to be written in `/tmp/x/y.vim`
    "
    " Here's what happens.
    " When we enter the buffer, `vim-cwd` resets Vim's cwd from `/tmp` to `~/.vim`.
    " Then, before writing the buffer, a custom autocmd in our vimrc runs this:
    "
    "     :call fnamemodify('x/y.vim', ':h')->mkdir()
    "     ⇔
    "     :call mkdir('x')
    "     ⇔
    "     " create directory `getcwd() .. '/x'`
    "     ⇔
    "     " create directory `~/.vim/x`
    "
    " Finally, Vim writes the file `~/.vim/x/y.vim`.
    "
    " ---
    "
    " You may wonder why this issue affects `$ vim x/y.vim`, but not `$ vim y.vim`.
    " Watch this:
    "
    "     $ rm -rf /tmp/a /tmp/b; mkdir -p /tmp/a /tmp/b && cd /tmp/a
    "     $ vim -Nu NONE +'cd /tmp/b' x/y
    "     :w
    "     E212~
    "     :call mkdir('/tmp/b/x')
    "     :w
    "     :echo expand('%:p')
    "     /tmp/b/x/y~
    "          ^
    "
    "     $ rm -rf /tmp/a /tmp/b; mkdir -p /tmp/a /tmp/b && cd /tmp/a
    "     $ vim -Nu NONE +'cd /tmp/b' y
    "     :w
    "     /tmp/a/y~
    "          ^
    "
    "     $ rm -rf /tmp/a /tmp/b; mkdir -p /tmp/a/x /tmp/b/x && cd /tmp/a
    "     $ vim -Nu NONE +'cd /tmp/b' x/y
    "     :w
    "     /tmp/a/x/y~
    "          ^
    "
    "     $ rm -rf /tmp/a /tmp/b; mkdir -p /tmp/a/x /tmp/b/x && cd /tmp/a
    "     $ vim -Nu NONE +'cd /tmp/b' y
    "     :w
    "     /tmp/a/y~
    "          ^
    "
    " It seems that most  of the time, Vim writes a file  (with a relative path)
    " in the cwd of the *shell*.  Except on one occasion; when:
    "
    "    - the file path contains a slash
    "    - there is no subdirectory in the shell's cwd matching the file's parent directory
    "
    " In that case, Vim writes the file in its *own* cwd.
    "
    " Note that changing  `+` with `--cmd` changes the name  of the buffer (from
    " relative to absolute), but it doesn't  change the file where the buffer is
    " written.
    "
    " ---
    "
    " What about a file path provided via `:e` instead of the shell's command-line?
    " In that case,  it seems that Vim always  uses its own cwd, at  the time of
    " the first successful writing of the buffer.
    "
    "     $ rm -rf /tmp/a /tmp/b; mkdir -p /tmp/a /tmp/b
    "     $ cd /tmp
    "     $ vim -Nu NONE
    "     :cd /tmp/a
    "     :e x/y
    "     :w
    "     E212~
    "     :cd /tmp/b
    "     :call mkdir('/tmp/b/x')
    "     :w
    "     /tmp/b/x/y~
    "          ^
    "}}}
    return index(s:BLACKLIST, &ft) != -1 || &bt != '' || !expand('<afile>:p')->filereadable()
endfu

fu s:is_directory(pat) abort "{{{2
    return a:pat[-1:-1] is# '/'
endfu

fu s:is_special() abort "{{{2
    " Why `isdirectory()`?{{{
    "
    " If we're moving in the filesystem with dirvish, or a similar plugin, while
    " working on  a project, we want  the cwd to  stay the same, and  not change
    " every time we go up/down into a directory to see its contents.
    "}}}
    return !empty(&bt) && !isdirectory(s:bufname)
endfu

fu s:in_wiki(root_dir) abort "{{{2
    return a:root_dir is# $HOME .. '/wiki' && expand('<afile>:p:h') isnot# $HOME .. '/wiki'
    "                                         ├───────────────────────────────────────────┘
    "                                         └ don't add any path component, if we're in `~/wiki/foo.md`{{{
    " Only if we're in `~/wiki/foo/bar.md`
    " Otherwise, we would end up with `let root_dir = ~/wiki/wiki`, which
    " doesn't exist.
    "}}}
endfu

