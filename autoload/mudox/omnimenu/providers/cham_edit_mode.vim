" vim: foldmethod=marker

" GUARD {{{1
if exists("s:loaded") || &cp || version < 700
  finish
endif
let s:loaded = 1
" }}}1

" PROVIDER MEMEBERS {{{1

function s:on_enter(session) " {{{2
  " close omnibuffer & clear cmd line.
  call mudox#omnimenu#close()

  if len(a:session.lines) == 1 && a:session.line =~ '\m^** '
    let selected_mode = a:session.input
  else
    let selected_mode = a:session.line
  endif

  call g:chameleon.editMode(selected_mode)
endfunction "  }}}2

function s:feed(session) " {{{2
  if !exists('s:full_modes_avail')
    call s:init()
  endif

  if !empty(a:session.input)
    let filtered_line_list = filter(copy(s:full_modes_avail),
          \ "match(v:val, '\\c\\V' . a:session.input) != -1")
    let &l:statusline = len(filtered_line_list)

    if empty(filtered_line_list)
      return [printf('** Add a new meta named < %s >? **', a:session.input)]
    else
      return filtered_line_list
    endif
  else
    return s:full_modes_avail
  endif
endfunction "  }}}2

" }}}1

" HELPER FUNCTIONS {{{1

" initialize s:full_modes_avail
function s:init() " {{{2
  let s:full_modes_avail = g:chameleon.modesAvail()
  lockvar! s:full_modes_avail
endfunction "  }}}2

" }}}1

" make the provider data structure.
let mudox#omnimenu#providers#cham_edit_mode#provider = {
      \ 'title'             : 'Edit Chameleon Mode',
      \ 'description'       : 'edit/create chameleon mode',
      \ 'feed'              : function('s:feed'),
      \ 'on_enter'          : function('s:on_enter'),
      \ }
