
" TODO!!!: unobjectify s:charm
" TODO!!: DSL like vader.vim for defining meta files

" GUARD                                                                             {{{1
if exists("s:loaded") || &cp || version < 700
  finish
endif
let s:loaded = 1
" }}}1

" CHAM -- THE CORE SINGLETON                                                        {{{1

let s:cham                 = {}

" currently use 'VimPlug' as the plugin manager.
"let s:cham.manager         = { 'name' : 'vimplug'   }
let s:cham.manager         = {}

function s:cham_init()                                                            " {{{2

  " initialize constants                                                            {{{3

  if has('win32') || has('win64') " on windows platform
    let s:cham.cham_dir        = get(g:, 'mdx_chameleon_root',
          \ expand('~/vimfiles/chameleon')
          \ )
  else " on *nix platform
    let s:cham.cham_dir        = get(g:, 'mdx_chameleon_root',
          \ expand('~/.vim/chameleon')
          \ )
  endif
  lockvar s:cham.cham_dir

  let s:cham.repo_dir        = g:rc_root . '/plugged'
  lockvar s:cham.repo_dir

  let s:cham.metas_dir       = s:cham.cham_dir . '/metas'
  lockvar s:cham.metas_dir

  let s:cham.modes_dir       = s:cham.cham_dir . '/modes'
  lockvar s:cham.modes_dir

  let s:cham.meta_tmpl       = s:cham.cham_dir . '/skel/meta_template'
  lockvar s:cham.meta_tmpl

  let s:cham.mode_tmpl       = s:cham.cham_dir . '/skel/mode_template'
  lockvar s:cham.mode_tmpl

  call s:cham_init_mode_name()
  lockvar s:cham.mode_name
  lockvar s:cham.mode_file_path
  lockvar g:mdx_chameleon_mode_name
  lockvar g:mdx_chameleon_cur_mode_file_path

  " use in :ChamInfo command output.
  let s:cham.prefix          = ' └ '
  lockvar s:cham.prefix
  "}}}3

  " initialize variables                                                            {{{3
  " they are all filled and locked in s:cham_load_mode()

  "let s:cham.title           = 'title description'
  let s:cham.mode_set        = [] " names of sourced modes/* files.
  let s:cham.modes_duplicate = []
  let s:cham.meta_set        = [] " names of sourced metas/* files.
  let s:cham.metas_duplicate = []

  " dict to hold config & bundle hierarchy.
  " will fild and locked in s:cham_load_mode()
  let s:cham.tree            = { 'metas' : [], 'modes' : {} }

  " it will filed and locked in s:cham_load_metas()
  " and unleted in s:cham_manager_init() after registering.
  let s:cham.meta_dicts      = [] " list of plugin meta dicts.
  "}}}3

  call s:cham_load_mode()
  call s:cham_load_metas()
  call s:cham_manager_init()
endfunction
" }}}2

" determine the mode name for this vim session. it initializes:
" - s:cham.mode_name
" - s:cham.mode_file_path
" - g:mdx_chameleon_mode_name
" - g:mdx_chameleon_mode_file_path
function s:cham_init_mode_name()                                                  " {{{2
  let mode_file_path = expand(s:cham.cham_dir . '/cur_mode')

  if exists('$MDX_CHAMELEON_MODE')

    " FIRST: see if mode name can be read from $MDX_CHAMELEON_MODE
    if index(s:cham_modes_avail(), $MDX_CHAMELEON_MODE) == -1
      throw printf(
            \ 'chameleon: invalid mode name [%s] found in $MDX_CHAMELEON_MODE',
            \ $MDX_CHAMELEON_MODE)
    endif

    let s:cham.mode_name = $MDX_CHAMELEON_MODE

  else

    " THEN: read mode name from 'cur_mode' file.
    " check file availability
    " if not exist, create & populate it with bootstrapping default
    if ! filereadable(mode_file_path)
      echohl WarningMsg
      echo 'mode file missing in ' . mode_file_path
      echo 'create & populate it with "vim" ...'
      echohl None

      " TODO: maybe a 'default' mode is more appropriate.
      call writefile(['vim'], mode_file_path)
    endif

    let name = readfile(expand(s:cham.cham_dir . '/cur_mode'))[0]
    if index(s:cham_modes_avail(), name) == -1
      throw printf(
            \ 'chameleon: invalid mode name [%s] in %s',
            \ name,
            \ mode_file_path)
    endif

    let s:cham.mode_name = name

  endif

  " only for inspection from outside the plugin
  let s:cham.mode_file_path = mode_file_path
  let g:mdx_chameleon_mode_name = s:cham.mode_name
  lockvar g:mdx_chameleon_mode_name
  let g:mdx_chameleon_mode_file_path = mode_file_path
  lockvar g:mdx_chameleon_mode_file_path
