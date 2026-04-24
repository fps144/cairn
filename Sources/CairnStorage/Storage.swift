import Foundation
import CairnCore

/// Cairn 存储层(v1 scaffold)。真实 GRDB + 11 表 + migrator 将在 M1.2 填入。
public enum CairnStorage {
    public static let scaffoldVersion = CairnCore.scaffoldVersion
}
