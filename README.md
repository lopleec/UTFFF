# UTFFF - Unicode `\uXXXX` 输入法（macOS / InputMethodKit）

## 项目说明
UTFFF 是一个基于 `InputMethodKit` 的 macOS 输入法 App，专门处理 `\uXXXX` 形式的 Unicode 输入。

支持点：
- 仅处理 `\u...` 相关输入（并包含轻微纠错：大小写混用、漏写反斜杠、少写一位）
- 支持连续编码：例如 `\u4F60\u597D -> 你好`
- 未完成输入也会给候选：例如 `\u004`
- 候选按“常用程度”启发式排序，默认显示 8 个
- `+` 展开全部候选
- `Space` / `Enter` 上屏
- 数字键（见下面“设计取舍”）选择候选
- 鼠标点击候选

候选显示格式：
- `\u0040  @`
- `\u0041  A`
- `\u4F60  你`

## 技术选型与取舍
### 1) 采用传统 InputMethodKit App
- 使用 `IMKServer + IMKInputController + IMKCandidates`。
- 配置通过 `Info.plist` 中的：
  - `InputMethodConnectionName`
  - `InputMethodServerControllerClass`
  - `LSBackgroundOnly`

### 2) 数字键选择 vs 十六进制继续输入冲突
- 冲突场景：数字键既可作为十六进制输入，也可作为候选选择键。
- 本实现规则：
  - 当当前 token 仍可继续补齐 4 位十六进制时（例如 `\u004`），数字键优先作为“继续输入”。
  - 当当前 token 已经完整（无法继续补位）时，`1..9` 用于候选选择。
- 这样可以稳定完成精确编码输入，同时保留数字键选词能力。

### 3) “显示全部候选”的实现
- 默认展示前 8 个候选。
- 按 `+` 后切换为显示全部（当前输入会话内保持展开状态，直到上屏或重置）。

### 4) 候选排序启发式
- 先按字符类型打分（字母 > 数字 > 常用 CJK > 其他标点/符号）。
- 再按编码字典序稳定排序。
- 例如 `\u004` 的候选里，`A`（`\u0041`）会排在 `@`（`\u0040`）前。

## 目录结构
- `UTFFF.xcodeproj`：Xcode 工程
- `UTFFF/main.swift`：输入法 App 入口
- `UTFFF/UnicodeInputController.swift`：输入处理与候选交互
- `UTFFF/UnicodeCandidateEngine.swift`：解析、纠错与候选排序引擎
- `Info.plist`：输入法注册配置
- `README.md`

## 如何编译
### 命令行构建
在项目根目录执行：

```bash
cd "/Users/luccazh/Documents/Programing☕️/UTFFF"
xcodebuild -project UTFFF.xcodeproj -scheme UTFFF -configuration Debug -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO build
```

产物默认在：
- `DerivedData/Build/Products/Debug/UTFFF.app`

### Xcode 构建
1. 用 Xcode 打开 `UTFFF.xcodeproj`
2. 选择 `UTFFF` scheme
3. Product -> Build

## 安装到 `~/Library/Input Methods`
```bash
cd "/Users/luccazh/Documents/Programing☕️/UTFFF"
rm -rf "$HOME/Library/Input Methods/UTFFF.app"
cp -R "./DerivedData/Build/Products/Debug/UTFFF.app" "$HOME/Library/Input Methods/"
```

可选（清除隔离属性）：
```bash
xattr -dr com.apple.quarantine "$HOME/Library/Input Methods/UTFFF.app"
```

## 在 macOS 中启用
1. 打开 `系统设置 -> 键盘 -> 输入法`
2. 点击 `+`
3. 在列表中找到 `UTFFF`（通常在“其他”或对应分类下）并添加
4. 切换到 `UTFFF` 输入法进行测试

## 刷新/重启相关服务
安装后如果没有立即出现，可执行：

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Library/Input Methods/UTFFF.app"
killall -KILL TextInputMenuAgent
killall -KILL SystemUIServer
```

如果仍未出现，注销并重新登录 macOS 会话。

## 功能测试用例
切换到 UTFFF 输入法后测试：
1. `\u0041` -> `A`
2. `\u4F60\u597D` -> `你好`
3. 输入 `\u004`：
   - 候选默认显示 8 个
   - 候选应按常用程度排序（`A` 在 `@` 前）
4. 按 `+`：候选展开为全部
5. `Space`、`Enter`、数字键、鼠标点击可完成候选上屏
6. 纠错：
   - 少写一位：`\u004` 可给出补全候选
   - 大小写混用：`\u4f60` -> `你`
   - 漏写反斜杠：`u4F60u597D` -> `你好`
7. 普通输入不应被改写；仅在识别 `\u...` 相关模式时介入

## 说明
- 当前实现只支持 BMP (`\u0000` 到 `\uFFFF`)。
- 对于无法可靠纠错的内容，会尽量按原样回退上屏。