endfunction
" }}}2

function! s:cham_add_essential_meta(name) abort                                   " {{{2
  " helper method only called in cham_load_mode()

  if index(s:cham.tree.metas, a:name) == -1
    call insert(s:cham.tree.metas, a:name)
  endif

  if index(s:cham.meta_set, a:name) == -1
    call insert(s:cham.meta_set, a:name)
  else
    if index(s:cham.metas_duplicate, a:name) == -1
      call add(s:cham.metas_duplicate, a:name)
    endif
  endif
endfunction " }}}2

function s:cham_add_metas(list)                                                   " {{{2
  " make sure meta set item be properly initialized.
  let s:cursor.metas = get(s:cursor, 'metas', [])

  if empty(a:list) | return | endif

  for name in a:list

    " check meta name's validity.
    if index(s:cham_metas_avail(), name) == -1
      echoerr printf("Invalid meta name: [%s] required by {%s}",
            \ name, s:stack[0].name)
      continue
    endif

    " add unique meta names to current tree.metas set.
    if index(s:cursor.metas, name) == -1
      call add(s:cursor.metas, name)
    endif

    " add unique meta names to the centralized set.
    if index(s:cham.meta_set, name) == -1
      call add(s:cham.meta_set, name)
    else
      if index(s:cham.metas_duplicate, name) == -1
        call add(s:cham.metas_duplicate, name)
      endif
    endif
  endfor
endfunction
" }}}2

function s:cham_merge_modes(list)                                                 " {{{2
  for name in a:list
    " check cyclic or duplicate merging.
    if index(s:cham.mode_set, name) != -1
      call add(s:cham.modes_duplicate, name)
      return
    else
      call add(s:cham.mode_set, name)
    endif

    " make sure sub-tree item is properly initialized.
    let s:cursor.modes[name] = get(s:cursor.modes, name,
          \ { 'metas' : [], 'modes' : {} })

    " push parent node.
    call insert(s:stack,
          \ { 'name' : name, 'ptr' : s:cursor.modes[name]}, 0)
    let s:cursor = s:cursor.modes[name] " step forward.

    " submerge.
    execute 'source ' . s:cham.modes_dir . '/' . name

    call sort(s:cursor.metas)
    " pop stack
    unlet s:stack[0]
    let s:cursor = s:stack[0].ptr
  endfor
endfunction
" }}}2

function s:cham_load_mode()                                                       " {{{2
  " parse mode files, and fill s:cham.tree, s:cham.meta_set, s:cham.mode_set ...
  " virtually, all jobs done by the 4 temporary global functions below.

  " temporary pointer tracing current sub tree during traversal.
  let s:cursor = s:cham.tree

  if s:cham.mode_name ==# 'update-all'
    let s:cham.tree.metas = filter(s:cham_metas_avail(), 'v:val !~ "@"')
    let s:cham.meta_set = s:cham.tree.metas
    let s:cham.mode_set = ['update-all']

    augroup Mdx_Chameleon_Udpate_All
      autocmd!
      autocmd VimEnter * PlugUpgrade | PlugUpdate | wincmd o
            \| autocmd! Mdx_Chameleon_Udpate_All
    augroup END

    return
  endif

  " the node of tree consist of
  "   [.metas] -- a list that simulate set type to hold metas introduced by
  "   the mode file.
  "   [.modes] -- a dictionary of which the keys hold the sub-modes' file
  "   names, and values will hold the corresponding sub-node.
  " tree starts growing ...

  " a stack tracing crrent node during traversing.
  " use a list to simulate a stack, with each elements to be a 2-tuple of the
  " form: (name, ptr).
  let s:stack = [ {'name' : s:cham.mode_name, 'ptr' : s:cursor} ]

  " the temporary global function MergeConfigs & AddBundles will be called in
  " the sourced mode files which, in turn, would do the dirty work to build
  " the tree
  execute 'source ' . s:cham.modes_dir . '/' . s:cham.mode_name

  " add 'chameleon' and it's dependencies uniquely to the root node.

  call s:cham_add_essential_meta('qpen')
  call s:cham_add_essential_meta('omnimenu')
  call s:cham_add_essential_meta('chameleon')

  " lock
  "lockvar  s:cham.title
  lockvar  s:cham.manager
  lockvar! s:cham.tree

  call sort(s:cham.meta_set)        | lockvar  s:cham.meta_set
  call sort(s:cham.metas_duplicate) | lockvar  s:cham.metas_duplicate
  call sort(s:cham.mode_set)        | lockvar  s:cham.mode_set
  call sort(s:cham.modes_duplicate) | lockvar  s:cham.modes_duplicate

  " clean up functions & commands
  delfunction AddBundles
  delfunction MergeConfigs
  delfunction SetTitle

  unlet s:cursor
  unlet s:stack
