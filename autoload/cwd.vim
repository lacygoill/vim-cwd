fu! cwd#cd_to_project_root() abort "{{{1
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

