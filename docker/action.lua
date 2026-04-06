local adapter = require 'docker.adapter'
local config = require 'docker.config'

local M = {}

local function span(text, color)
  local s = lc.style.span(tostring(text or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function line(parts) return lc.style.line(parts) end
local function text(lines) return lc.style.text(lines) end

local function trim_or_empty(value)
  return tostring(value or ''):trim()
end

local function command_name()
  local cfg = config.get() or {}
  return cfg.command or 'docker'
end

local function exec_p(cmd)
  return Promise.new(function(resolve, reject)
    lc.system(cmd, function(out)
      if out.code == 0 then
        resolve(out)
        return
      end

      local err = trim_or_empty(out.stderr)
      if err == '' then err = trim_or_empty(out.stdout) end
      if err == '' then err = table.concat(cmd, ' ') .. ' failed' end
      reject(err)
    end)
  end)
end

local function current_entry(kind)
  local entry = lc.api.get_hovered()
  if type(entry) ~= 'table' or entry.kind ~= kind then return nil end
  return entry
end

local function set_preview(path, lines_or_text)
  lc.api.set_preview(path, lines_or_text)
end

local function notify_error(prefix, err)
  lc.notify(prefix .. ': ' .. trim_or_empty(err))
end

local function reload()
  if (lc.api.get_current_path() or {})[1] == 'docker' then lc.cmd 'reload' end
end

local function container_for(entry)
  entry = entry or current_entry 'container'
  if not entry or not entry.container then
    lc.notify 'No container selected'
    return nil
  end
  return entry.container
end

local function image_for(entry)
  entry = entry or current_entry 'image'
  if not entry or not entry.image then
    lc.notify 'No image selected'
    return nil
  end
  return entry.image
end

local function operate_container(container, args, success_message, error_prefix)
  exec_p(lc.list_extend({ command_name(), 'container' }, args))
    :next(function()
      lc.notify(success_message)
      reload()
    end)
    :catch(function(err) notify_error(error_prefix, err) end)
end

local function log_command(container, follow)
  return adapter.get_log_cmd(container.id, container.name, follow)
end

function M.preview_resource(entry, cb)
  local lines = {
    line { span(entry.title or 'Docker', 'cyan') },
    line { span(entry.description or '', 'darkgray') },
  }

  if not entry.implemented then
    table.insert(lines, line { '' })
    table.insert(lines, line { span('This section is not implemented yet.', 'yellow') })
  end

  cb(text(lines))
end

function M.preview_info(entry, cb)
  cb(text {
    line { span(entry.message or '', entry.color or 'darkgray') },
  })
end

function M.preview_container(entry, cb)
  local container = entry.container
  local detail_area = adapter.inspect_container(container.id):next(function(detail)
    local cfg = detail.Config or {}
    local host_cfg = detail.HostConfig or {}
    local log_cfg = host_cfg.LogConfig or {}
    local lines = {
      line { span('Name', 'cyan'), span(': ' .. tostring(container.name or ''), 'white') },
      line { span('Image', 'cyan'), span(': ' .. tostring(container.image or ''), 'white') },
      line { span('State', 'cyan'), span(': ' .. tostring(container.state or ''), 'white') },
      line { span('Status', 'cyan'), span(': ' .. tostring(container.status or ''), 'white') },
      line { span('ID', 'cyan'), span(': ' .. tostring(container.id or ''), 'darkgray') },
    }

    if trim_or_empty(container.ports) ~= '' then
      table.insert(lines, line { span('Ports', 'cyan'), span(': ' .. container.ports, 'white') })
    end
    if trim_or_empty(container.created) ~= '' then
      table.insert(lines, line { span('Created', 'cyan'), span(': ' .. container.created, 'white') })
    end
    if cfg.Cmd and #cfg.Cmd > 0 then
      table.insert(lines, line { span('Cmd', 'cyan'), span(': ' .. table.concat(cfg.Cmd, ' '), 'white') })
    end
    if cfg.Entrypoint and #cfg.Entrypoint > 0 then
      table.insert(lines, line { span('Entrypoint', 'cyan'), span(': ' .. table.concat(cfg.Entrypoint, ' '), 'white') })
    end
    if trim_or_empty(log_cfg.Type) ~= '' then
      table.insert(lines, line { span('Log Driver', 'cyan'), span(': ' .. log_cfg.Type, 'white') })
    end

    return lines
  end)

  local log_area = log_command(container, false):next(function(cmd)
    return adapter.exec(cmd)
  end):next(function(stdout)
    local lines = {
      line { '' },
      line { span('Recent Logs', 'yellow') },
    }

    for raw in (trim_or_empty(stdout) .. '\n'):gmatch '(.-)\n' do
      if raw ~= '' then table.insert(lines, line { raw }) end
    end

    if #lines == 2 then table.insert(lines, line { span('No logs', 'darkgray') }) end
    return lines
  end)

  Promise.all({ detail_area, log_area }):next(function(results)
    local lines = results[1]
    lc.list_extend(lines, results[2])
    cb(text(lines))
  end):catch(function(err)
    cb(text {
      line { span('Failed to load container preview', 'red') },
      line { span(trim_or_empty(err), 'darkgray') },
    })
  end)
end

function M.preview_image(entry, cb)
  local image = entry.image
  local detail_area = adapter.inspect_image(image.id):next(function(detail)
    local cfg = detail.Config or {}
    local lines = {
      line { span('Reference', 'cyan'), span(': ' .. tostring(image.repository .. ':' .. image.tag), 'white') },
      line { span('ID', 'cyan'), span(': ' .. tostring(image.id or ''), 'darkgray') },
      line { span('Created', 'cyan'), span(': ' .. tostring(image.created_since or image.created_at or ''), 'white') },
      line { span('Size', 'cyan'), span(': ' .. tostring(image.size or ''), 'white') },
    }

    if trim_or_empty(detail.Architecture) ~= '' then
      table.insert(lines, line { span('Arch', 'cyan'), span(': ' .. detail.Architecture, 'white') })
    end
    if trim_or_empty(detail.Os) ~= '' then
      table.insert(lines, line { span('OS', 'cyan'), span(': ' .. detail.Os, 'white') })
    end
    if cfg.Cmd and #cfg.Cmd > 0 then
      table.insert(lines, line { span('Cmd', 'cyan'), span(': ' .. table.concat(cfg.Cmd, ' '), 'white') })
    end
    if cfg.Entrypoint and #cfg.Entrypoint > 0 then
      table.insert(lines, line { span('Entrypoint', 'cyan'), span(': ' .. table.concat(cfg.Entrypoint, ' '), 'white') })
    end

    return lines
  end)

  local history_area = adapter.image_history(image.id):next(function(layers)
    local lines = {
      line { '' },
      line { span('History', 'yellow') },
    }
    for _, layer in ipairs(layers) do
      table.insert(lines, line {
        span(tostring(layer.size or ''), 'cyan'),
        span('  ', 'darkgray'),
        span(layer.created_by or '', 'white'),
      })
    end
    return lines
  end)

  Promise.all({ detail_area, history_area }):next(function(results)
    local lines = results[1]
    lc.list_extend(lines, results[2])
    cb(text(lines))
  end):catch(function(err)
    cb(text {
      line { span('Failed to load image preview', 'red') },
      line { span(trim_or_empty(err), 'darkgray') },
    })
  end)
end

function M.select_container_action(entry)
  local container = container_for(entry)
  if not container then return end

  local options = {}
  local function add(value, label, color)
    table.insert(options, {
      value = value,
      display = line { span(label, color) },
    })
  end

  if container.state == 'running' then
    add('follow_logs', 'Follow Logs', 'blue')
    add('exec_shell', 'Shell', 'yellow')
    add('stats', 'Stats', 'magenta')
    add('stop_container', 'Stop', 'red')
    add('restart_container', 'Restart', 'cyan')
    add('pause_container', 'Pause', 'yellow')
  elseif container.state == 'paused' then
    add('unpause_container', 'Unpause', 'green')
    add('stop_container', 'Stop', 'red')
  else
    add('start_container', 'Start', 'green')
  end

  add('inspect_container', 'Inspect', 'cyan')
  add('show_logs', 'Recent Logs', 'blue')
  add('remove_container', 'Remove', 'red')

  lc.select({
    prompt = 'Container action',
    options = options,
  }, function(choice)
    if choice and M[choice] then M[choice](entry) end
  end)
end

function M.select_image_action(entry)
  local image = image_for(entry)
  if not image then return end

  lc.select({
    prompt = 'Image action',
    options = {
      { value = 'inspect_image', display = line { span('Inspect', 'cyan') } },
      { value = 'pull_image', display = line { span('Pull', 'blue') } },
      { value = 'save_image', display = line { span('Save', 'green') } },
      { value = 'remove_image', display = line { span('Remove', 'red') } },
    },
  }, function(choice)
    if choice and M[choice] then M[choice](entry) end
  end)
end

function M.start_container(entry)
  local container = container_for(entry)
  if not container then return end
  operate_container(container, { 'start', container.name }, 'Started: ' .. container.name, 'Failed to start container')
end

function M.stop_container(entry)
  local container = container_for(entry)
  if not container then return end
  operate_container(container, { 'stop', container.name }, 'Stopped: ' .. container.name, 'Failed to stop container')
end

function M.restart_container(entry)
  local container = container_for(entry)
  if not container then return end
  operate_container(container, { 'restart', container.name }, 'Restarted: ' .. container.name, 'Failed to restart container')
end

function M.pause_container(entry)
  local container = container_for(entry)
  if not container then return end
  operate_container(container, { 'pause', container.name }, 'Paused: ' .. container.name, 'Failed to pause container')
end

function M.unpause_container(entry)
  local container = container_for(entry)
  if not container then return end
  operate_container(container, { 'unpause', container.name }, 'Unpaused: ' .. container.name, 'Failed to unpause container')
end

function M.remove_container(entry)
  local container = container_for(entry)
  if not container then return end

  lc.confirm {
    prompt = 'Remove container: ' .. container.name .. '?',
    on_confirm = function()
      operate_container(container, { 'rm', container.name }, 'Removed: ' .. container.name, 'Failed to remove container')
    end,
  }
end

function M.follow_logs(entry)
  local container = container_for(entry)
  if not container then return end

  log_command(container, true):next(function(cmd)
    lc.interactive(cmd)
  end):catch(function(err)
    notify_error('Failed to open logs', err)
  end)
end

function M.show_logs(entry)
  local container = container_for(entry)
  if not container then return end
  local hovered_path = lc.api.get_hovered_path()

  log_command(container, false):next(function(cmd)
    return adapter.exec(cmd)
  end):next(function(stdout)
    set_preview(hovered_path, stdout)
  end):catch(function(err)
    notify_error('Failed to load logs', err)
  end)
end

function M.exec_shell(entry)
  local container = container_for(entry)
  if not container then return end
  lc.interactive { command_name(), 'exec', '-it', container.id, '/bin/sh' }
end

function M.stats(entry)
  local container = container_for(entry)
  if not container then return end
  lc.interactive { command_name(), 'container', 'stats', container.id }
end

function M.inspect_container(entry)
  local container = container_for(entry)
  if not container then return end
  local hovered_path = lc.api.get_hovered_path()

  adapter.exec({ command_name(), 'inspect', container.id }):next(function(stdout)
    set_preview(hovered_path, lc.style.highlight(stdout, 'json'))
  end):catch(function(err)
    notify_error('Failed to inspect container', err)
  end)
end

function M.inspect_image(entry)
  local image = image_for(entry)
  if not image then return end
  local hovered_path = lc.api.get_hovered_path()

  adapter.exec({ command_name(), 'image', 'inspect', image.id }):next(function(stdout)
    set_preview(hovered_path, lc.style.highlight(stdout, 'json'))
  end):catch(function(err)
    notify_error('Failed to inspect image', err)
  end)
end

function M.pull_image(entry)
  local image = image_for(entry)
  if not image then return end
  lc.interactive { command_name(), 'pull', image.repository .. ':' .. image.tag }
end

function M.remove_image(entry)
  local image = image_for(entry)
  if not image then return end
  local ref = image.repository .. ':' .. image.tag

  lc.confirm {
    prompt = 'Remove image: ' .. ref .. '?',
    on_confirm = function()
      exec_p({ command_name(), 'rmi', image.id }):next(function()
        lc.notify('Removed image: ' .. ref)
        reload()
      end):catch(function(err)
        notify_error('Failed to remove image', err)
      end)
    end,
  }
end

function M.save_image(entry)
  local image = image_for(entry)
  if not image then return end

  local filename = image.repository:gsub('/', '-') .. '-' .. image.tag .. '.tar'
  lc.input {
    prompt = 'Save image to',
    value = filename,
    on_submit = function(input)
      local target = trim_or_empty(input)
      if target == '' then
        lc.notify 'Target path is required'
        return
      end

      exec_p({ command_name(), 'save', image.id, '-o', target }):next(function()
        lc.notify('Saved image to: ' .. target)
      end):catch(function(err)
        notify_error('Failed to save image', err)
      end)
    end,
  }
end

return M
