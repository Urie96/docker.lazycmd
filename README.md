# Docker Plugin for lazycmd

Docker 管理插件，当前已实现容器和镜像浏览与常见操作。目录结构已按 `examples/demo.lazycmd/demo` 的方式拆成 `init/config/meta/action` 四层：

- `docker/init.lua` 负责页面路由和列表构建
- `docker/config.lua` 负责默认配置和键位
- `docker/meta.lua` 负责 entry 元表与局部 keymap
- `docker/action.lua` 负责预览和操作行为

## 已实现资源

- `Containers`：查看、启动、停止、重启、暂停、恢复、删除、查看日志、进入 shell、查看 stats、inspect
- `Images`：查看、拉取、保存、删除、inspect

`Volumes` 和 `Networks` 入口仍保留，但目前只作为占位说明。

## 默认快捷键

- `<enter>`：打开当前资源的操作菜单
- `i`：inspect 当前容器或镜像
- `d`：删除当前容器或镜像
- `l`：查看容器日志
- `e`：进入容器 shell
- `s`：查看容器 stats
- `r`：启动容器
- `x`：停止容器
- `R`：重启容器
- `p`：暂停容器
- `u`：恢复容器
- `P`：拉取镜像
- `S`：保存镜像到文件

## 配置示例

```lua
{
  'docker',
  config = function()
    require('docker').setup {
      command = 'docker',
      keymap = {
        action = '<enter>',
      },
    }
  end,
}
```

`command` 可改成兼容 Docker CLI 的其他命令，例如 `podman`。

## 依赖

- `docker` 或其他兼容 Docker CLI 的命令
- 查看 journald 日志时需要 `journalctl`
