# vivado_portable_project — 可移植重建 Vivado 工程

## 适用场景
- 工程需要交给他人或评委从零复现，不能依赖本机绝对路径。
- 工程目录被 Vivado 反复保存后，XPR 里混入了旧 IP、生成文件（`.gen`、`synth/*.v`）或 `../` 外部路径。
- 想用 Git 管理工程，只提交源码，生成目录由脚本重建。

## 原理
把"工程里应该有哪些文件"写成一份 Tcl 清单（`project_manifest_example.tcl`），重建脚本（`recreate_project_example.tcl`）只做三件事：

1. 检查清单中的每个源文件都存在；
2. 用一份干净的 XPR 模板替换现有 XPR（先备份），重新打开并设置顶层、仿真顶层和约束属性；
3. 检查 XPR 中每个文件引用都是 `$PSRCDIR/` 或 `$PPRDIR/` 开头的相对路径，且没有旧 IP、生成文件或 `../` 路径。

## 使用方法
1. 复制两个脚本到工程根目录，去掉文件名中的 `_example`。
2. 修改 `project_manifest.tcl` 中的 `修改此处` 部分：工程名、RTL 文件名列表、IP 列表（`.xcix` 或 `.xci`）、XDC、仿真顶层，以及不允许再出现的旧 IP 名称。
3. 在 Vivado 中关闭工程，在工程根目录执行：
   ```
   vivado -mode batch -source recreate_project.tcl
   ```
   输出 `RECREATE_PROJECT=PASS` 即成功。构建脚本开头调用 `pk_assert_project_inputs`，可在每次构建前自动检查清单。

## 失效条件
- 清单需要人工维护：新增 RTL 或 IP 后忘记加入清单，检查会报 `Required source is missing` 或 `not referenced by XPR`，这正是预期行为。
- XPR 模板与 Vivado 版本绑定，跨大版本（如 2024.1 → 2025.2）时 IP 可能需要升级，应重新生成模板。
- 只重建工程元数据，不负责重新生成 IP 输出产品；IP 升级与生成仍由 Vivado 完成。

## 已验证的效果
本项目在独立目录中执行重建后，用 SHA256 校验源码与约束文件哈希不变（见仓库 `build/reports/recreate/`），XPR 中旧 ROM IP、旧 ILA 及重复的 VIO 生成 HDL 引用全部清除。

## 来源
- 在已有工程目录中执行 `create_project -force` 时，Vivado 会删除同名的 `.srcs` 目录，源码随之丢失。因此脚本只替换 XPR、绝不使用 `-force`，并在替换前自动备份。
- 多次在 GUI 中保存后，XPR 中出现了不参与设计的旧 IP 和 `../` 路径，换电脑后无法打开。清单检查把这类问题变成构建前的硬性错误。