endfunction
" }}}2

function s:cham_load_metas()                                                      " {{{2

  for name in s:cham.meta_set
    " initialize the global temp dict
    let g:this_meta = {}

    execute 'source ' . s:cham.metas_dir . '/' . name

    let dir = substitute(name, '@.*$', '', '')
    let g:this_meta.vimplug_cmd_dict.dir = '~/.vim/plugged/' . dir

    if s:cham.mode_name ==# 'update-all'
      let g:this_meta.vimplug_cmd_dict.on = []
      unlet g:this_meta.config
    endif

    call add(s:cham.meta_dicts, g:this_meta)
    unlet g:this_meta
  endfor

  lockvar! s:cham.meta_dicts
endfunction
" }}}2

function s:cham_init_bundles()                                                    " {{{2
  for meta in s:cham.meta_dicts
    " in 'udpate' mode, no config function is needed.
    if has_key(meta, 'config')
      call meta.config()
    endif
  endfor

  unlock! s:cham.meta_dicts
  unlet s:cham.meta_dicts
endfunction
" }}}2

function s:cham_metas_avail()                                                     " {{{2
  let metas = glob(s:cham.metas_dir . '/*', 1, 1)
  call map(metas, 'fnamemodify(v:val, ":t:r")')
  return metas
endfunction
" }}}2

function s:cham_modes_avail()                                                     " {{{2
  let modes = glob(s:cham.modes_dir . '/*', 1, 1)
  call map(modes, 'fnamemodify(v:val, ":t:r")')
  call add(modes, 'update-all')
  return modes
endfunction
" }}}2

" NOTE: currrently unused
function s:cham_repo_avail()                                                      " {{{2
  let metas_installed = glob(s:cham.repo_dir . '/*', 1, 1)
  call map(metas_installed, 'fnamemodify(v:val, ":t:r")')
  return metas_installed
endfunction
" }}}2

function s:cham_manager_init()                                                    " {{{2
  call plug#begin('~/.vim/plugged')

  for meta in s:cham.meta_dicts
    execute "Plug " . string(meta.site) . ', ' .
          \ string(meta.vimplug_cmd_dict)
  endfor

  call plug#end()
endfunction
" }}}2

function s:cham_info()                                                            " {{{2
  " mode name
  "echohl Title
  "echon printf("%-14s ", 'Mode:')
  "echohl Identifier
  "echon printf("%s\n", s:cham.title)

  " mode file name
  echohl Title
  echon printf("%-14s ", 'Mode file:')
  echohl Identifier
  echon printf("%s\n", s:cham.mode_name)

  " bundle manager name
  "echohl Title
  "echon printf("%-14s ", 'Manager:')
  "echohl Identifier
  "echon printf("%s\n", s:cham.manager.name)

  " long delimiter line.
  echohl Number
  echon printf("%-3d ", len(s:cham.meta_set))
  echohl Title
  echon printf("%-14s ", "Metas Enrolled")

  echohl Delimiter
  echon '-'
  for n in range(&columns - 38)
    echon '-'
    let n = n " suppres vimlint complaining.
  endfor

  echohl Number
  echon printf(" in %2d ", len(s:cham.mode_set) + 1)
  echohl Title
  echon "Mode files"
  call s:cham_dump_tree(s:cham.tree, ['.'])

  " must have.
  echohl None
endfunction "}}}2

function s:cham_dump_tree(dict, path)                                             " {{{2
  " arg path: a list record recursion path.
  let max_width = max(map(s:cham.meta_set[:], 'len(v:val)')) + 2
  let fields = (&columns - len(s:cham.prefix)) / max_width

  " print tree path.
  echohl Title
  echo join(a:path, '/') . ':'

  " print meta list.
  echohl Special

  if empty(a:dict.metas)
    echo s:cham.prefix . '< empty >'
  else
    for i in range(len(a:dict.metas))
      if i % fields == 0 | echo s:cham.prefix | endif
      if index(s:cham.metas_duplicate, a:dict.metas[i]) != -1
        echohl MoreMsg
      endif
      execute 'echon printf("%-' . max_width . 's", a:dict.metas[i])'
      echohl Special
    endfor
  endif

  " print sub-modes.
  for [name, mode] in items(a:dict.modes)
    call s:cham_dump_tree(mode, add(a:path[:], name))
  endfor

  echohl None
endfunction
" }}}2

