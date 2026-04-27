import Foundation
import CairnCore

/// Cairn 存储层命名空间。封装 GRDB,对外暴露 `CairnDatabase` actor + 各 DAO。
///
/// spec §3.2:CairnStorage 只依赖 CairnCore + GRDB。
/// 本模块不暴露 GRDB 原生类型给上层(Services / UI)。
public enum CairnStorage {
    public static let scaffoldVersion = CairnCore.scaffoldVersion
}
