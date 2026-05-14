local adapter = require 'docker.adapter'

local M = {}

function M.list(cb)
  adapter
    .image_list()
    :next(function(images)
      -- 按创建时间排序（新的在前）
      table.sort(images, function(a, b)
        local a_time = a.created_at or ''
        local b_time = b.created_at or ''
        return a_time > b_time
      end)

      local entries = deck.tbl_map(function(image)
        local display_parts = {
          (image.repository .. ':' .. image.tag):fg 'yellow',
          ' ',
          tostring(image.size):fg 'cyan',
        }

        return {
          key = image.id,
          display = deck.style.line(display_parts),
          image = image,
        }
      end, images)

      local lines = deck.tbl_map(function(line) return line.display end, entries)

      deck.style.align_columns(lines)

      cb(entries)
    end)
    :catch(function(err) deck.notify('Failed to list images: ' .. tostring(err)) end)
end

function M.preview(entry, cb)
  local detail_area = adapter
    .inspect_image(entry.image.id)
    :next(function(detail)
      local image = entry.image
      local config = detail.Config or {}

      local lines = {
        deck.style.line({ '🆔 ID: ', image.id or 'unknown' }):fg 'bright_magenta',
        deck.style.line({ '📅 Created: ', image.created_since or 'unknown' }):fg 'green',
      }

      -- 添加镜像配置信息
      if config.Cmd and #config.Cmd > 0 then
        table.insert(lines, deck.style.line({ '⌨️ Cmd: ', table.concat(config.Cmd, ' ') }):fg 'blue')
      end

      if config.Entrypoint and #config.Entrypoint > 0 then
        table.insert(lines, deck.style.line({ '🚪 Entrypoint: ', table.concat(config.Entrypoint, ' ') }):fg 'yellow')
      end

      if config.WorkingDir then
        table.insert(lines, deck.style.line({ '📁 WorkingDir: ', config.WorkingDir }):fg 'bright_blue')
      end

      local arch = detail.Architecture
      if arch then table.insert(lines, deck.style.line({ '🖥️ Architecture: ', arch }):fg 'bright_green') end

      local os_type = detail.Os
      if os_type then table.insert(lines, deck.style.line({ '💻 OS: ', os_type }):fg 'bright_green') end

      if config.ExposedPorts then
        local ports = {}
        for port, _ in pairs(config.ExposedPorts) do
          table.insert(ports, port)
        end
        table.insert(lines, deck.style.line({ '🔌 Exposed Ports: ', table.concat(ports, ', ') }):fg 'bright_magenta')
      end

      if config.Env and #config.Env > 0 then
        table.insert(lines, deck.style.line({ '🌎 Environment:' }):fg 'cyan')
        for _, env in ipairs(config.Env) do
          table.insert(lines, ('    ' .. env):fg 'cyan')
        end
      end

      deck.style.align_columns(lines)
      return lines
    end)
    :catch(function(err)
      deck.notify('Failed to get image details: ' .. tostring(err))
      return { 'Failed to get image details' }
    end)

  -- 获取使用该镜像的容器
  local container_area = adapter
    .container_list()
    :next(function(containers)
      containers = deck.tbl_filter(function(data)
        -- 检查容器是否使用当前镜像
        return data.image == entry.image.repository .. ':' .. entry.image.tag
          or data.image:sub(1, entry.image.id:len()) == entry.image.id
      end, containers)

      if #containers > 0 then
        local lines = {
          ' ',
          ('Containers using this image (' .. #containers .. '):'):fg 'yellow',
        }
        for _, container in ipairs(containers) do
          local color = container.state == 'running' and 'green' or 'red'
          table.insert(lines, deck.style.line { '  • ', container.name:fg(color), ' ', container.state:fg 'white' })
        end
        return lines
      else
        return { ' ', ('No containers using this image'):fg 'gray' }
      end
    end)
    :catch(function(err) deck.notify('Failed to get container list' .. tostring(err)) end)

  local history_area = adapter
    .image_history(entry.image.id)
    :next(function(layers)
      local lines = {
        ' ',
        ' ',
        deck.style.line { 'SIZE', ' ', 'COMMAND' },
      }
      for _, layer in ipairs(layers) do
        table.insert(lines, deck.style.line { tostring(layer.size):fg 'cyan', ' ', layer.created_by })
      end

      deck.style.align_columns(lines)
      return lines
    end)
    :catch(function(err) deck.notify('Failed to get image history' .. tostring(err)) end)

  Promise.all({ detail_area, container_area, history_area }):next(function(results)
    local lines = results[1]
    deck.list_extend(lines, results[2])
    deck.list_extend(lines, results[3])
    cb(deck.style.text(lines))
  end)
end

-- 辅助函数：获取当前选中的镜像信息
local function get_selected_image()
  local entry = deck.api.get_hovered()
  if not entry or not entry.image then return nil end
  return entry
end

function M.select_action()
  local entry = get_selected_image()
  if not entry then
    deck.notify 'Please select an image first'
    return
  end

  local image = entry.image
  local options = {
    { value = 'inspect', display = deck.style.line { ('🔍 Inspect'):fg 'cyan' } },
    { value = 'remove', display = deck.style.line { ('🗑️ Remove'):fg 'red' } },
    { value = 'pull', display = deck.style.line { ('⬇️ Pull/Update'):fg 'blue' } },
    { value = 'save', display = deck.style.line { ('💾 Save to file'):fg 'green' } },
  }

  deck.select({
    prompt = 'Select an action',
    options = options,
  }, function(choice)
    if choice then M[choice](image) end
  end)
end

function M.inspect(image)
  local hovered_path = deck.api.get_hovered_path()
  adapter
    .exec({ 'docker', 'image', 'inspect', image.id })
    :next(function(stdout) deck.api.set_preview(hovered_path, deck.style.highlight(stdout, 'json')) end)
    :catch(function(stderr) deck.notify('Failed to inspect image: ' .. tostring(stderr)) end)
end

function M.pull(image)
  local image_ref = image.repository .. ':' .. image.tag
  deck.notify('Pulling image: ' .. image_ref)
  deck.interactive { 'docker', 'pull', image_ref }
end

function M.remove(image)
  local image_ref = image.repository .. ':' .. image.tag
  deck.confirm {
    prompt = 'Remove image: ' .. image_ref .. '?',
    on_confirm = function()
      deck.notify('Removing image: ' .. image_ref)
      deck.system({ 'docker', 'rmi', image.id }, function(out)
        if out.code == 0 then
          deck.notify 'Image removed successfully'
          deck.cmd 'reload'
        else
          deck.notify('Failed to remove image: ' .. out.stderr)
        end
      end)
    end,
  }
end

function M.save(image)
  local filename = image.repository:gsub('/', '-') .. '-' .. image.tag .. '.tar'
  deck.confirm {
    prompt = 'Save image to file: ' .. filename .. '?',
    on_confirm = function()
      deck.notify('Saving image to file: ' .. filename)
      deck.system({ 'docker', 'save', image.id, '-o', filename }, function(out)
        if out.code == 0 then
          deck.notify 'Image saved successfully'
        else
          deck.notify('Failed to save image: ' .. out.stderr)
        end
      end)
    end,
  }
end

return M