function g:ChameleonEditMode(arg)                                                 " {{{2
  let names = split(a:arg)
  if len(names) > 2
    echoerr 'Too many arguments, at most 2 arguemnts is needed'
    return
  endif

  try
    if len(names) == 0 " Edit current mode.
      let file_path = s:cham.modes_dir . '/' . s:cham.mode_name
      call Qpen(file_path)
    else " edit a new or existing mode.
      let file_path = s:cham.modes_dir . '/' . names[0]

      if filereadable(file_path) " edit a existing file.
        call Qpen(file_path)
      else " edit a new file.
        " read template content if any.
        if filereadable(s:cham.mode_tmpl)
          let tmpl = readfile(s:cham.mode_tmpl)
        else
          echohl WarningMsg
          echo 'Template file [' . s:cham.mode_tmpl
                \ . "] unreadable"
          echo "creating an empty mode ..."
          echohl None
        endif

        call Qpen(file_path)
        setlocal filetype=vim
        setlocal foldmethod=marker
        setlocal fileformat=unix

        if exists('tmpl')
          call append(0, tmpl)
          delete _
        endif
      endif
    endif
  catch /^Qpen: Canceled$/
    echohl WarningMsg | echo '* EditMode: Canceled *' | echohl None
    return
  endtry
endfunction
" }}}2

function g:ChameleonEditMeta(name)                                                " {{{2
  let file_name = s:cham.metas_dir . '/' . a:name

  try
    call Qpen(file_name)
  catch /^Qpen: Canceled$/
    echohl WarningMsg | echo '* EditMeta: Canceled *' | echohl None
    return
  endtry

  if !filereadable(file_name)
    " read template content
    if filereadable(s:cham.meta_tmpl)
      let tmpl = readfile(s:cham.meta_tmpl)
    else
      echohl WarningMsg
      echo 'Mode template file [' . s:cham.meta_tmpl . '] unreadable'
      echo "creating an empty meta ..."
      echohl None
    endif
  endif

  " if it is creating a new meta, fill it with appropriate template.
  if exists('tmpl')
    let g:create_tmpl = 1
    setlocal filetype=vim
    setlocal foldmethod=marker
    setlocal fileformat=unix

    " fill with template.
    " if register + got a valid git repo address, then automatically
    " insert the shrotened address into appropriate place.
    let repo_addr = s:cham_peek_url()
    if len(repo_addr) > 0
      let n = match(tmpl, 'let g:this_meta.site = " TODO:')
      let tmpl[n] = substitute(tmpl[n], '" TODO:.*$', string(repo_addr), '')
    endif

    call append(0, tmpl)
    delete _

    call cursor(1, 1)
    call search("let g:this_mode.site = '.", 'e')
  endif
endfunction
" }}}2

function s:cham_peek_url()                                                        " {{{2
  let url_pat = '\m\c^\%(https://\|git@\).*'

  for reg in [@", @+, @*, @a]
    let url = matchstr(reg, url_pat)
    if !empty(url)
      break
    endif
  endfor

  let g:parsed_url = url

  " will returns an empty string if parsing failed.
  return url
endfunction
" }}}2
" }}}1

" INTERMEDIATE FUNCTIONS                                                            {{{1

" temporary global functions used in modes/* to for mode configurations.
" these function only survive during the only invocation of s:cham_init().

function AddBundles(list)                                                         " {{{2
  call s:cham_add_metas(a:list)
endfunction
" }}}2

function MergeConfigs(list)                                                       " {{{2
  call s:cham_merge_modes(a:list)
endfunction
" }}}2

function SetTitle(name)                                                           " {{{2
  " only top level config file can call this function.
  if !empty(s:cham.title)
    return
  endif

  let s:cham.title = a:name
  lockvar s:cham.title
endfunction
" }}}2

"}}}1

" PUBLIC INTERFACES                                                                 {{{1

function mudox#chameleon#Init()                                                   " {{{2
  " try to download & install Vim-Plug if not.
  " for bootstrapping.
  if empty(glob('~/.vim/autoload/plug.vim'))
    echohl WarningMsg | echo "vim-plug not available, try install ..." | echohl None
    silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
          \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    autocmd VimEnter * PlugInstall
  endif

  call s:cham_init()
endfunction " }}}2

function mudox#chameleon#InitBundles()                                            " {{{2
  call s:cham_init_bundles()
endfunction " }}}2

let ChameleonModeList = function('s:cham_modes_avail')
let ChameleonMetaList = function('s:cham_metas_avail')

function mudox#chameleon#TopModeList()                                            " {{{2
  return filter(s:cham_modes_avail(), 'v:val !~# "^x_"')
endfunction "  }}}2

" :ChamInfo                                                                         {{{2
command ChamInfo call mudox#chameleon#Info()
function mudox#chameleon#Info()
  call s:cham_info()
endfunction

" }}}2

" }}}2

let g:mdx_chameleon = s:cham

"}}}1
