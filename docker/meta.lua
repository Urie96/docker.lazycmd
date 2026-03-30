local action = require 'docker.action'

local M = {}

local function add_keymap(targets, key, callback, desc)
  if not key or key == '' then return end
  for _, target in ipairs(targets) do
    target[key] = { callback = callback, desc = desc }
  end
end

local metas = {
  resource = {
    __index = {
      keymap = {},
      preview = function(entry, cb)
        action.preview_resource(entry, cb)
      end,
    },
  },
  container = {
    __index = {
      keymap = {},
      preview = function(entry, cb)
        action.preview_container(entry, cb)
      end,
    },
  },
  image = {
    __index = {
      keymap = {},
      preview = function(entry, cb)
        action.preview_image(entry, cb)
      end,
    },
  },
  info = {
    __index = {
      keymap = {},
      preview = function(entry, cb)
        action.preview_info(entry, cb)
      end,
    },
  },
}

function M.setup(cfg)
  local keymap = (cfg or {}).keymap or {}
  local container_map = metas.container.__index.keymap
  local image_map = metas.image.__index.keymap

  for _, map in ipairs({ container_map, image_map }) do
    for key, _ in pairs(map) do
      map[key] = nil
    end
  end

  add_keymap({ container_map }, keymap.action, action.select_container_action, 'container actions')
  add_keymap({ container_map }, keymap.inspect, action.inspect_container, 'inspect container')
  add_keymap({ container_map }, keymap.logs, action.show_logs, 'show logs')
  add_keymap({ container_map }, keymap.shell, action.exec_shell, 'open shell')
  add_keymap({ container_map }, keymap.stats, action.stats, 'container stats')
  add_keymap({ container_map }, keymap.start, action.start_container, 'start container')
  add_keymap({ container_map }, keymap.stop, action.stop_container, 'stop container')
  add_keymap({ container_map }, keymap.restart, action.restart_container, 'restart container')
  add_keymap({ container_map }, keymap.pause, action.pause_container, 'pause container')
  add_keymap({ container_map }, keymap.unpause, action.unpause_container, 'unpause container')
  add_keymap({ container_map }, keymap.remove, action.remove_container, 'remove container')

  add_keymap({ image_map }, keymap.action, action.select_image_action, 'image actions')
  add_keymap({ image_map }, keymap.inspect, action.inspect_image, 'inspect image')
  add_keymap({ image_map }, keymap.pull, action.pull_image, 'pull image')
  add_keymap({ image_map }, keymap.save, action.save_image, 'save image')
  add_keymap({ image_map }, keymap.remove, action.remove_image, 'remove image')
end

function M.attach(entries)
  for i, entry in ipairs(entries or {}) do
    local mt = metas[entry.kind]
    if mt then entries[i] = setmetatable(entry, mt) end
  end
  return entries
end

return M
