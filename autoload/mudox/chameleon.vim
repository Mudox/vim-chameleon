" vim: foldmethod=marker

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

function s:cham.init() dict                                                       "    {{{2

  " constants                                                                             {{{3

  if has('win32') || has('win64') " on windows platform
    let self.cham_dir        = get(g:, 'mdx_chameleon_root',
          \ expand('~/vimfiles/chameleon')
          \ )
  else " on *nix platform
    let self.cham_dir        = get(g:, 'mdx_chameleon_root',
          \ expand('~/.vim/chameleon')
          \ )
  endif
  lockvar self.cham_dir

  let self.repo_dir        = g:rc_root . '/plugged'
  lockvar self.repo_dir

  let self.metas_dir       = self.cham_dir . '/metas'
  lockvar self.metas_dir

  let self.modes_dir       = self.cham_dir . '/modes'
  lockvar self.modes_dir

  let self.meta_tmpl       = self.cham_dir . '/skel/meta_template'
  lockvar self.meta_tmpl

  let self.mode_tmpl       = self.cham_dir . '/skel/mode_template'
  lockvar self.mode_tmpl

  call self.initModeName()
  lockvar self.mode_name
  lockvar self.mode_file_path
  lockvar g:mdx_chameleon_mode_name
  lockvar g:mdx_chameleon_cur_mode_file_path

  " use in :ChamInfo command output.
  let self.prefix          = ' └ '
  lockvar self.prefix
  "}}}3

  " variables                                                                             {{{3
  " they are all filled and locked in s:cham.loadMode()

  "let self.title           = 'title description'
  let self.mode_set        = [] " names of sourced modes/* files.
  let self.modes_duplicate = []
  let self.meta_set        = [] " names of sourced metas/* files.
  let self.metas_duplicate = []

  " dict to hold config & bundle hierarchy.
  " will fild and locked in self.loadMode()
  let self.tree            = { 'metas' : [], 'modes' : {} }

  " it will filed and locked in self.loadMetas()
  " and unleted in self.manager.init() after registering.
  let self.meta_dicts      = [] " list of plugin meta dicts.
  "}}}3

  call self.loadMode()
  call self.loadMetas()
  call self.manager.init()
endfunction
" }}}2

" determine the mode name for this vim session. it initializes:
" - self.mode_name
" - self.mode_file_path
" - g:mdx_chameleon_mode_name
" - g:mdx_chameleon_mode_file_path
function s:cham.initModeName() dict                                               "    {{{2
  let mode_file_path = expand(self.cham_dir . '/cur_mode')

  if exists('$MDX_CHAMELEON_MODE')

    " FIRST: see if mode name can be read from $MDX_CHAMELEON_MODE
    if index(self.modesAvail(), $MDX_CHAMELEON_MODE) == -1
      throw printf(
            \ 'chameleon: invalid mode name [%s] found in $MDX_CHAMELEON_MODE',
            \ $MDX_CHAMELEON_MODE)
    endif

    let self.mode_name = $MDX_CHAMELEON_MODE

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

    let name = readfile(expand(self.cham_dir . '/cur_mode'))[0]
    if index(self.modesAvail(), name) == -1
      throw printf(
            \ 'chameleon: invalid mode name [%s] in %s',
            \ name,
            \ mode_file_path)
    endif

    let self.mode_name = name

  endif

  " only for inspection from outside the plugin
  let self.mode_file_path = mode_file_path
  let g:mdx_chameleon_mode_name = self.mode_name
  let g:mdx_chameleon_mode_file_path = mode_file_path
endfunction
" }}}2

function s:cham.addMetas(list) dict                                               "    {{{2
  " make sure meta set item be properly initialized.
  let s:cursor.metas = get(s:cursor, 'metas', [])

  if empty(a:list) | return | endif

  for name in a:list

    " check meta name's validity.
    if index(self.metasAvail(), name) == -1
      echoerr printf("Invalid meta name: [%s] required by {%s}",
            \ name, s:stack[0].name)
      break
    endif

    " add unique meta names to current tree.metas set.
    if index(s:cursor.metas, name) == -1
      call add(s:cursor.metas, name)
    endif

    " add unique meta names to the centralized set.
    if index(self.meta_set, name) == -1
      call add(self.meta_set, name)
    else
      if index(self.metas_duplicate, name) == -1
        call add(self.metas_duplicate, name)
      endif
    endif
  endfor
endfunction
" }}}2

function s:cham.mergeModes(list) dict                                             "    {{{2
  for name in a:list
    " check cyclic or duplicate merging.
    if index(self.mode_set, name) != -1
      call add(self.modes_duplicate, name)
      return
    else
      call add(self.mode_set, name)
    endif

    " make sure sub-tree item is properly initialized.
    let s:cursor.modes[name] = get(s:cursor.modes, name,
          \ { 'metas' : [], 'modes' : {} })

    " push parent node.
    call insert(s:stack,
          \ { 'name' : name, 'ptr' : s:cursor.modes[name]}, 0)
    let s:cursor = s:cursor.modes[name] " step forward.

    " submerge.
    execute 'source ' . self.modes_dir . '/' . name

    call sort(s:cursor.metas)
    " pop stack
    unlet s:stack[0]
    let s:cursor = s:stack[0].ptr
  endfor
