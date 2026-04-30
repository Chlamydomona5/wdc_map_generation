## 文件职责：`DataMapGeometryDefaults` 提供地图/建造相关共享几何默认值。
## 边界约束：这里只保存稳定常量，不依赖具体 runtime 或表现节点。

class_name WdcMapGenerationGeometryDefaults
extends RefCounted

const WALL_HEIGHT_M: float = 2.0

