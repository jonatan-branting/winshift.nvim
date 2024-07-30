if !has('nvim-0.5') || exists('g:winshift_nvim_loaded') | finish | endif

command! -complete=customlist,s:completion -nargs=? WinShift lua require("winshift").cmd_winshift(<f-args>)

function s:completion(argLead, cmdLine, curPos)
    return luaeval("require('winshift').completion("
                \ . "vim.fn.eval('a:argLead'),"
                \ . "vim.fn.eval('a:cmdLine'),"
                \ . "vim.fn.eval('a:curPos'))")
endfunction

let g:winshift_nvim_loaded = 1
