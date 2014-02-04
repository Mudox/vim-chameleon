" vim: foldmethod=marker

" GUARD {{{1
if exists("s:loaded") || &cp || version < 700
  finish
endif

if !exists(':OmniMenu')
  finish
endif

let s:loaded = 1
" }}}1

" REGISTRATION {{{1

call mudox#omnimenu#register#add(
      \ 'Edit Chameleon Meta'                             ,
      \ 'edit/create chameleon meta.'                     ,
      \ 'mudox#omnimenu#providers#cham_edit_meta#provider',
      \ )

call mudox#omnimenu#register#add(
      \ 'Edit Chameleon Mode'                             ,
      \ 'edit/create chameleon mode.'                     ,
      \ 'mudox#omnimenu#providers#cham_edit_mode#provider',
      \ )

call mudox#omnimenu#register#add(
      \ 'Startup'                                       ,
      \ 'spawn a new gvim isntance in selected mode.'   ,
      \ 'mudox#omnimenu#providers#cham_startup#provider',
      \ )

" }}}1

" PUBLIC INTERFACE {{{1

command -narg=0 ChamStartup call OmniMenu(
      \ mudox#omnimenu#providers#cham_startup#provider_startup)
nnoremap <silent> <Plug>(OmniMenu_ChamStartup) :<C-U>ChamStartup<Cr>

command -narg=0 ChamNewInstance call OmniMenu(
      \ mudox#omnimenu#providers#cham_startup#provider)
nnoremap <silent> <Plug>(OmniMenu_ChamNewInstance) :<C-U>ChamNewInstance<Cr>

nnoremap <silent> <Plug>(Chameleon_Edit_Meta_OmniMenu) :<C-U>call OmniMenu(
      \ mudox#omnimenu#providers#cham_edit_meta#provider)<Cr>

nnoremap <silent> <Plug>(Chameleon_Edit_Mode_OmniMenu) :<C-U>call OmniMenu(
      \ mudox#omnimenu#providers#cham_edit_mode#provider)<Cr>
" }}}1
