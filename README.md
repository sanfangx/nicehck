# 原道 (NiceHCK) v2.2.7 — iOS 16.0+ (16.6.1 TrollStore) 兼容重构版

本项目是基于官方 `原道_2.2.7.ipa` (`com.nicehck.yuandao`) 逆向提取全部蓝牙控制协议、BES 恒玄 BLE OTA 升级协议、静态设备配置及多语言资源后，针对 **iOS 16.0+（含 iOS 16.6.1 巨魔 TrollStore）** 原生重构的 SwiftUI 客户端。

## 为什么原版 2.2.7 在 iOS 16.6.1 上闪退？

原版 `原道_2.2.7.ipa` 使用了 iOS 17.0 独占的系统框架与符号，在 iOS 16.6.1 启动阶段即因 `dyld` 符号缺失崩溃：
1. `libswiftObservation.dylib`（`@Observable` / `ObservationRegistrar`）
2. `SwiftData.framework` & `_SwiftData_SwiftUI.framework`（`@Model ConnectedDevice` / `@Query`）
3. 27 个 iOS 17 新增的 `SwiftUI` 符号（如 `ContentUnavailableView`、双参数 `.onChange(of:initial:)`、`.symbolEffect`、`UnevenRoundedRectangle` 等）

## 本重构版特性

- **最低系统要求**：`iOS 16.0`（`LC_BUILD_VERSION minos = 16.0`，零 `Observation` / `SwiftData` 依赖）
- **100% 协议兼容**：
  - 完整实现 `0x4E` 帧头控制协议（16 条连接状态查询指令 + 11 条控制与设置指令）
  - 完整实现 BES 恒玄 12 步 BLE OTA 固件升级状态机（`0x99` -> `0x92`，32KB 分段 CRC32 校验）
  - 完整保留降噪控制（关/通透/抗风噪/普通降噪/深度降噪/实验性降噪）、7 档 EQ 预设、提示音音量、AAC/LHDC 编码显示、游戏模式、低延迟模式、双设备连接、左右耳触控自定义、长按降噪循环配置、入耳检测、查找耳机及实验性功能
  - 已按需移除在线问题反馈模块
  - 内置简中 (`zh-Hans`)、英 (`en`)、日 (`ja`)、韩 (`ko`) 四国语言本地化

## 编译方式 (GitHub Actions)

推送至 GitHub 后由 `.github/workflows/build-ios.yml` 自动在 macOS Runner 上编译并产出 `nicehck_2.2.7_iOS16.ipa`，可直接通过巨魔 (TrollStore) 安装至 iOS 16.6.1 设备。
