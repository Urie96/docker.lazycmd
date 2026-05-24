local adapter = require 'docker.adapter'
local action = require 'docker.action'
local config = require 'docker.config'

local M = {}

function M.meta()
  return {
    icon = '󰡨',
    desc = 'Docker containers and images',
    color = 'cyan',
  }
end

local function span(text, color)
  local s = deck.style.span(tostring(text or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function line(parts) return deck.style.line(parts) end

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
    selectable = false,
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

  local entries = deck.tbl_map(function(container)
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

  deck.style.align_columns(deck.tbl_map(function(entry) return entry.display end, entries))
  return entries
end

local function build_image_entries(images)
  table.sort(images, function(a, b)
    return tostring(a.created_at or '') > tostring(b.created_at or '')
  end)

  local entries = deck.tbl_map(function(image)
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

  deck.style.align_columns(deck.tbl_map(function(entry) return entry.display end, entries))
  return entries
end

local function root_entries()
  return {
    resource_entry('container', 'Containers', 'List and operate containers', true),
    resource_entry('image', 'Images', 'List and operate images', true),
    resource_entry('volume', 'Volumes', 'Reserved for future implementation', false),
    resource_entry('network', 'Networks', 'Reserved for future implementation', false),
  }
end

local function with_loading(path, cb, message)
  local expected_path = path
  cb({
    info_entry('loading', message, 'darkgray'),
  })
  return function(handler)
    return function(...)
      if not deck.deep_equal(expected_path, deck.api.get_current_path()) then return end
      handler(...)
    end
  end
end

local function list_containers(path, cb)
  local guard = with_loading(path, cb, 'Loading containers...')
  adapter.container_list():next(guard(function(containers)
    if #containers == 0 then
      cb({
        info_entry('empty', 'No containers found', 'yellow'),
      })
      return
    end
    cb(build_container_entries(containers))
  end)):catch(guard(function(err)
    cb({
      info_entry('error', 'Failed to list containers: ' .. tostring(err), 'red'),
    })
  end))
end

local function list_images(path, cb)
  local guard = with_loading(path, cb, 'Loading images...')
  adapter.image_list():next(guard(function(images)
    if #images == 0 then
      cb({
        info_entry('empty', 'No images found', 'yellow'),
      })
      return
    end
    cb(build_image_entries(images))
  end)):catch(guard(function(err)
    cb({
      info_entry('error', 'Failed to list images: ' .. tostring(err), 'red'),
    })
  end))
end

local function register_page_keymaps()
  local keymap = (config.get() or {}).keymap or {}

  local function map(path, key, callback, desc)
    if key and key ~= '' then
      deck.keymap.set('main', key, callback, { path = path, desc = desc })
    end
  end

  map('/docker/container/**', keymap.action, action.select_container_action, 'container actions')
  map('/docker/container/**', keymap.inspect, action.inspect_container, 'inspect container')
  map('/docker/container/**', keymap.logs, action.show_logs, 'show logs')
  map('/docker/container/**', keymap.shell, action.exec_shell, 'open shell')
  map('/docker/container/**', keymap.stats, action.stats, 'container stats')
  map('/docker/container/**', keymap.start, action.start_container, 'start container')
  map('/docker/container/**', keymap.stop, action.stop_container, 'stop container')
  map('/docker/container/**', keymap.restart, action.restart_container, 'restart container')
  map('/docker/container/**', keymap.pause, action.pause_container, 'pause container')
  map('/docker/container/**', keymap.unpause, action.unpause_container, 'unpause container')
  map('/docker/container/**', keymap.remove, action.remove_container, 'remove container')

  map('/docker/image/**', keymap.action, action.select_image_action, 'image actions')
  map('/docker/image/**', keymap.inspect, action.inspect_image, 'inspect image')
  map('/docker/image/**', keymap.pull, action.pull_image, 'pull image')
  map('/docker/image/**', keymap.save, action.save_image, 'save image')
  map('/docker/image/**', keymap.remove, action.remove_image, 'remove image')
end

function M.setup(opt)
  config.setup(opt or {})
  register_page_keymaps()

  if not deck.system.executable(config.get().command) then
    deck.notify(config.get().command .. ' command not found')
    deck.log('warn', config.get().command .. ' command not found')
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

  cb({
    info_entry('todo', 'This section is not implemented yet.', 'yellow'),
  })
end

function M.preview(entry, cb)
  if not entry then
    cb(deck.style.text { deck.style.line { 'Docker' } })
    return
  end

  if entry.kind == 'resource' then
    action.preview_resource(entry, cb)
    return
  end

  if entry.kind == 'container' then
    action.preview_container(entry, cb)
    return
  end

  if entry.kind == 'image' then
    action.preview_image(entry, cb)
    return
  end

  cb(action.preview_info(entry))
end

return M
