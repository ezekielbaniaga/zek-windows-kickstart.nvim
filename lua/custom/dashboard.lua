-- Animated btop-style start screen.
--  Fake cpu/mem/net/proc panels animate in the background, with a centered
--  popup holding the "ZEK NEOVIM" logo, the usual :intro info and quick keys.
--  Reopen it anytime with :ZekDash

local M = {}

local api = vim.api
local ns = api.nvim_create_namespace 'zek-dashboard'

local FRAME_MS = 125
local GRAD_STEPS = 12

-- Colors
local logo_stops = { '#5fd7ff', '#8f8fff', '#d787ff', '#ff6fb5' }
local cpu_stops = { '#4cae6b', '#b3ad45', '#c0504d' }
local net_stops = { '#4b6fb3', '#7d5bbf', '#b0569e' }
local plain = {
  ZekLogoShadow = { fg = '#5f5f87' },
  ZekBorder = { fg = '#4e4e4e' },
  ZekTitle = { fg = '#bcbcbc', bold = true },
  ZekTitleNum = { fg = '#ff875f' },
  ZekLabel = { fg = '#8a8a8a' },
  ZekMeterEmpty = { fg = '#303030' },
  ZekPopupBorder = { fg = '#af87ff' },
  ZekVersion = { fg = '#ffffff', bold = true },
  ZekText = { fg = '#c6c6c6' },
  ZekMuted = { fg = '#808080' },
  ZekCmd = { fg = '#87d7ff' },
  ZekKey = { fg = '#ffaf5f', bold = true },
}

-- Big letters (ANSI Shadow style)
-- stylua: ignore
local glyphs = {
  Z = { '███████╗', '╚══███╔╝', '  ███╔╝ ', ' ███╔╝  ', '███████╗', '╚══════╝' },
  E = { '███████╗', '██╔════╝', '█████╗  ', '██╔══╝  ', '███████╗', '╚══════╝' },
  K = { '██╗  ██╗', '██║ ██╔╝', '█████╔╝ ', '██╔═██╗ ', '██║  ██╗', '╚═╝  ╚═╝' },
  N = { '███╗   ██╗', '████╗  ██║', '██╔██╗ ██║', '██║╚██╗██║', '██║ ╚████║', '╚═╝  ╚═══╝' },
  O = { ' ██████╗ ', '██╔═══██╗', '██║   ██║', '██║   ██║', '╚██████╔╝', ' ╚═════╝ ' },
  V = { '██╗   ██╗', '██║   ██║', '██║   ██║', '╚██╗ ██╔╝', ' ╚████╔╝ ', '  ╚═══╝  ' },
  I = { '██╗', '██║', '██║', '██║', '██║', '╚═╝' },
  M = { '███╗   ███╗', '████╗ ████║', '██╔████╔██║', '██║╚██╔╝██║', '██║ ╚═╝ ██║', '╚═╝     ╚═╝' },
  [' '] = { '   ', '   ', '   ', '   ', '   ', '   ' },
}

local BARS = { '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' }

local keys = {
  { 'e', 'File explorer' },
  { 'f', 'Find files' },
  { 'r', 'Recent files' },
  { 'g', 'Live grep' },
  { 'c', 'Config' },
  { 'l', 'Lazy' },
  { 'm', 'Mason' },
  { 'n', 'New file' },
  { 'q', 'Quit' },
}

local proc_names = {
  'nvim',
  'lua-language-server',
  'jdtls',
  'godot',
  'zsh',
  'tmux',
  'Xorg',
  'pipewire',
  'firefox',
  'kitty',
  'dbus-daemon',
  'systemd',
  'NetworkManager',
  'stylua',
  'git',
  'ssh-agent',
  'gvfsd',
  'polkitd',
  'cron',
  'rg',
}

--- Helpers

local function chars(s)
  if not s:find '[\128-\255]' then
    local t = {}
    for i = 1, #s do
      t[i] = s:sub(i, i)
    end
    return t
  end
  return vim.fn.split(s, '\\zs')
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function grad_idx(t)
  return math.floor(clamp(t, 0, 1) * (GRAD_STEPS - 1) + 0.5) + 1
end

