local promise = require 'promise'
local adapter = require 'docker.adapter'

local M = {}

function M.list(cb)
  adapter
    .container_list()
    :next(function(containers)
      local state_info = {
        running = { priority = 1, color = 'green' },
        exited = { priority = 2, color = 'red' },
        created = { priority = 3, color = 'yellow' },
      }

      table.sort(containers, function(a, b)
        local a_priority = state_info[a.state] and state_info[a.state].priority or 4
        local b_priority = state_info[b.state] and state_info[b.state].priority or 4

        return a_priority < b_priority
      end)

      local entries = lc.tbl_map(function(container)
        local display_parts = {
          container.name:fg(state_info[container.state] and state_info[container.state].color or 'white'),
          ' ',
          container.image:fg 'blue',
        }

        return {
          key = container.id,
          display = lc.style.line(display_parts),
          container = container,
        }
      end, containers)

      local lines = lc.tbl_map(function(line) return line.display end, entries)

      lc.style.align_columns(lines)

      cb(entries)
    end)
    :catch(function(err) lc.notify('Failed to list containers: ' .. tostring(err)) end)
end

function M.preview(entry, cb)
  local detail_area = adapter
    .inspect_container(entry.container.id)
    :next(function(detail)
      local container = entry.container
      local config = detail.Config or {}
      local log_config = detail.HostConfig and detail.HostConfig.LogConfig or {}
      local log_type = log_config.Type or 'unknown'
      local lines = {
        lc.style.line({ '🆔 ID: ', container.id or 'unknown' }):fg 'magenta',
        lc.style.line({ '📊 State: ', container.state or 'unknown' }):fg 'yellow',
        lc.style.line({ 'ℹ️ Status: ', container.status or 'unknown' }):fg 'cyan',
        lc.style.line({ '⌨️ Command: ', table.concat(config.Cmd or {}, ' ') }):fg 'blue',
        lc.style.line({ '🚪 Entrypoint: ', table.concat(config.Entrypoint or {}, ' ') }):fg 'yellow',
        lc.style.line({ '📋 Log Driver: ', log_type }):fg 'cyan',
      }
      if container.ports and container.ports ~= '' and type(container.ports) == 'string' then
        table.insert(lines, lc.style.line({ '🔌 Ports: ', container.ports }):fg 'magenta')
      end
      if container.created then
        table.insert(lines, lc.style.line({ '📅 Created: ', container.created }):fg 'green')
      end
      lc.style.align_columns(lines)
      return lines
    end)
    :catch(function(err) lc.notify('Failed to get container details: ' .. tostring(err)) end)

  local log_area = adapter
    .get_log_cmd(entry.container.id, entry.container.name, false)
    :next(function(cmd)
      return adapter.exec(cmd)
    end)
    :next(function(logs)
      local lines = {
        ('Logs: '):fg 'blue',
        logs,
      }
      return lines
    end)
    :catch(function(err) lc.notify('Failed to get container logs: ' .. tostring(err)) end)

  promise.all({ detail_area, log_area }):next(function(results)
    local lines = results[1]
    table.insert(lines, ' ')
    lc.list_extend(lines, results[2])
    cb(lc.style.text(lines))
  end)
end

-- 辅助函数：获取当前选中的容器信息
local function get_selected_container()
  local entry = lc.api.page_get_hovered()
  if not entry or not entry.container then return nil end
  return entry
end

function M.select_action()
  local entry = get_selected_container()
  if not entry then
    lc.notify 'Please select a container first'
    return
  end

  local container = entry.container
  local options = {}

  -- 根据容器状态显示不同操作
  if container.state == 'running' then
    table.insert(options, {
      value = 'follow_logs',
      display = lc.style.line { ('📋 Follow Logs'):fg 'blue' },
    })
    table.insert(options, {
      value = 'exec',
      display = lc.style.line { ('💻 Exec'):fg 'yellow' },
    })
    table.insert(options, {
      value = 'stop',
      display = lc.style.line { ('⏹️ Stop'):fg 'red' },
    })
    table.insert(options, {
      value = 'restart',
      display = lc.style.line { ('🔄 Restart'):fg 'blue' },
    })
    table.insert(options, {
      value = 'pause',
      display = lc.style.line { ('⏸️ Pause'):fg 'yellow' },
    })
  elseif container.state == 'paused' then
    table.insert(options, {
      value = 'unpause',
      display = lc.style.line { ('▶️ Unpause'):fg 'green' },
    })
    table.insert(options, {
      value = 'stop',
      display = lc.style.line { ('⏹️ Stop'):fg 'red' },
    })
    table.insert(options, {
      value = 'stats',
      display = lc.style.line { ('📊 Stats'):fg 'magenta' },
    })
  else
    -- exited, created 等状态
    table.insert(options, {
      value = 'start',
      display = lc.style.line { ('▶️ Start'):fg 'green' },
    })

    table.insert(options, {
      value = 'remove',
      display = lc.style.line { ('🗑️ Remove'):fg 'red' },
    })
  end

  table.insert(options, {
    value = 'inspect',
    display = lc.style.line { ('🔍 Inspect'):fg 'cyan' },
  })

  table.insert(options, {
    value = 'all_logs',
    display = lc.style.line { ('📋 All Logs'):fg 'blue' },
  })

  lc.select({
    prompt = 'Select an action',
    options = options,
  }, function(choice)
    if choice then M[choice](container) end
  end)
end

local function operate_container(action_name, container_name)
  lc.notify(string.format('Operating container %s: %s', container_name, action_name))
  lc.system({ 'docker', 'container', action_name, container_name }, function(out)
    if out.code == 0 then
      lc.notify(string.format('Container %s %sed successfully', container_name, action_name))
      lc.cmd 'reload'
    else
      lc.notify(string.format('Failed to %s container %s', action_name, container_name))
    end
  end)
end

-- 容器操作
function M.start(container) operate_container('start', container.name) end

function M.stop(container) operate_container('stop', container.name) end

function M.restart(container) operate_container('restart', container.name) end

function M.pause(container) operate_container('pause', container.name) end

function M.unpause(container) operate_container('unpause', container.name) end

function M.remove(container) operate_container('rm', container.name) end

function M.follow_logs(container)
  adapter
    .get_log_cmd(container.id, container.name, true)
    :next(function(cmd)
      lc.interactive(cmd)
    end)
    :catch(function(err)
      lc.notify('Failed to get log command: ' .. tostring(err))
    end)
end

function M.exec(container) lc.interactive { 'docker', 'exec', '-it', container.id, '/bin/sh' } end

function M.stats(container) lc.interactive { 'docker', 'container', 'stats', container.id } end

function M.inspect(container)
  adapter
    .exec({ 'docker', 'inspect', container.id })
    :next(function(stdout) lc.api.page_set_preview(lc.style.highlight(stdout, 'json')) end)
    :catch(function(stderr) lc.notify('Failed to get container details: ' .. tostring(stderr)) end)
end

function M.all_logs(container)
  adapter
    .get_log_cmd(container.id, container.name, false)
    :next(function(cmd)
      return adapter.exec(cmd)
    end)
    :next(function(stdout) lc.api.page_set_preview(stdout) end)
    :catch(function(stderr) lc.notify('Failed to get container logs: ' .. tostring(stderr)) end)
end

return M
