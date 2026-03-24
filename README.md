# Docker Plugin for lazycmd

Docker 管理插件，支持管理容器、镜像、卷和网络。

## 功能

### 资源类型

- **容器** (Containers) - 查看、启动、停止、重启、暂停、删除、查看日志、执行命令、查看统计信息
- **镜像** (Images) - 查看、拉取、删除、检查详情
- **卷** (Volumes) - 查看、删除、创建
- **网络** (Networks) - 查看、连接、断开、删除、创建

## 键盘快捷键

- `Enter` - 进入选中项 / 显示操作菜单
- `Esc` - 返回上一级
- `j/k` 或 `↑/↓` - 上下移动
- `q` - 退出应用

## 操作说明

### 容器操作

当容器处于不同状态时，可执行以下操作：

**运行中的容器:**
- 🔄 Restart - 重启容器
- ⏹️ Stop - 停止容器
- ⏸️ Pause - 暂停容器

**暂停的容器:**
- ▶️ Unpause - 恢复容器
- ⏹️ Stop - 停止容器

**停止的容器:**
- ▶️ Start - 启动容器

**所有容器:**
- 📋 Logs - 查看容器日志（跟随模式）
- 💻 Exec - 进入容器 shell
- 📊 Stats - 查看容器资源使用统计
- 🔍 Inspect - 查看容器详细信息
- 🗑️ Remove - 删除容器

### 镜像操作

- ⬇️ Pull - 拉取/更新镜像
- 🔍 Inspect - 查看镜像详细信息
- 🗑️ Remove - 删除镜像

### 卷操作

- 🔍 Inspect - 查看卷详细信息
- 🗑️ Remove - 删除卷
- ➕ Create - 创建新卷（快捷键或菜单）

### 网络操作

- 🔗 Connect - 连接容器到网络
- 🔌 Disconnect - 断开容器与网络的连接
- 🔍 Inspect - 查看网络详细信息
- 🗑️ Remove - 删除网络
- ➕ Create - 创建新网络（快捷键或菜单）

## 状态颜色

- 🟢 绿色 - 容器运行中
- 🔵 蓝色 - 容器已暂停
- 🟡 黄色 - 容器已创建
- ⚪ 灰色 - 容器已停止
- 🔴 红色 - 容器已停止（异常）
- 🔵 青色 - 容器重启中

## 使用示例

1. 启动 lazycmd 并选择 docker 插件：
   ```bash
   cargo run -- docker
   ```

2. 使用箭头键或 j/k 选择资源类型（容器/镜像/卷/网络）

3. 按 Enter 进入资源列表

4. 选择具体资源后按 Enter 查看可用操作

5. 使用方向键选择操作后按 Enter 执行

## 配置

插件已默认配置在 `examples/init.lua` 中：

```lua
{
  'docker',
  config = function() require('docker').setup() end,
},
```

## 依赖

- Docker 或 Podman（使用 docker CLI 兼容接口）
- docker CLI 命令行工具

## 注意事项

- 容器操作可能需要 sudo 权限
- 删除操作会弹出确认对话框
- 某些操作（如 logs、exec）会进入交互式终端模式
- 在操作完成后，列表会自动刷新
