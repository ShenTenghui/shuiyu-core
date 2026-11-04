# 水鱼：规则与对局核心

从正在做的 Godot 水鱼游戏中整理出的规则层和服务端对局代码。水鱼是一种扑克牌游戏：四张手牌分成鱼头、鱼尾，闲家选择行动，庄家依次回应，再统一结算。

这里主要保留三件事：

- **规则计算**：牌型、合法排列、比牌和分数结算。
- **对局推进**：四个座位、十二小局、阶段约束、命令校验和最终排名。
- **信息可见性**：为每个座位生成单独快照，隐藏对手手牌及未公开决策。

## 跑起来

使用 Godot 4.6。先导入一次项目，让引擎建立脚本类缓存，然后执行三个 headless 测试场景：

```sh
godot --headless --editor --path . --import
godot --headless --path . res://test/unit/test_m1d01_controller.tscn
godot --headless --path . res://test/unit/test_m1d02_snapshot.tscn
godot --headless --path . res://test/unit/test_m1d03_network.tscn
```

Windows 下将 `godot` 替换为本机 Godot 控制台可执行文件路径。每个场景会打印检查结果，并用退出码表示成功或失败。

三个场景分别检查对局控制器、按座位裁剪的快照，以及服务端命令处理。命令测试直接调用处理层，不需要启动数据库，也不等同于四个真实客户端的端到端联网测试。测试使用固定随机种子，并由 `test/support/legal_decisions.gd` 选择合法动作来驱动流程；这个辅助文件不代表 AI 策略。

## 代码入口

| 路径 | 内容 |
| --- | --- |
| `脚本/core/` | 牌型、排列、比牌和结算 |
| `脚本/server/game_controller.gd` | 维护唯一的权威对局状态 |
| `脚本/server/game_dealer.gd` | 发牌 |
| `脚本/server/game_sync.gd` | 按接收者生成可见快照 |
| `脚本/server/game_session_manager.gd` | 按阶段和身份验证命令，再交给控制器 |
| `脚本/shared/protocol_types.gd` | 命令与事件常量 |
| `test/unit/` | 三组 headless 检查场景 |

## 当前范围

这是一个独立源码快照，不包含整款游戏的界面、美术、字体、音效、登录数据库、训练检查点或大型策略表。双击运行项目会执行控制器测试，退出后结束，不会打开完整打牌界面。

原游戏里的 AI 策略模块及训练数据不在这里。测试辅助只负责驱动对局，不验证训练策略的强度或收敛效果。

已在 Ubuntu 24.04 / Godot 4.6.3 的 [GitHub Actions](https://github.com/ShenTenghui/shuiyu-core/actions/runs/41847254924) 中通过三组 headless 场景检查：控制器 5/5、快照 10/10、命令处理 15/15，共 30 项。这不是四个真实客户端的端到端联网验收；Windows 本机尚未复跑。

来源和文件校验值见 [PROVENANCE.md](PROVENANCE.md) 与 [source-files.json](source-files.json)。
