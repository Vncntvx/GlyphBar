import Foundation

// P1.15: Kernel/Contracts anchor file for module core types.
//
// The actual type definitions (ModuleID, ModuleManifest, RefreshPolicy,
// SnapshotFreshness, ModuleAction, StatusSignal, ModuleSnapshot, ModuleEvent,
// etc.) remain in `GlyphBar/Core/Modules/ModuleTypes.swift` during the P1→P2
// transition. P2 will move them here and delete the old file.
//
// `ModuleManifest.priority` was added in P1.15/P1.16 to replace the hardcoded
// "deepseek first" ordering in AppEnvironment.
