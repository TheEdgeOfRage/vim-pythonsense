"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" File:         autoload/pythonsense.vim
" Author:       Jeet Sukumaran
"
" Copyright:    (C) 2018 Jeet Sukumaran
"
" License:      Permission is hereby granted, free of charge, to any person obtaining
"               a copy of this software and associated documentation files (the
"               "Software"), to deal in the Software without restriction, including
"               without limitation the rights to use, copy, modify, merge, publish,
"               distribute, sublicense, and/or sell copies of the Software, and to
"               permit persons to whom the Software is furnished to do so, subject to
"               the following conditions:
"
"               The above copyright notice and this permission notice shall be included
"               in all copies or substantial portions of the Software.
"
"               THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"               OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"               MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"               IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"               CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"               TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"
"               SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"
" Credits:      - pythontextobj.vim by Nat Williams (https://github.com/natw/vim-pythontextobj)
"               - chapa.vim by Alfredo Deza (https://github.com/alfredodeza/chapa.vim)
"               - indentobj by Austin Taylor (https://github.com/austintaylor/vim-indentobject)
"               - Python Docstring Text Objects by gfixler (https://pastebin.com/u/gfixler)
"               - vim-indent-object by Michael Smith (http://github.com/michaeljsmith/vim-indent-object)
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Support Functions {{{1
function! pythonsense#trawl_search(pattern, start_line, fwd)
    let current_line = a:start_line
    let lastline = line('$')
    if a:fwd
        let stepvalue = 1
    else
        let stepvalue = -1
    endif
    while (current_line > 0 && current_line <= lastline)
        let line_text = getline(current_line)
        let m = match(line_text, a:pattern)
        if m >= 0
            return current_line
        endif
        let current_line = current_line + stepvalue
    endwhile
    return 0
endfunction
" }}}1

" Python (Statement) Text Objects {{{1
" Based on:
"   - https://github.com/natw/vim-pythontextobj
"   - https://github.com/alfredodeza/chapa.vim
"   - https://github.com/austintaylor/vim-indentobject
"   - http://github.com/michaeljsmith/vim-indent-object

"   Select an object ("class"/"function")
let s:pythonsense_obj_start_line = -1
let s:pythonsense_obj_end_line = -1
function! pythonsense#select_named_object(obj_name, inner, range, count)

	" Is this a new selection?
	let new_vis = 0
	let new_vis = new_vis || s:pythonsense_obj_start_line != a:range[0]
	let new_vis = new_vis || s:pythonsense_obj_end_line != a:range[1]

    " store current range
	let s:pythonsense_obj_start_line = a:range[0]
	let s:pythonsense_obj_end_line = a:range[1]

	" Repeatedly increase the scope of the selection.
	let itr_cnt = 0
	let cnt = a:count
	let scan_start_line = s:pythonsense_obj_start_line
	while scan_start_line > 0
        if getline(scan_start_line) !~ '^\s*$'
            break
        endif
        let scan_start_line -= 1
    endwhile
    if scan_start_line == 0
        return
    endif
	let obj_max_indent_level = -1
	while cnt > 0
        let current_line_nr = scan_start_line

        let [obj_start_line, obj_end_line] = pythonsense#get_object_line_range(a:obj_name, obj_max_indent_level, current_line_nr, s:pythonsense_obj_end_line, a:inner)
        if obj_start_line == -1
            return
        endif

		let is_changed = 0
		let is_changed = is_changed || s:pythonsense_obj_start_line != obj_start_line
		let is_changed = is_changed || s:pythonsense_obj_end_line != obj_end_line
		if new_vis
			let is_changed = 1
		endif

		let s:pythonsense_obj_start_line = obj_start_line
		let s:pythonsense_obj_end_line = obj_end_line

		" If there was no change, then don't decrement the count (it didn't
		" count because it didn't do anything).
		if is_changed
		    let cnt = cnt - 1
		else
            " no change to selection;
            " move to line above selection and try again
		    if scan_start_line == 0
		        return
            endif
            let [min_indent, max_indent] = pythonsense#get_minmax_indent_count('\(class\|def\)', scan_start_line, obj_end_line)
            if min_indent == 0
                return
            endif
            let obj_max_indent_level = min_indent - 1
            let scan_start_line -= 1
        endif
    endwhile

    " select range
    exec obj_start_line
    if obj_end_line >= obj_start_line
        execute "normal! V" . obj_end_line . "G"
        if has("folding") && foldclosed(line('.')) != -1
            " try
            "     execute "normal! zO"
            " catch /E490/ " no fold found
            " endtry
            execute "normal! zO"
        endif
    else
        execute "normal VG"
    endif
    " move to beginning of range
    if get(g:, "pythonsense_move_to_top_of_selection", 1)
        normal! o
    endif

	" Update these static variables - we need to keep these up-to-date between
	" invocations because it's the only way we can detect whether it's a new
	" visual mode. We need to know if it's a new visual mode because otherwise
	" if there's a single line block in visual line mode and we select it with
	" "V", we can't tell whether it's already been selected using Vii.
	exe "normal! \<Esc>"
	let s:l0 = line("'<")
	let s:l1 = line("'>")
	normal gv

endfunction

function! pythonsense#get_object_line_range(obj_name, obj_max_indent_level, line_range_start, line_range_end, inner)
    " find definition line
    let current_line_nr = a:line_range_start
    let obj_start_line = pythonsense#get_named_python_obj_start_line_nr(a:obj_name, a:obj_max_indent_level, current_line_nr, 0)
    " no object definition line in file
    if (! obj_start_line)
        return [-1, -1]
    endif
    let obj_header_line = obj_start_line
    let obj_header_indent = pythonsense#get_line_indent_count(obj_header_line)
    if obj_header_indent > 0
        let obj_header_indent -= 1
    endif

    " get end (w/ or w/out whitespace)
    let obj_end_line = pythonsense#get_object_end_line_nr(obj_start_line, a:line_range_end, a:inner)
    if (a:inner)
        " find class/function body
        call cursor(obj_start_line, 0)
        let inner_start_line = search('):\(\s*$\|\s*#.*$\)', "Wce")
        if inner_start_line
            let obj_start_line = inner_start_line + 1
        endif
    else
        " include decorators
        let dec_line = pythonsense#get_start_decorators_line_nr(obj_start_line)
        if dec_line < obj_start_line
            let obj_start_line = dec_line
        endif
    endif

    " This is an ugly hack to deal with (some) specially indented cases
    " (especially when searching for a 'class' while inside a non-class member
    " function, or when searching for a 'def' with nothing but class
    " definitions above)
    " Make sure there is no statement line with a lower indentation than the
    " definition line in between the current line and the definition line
    if a:obj_name == 'class'
        let pattern = 'def'
    else
        let pattern = 'class'
    endif
    let pattern = '^\s*[^#]*\s*\k'
    if pythonsense#is_statement_encountered_between_two_lines(pattern, obj_header_indent, obj_start_line, current_line_nr)
        return [-1, -1]
    endif

    return [obj_start_line, obj_end_line]
endfunction

function! pythonsense#get_object_end_line_nr(obj_start, search_start, inner)
    let obj_indent = pythonsense#get_line_indent_count(a:obj_start)
    let obj_end = pythonsense#get_next_indent_line_nr(a:search_start, obj_indent)
    if a:inner
        let obj_end = prevnonblank(obj_end)
    endif
    return obj_end
endfunction

function! pythonsense#get_next_indent_line_nr(search_start, obj_indent)
    let line = a:search_start
    let lastline = line('$')
    while (line > 0 && line <= lastline)
        let line = line + 1
        if (pythonsense#get_line_indent_count(line) <= a:obj_indent && getline(line) !~ '^\s*$')
            return line - 1
        endif
    endwhile
    return lastline
endfunction

function! pythonsense#get_start_decorators_line_nr(start)
    " Returns the line of the first decorator line above the starting line,
    " counting only decorators with the same level.
    exec a:start
    normal ^
    let def_indent = indent(line("."))
    normal k
    while (indent(line(".") == def_indent) && getline(".") =~ '\v^\s*\@')
        normal k
    endwhile
    return line(".") + 1
endfunction

function! pythonsense#get_line_indent_count(line_nr)
    if b:pythonsense_is_tab_indented
        let indent_count = matchstrpos(getline(a:line_nr), '^\t\+')[2]
    else
        let indent_count = indent(a:line_nr)
    endif
    return indent_count
endfunction

function! pythonsense#get_minmax_indent_count(pattern, line_range_start, line_range_end)
    let current_line = a:line_range_start
    let min_indent_count = -1
    let max_indent_count = -1
    while current_line <= a:line_range_end && current_line <= line('$')
        if getline(current_line) !~ '^\s*$'
            if getline(current_line) =~ a:pattern
                let current_indent = pythonsense#get_line_indent_count(current_line)
                if min_indent_count < 0 || current_indent < min_indent_count
                    let min_indent_count = current_indent
                endif
                if max_indent_count < 0 || current_indent > max_indent_count
                    let max_indent_count = current_indent
                endif
            endif
        endif
        let current_line = current_line + 1
    endwhile
    return [min_indent_count, max_indent_count]
endfunction

function! pythonsense#is_statement_encountered_between_two_lines(pattern, max_indent, line_range_start, line_range_end)
    let current_line = a:line_range_start
    while current_line <= a:line_range_end && current_line <= line('$')
        if getline(current_line) !~ '^\s*$'
            if getline(current_line) =~ a:pattern
                let current_indent = pythonsense#get_line_indent_count(current_line)
                if a:max_indent > -1 && current_indent < a:max_indent
                    return 1
                endif
            endif
        endif
        let current_line += 1
    endwhile
    return 0
endfunction

function! pythonsense#get_indent_char()
    if b:pythonsense_is_tab_indented
        let indent_char = '\t'
    else
        let indent_char = " "
    endif
    return indent_char
endfunction

function! pythonsense#get_named_python_obj_start_line_nr(obj_name, obj_max_indent_level, start_line, fwd)
    " let target_line_indent = indent(current_line)
    " let head_pattern = '^\s\{0,' . target_line_indent. '}' . a:obj_name
    " let head_lnum = pythonsense#trawl_search(head_pattern, current_line, a:fwd)
    " return head_lnum
    let lastline = line('$')
    if a:fwd
        let stepvalue = 1
    else
        let stepvalue = -1
    endif
    let indent_char = pythonsense#get_indent_char()

    let current_line = a:start_line
    while (current_line > 0 && current_line <= lastline)
        if getline(current_line) !~ '^\s*$'
            break
        endif
        let current_line = current_line + stepvalue
    endwhile
    if a:obj_max_indent_level > -1
        let pattern = '^' . indent_char . '\{0,' . a:obj_max_indent_level . '}' . '\(class\|def\)'
    else
        let pattern = '^\s*' . '\(class\|def\)'
    endif
    if getline(current_line) =~ pattern
        if getline(current_line) =~ a:obj_name
            return current_line
        endif
    endif

    let target_line_indent = pythonsense#get_line_indent_count(current_line) - 1
    if target_line_indent < 0
        let target_line_indent = 0
    endif
    if a:obj_max_indent_level > -1 && target_line_indent > a:obj_max_indent_level
        let target_line_indent = a:obj_max_indent_level
    endif
    let max_indent = target_line_indent
    while (current_line > 0 && current_line <= lastline)
        let pattern = '^' . indent_char . '\{0,' . max_indent . '}' . '\(class\|def\)'
        if getline(current_line) =~ pattern
            if getline(current_line) =~ a:obj_name
                return current_line
            else
                if a:obj_name != 'class' && pythonsense#get_line_indent_count(current_line) <= max_indent
                    " encountered a scope block at a lower indent level before
                    " encountering object definition
                    return 0
                endif
            endif
        endif
        " let m = match(getline(current_line), pattern)
        " if m >= 0
        "     return current_line
        " endif

        let target_line_indent = pythonsense#get_line_indent_count(current_line) - 1
        if target_line_indent >= 0 && target_line_indent < max_indent
            let max_indent = target_line_indent
        endif
        if a:obj_max_indent_level > -1 && target_line_indent > a:obj_max_indent_level
            let target_line_indent = a:obj_max_indent_level
        endif

        let current_line = current_line + stepvalue
    endwhile
    return 0
endfunction

function! pythonsense#python_function_text_object(inner, range)
    call pythonsense#select_named_object('def', a:inner, a:range, 1)
endfunction

function! pythonsense#python_class_text_object(inner, range)
    call pythonsense#select_named_object('class', a:inner, a:range, 1)
endfunction

" }}}1

" Python Docstring Text Objects {{{1
" From: https://pastebin.com/u/gfixler
function! pythonsense#python_docstring_text_object (inner)
    " get current line number
    let s = line('.')
    " climb up to first def/class line, or first line of buffer
    while s > 0 && getline(s) !~ '^\s*\(def\|class\)'
        let s = s - 1
    endwhile
    " set search start to just after def/class line, or on first buffer line
    let s = s + 1
    " descend lines obj_end_line end of buffer or def/class line
    while s < line('$') && getline(s) !~ '^\s*\(def\|class\)'
        " if line begins with optional whitespace followed by '''
        if getline(s) =~ "^\\s*'''" || getline(s) =~ '^\s*"""'
            if getline(s) =~ "^\\s*'''"
                let close_pattern = "'''\\s*$"
            else
                let close_pattern = '"""\s*$'
            endif
            " set search end to just after found start line
            let e = s + 1
            " descend lines obj_end_line end of buffer or def/class line
            while e <= line('$') && getline(e) !~ '^\s*\(def\|class\)'
                " if line ends with ''' followed by optional whitespace
                if getline(e) =~ close_pattern
                    " TODO check first for blank lines above to select instead
                    " for 'around', extend search end through blank lines
                    if !a:inner
                        let x = e + 1
                        while x <= line('$') && getline(x) =~ '^\s*$'
                            let e = x
                            let x = x + 1
                        endwhile
                    endif
                    " visual line select from start to end (first cursor move)
                    exe 'norm '.s.'ggV'.e.'gg'
                    return
                endif
                " move search end down a line
                let e = e + 1
            endwhile
        endif
        " move search start down a line
        let s = s + 1
    endwhile
endfunction
" }}}1

" Python Movements {{{1
function! pythonsense#move_to_python_object(obj_name, to_end, fwd, vim_mode) range
    if a:fwd
        let current_line = a:lastline
        let stepvalue = 1
    else
        let current_line = a:firstline
        let stepvalue = -1
    endif
    let pattern = '^\s*' . a:obj_name . '\s\+'
    if a:to_end
        let is_search_forward = 0
    else
        let is_search_forward = a:fwd
    endif
    while 1
        if current_line <= 0 || current_line > line('$')
            return
        endif
        let target_line = pythonsense#trawl_search(pattern, current_line, is_search_forward)
        if !target_line
            return
        elseif target_line == current_line
            let current_line = current_line + stepvalue
        else
            break
        endif
    endwhile
    if a:to_end
        let obj_end_line = pythonsense#get_object_end_line_nr(target_line, target_line, 1)
        echom target_line . ", " . obj_end_line
        if ! obj_end_line
            return
        endif
        let target_line = obj_end_line
    endif
    let current_column = col('.')
    let preserve_col_pos = get(b:, "pythonsense_preserve_col_pos", get(g:, "pythonsense_preserve_col_pos", 0))
    let fold_open = ""
    if a:vim_mode == "v"
        normal! gv
    endif
    if has("folding") && foldclosed(line('.')) != -1
        let fold_open = "zO"
    else
        let fold_open = ""
    endif
    try
        if preserve_col_pos
            execute "normal! " . target_line . "G" . current_column . "|" . preserve_col_pos . fold_open
        else
            execute "normal! " . target_line . "G^" . fold_open
        endif
    catch /E490/ " no fold found
    endtry
endfunction

" }}}1

" Python Location Information {{{1
function! pythonsense#echo_python_location()
    let indent_char = pythonsense#get_indent_char()
    let pyloc = []
    let current_line = line('.')
    let obj_pattern = '\(class\|def\)'
    while current_line > 0
        if getline(current_line) !~ '^\s*$'
            break
        endif
        let current_line = current_line - 1
    endwhile
    if current_line == 0
        return
    endif
    let target_line_indent = pythonsense#get_line_indent_count(current_line)
    if target_line_indent < 0
        break
    endif
    let previous_line = current_line
    while current_line > 0
        let pattern = '^' . indent_char . '\{0,' . target_line_indent . '}' . obj_pattern
        let current_line_text = getline(current_line)
        if current_line_text =~ pattern
            let obj_name = matchstr(current_line_text, '^\s*\(class\|def\)\s\+\zs\k\+')
            if get(g:, "pythonsense_extended_location_info", 1)
                let obj_type = matchstr(current_line_text, '^\s*\zs\(class\|def\)')
                call add(pyloc, "(" . obj_type . ") " . obj_name)
            else
                call add(pyloc, obj_name)
            endif
            let target_line_indent = pythonsense#get_line_indent_count(current_line) - 1
        endif
        if target_line_indent < 0
            break
        endif
        let previous_line = current_line
        let current_line = current_line - 1
    endwhile
    if get(g:, "pythonsense_extended_location_info", 1)
        let joiner = " > "
    else
        let joiner = "."
    endif
    echo join(reverse(pyloc), joiner)
    return
endfunction
" }}}1
