vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Inspiration: https://github.com/airblade/vim-rooter
# Similar Plugin: https://github.com/mattn/vim-findroot/blob/master/plugin/findroot.vim

# Config {{{1

const ROOT_MARKER: list<string> =<< trim END
    .bzr/
    .git/
    .gitignore
    .hg/
    .svn/
    Rakefile
    _darcs/
END

const BLACKLIST: list<string> =<< trim END

    git
    gitcommit
END

# Declarations {{{1

var bufname: string

import REPO_ROOT from 'cwd.vim'

# Autocmd {{{1

augroup MyCwd | autocmd!
    # `++nested` because: https://github.com/airblade/vim-rooter/commit/eef98131fef264d0f4e4f95c42e0de476c78009c
    # `BufReadPost` is not frequent enough.{{{
    #
    # For example,  if – for  some reason –  the cwd has  been wrongly set  in a
    # window, after saving/restoring  a session, it remains  wrong.  Our autocmd
    # should fix this automatically.
    #
    # ---
    #
    # If you notice other cases where  the cwd has not been correctly set/fixed,
    # just listen to `BufEnter`.
    #}}}
    autocmd BufWinEnter * ++nested CdRoot()
augroup END

# Interface {{{1
def CdRoot() #{{{2
    # Changing the cwd automatically can lead to hard-to-debug issues.{{{
    #
    # It  only makes  sense when  we're working  on some  repository in  a known
    # programming language.
    #
    # In the  past, we had  several issues because we  changed the cwd  where it
    # didn't make sense; e.g.: https://github.com/justinmk/vim-dirvish/issues/168
    # Another issue was in an unexpected output of ``expand('`shell cmd`')``.
    #
    # I'm tired of finding bugs which no one else finds/can reproduce...
    #}}}
    if ShouldBeIgnored()
        return
    endif

    # Why `resolve()`?{{{
    #
    # Useful when editing a file within a repository from a symbolic link outside.
    #}}}
    bufname = expand('<afile>:p')->resolve()
    if empty(bufname)
        return
    endif

    if IsSpecial()
        return
    endif

    var repo_root: string = GetRootDir()
    if empty(repo_root)
        # Why this guard?{{{
        #
        #     $ cd /tmp; echo ''>r.vim; vim -S r.vim /tmp/r.vim
        #     Error detected while processing command line:˜
        #     E484: Can't open file r.vim˜
        #
        # More generally, any relative file path used in a `+''` command will be
        # completed with Vim's cwd.  If the latter is different than the shell's
        # cwd, this will lead to unexpected results.
        #}}}
        if !has('vim_starting')
            # Do *not* use `$HOME` as a default root directory!{{{
            #
            # Vim would be stuck for too much time after pressing:
            #
            #     :fin * C-d
            #
            # because there are a lot of files in our home.
            #}}}
            SetCwd($HOME .. '/.vim')
        endif
    else
        # If we're in  `~/wiki/foo/bar.md`, we want the working  directory to be
        # `~/wiki/foo`, and not `~/wiki`.  So, we might need to add a path component.
        if InSubWiki(repo_root)
            var dir_just_below: string = expand('<afile>:p')
                ->matchstr('^\V' .. escape(repo_root, '\') .. '\m' .. '/\zs[^/]*')
            repo_root ..= '/' .. dir_just_below
        endif
        SetCwd(repo_root)
    endif
enddef
# }}}1
# Core {{{1
def GetRootDir(): string #{{{2
    var repo_root: string = getbufvar('%', REPO_ROOT, '')
    if empty(repo_root)
        for pat in ROOT_MARKER
            repo_root = FindRootForThisMarker(pat)
            if !empty(repo_root)
                break
            endif
        endfor
        if !empty(repo_root)
            # cache the result
            setbufvar('%', REPO_ROOT, repo_root)
            # We need to fire this event for `vim-indent`.
            if exists('#IndentSettings#User')
                doautocmd <nomodeline> User RepoRootIsCached
            endif
        endif
    endif
    return repo_root
enddef

def FindRootForThisMarker(pat: string): string #{{{2
    var dir: string = bufname->isdirectory() ? bufname : bufname->fnamemodify(':h')
    var dir_escaped: string = escape(dir, ' ')

    var match: string
    # `.git/`
    if pat->IsDirectory()
        match = finddir(pat, dir_escaped .. ';')
    # `Rakefile`
    else
        var suffixesadd_save: string = &suffixesadd
        &suffixesadd = ''
        match = findfile(pat, dir_escaped .. ';')
        &suffixesadd = suffixesadd_save
    endif

    if empty(match)
        return ''
    endif
    # `match` should be sth like:{{{
    #
    #    - /path/to/.git/
    #    - /path/to/Rakefile
    #    ...
    #}}}

    # `.git/`
    if pat->IsDirectory()
        # Why `return full_match` ?{{{
        #
        # If our current file is under the directory where what we found (`match`) is:
        #
        #     /path/to/.git/my/file
        #     ├───────────┘
        #     └ `match`
        #
        # We don't want `/path/to` to be the root of our repository.
        # Instead we prefer `/path/to/.git`.
        # So, we return the latter.
        #
        # It makes  more sense.  If we're  working in a file  under `.git/`, and
        # we're looking for some info, we probably want our search to be limited
        # to only the  files in `.git/`, and  not also include the  files of the
        # working tree.
        #}}}
        # Why `:p:h`?  Isn't `:p` enough?{{{
        #
        # `:p` will add a trailing slash, wich may interfere:
        #
        #                                                            v
        #     var full_match: string = '~/.vim/pack/mine/opt/cwd/.git/'
        #     var dir: string = '~/.vim/pack/mine/opt/cwd/.git'
        #     echo stridx(dir, full_match)
        #     -1˜
        #
        # `:h` will remove this trailing slash:
        #
        #     var full_match: string = '~/.vim/pack/mine/opt/cwd/.git'
        #     var dir: string = '~/.vim/pack/mine/opt/cwd/.git'
        #     echo stridx(dir, full_match)
        #     0˜
        #}}}
        var full_match: string = match->fnamemodify(':p:h')
        if stridx(dir, full_match) == 0
            return full_match
        # Otherwise, what  we found  is contained  right below  the root  of the
        # repository, so we return its parent.
        else
            return match->fnamemodify(':p:h:h')
        endif
    # `Rakefile`
    else
        return match->fnamemodify(':p:h')
    endif
enddef

def SetCwd(dir: string) #{{{2
    # Why `!dir->isdirectory()`?{{{
    #
    #     :split ~/wiki/non_existing_dir/file.md
    #     E344: Can't find directory "/home/user/wiki/non_existing_dir" in cdpath˜
    #     E472: Command failed˜
    #}}}
    if !dir->isdirectory() || dir == winnr()->getcwd()
        return
    endif
    execute 'lcd ' .. dir->fnameescape()
enddef
# }}}1
# Utilities {{{1
def ShouldBeIgnored(): bool #{{{2
    # Alternatively, you could use a whitelist, which by definition would be more restrictive.{{{
    #
    # Something like that:
    #
    #     return index(WHITELIST, &filetype) == -1 || ...
    #}}}
    # Why the `filereadable()` condition?{{{
    #
    # If we're editing  a new file, we don't want  any discrepancy between Vim's
    # cwd  and the  shell's one.   Otherwise,  Vim could  write the  file in  an
    # unexpected location:
    #
    #     $ cd /tmp
    #     $ vim x/y.vim
    #     :echo expand('%:p')
    #     x/y.vim˜
    #     :write
    #     :echo expand('%:p')
    #     ~/.vim/x/y.vim˜
    #     " this is wrong; I would expect the new file to be written in `/tmp/x/y.vim`
    #
    # Here's what happens.
    # When we enter the buffer, `vim-cwd` resets Vim's cwd from `/tmp` to `~/.vim`.
    # Then, before writing the buffer, a custom autocmd in our vimrc runs this:
    #
    #     :call fnamemodify('x/y.vim', ':h')->mkdir()
    #     ⇔
    #     :call mkdir('x')
    #     ⇔
    #     " create directory `getcwd() .. '/x'`
    #     ⇔
    #     " create directory `~/.vim/x`
    #
    # Finally, Vim writes the file `~/.vim/x/y.vim`.
    #
    # ---
    #
    # You may wonder why this issue affects `$ vim x/y.vim`, but not `$ vim y.vim`.
    # Watch this:
    #
    #     $ rm -rf /tmp/a /tmp/b; mkdir -p /tmp/a /tmp/b && cd /tmp/a
    #     $ vim -Nu NONE +'cd /tmp/b' x/y
    #     :write
    #     E212˜
    #     :call mkdir('/tmp/b/x')
    #     :write
    #     :echo expand('%:p')
    #     /tmp/b/x/y˜
    #          ^
    #
    #     $ rm -rf /tmp/a /tmp/b; mkdir -p /tmp/a /tmp/b && cd /tmp/a
    #     $ vim -Nu NONE +'cd /tmp/b' y
    #     :write
    #     /tmp/a/y˜
    #          ^
    #
    #     $ rm -rf /tmp/a /tmp/b; mkdir -p /tmp/a/x /tmp/b/x && cd /tmp/a
    #     $ vim -Nu NONE +'cd /tmp/b' x/y
    #     :write
    #     /tmp/a/x/y˜
    #          ^
    #
    #     $ rm -rf /tmp/a /tmp/b; mkdir -p /tmp/a/x /tmp/b/x && cd /tmp/a
    #     $ vim -Nu NONE +'cd /tmp/b' y
    #     :write
    #     /tmp/a/y˜
    #          ^
    #
    # It seems that most  of the time, Vim writes a file  (with a relative path)
    # in the cwd of the *shell*.  Except on one occasion; when:
    #
    #    - the file path contains a slash
    #    - there is no subdirectory in the shell's cwd matching the file's parent directory
    #
    # In that case, Vim writes the file in its *own* cwd.
    #
    # Note that changing  `+` with `--cmd` changes the name  of the buffer (from
    # relative to absolute), but it doesn't  change the file where the buffer is
    # written.
    #
    # ---
    #
    # What about a file path provided via `:edit` instead of the shell's command-line?
    # In that case,  it seems that Vim always  uses its own cwd, at  the time of
    # the first successful writing of the buffer.
    #
    #     $ rm -rf /tmp/a /tmp/b; mkdir -p /tmp/a /tmp/b
    #     $ cd /tmp
    #     $ vim -Nu NONE
    #     :cd /tmp/a
    #     :edit x/y
    #     :write
    #     E212˜
    #     :cd /tmp/b
    #     :call mkdir('/tmp/b/x')
    #     :write
    #     /tmp/b/x/y˜
    #          ^
    #}}}
    return index(BLACKLIST, &filetype) >= 0
        || &buftype != ''
        || !expand('<afile>:p')->filereadable()
enddef

def IsDirectory(pat: string): bool #{{{2
    return pat[-1] == '/'
enddef

def IsSpecial(): bool #{{{2
    # Why `isdirectory()`?{{{
    #
    # If we're moving in the filesystem with dirvish, or a similar plugin, while
    # working on a repository, we want the  cwd to stay the same, and not change
    # every time we go up/down into a directory to see its contents.
    #}}}
    return !empty(&buftype) && !isdirectory(bufname)
enddef

def InSubWiki(repo_root: string): bool #{{{2
# A sub wiki is sth like `~/wiki/some_subject/`.
    return repo_root == $HOME .. '/wiki'
        # `~/wiki/` itself is not a subwiki.
        && expand('<afile>:p:h') != $HOME .. '/wiki'
enddef