local function lerp_color(stops, t)
  local n = #stops - 1
  local seg = math.min(math.floor(t * n), n - 1)
  local lt = t * n - seg
  local a, b = stops[seg + 1], stops[seg + 2]
  local out = {}
  for i = 0, 2 do
    local ca = tonumber(a:sub(2 + i * 2, 3 + i * 2), 16)
    local cb = tonumber(b:sub(2 + i * 2, 3 + i * 2), 16)
    out[#out + 1] = math.floor(ca + (cb - ca) * lt + 0.5)
  end
  return string.format('#%02x%02x%02x', out[1], out[2], out[3])
end

local function define_hl()
  for i = 1, GRAD_STEPS do
    local t = (i - 1) / (GRAD_STEPS - 1)
    api.nvim_set_hl(0, 'ZekLogo' .. i, { fg = lerp_color(logo_stops, t), bold = true })
    api.nvim_set_hl(0, 'ZekCpu' .. i, { fg = lerp_color(cpu_stops, t) })
    api.nvim_set_hl(0, 'ZekNet' .. i, { fg = lerp_color(net_stops, t) })
  end
  for name, hl in pairs(plain) do
    api.nvim_set_hl(0, name, hl)
  end
end

local function build_logo(text)
  local rows = { {}, {}, {}, {}, {}, {} }
  for i = 1, #text do
    local g = glyphs[text:sub(i, i)]
    local gw = 0
    for r = 1, 6 do
      gw = math.max(gw, api.nvim_strwidth(g[r]))
    end
    for r = 1, 6 do
      local cs = chars(g[r])
      for _ = #cs + 1, gw do
        cs[#cs + 1] = ' '
      end
      vim.list_extend(rows[r], cs)
    end
  end
  return rows
end

local logos = {
  one = build_logo 'ZEK NEOVIM',
  zek = build_logo 'ZEK',
  neovim = build_logo 'NEOVIM',
}

--- Fake system state

local state = {}

local function walk(v, step, mean)
  v = v + (mean - v) * 0.08 + (math.random() - 0.5) * step
  if math.random() < 0.04 then
    v = v + math.random() * 0.4
  end
  return clamp(v, 0.02, 0.98)
end

local function push(hist, v)
  hist[#hist + 1] = v
  if #hist > 600 then
    table.remove(hist, 1)
  end
end

local function init_state()
  math.randomseed(os.time())
  state = {
    tick = 0,
    cpu = {},
    cpu_v = 0.3,
    cores = {},
    mem = { used = 0.55, cached = 0.25, swap = 0.08, root = 0.42, home = 0.67 },
    down = {},
    up = {},
    down_v = 0.3,
    up_v = 0.15,
    procs = {},
  }
  for i = 1, 16 do
    state.cores[i] = math.random() * 0.5
  end
  for i, name in ipairs(proc_names) do
    state.procs[i] = { pid = math.random(300, 99999), name = name, cpu = math.random() * 0.3, mem = math.random() * 6 }
  end
end

local function update_data()
  state.tick = state.tick + 1
  state.cpu_v = walk(state.cpu_v, 0.18, 0.35)
  push(state.cpu, state.cpu_v)
  for i, c in ipairs(state.cores) do
    state.cores[i] = clamp(c + (state.cpu_v - c) * 0.3 + (math.random() - 0.5) * 0.25, 0.01, 0.99)
  end

  local mem = state.mem
  mem.used = clamp(mem.used + (math.random() - 0.5) * 0.02, 0.35, 0.85)
  mem.cached = clamp(mem.cached + (math.random() - 0.5) * 0.015, 0.1, 0.4)
  mem.swap = clamp(mem.swap + (math.random() - 0.5) * 0.005, 0.02, 0.2)

  state.down_v = walk(state.down_v, 0.25, 0.25)
  state.up_v = walk(state.up_v, 0.15, 0.12)
  push(state.down, state.down_v)
  push(state.up, state.up_v)

  for _, p in ipairs(state.procs) do
    p.cpu = clamp(p.cpu + (math.random() - 0.5) * 0.08 + (p.name == 'nvim' and 0.01 or -0.004), 0, 0.9)
  end
  if state.tick % 8 == 0 then
    table.sort(state.procs, function(a, b)
      return a.cpu > b.cpu
    end)
  end
end

--- Canvas: a grid of { char, hl } cells flushed into the buffer each frame

local W, H, cv_ch, cv_hl

local function canvas_reset(w, h)
  W, H, cv_ch, cv_hl = w, h, {}, {}
  for r = 1, h do
    local row = {}
    for c = 1, w do
      row[c] = ' '
    end
    cv_ch[r], cv_hl[r] = row, {}
  end
end

local function put_ch(r, c, ch, hl)
  if r >= 1 and r <= H and c >= 1 and c <= W then
    cv_ch[r][c] = ch
    cv_hl[r][c] = hl
  end
end

local function put(r, c, text, hl)
  for i, ch in ipairs(chars(text)) do
    put_ch(r, c + i - 1, ch, hl)
  end
end

local function box(r, c, h, w, num, title, hl)
  if h < 2 or w < 2 then
    return
  end
  for x = c + 1, c + w - 2 do
    put_ch(r, x, '─', hl)
    put_ch(r + h - 1, x, '─', hl)
  end
  for y = r + 1, r + h - 2 do
    put_ch(y, c, '│', hl)
    put_ch(y, c + w - 1, '│', hl)
  end
  put_ch(r, c, '╭', hl)
  put_ch(r, c + w - 1, '╮', hl)
  put_ch(r + h - 1, c, '╰', hl)
  put_ch(r + h - 1, c + w - 1, '╯', hl)
  if title and w > #title + 6 then
    put_ch(r, c + 1, '┐', hl)
    put_ch(r, c + 2, num, 'ZekTitleNum')
    put(r, c + 3, title, 'ZekTitle')
    put_ch(r, c + 3 + #title, '┌', hl)
  end
end

local function graph(r, c, h, w, hist, prefix)
  local n = #hist
  for x = 0, w - 1 do
    local total = (hist[n - (w - 1 - x)] or 0) * h * 8
    for y = 0, h - 1 do
      local fill = math.floor(total - y * 8 + 0.5)
      if fill > 0 then
        put_ch(r + h - 1 - y, c + x, BARS[math.min(fill, 8)], prefix .. grad_idx(h > 1 and y / (h - 1) or 0))
      end
    end
  end
end

local function meter(r, c, w, v)
  local filled = math.floor(v * w + 0.5)
  for i = 1, w do
    put_ch(r, c + i - 1, '■', i <= filled and 'ZekCpu' .. grad_idx((i - 1) / math.max(w - 1, 1)) or 'ZekMeterEmpty')
  end
end

--- Background panels

local function draw_cpu(h)
  box(1, 1, h, W, '¹', 'cpu', 'ZekBorder')
  local freq = string.format(' %.1f GHz ', 2.4 + state.cpu_v * 2.2)
  put(1, W - #freq - 1, freq, 'ZekLabel')

  local cores_w = W >= 90 and 26 or 0
  local gw = W - 2 - cores_w
  graph(2, 2, h - 2, gw, state.cpu, 'ZekCpu')
  if cores_w == 0 then
    return
  end

  local cx = W - cores_w
  box(2, cx, h - 2, cores_w, nil, nil, 'ZekBorder')
  for i, v in ipairs(state.cores) do
    local row = 2 + i
    if row > h - 2 then
      break
    end
    put(row, cx + 1, string.format('C%-2d', i - 1), 'ZekLabel')
    meter(row, cx + 5, cores_w - 12, v)
    put(row, cx + cores_w - 6, string.format('%4d%%', math.floor(v * 100)), 'ZekText')
  end
end

local function draw_mem(top, h, w)
  box(top, 1, h, w, '²', 'mem', 'ZekBorder')
  local iw = w - 2
  local mem = state.mem
  local entries = {
    { 'Used:', mem.used },
    { 'Available:', 1 - mem.used },
    { 'Cached:', mem.cached },
    { 'Free:', clamp(1 - mem.used - mem.cached, 0, 1) },
    { 'Swap:', mem.swap },
    { 'root:', mem.root },
    { 'home:', mem.home },
  }
  local row = top + 1
  if row <= top + h - 2 then
    put(row, 2, 'Total:', 'ZekTitle')
    put(row, 2 + iw - 9, '31.3 GiB', 'ZekText')
  end
  for _, e in ipairs(entries) do
    row = row + 1
    if row > top + h - 2 then
      break
    end
    put(row, 2, e[1], 'ZekLabel')
    local mw = iw - 11 - 6
    if mw >= 3 then
      meter(row, 13, mw, e[2])
    end
    put(row, 2 + iw - 5, string.format('%3d%%', math.floor(e[2] * 100)), 'ZekText')
  end
end

local function draw_net(top, h, w)
  box(top, 1, h, w, '³', 'net', 'ZekBorder')
  local ih, iw = h - 2, w - 2
  if ih < 1 then
    return
  end
  local dh = math.ceil(ih / 2)
  graph(top + 1, 2, dh, iw, state.down, 'ZekNet')
  graph(top + 1 + dh, 2, ih - dh, iw, state.up, 'ZekNet')
  local down = string.format('▼ %5.1f MiB/s', state.down_v * 85)
  local up = string.format('▲ %5.1f MiB/s', state.up_v * 12)
  put(top + 1, 2 + iw - api.nvim_strwidth(down) - 1, down, 'ZekText')
  if ih - dh >= 1 then
    put(top + h - 2, 2 + iw - api.nvim_strwidth(up) - 1, up, 'ZekText')
  end
end

local function draw_proc(top, h, left, w)
  box(top, left, h, w, '⁴', 'proc', 'ZekBorder')
  local c, pw = left + 1, w - 2
  local pc = c + pw - 6
  local mc = pc - 6
  local name_w = mc - 6 - (c + 8) - 1
  local show_meter = name_w >= 6
  local mm = show_meter and mc - 6 or pc - 6
  if not show_meter then
    name_w = mm - (c + 8) - 1
  end
  if name_w < 4 or h < 4 then
    return
  end

  put(top + 1, c, 'Pid:', 'ZekTitle')
  put(top + 1, c + 8, 'Program:', 'ZekTitle')
  put(top + 1, mm, ' Mem%', 'ZekTitle')
  put(top + 1, pc, ' Cpu%', 'ZekTitle')
  for i, p in ipairs(state.procs) do
    local row = top + 1 + i
    if row > top + h - 2 then
      break
    end
    put(row, c, tostring(p.pid), 'ZekLabel')
    put(row, c + 8, p.name:sub(1, name_w), 'ZekText')
    put(row, mm, string.format('%5.1f', p.mem), 'ZekLabel')
    if show_meter then
      meter(row, mc, 5, p.cpu)
    end
    put(row, pc, string.format('%5.1f', p.cpu * 100), 'ZekText')
  end
end

local function draw_background()
  local cpu_h = math.max(6, math.floor(H * 0.42))
  draw_cpu(cpu_h)
  local top, lh = cpu_h + 1, H - cpu_h
  if lh < 6 then
    return
  end
  local lw = math.floor(W * 0.45)
  local mem_h = math.floor(lh / 2)
  draw_mem(top, mem_h, lw)
  draw_net(top + mem_h, lh - mem_h, lw)
  draw_proc(top, lh, lw + 1, W - lw)
end

--- Popup

local function line_width(segs)
  local w = 0
  for _, s in ipairs(segs) do
    w = w + api.nvim_strwidth(s[1])
  end
  return w
end

local function logo_lines(rows)
  local out, w = {}, #rows[1]
  local phase = state.tick * 0.012
  for _, row in ipairs(rows) do
    local segs = {}
    for x, ch in ipairs(row) do
      local hl
      if ch == '█' then
        -- Ping-pong the gradient across the letters so it slowly shimmers
        local t = ((x - 1) / math.max(w - 1, 1) * 0.6 + phase) % 1
        hl = 'ZekLogo' .. grad_idx(1 - math.abs(2 * t - 1))
      elseif ch ~= ' ' then
        hl = 'ZekLogoShadow'
      end
      segs[#segs + 1] = { ch, hl }
    end
    out[#out + 1] = segs
  end
  return out
end

local function hint(cmd, desc)
  local pad = string.rep(' ', math.max(1, 24 - #cmd - 7))
  return { { 'type  ', 'ZekMuted' }, { cmd, 'ZekCmd' }, { '<Enter>', 'ZekKey' }, { pad .. desc, 'ZekText' } }
end

local function popup_sections(logo)
  local v = vim.version()
  local key_lines = {}
  for i = 1, #keys, 2 do
    local line = {}
    for j = i, math.min(i + 1, #keys) do
      local k = keys[j]
      if j > i then
        line[#line + 1] = { '   ' }
      end
      line[#line + 1] = { ' ' .. k[1] .. ' ', 'ZekKey' }
      line[#line + 1] = { ' ' .. k[2] .. string.rep(' ', 14 - #k[2]), 'ZekText' }
    end
    if #line < 4 then
      line[#line + 1] = { string.rep(' ', 3 + 3 + 15) }
    end
    key_lines[#key_lines + 1] = line
  end

  local ok, lazy = pcall(require, 'lazy')
  local stats = {}
  if ok then
    local s = lazy.stats()
    local icon = vim.g.have_nerd_font and '' or '*'
    stats = { { { icon .. ' ', 'ZekKey' }, { string.format('%d/%d plugins loaded in %.1f ms', s.loaded, s.count, s.startuptime), 'ZekMuted' } } }
  end

  return {
    { prio = 10, lines = logo },
    { prio = 9, lines = { { { string.format('NVIM v%d.%d.%d', v.major, v.minor, v.patch), 'ZekVersion' } } } },
    { prio = 4, lines = { { { 'Nvim is open source and freely distributable', 'ZekText' } }, { { 'https://neovim.io/#chat', 'ZekCmd' } } } },
    {
      prio = 6,
      lines = {
        hint(':help nvim', 'if you are new! '),
        hint(':checkhealth', 'to optimize Nvim'),
        hint(':q', 'to exit         '),
        hint(':help', 'for help        '),
      },
    },
    { prio = 3, lines = { hint(':help news', string.format('to see changes in v%d.%d', v.major, v.minor)) } },
    { prio = 2, lines = { { { 'Help poor children in Uganda!', 'ZekText' } }, hint(':help iccf', 'for information ') } },
    { prio = 8, lines = key_lines },
    { prio = 5, lines = stats },
  }
end

local function sections_height(sections)
  local h = 0
  for i, s in ipairs(sections) do
    h = h + #s.lines + (i > 1 and 1 or 0)
  end
  return h
end

-- Pick the biggest logo that fits, then drop the least important sections until the popup fits
local function popup_lines()
  local max_w, max_h = W - 6, H - 4
  local candidates = {
    function()
      return logo_lines(logos.one)
    end,
    function()
      local l = logo_lines(logos.zek)
      l[#l + 1] = {}
      return vim.list_extend(l, logo_lines(logos.neovim))
    end,
    function()
      return { { { 'Z E K   N E O V I M', 'ZekLogo6' } } }
    end,
  }
  local sections
  for _, make in ipairs(candidates) do
    sections = vim.tbl_filter(function(s)
      if #s.lines == 0 then
        return false
      end
      for _, l in ipairs(s.lines) do
        if line_width(l) > max_w then
          return false
        end
      end
      return true
    end, popup_sections(make()))
    while sections_height(sections) > max_h and #sections > 1 do
      local mi
      for i, s in ipairs(sections) do
        if not mi or s.prio < sections[mi].prio then
          mi = i
        end
      end
      table.remove(sections, mi)
    end
    if sections[1] and sections[1].prio == 10 and sections_height(sections) <= max_h then
      break
    end
  end

  local lines = {}
  for i, s in ipairs(sections) do
    if i > 1 then
      lines[#lines + 1] = {}
    end
    vim.list_extend(lines, s.lines)
  end
  return lines
end

local function draw_popup()
  local lines = popup_lines()
  local pw = 0
  for _, l in ipairs(lines) do
    pw = math.max(pw, line_width(l))
  end
  local h, w = #lines + 4, pw + 6
  local r0 = math.floor((H - h) / 2) + 1
  local c0 = math.floor((W - w) / 2) + 1
  for r = r0, r0 + h - 1 do
    for c = c0, c0 + w - 1 do
      put_ch(r, c, ' ', nil)
    end
  end
  box(r0, c0, h, w, nil, nil, 'ZekPopupBorder')
  for i, segs in ipairs(lines) do
    local x = c0 + math.floor((w - line_width(segs)) / 2)
    for _, s in ipairs(segs) do
      put(r0 + 1 + i, x, s[1], s[2])
      x = x + api.nvim_strwidth(s[1])
    end
  end
end

--- Rendering

local function flush(buf)
  local lines, marks = {}, {}
  for r = 1, H do
    local cr, hr = cv_ch[r], cv_hl[r]
    local byte, run_hl, run_start = 0, nil, 0
    for c = 1, W do
      local hl = hr[c]
      if hl ~= run_hl then
        if run_hl then
          marks[#marks + 1] = { r - 1, run_start, byte, run_hl }
        end
        run_hl, run_start = hl, byte
      end
      byte = byte + #cr[c]
    end
    if run_hl then
      marks[#marks + 1] = { r - 1, run_start, byte, run_hl }
    end
    lines[r] = table.concat(cr)
  end

  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
end

local function render(win)
  canvas_reset(api.nvim_win_get_width(win), api.nvim_win_get_height(win))
  if W >= 40 and H >= 12 then
    draw_background()
  end
  draw_popup()
  flush(M.buf)
end

function M.stop()
  if M.timer then
    M.timer:stop()
    M.timer:close()
    M.timer = nil
  end
end

local function tick()
  if not (M.buf and api.nvim_buf_is_valid(M.buf)) then
    return M.stop()
  end
  local win = vim.fn.bufwinid(M.buf)
  if win == -1 then
    return M.stop()
  end
  update_data()
  render(win)
end

function M.start()
  if M.timer then
    return
  end
  M.timer = vim.uv.new_timer()
  M.timer:start(0, FRAME_MS, vim.schedule_wrap(tick))
end

function M.open()
  local win = api.nvim_get_current_win()
  local old = api.nvim_get_current_buf()
  local buf = api.nvim_create_buf(false, true)
  M.buf = buf

  local bo = vim.bo[buf]
  bo.bufhidden = 'wipe'
  bo.buftype = 'nofile'
  bo.swapfile = false
  bo.undolevels = -1
  bo.filetype = 'zekdash'
  api.nvim_win_set_buf(win, buf)

  local wo = vim.wo[win][0]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = 'no'
  wo.foldcolumn = '0'
  wo.statuscolumn = ''
  wo.colorcolumn = ''
  wo.cursorline = false
  wo.cursorcolumn = false
  wo.list = false
  wo.wrap = false
  wo.spell = false

  -- Drop the empty buffer Neovim starts with
  if old ~= buf and api.nvim_buf_is_valid(old) and api.nvim_buf_get_name(old) == '' and not vim.bo[old].modified then
    if api.nvim_buf_line_count(old) == 1 and api.nvim_buf_get_lines(old, 0, 1, false)[1] == '' then
      pcall(api.nvim_buf_delete, old, {})
    end
  end

  local function map(lhs, rhs)
    vim.keymap.set('n', lhs, rhs, { buffer = buf, nowait = true, silent = true })
  end
  map('e', function()
    require('mini.files').open()
  end)
  map('f', function()
    require('telescope.builtin').find_files()
  end)
  map('r', function()
    require('telescope.builtin').oldfiles()
  end)
  map('g', function()
    require('telescope.builtin').live_grep()
  end)
  map('c', function()
    require('telescope.builtin').find_files { cwd = vim.fn.stdpath 'config' }
  end)
  map('l', '<cmd>Lazy<CR>')
  map('m', '<cmd>Mason<CR>')
  map('n', '<cmd>enew<CR>')
  map('i', '<cmd>enew | startinsert<CR>')
  map('q', '<cmd>qa<CR>')

  local group = api.nvim_create_augroup('zek-dashboard-buf', { clear = true })
  api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = buf,
    callback = function(args)
      if M.buf == args.buf then
        M.stop()
        M.buf = nil
      end
    end,
  })
  api.nvim_create_autocmd('VimResized', {
    group = group,
    buffer = buf,
    callback = tick,
  })
  -- Pause the animation while the terminal is unfocused
  api.nvim_create_autocmd('FocusLost', { group = group, callback = M.stop })
  api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = function()
      if M.buf and api.nvim_buf_is_valid(M.buf) and vim.fn.bufwinid(M.buf) ~= -1 then
        M.start()
      end
    end,
  })

  M.start()
end

function M.setup()
  vim.opt.shortmess:append 'I' -- hide the built-in intro, the dashboard shows it instead
  init_state()
  for _ = 1, 300 do
    update_data()
  end
  define_hl()

  local group = api.nvim_create_augroup('zek-dashboard', { clear = true })
  api.nvim_create_autocmd('ColorScheme', { group = group, callback = define_hl })
  api.nvim_create_autocmd('StdinReadPre', {
    group = group,
    once = true,
    callback = function()
      vim.g.zek_dash_stdin = true
    end,
  })
  api.nvim_create_autocmd('VimEnter', {
    group = group,
    once = true,
    callback = function()
      if vim.fn.argc() > 0 or vim.g.zek_dash_stdin or #api.nvim_list_uis() == 0 then
        return
      end
      local buf = api.nvim_get_current_buf()
      if api.nvim_buf_get_name(buf) ~= '' or vim.bo[buf].modified or api.nvim_buf_line_count(buf) > 1 then
        return
      end
      if api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= '' then
        return
      end
      M.open()
    end,
  })
  api.nvim_create_user_command('ZekDash', M.open, { desc = 'Open the Zek start screen' })
end

return M
