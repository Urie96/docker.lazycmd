local promise = require 'promise'

local M = {}

-- 辅助函数：格式化时间差，类似 Docker 的输出格式
local function format_duration(seconds, ago)
  if not seconds or seconds <= 0 then return ago and 'Just now' or 'Up less than a second' end

  local intervals = {
    { 'year', 365 * 24 * 60 * 60 },
    { 'month', 30 * 24 * 60 * 60 },
    { 'week', 7 * 24 * 60 * 60 },
    { 'day', 24 * 60 * 60 },
    { 'hour', 60 * 60 },
    { 'minute', 60 },
    { 'second', 1 },
  }

  for _, interval in ipairs(intervals) do
    local unit, unit_seconds = interval[1], interval[2]
    local value = math.floor(seconds / unit_seconds)
    if value >= 1 then
      local suffix = value == 1 and '' or 's'
      if ago then
        return string.format('%s %s%s ago', value, unit, suffix)
      else
        return string.format('%s %s%s', value, unit, suffix)
      end
    end
  end

  return ago and 'Just now' or 'less than a second'
end

-- 辅助函数：格式化字节大小为人类可读格式
local function format_size(bytes)
  if not bytes or bytes < 0 then return '' end
  if bytes == 0 then return '0B' end

  local units = {
    { 'TB', 1024 * 1024 * 1024 * 1024 },
    { 'GB', 1024 * 1024 * 1024 },
    { 'MB', 1024 * 1024 },
    { 'kB', 1024 },
    { 'B', 1 },
  }

  for _, unit in ipairs(units) do
    local name, threshold = unit[1], unit[2]
    if bytes >= threshold then
      local value = bytes / threshold
      -- 如果是整数或只有一位小数，简化显示
      if value >= 100 then
        return string.format('%.0f%s', value, name)
      elseif value >= 10 then
        return string.format('%.1f%s', value, name)
      else
        return string.format('%.2f%s', value, name)
      end
    end
  end

  return '0B'
end

-- 辅助函数：统一处理不同格式的容器数据（Docker 和 Podman）
local function normalize_container_data(data)
  -- 处理 ID 字段
  local id = data.ID or data.Id

  -- 处理 Names 字段（Docker 是字符串，Podman 是数组）
  local name
  if type(data.Names) == 'table' then
    name = data.Names[1] or ''
  else
    name = data.Names or ''
  end

  -- 处理 Ports 字段（Docker 是字符串，Podman 是对象数组）
  local ports
  if type(data.Ports) == 'table' then
    -- Podman 格式：将对象数组转换为字符串
    local port_strs = {}
    for _, port in ipairs(data.Ports) do
      local host_port = port.host_port and port.host_port ~= '' and port.host_port or port.container_port
      local mapping = host_port and string.format('%s->%s/%s', host_port, port.container_port, port.protocol or 'tcp')
        or ''
      if mapping ~= '' then table.insert(port_strs, mapping) end
    end
    ports = table.concat(port_strs, ', ')
  else
    -- Docker 格式：直接使用字符串
    ports = data.Ports or ''
  end

  -- 处理创建时间（Podman 可能是空字符串，但有 StartedAt）
  local created = data.CreatedAt
  if not created or created == '' then
    if data.StartedAt and data.StartedAt ~= 0 then
      created = os.date('%Y-%m-%d %H:%M:%S', data.StartedAt)
    else
      created = 'unknown'
    end
  end

  -- 处理状态（Podman 可能是空字符串）
  local state = data.State or ''
  local status = data.Status

  -- 如果 Docker Status 已包含时间信息（如 "Up 21 hours" 或 "Exited (0) 8 months ago"），直接使用
  if status and (status:match '^Up ' or status:match '^Exited %(') then
    -- Docker 格式，直接使用
  elseif not status or status == '' then
    -- Podman 格式，需要自己构建状态和时间信息
    local now = os.time()

    if state == 'exited' then
      -- 退出的容器：使用 ExitedAt 或 ExitCode
      local exit_code = data.ExitCode or 0
      local exited_at = data.ExitedAt

      if exited_at and exited_at ~= 0 then
        status = string.format('Exited (%d) %s', exit_code, format_duration(now - exited_at, true))
      end
    elseif state == 'running' then
      -- 运行中的容器：从 StartedAt 计算运行时间
      local started_at = data.StartedAt

      if started_at and started_at ~= 0 then
        status = string.format('Up %s', format_duration(now - started_at, false))
      end
    else
      -- 其他状态
      status = state or 'unknown'
    end
  end

  return {
    id = id,
    name = name,
    image = data.Image,
    state = string.lower(state or ''),
    status = status or '',
    ports = ports,
    created = created,
  }
end