endfunction
" }}}2

function s:cham.loadMode() dict                                                   "    {{{2
  " parse mode files, and fill self.tree, self.meta_set, self.mode_set ...
  " virtually, all jobs done by the 4 temporary global functions below.

  " temporary pointer tracing current sub tree during traversal.
  let s:cursor = self.tree

  " the node of tree consist of
  "   [.metas] -- a list that simulate set type to hold metas introduced by
  "   the mode file.
  "   [.modes] -- a dictionary of which the keys hold the sub-modes' file
  "   names, and values will hold the corresponding sub-node.
  " tree starts growing ...

  " a stack tracing crrent node during traversing.
  " use a list to simulate a stack, with each elements to be a 2-tuple of the
  " form: (name, ptr).
  let s:stack = [ {'name' : self.mode_name, 'ptr' : s:cursor} ] " initialize.
  " the temporary global function MergeConfigs & AddBundles will be called in
  " the sourced mode files which, in turn, would do the dirty work to build
  " the tree
  execute 'source ' . self.modes_dir . '/' . self.mode_name

  " add 'chameleon' name uniquely to the top level node.
  if index(self.tree.metas, 'chameleon')
    call insert(self.tree.metas, 'chameleon')
  endif

  if index(self.meta_set, 'chameleon') == -1
    let self.meta_set = insert(self.meta_set, 'chameleon')
  else
    if index(self.metas_duplicate, 'chameleon') == -1
      call add(self.metas_duplicate, 'chameleon')
    endif
  endif

  " lock
  "lockvar  self.title
  lockvar  self.manager
  lockvar! self.tree

  call sort(self.meta_set)        | lockvar  self.meta_set
  call sort(self.metas_duplicate) | lockvar  self.metas_duplicate
  call sort(self.mode_set)        | lockvar  self.mode_set
  call sort(self.modes_duplicate) | lockvar  self.modes_duplicate

  " clean up functions & commands
  delfunction AddBundles
  delfunction MergeConfigs
  delfunction SetTitle

  unlet s:cursor
  unlet s:stack
endfunction
" }}}2

function s:cham.loadMetas() dict                                                  "    {{{2
  for name in self.meta_set
    " initialize the global temp dict
    let g:this_meta = {}

    execute 'source ' . self.metas_dir . '/' . name

    let dir = substitute(name, '@.*$', '', '')
    let g:this_meta.vimplug_cmd_dict.dir = '~/.vim/plugged/' . dir

    call add(self.meta_dicts, g:this_meta)
    unlet g:this_meta
  endfor

  lockvar! self.meta_dicts
endfunction
" }}}2

function s:cham.initBundles() dict                                                "    {{{2
  for meta in self.meta_dicts
    call meta.config()
  endfor

  unlock! self.meta_dicts
  unlet self.meta_dicts
endfunction
" }}}2

function s:cham.metasAvail() dict                                                 "    {{{2
  let metas = glob(self.metas_dir . '/*', 1, 1)
  call map(metas, 'fnamemodify(v:val, ":t:r")')
  return metas
endfunction
" }}}2

function s:cham.modesAvail() dict                                                 "    {{{2
  let modes = glob(self.modes_dir . '/*', 1, 1)
  call map(modes, 'fnamemodify(v:val, ":t:r")')
  return modes
endfunction
" }}}2

" NOTE: currrently unused
function s:cham.repoAvail() dict                                                  "    {{{2
  let metas_installed = glob(self.repo_dir . '/*', 1, 1)
  call map(metas_installed, 'fnamemodify(v:val, ":t:r")')
  return metas_installed
endfunction
" }}}2

function s:cham.manager.init() dict                                               "    {{{2
  call plug#begin('~/.vim/plugged')

  for meta in s:cham.meta_dicts
    execute "Plug " . string(meta.site) . ', ' .
          \ string(meta.vimplug_cmd_dict)
  endfor

  call plug#end()
endfunction
" }}}2

function s:cham.info() dict                                                       "    {{{2
  " mode name
  "echohl Title
  "echon printf("%-14s ", 'Mode:')
  "echohl Identifier
  "echon printf("%s\n", self.title)

  " mode file name
  echohl Title
  echon printf("%-14s ", 'Mode file:')
  echohl Identifier
  echon printf("%s\n", self.mode_name)

  " bundle manager name
  "echohl Title
  "echon printf("%-14s ", 'Manager:')
  "echohl Identifier
  "echon printf("%s\n", self.manager.name)

  " long delimiter line.
  echohl Number
  echon printf("%-3d ", len(self.meta_set))
  echohl Title
  echon printf("%-14s ", "Metas Enrolled")

  echohl Delimiter
  echon '-'
  for n in range(&columns - 38)
    echon '-'
    let n = n " suppres vimlint complaining.
  endfor

  echohl Number
  echon printf(" in %2d ", len(self.mode_set) + 1)
  echohl Title
  echon "Mode files"
  call self.dumpTree(self.tree, ['.'])

  " must have.
  echohl None
