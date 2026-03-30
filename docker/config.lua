local M = {}

local cfg = {
  route_name = 'docker',
  title = 'Docker',
  command = 'docker',
  preview_log_lines = 35,
  keymap = {
    action = '<enter>',
    inspect = 'i',
    logs = 'l',
    shell = 'e',
    stats = 's',
    start = 'r',
    stop = 'x',
    restart = 'R',
    pause = 'p',
    unpause = 'u',
    remove = 'd',
    pull = 'P',
    save = 'S',
  },
}

function M.setup(opt)
  local global_keymap = lc.config.get().keymap or {}
  cfg = lc.tbl_deep_extend('force', cfg, { keymap = global_keymap }, opt or {})
end

function M.get() return cfg end

return M