local function normalize_image_data(data)
  local id = data.ID or data.Id
  local repository = data.Repository or data.repository or ''
  local tag = data.Tag or data.tag or ''

  -- 处理 size 字段
  local size = data.Size
  -- 如果 size 是纯数字（Podman 的字节数），格式化为人类可读格式
  -- 如果 size 已包含单位（如 Docker 的 "150MB"），直接使用
  if type(size) == 'number' or (type(size) == 'string' and size:match '^%d+$') then
    size = format_size(tonumber(size))
  end

  local digest = data.Digest or ''
  local created_at = data.CreatedAt
  local created_since = data.CreatedSince

  if not created_at or created_at == '' then
    -- Podman 使用 Created (Unix 时间戳)
    local created_timestamp = data.Created
    if created_timestamp and created_timestamp ~= 0 then
      created_at = os.date('%Y-%m-%d %H:%M:%S', created_timestamp)
      -- 如果 Docker 格式没有 CreatedSince，自己计算
      if not created_since or created_since == '' then
        local now = os.time()
        created_since = format_duration(now - created_timestamp, true)
      end
    else
      created_at = 'unknown'
      created_since = 'unknown'
    end
  end

  return {
    id = id,
    repository = repository,
    tag = tag,
    created_since = created_since,
    size = size,
    digest = digest,
    created_at = created_at,
  }
end

function M.exec(cmd)
  return promise.new(function(resolve, reject)
    lc.system(cmd, function(output)
      if output.code == 0 then
        resolve(output.stdout)
      else
        reject(output.stderr)
      end
    end)
  end)
end

function M.container_list()
  local cmd = { 'docker', 'container', 'ps', '-a', '--format', '{{json .}}' }

  return M.exec(cmd):next(function(stdout)
    stdout = stdout:trim()
    if stdout == '' then error 'No containers found' end
    local containers = lc.tbl_map(function(line)
      local success, data = pcall(lc.json.decode, line)
      assert(success and type(data) == 'table', 'Failed to parse JSON output: ' .. line)

      return normalize_container_data(data)
    end, stdout:split '\n')

    return containers
  end)
end

function M.inspect_container(container_id)
  local cmd = { 'docker', 'container', 'inspect', container_id }

  return M.exec(cmd):next(function(stdout)
    local success, data = pcall(lc.json.decode, stdout)
    assert(success and type(data) == 'table' and #data > 0, 'Failed to parse JSON output: ' .. stdout)
    return data[1]
  end)
end

function M.image_list()
  local cmd = { 'docker', 'image', 'ls', '--format', '{{json .}}' }

  return M.exec(cmd):next(function(stdout)
    stdout = stdout:trim()
    if stdout == '' then error 'No images found' end
    local images = lc.tbl_map(function(line)
      local success, data = pcall(lc.json.decode, line)
      assert(success and type(data) == 'table', 'Failed to parse JSON output: ' .. line)

      return normalize_image_data(data)
    end, stdout:split '\n')

    return images
  end)
end

function M.inspect_image(image_id)
  local cmd = { 'docker', 'image', 'inspect', image_id }

  return M.exec(cmd):next(function(stdout)
    local success, data = pcall(lc.json.decode, stdout)
    assert(success and type(data) == 'table' and #data > 0, 'Failed to parse JSON output: ' .. stdout)
    return data[1]
  end)
end

function M.image_history(image_id)
  return M.exec({ 'docker', 'image', 'history', image_id, '--no-trunc', '--format', '{{json .}}' }):next(
    function(stdout)
      local layers = lc.tbl_map(function(line)
        local success, data = pcall(lc.json.decode, line)
        assert(success and type(data) == 'table', 'Failed to parse JSON output: ' .. line)

        local size = data.Size or data.size
        if type(size) == 'number' or (type(size) == 'string' and size:match '^%d+$') then
          size = format_size(tonumber(size))
        end

        return {
          created_by = data.CreatedBy or '',
          size = size,
        }
      end, stdout:trim():split '\n')

      return layers
    end
  )
end

-- 检查容器是否使用 journald 日志驱动
-- 返回一个 promise，成功时传递 true/false
function M.is_journald_logging(container_id)
  return M
    .inspect_container(container_id)
    :next(function(detail)
      local log_config = detail.HostConfig and detail.HostConfig.LogConfig
      return log_config and log_config.Type == 'journald'
    end)
end

-- 获取容器日志命令
-- 如果容器使用 journald，返回 journalctl 命令；否则返回 docker logs 命令
function M.get_log_cmd(container_id, container_name, follow)
  return M.is_journald_logging(container_id)
    :next(function(is_journald)
      if is_journald then
        local args = { 'journalctl', '--no-pager' }
        if follow then
          table.insert(args, '-f')
        else
          table.insert(args, '-n')
          table.insert(args, '35')
        end
        table.insert(args, 'CONTAINER_NAME=' .. container_name)
        return args
      else
        local args = { 'docker', 'container', 'logs' }
        if follow then
          table.insert(args, '--follow')
        else
          table.insert(args, '--tail')
          table.insert(args, '35')
        end
        table.insert(args, container_id)
        return args
      end
    end)
end

return M
