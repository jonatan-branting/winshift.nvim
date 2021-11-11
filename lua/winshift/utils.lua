local api = vim.api
local M = {}

---@alias vector any[]

local setlocal_opr_templates = {
  set = [[setl ${option}=${value}]],
  remove = [[exe 'setl ${option}-=${value}']],
  append = [[exe 'setl ${option}=' . (&${option} == "" ? "" : &${option} . ",") . '${value}']],
  prepend = [[exe 'setl ${option}=${value}' . (&${option} == "" ? "" : "," . &${option})]],
}

function M._echo_multiline(msg, hl, schedule)
  if schedule then
    vim.schedule(function()
      M._echo_multiline(msg, hl, false)
    end)
    return
  end

  vim.cmd("echohl " .. (hl or "None"))
  for _, line in ipairs(vim.split(msg, "\n")) do
    vim.cmd(string.format('echom "%s"', vim.fn.escape(line, [["\]])))
  end
  vim.cmd("echohl None")
end

---@param msg string
---@param schedule? boolean Schedule the echo call.
function M.info(msg, schedule)
  M._echo_multiline("[WinShift.nvim] " .. msg, "Directory", schedule)
end

---@param msg string
---@param schedule? boolean Schedule the echo call.
function M.warn(msg, schedule)
  M._echo_multiline("[WinShift.nvim] " .. msg, "WarningMsg", schedule)
end

---@param msg string
---@param schedule? boolean Schedule the echo call.
function M.err(msg, schedule)
  M._echo_multiline("[WinShift.nvim] " .. msg, "ErrorMsg", schedule)
end

function M.no_win_event_call(cb)
  local last = vim.opt.eventignore._value
  vim.opt.eventignore = (
      "WinEnter,WinLeave,WinNew,WinClosed,BufEnter,BufLeave"
      .. (last ~= "" and "," .. last or "")
    )
  local ok, err = pcall(cb)
  vim.opt.eventignore = last
  return ok, err
end

---Escape a string for use as a pattern.
---@param s string
---@return string
function M.pattern_esc(s)
  local result = string.gsub(s, "[%(|%)|%%|%[|%]|%-|%.|%?|%+|%*|%^|%$]", {
    ["%"] = "%%",
    ["-"] = "%-",
    ["("] = "%(",
    [")"] = "%)",
    ["."] = "%.",
    ["["] = "%[",
    ["]"] = "%]",
    ["?"] = "%?",
    ["+"] = "%+",
    ["*"] = "%*",
    ["^"] = "%^",
    ["$"] = "%$",
  })
  return result
end

function M.tbl_clone(t)
  if not t then
    return
  end
  local clone = {}

  for k, v in pairs(t) do
    clone[k] = v
  end

  return clone
end

function M.tbl_deep_clone(t)
  if not t then
    return
  end
  local clone = {}

  for k, v in pairs(t) do
    if type(v) == "table" then
      clone[k] = M.tbl_deep_clone(v)
    else
      clone[k] = v
    end
  end

  return clone
end

function M.tbl_pack(...)
  return { n = select("#", ...), ... }
end

function M.tbl_unpack(t, i, j)
  return unpack(t, i or 1, j or t.n or #t)
end

function M.tbl_clear(t)
  for k, _ in pairs(t) do
    t[k] = nil
  end
end

---Create a shallow copy of a portion of a vector.
---@param t vector
---@param first? integer First index, inclusive
---@param last? integer Last index, inclusive
---@return vector
function M.vec_slice(t, first, last)
  local slice = {}
  for i = first or 1, last or #t do
    table.insert(slice, t[i])
  end

  return slice
end

---Join multiple vectors into one.
---@vararg vector
---@return vector
function M.vec_join(...)
  local result = {}
  local args = {...}
  local n = 0

  for i = 1, select("#", ...) do
    if type(args[i]) ~= "nil" then
      if type(args[i]) ~= "table" then
        result[n + 1] = args[i]
        n = n + 1
      else
        for j, v in ipairs(args[i]) do
          result[n + j] = v
        end
        n = n + #args[i]
      end
    end
  end

  return result
end

---Return the first index a given object can be found in a vector, or -1 if
---it's not present.
---@param t vector
---@param v any
---@return integer
function M.vec_indexof(t, v)
  for i, vt in ipairs(t) do
    if vt == v then
      return i
    end
  end
  return -1
end

---Append any number of objects to the end of a vector. Pushing `nil`
---effectively does nothing.
---@param t vector
---@return vector t
function M.vec_push(t, ...)
  for _, v in ipairs({...}) do
    t[#t + 1] = v
  end
  return t
end

---Simple string templating
---Example template: "${name} is ${value}"
---@param str string Template string
---@param table table Key-value pairs to replace in the string
function M.str_template(str, table)
  return (str:gsub("($%b{})", function(w)
    return table[w:sub(3, -2)] or w
  end))
end

function M.clear_prompt()
  vim.cmd("norm! :esc<CR>")
end

function M.input_char(prompt, opt)
  opt = vim.tbl_extend("keep", opt or {}, {
    clear_prompt = true,
    allow_non_ascii = false,
    prompt_hl = nil,
  })

  if prompt then
    vim.api.nvim_echo({ { prompt, opt.prompt_hl } }, false, {})
  end

  local c
  if not opt.allow_non_ascii then
    while type(c) ~= "number" do
      c = vim.fn.getchar()
    end
  else
    c = vim.fn.getchar()
  end

  if opt.clear_prompt then
    M.clear_prompt()
  end

  local s = type(c) == "number" and vim.fn.nr2char(c) or nil
  local raw = type(c) == "number" and s or c
  return s, raw
end

function M.input(prompt, default, completion)
  local v = vim.fn.input({
    prompt = prompt,
    default = default,
    completion = completion,
    cancelreturn = "__INPUT_CANCELLED__",
  })
  M.clear_prompt()
  return v
end

function M.raw_key(vim_key)
  return api.nvim_eval(string.format([["\%s"]], vim_key))
end

---HACK: workaround for inconsistent behavior from `vim.opt_local`.
---@see [Neovim issue](https://github.com/neovim/neovim/issues/14670)
---@param winids number[]|number Either a list of winids, or a single winid (0 for current window).
---`opt` fields:
---   @tfield method '"set"'|'"remove"'|'"append"'|'"prepend"' Assignment method. (default: "set")
---@overload fun(winids: number[]|number, option: string, value: string[]|string|boolean, opt?: any)
---@overload fun(winids: number[]|number, map: table<string, string[]|string|boolean>, opt?: table)
function M.set_local(winids, x, y, z)
  if type(winids) ~= "table" then
    winids = { winids }
  end

  local map, opt
  if y == nil or type(y) == "table" then
    map = x
    opt = y
  else
    map = { [x] = y }
    opt = z
  end

  opt = vim.tbl_extend("keep", opt or {}, { method = "set" })

  local cmd
  local ok, err = M.no_win_event_call(function()
    for _, id in ipairs(winids) do
      api.nvim_win_call(id, function()
        for option, value in pairs(map) do
          local o = opt

          if type(value) == "boolean" then
            cmd = string.format("setl %s%s", value and "" or "no", option)
          else
            if type(value) == "table" then
              ---@diagnostic disable-next-line: undefined-field
              o = vim.tbl_extend("force", opt, value.opt or {})
              value = table.concat(value, ",")
            end

            cmd = M.str_template(
              setlocal_opr_templates[o.method],
              { option = option, value = tostring(value):gsub("'", "''") }
            )
          end

          vim.cmd(cmd)
        end
      end)
    end
  end)

  if not ok then
    error(err)
  end
end

---@param winids number[]|number Either a list of winids, or a single winid (0 for current window).
---@param option string
function M.unset_local(winids, option)
  if type(winids) ~= "table" then
    winids = { winids }
  end

  M.no_win_event_call(function()
    for _, id in ipairs(winids) do
      api.nvim_win_call(id, function()
        vim.cmd(string.format("set %s<", option))
      end)
    end
  end)
end

return M
