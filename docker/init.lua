-- docker.lazycmd - Docker manager

local M = {}

function M.setup()
  lc.keymap.set('main', '<enter>', function()
    local path = lc.api.get_current_path()
    if #path < 1 then
      lc.cmd 'enter'
    elseif path[1] == 'container' then
      require('docker.container').select_action()
    elseif path[1] == 'image' then
      require('docker.image').select_action()
    end
  end)
end

-- 第1级：显示资源类型
local function list_level_1(cb)
  cb {
    { key = 'container', display = ('📦 Containers'):fg 'yellow' },
    { key = 'image', display = ('🖼️ Images'):fg 'yellow' },
    { key = 'volume', display = ('💾 Volumes'):fg 'yellow' },
    { key = 'network', display = ('🌐 Networks'):fg 'yellow' },
  }
end

-- 第2级：显示指定类型的所有资源
local function list_level_2(path, cb)
  local resource_type = path[1]

  if resource_type == 'container' then
    require('docker.container').list(cb)
  elseif resource_type == 'image' then
    require('docker.image').list(cb)
  end
end

function M.list(path, cb)
  if #path == 0 then
    -- 第1级：资源类型
    list_level_1(cb)
  elseif #path == 1 then
    -- 第2级：具体资源
    list_level_2(path, cb)
  else
    cb {}
  end
end

function M.preview(entry, cb)
  local path = lc.api.get_current_path()

  -- 第1级：显示提示信息
  if #path == 0 then
    cb 'Select a resource type to view'
    return
  elseif #path == 1 then
    if path[1] == 'container' then require('docker.container').preview(entry, cb) end
  else
  end

  -- 第2级：显示资源详细状态
  if #path == 1 then
    if path[1] == 'image' then
      require('docker.image').preview(entry, cb)
      return
    end
  end

  cb 'No preview available'
end

return M