endfunction "}}}2

function s:cham.dumpTree(dict, path) dict                                         "    {{{2
  " arg path: a list record recursion path.
  let max_width = max(map(self.meta_set[:], 'len(v:val)')) + 2
  let fields = (&columns - len(self.prefix)) / max_width

  " print tree path.
  echohl Title
  echo join(a:path, '/') . ':'

  " print meta list.
  echohl Special

  if empty(a:dict.metas)
    echo self.prefix . '< empty >'
  else
    for i in range(len(a:dict.metas))
      if i % fields == 0 | echo self.prefix | endif
      if index(self.metas_duplicate, a:dict.metas[i]) != -1
        echohl MoreMsg
      endif
      execute 'echon printf("%-' . max_width . 's", a:dict.metas[i])'
      echohl Special
    endfor
  endif

  " print sub-modes.
  for [name, mode] in items(a:dict.modes)
    call self.dumpTree(mode, add(a:path[:], name))
  endfor

  echohl None
endfunction
" }}}2

function s:cham.editMode(arg) dict                                                "    {{{2
  let names = split(a:arg)
  if len(names) > 2
    echoerr 'Too many arguments, at most 2 arguemnts is needed'
    return
  endif

  try
    if len(names) == 0 " Edit current mode.
      let file_path = self.modes_dir . '/' . self.mode_name
      execute mudox#query_open_file#New(file_path)
    else " edit a new or existing mode.
      let file_path = self.modes_dir . '/' . names[0]

      if filereadable(file_path) " edit a existing file.
        execute mudox#query_open_file#New(file_path)
      else " edit a new file.
        " read template content if any.
        if filereadable(self.mode_tmpl)
          let tmpl = readfile(self.mode_tmpl)
        else
          echohl WarningMsg
          echo 'Template file [' . self.mode_tmpl
                \ . "] unreadable"
          echo "creating an empty mode ..."
          echohl None
        endif

        call mudox#query_open_file#New(file_path)
        setlocal filetype=vim
        setlocal foldmethod=marker
        setlocal fileformat=unix

        if exists('tmpl')
          call append(0, tmpl)
          delete _
        endif
      endif
    endif
  catch /^mudox#query_open_file: Canceled$/
    echohl WarningMsg | echo '* EditMode: Canceled *' | echohl None
    return
  endtry
endfunction
" }}}2

function s:cham.editMeta(name) dict                                               "    {{{2
  let file_name = self.metas_dir . '/' . a:name

  try
    call mudox#query_open_file#New(file_name) " gvie user chance to cancel.
  catch /^mudox#query_open_file: Canceled$/
    echohl WarningMsg | echo '* EditMeta: Canceled *' | echohl None
    return
  endtry

  if !filereadable(file_name)
    " read template content
    if filereadable(self.meta_tmpl)
      let tmpl = readfile(self.meta_tmpl)
    else
      echohl WarningMsg
      echo 'Mode template file [' . self.meta_tmpl . '] unreadable'
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
    let repo_addr = self.peekUrl()
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

function s:cham.peekUrl() dict                                                    "    {{{2
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
" these function only survive during the only invocation of s:cham.init().

function AddBundles(list)                                                         "    {{{2
  call s:cham.addMetas(a:list)
endfunction
" }}}2

function MergeConfigs(list)                                                       "    {{{2
  call s:cham.mergeModes(a:list)
endfunction
" }}}2

function SetTitle(name)                                                           "    {{{2
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

function mudox#chameleon#Init()                                                   "    {{{2
  " try to download & install Vim-Plug if not.
  " for bootstrapping.
  if empty(glob('~/.vim/autoload/plug.vim'))
    echohl WarningMsg | echo "vim-plug not available, try install ..." | echohl None
    silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
          \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    autocmd VimEnter * PlugInstall
  endif

  call s:cham.init()
endfunction " }}}2

function mudox#chameleon#InitBundles()                                            "    {{{2
  call s:cham.initBundles()
endfunction " }}}2

function mudox#chameleon#ModeList()                                               "    {{{2
  return s:cham.modesAvail()
endfunction "  }}}2

function mudox#chameleon#MetaList()                                               "    {{{2
  return s:cham.metasAvail()
endfunction "  }}}2

function mudox#chameleon#TopModeList()                                            "    {{{2
  return filter(s:cham.modesAvail(), 'v:val !~# "^x_"')
endfunction "  }}}2

" :ChamInfo                                                                            {{{2
command ChamInfo call mudox#chameleon#Info()
function mudox#chameleon#Info()
  call s:cham.info()
endfunction

" }}}2

" autocmd VimEnter                                                                     {{{2
autocmd VimEnter * call <SID>OnVimEnter()

function <SID>OnVimEnter()
  let title = get(s:cham, 'title', s:cham.mode_name)

  silent set title
  let &titlestring = title
endfunction

" }}}2

let g:mdx_chameleon = s:cham

"}}}1
