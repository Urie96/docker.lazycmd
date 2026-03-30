local adapter = require 'docker.adapter'
local config = require 'docker.config'
local meta = require 'docker.meta'

local M = {}

local function span(text, color)
  local s = lc.style.span(tostring(text or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function line(parts) return lc.style.line(parts) end

local function resource_entry(resource, title, description, implemented)
  return {
    key = resource,
    kind = 'resource',
    resource = resource,
    title = title,
    description = description,
    implemented = implemented,
    display = line {
      span(title, implemented and 'yellow' or 'darkgray'),
      span('  ', 'darkgray'),
      span(description, 'darkgray'),
    },
  }
end

local function info_entry(key, message, color)
  return {
    key = key,
    kind = 'info',
    message = message,
    color = color or 'darkgray',
    display = line {
      span(message, color or 'darkgray'),
    },
  }
end

local function container_state_color(state)
  if state == 'running' then return 'green' end
  if state == 'paused' then return 'yellow' end
  if state == 'created' then return 'cyan' end
  if state == 'exited' then return 'red' end
  return 'darkgray'
end

local function build_container_entries(containers)
  table.sort(containers, function(a, b)
    local order = {
      running = 1,
      paused = 2,
      created = 3,
      exited = 4,
    }
    local left = order[a.state] or 9
    local right = order[b.state] or 9
    if left ~= right then return left < right end
    return string.lower(a.name or '') < string.lower(b.name or '')
  end)

  local entries = lc.tbl_map(function(container)
    return {
      key = container.id,
      kind = 'container',
      container = container,
      display = line {
        span(container.name, container_state_color(container.state)),
        span('  ', 'darkgray'),
        span(container.image, 'blue'),
        span('  ', 'darkgray'),
        span(container.status, 'darkgray'),
      },
    }
  end, containers)

  lc.style.align_columns(lc.tbl_map(function(entry) return entry.display end, entries))
  return meta.attach(entries)
end

local function build_image_entries(images)
  table.sort(images, function(a, b)
    return tostring(a.created_at or '') > tostring(b.created_at or '')
  end)

  local entries = lc.tbl_map(function(image)
    local ref = image.repository .. ':' .. image.tag
    return {
      key = image.id,
      kind = 'image',
      image = image,
      display = line {
        span(ref, 'yellow'),
        span('  ', 'darkgray'),
        span(image.size, 'cyan'),
        span('  ', 'darkgray'),
        span(image.created_since, 'darkgray'),
      },
    }
  end, images)

  lc.style.align_columns(lc.tbl_map(function(entry) return entry.display end, entries))
  return meta.attach(entries)
end

local function root_entries()
  return meta.attach {
    resource_entry('container', 'Containers', 'List and operate containers', true),
    resource_entry('image', 'Images', 'List and operate images', true),
    resource_entry('volume', 'Volumes', 'Reserved for future implementation', false),
    resource_entry('network', 'Networks', 'Reserved for future implementation', false),
  }
end

local function with_loading(path, cb, message)
  local expected_path = path
  cb(meta.attach {
    info_entry('loading', message, 'darkgray'),
  })
  return function(handler)
    return function(...)
      if not lc.deep_equal(expected_path, lc.api.get_current_path()) then return end
      handler(...)
    end
  end
end

local function list_containers(path, cb)
  local guard = with_loading(path, cb, 'Loading containers...')
  adapter.container_list():next(guard(function(containers)
    if #containers == 0 then
      cb(meta.attach {
        info_entry('empty', 'No containers found', 'yellow'),
      })
      return
    end
    cb(build_container_entries(containers))
  end)):catch(guard(function(err)
    cb(meta.attach {
      info_entry('error', 'Failed to list containers: ' .. tostring(err), 'red'),
    })
  end))
end

local function list_images(path, cb)
  local guard = with_loading(path, cb, 'Loading images...')
  adapter.image_list():next(guard(function(images)
    if #images == 0 then
      cb(meta.attach {
        info_entry('empty', 'No images found', 'yellow'),
      })
      return
    end
    cb(build_image_entries(images))
  end)):catch(guard(function(err)
    cb(meta.attach {
      info_entry('error', 'Failed to list images: ' .. tostring(err), 'red'),
    })
  end))
end

function M.setup(opt)
  config.setup(opt or {})
  meta.setup(config.get())

  if not lc.system.executable(config.get().command) then
    lc.notify(config.get().command .. ' command not found')
    lc.log('warn', config.get().command .. ' command not found')
  end
end

function M.list(path, cb)
  if #path == 1 then
    cb(root_entries())
    return
  end

  if path[2] == 'container' then
    list_containers(path, cb)
    return
  end

  if path[2] == 'image' then
    list_images(path, cb)
    return
  end

  cb(meta.attach {
    info_entry('todo', 'This section is not implemented yet.', 'yellow'),
  })
end

return M
