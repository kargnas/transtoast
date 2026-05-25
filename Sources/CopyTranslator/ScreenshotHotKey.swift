import Carbon
import Foundation

private let screenshotHotKeySignature = OSType(0x4354524E) // "CTRN"
private let screenshotHotKeyID = UInt32(1)

@MainActor
final class ScreenshotHotKey {
    private let onTrigger: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    func start() -> OSStatus {
        guard hotKeyRef == nil, eventHandler == nil else {
            return noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let eventTarget = GetEventDispatcherTarget()
        let installStatus = InstallEventHandler(
            eventTarget,
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr,
                      hotKeyID.signature == screenshotHotKeySignature,
                      hotKeyID.id == screenshotHotKeyID else {
                    return noErr
                }

                let manager = Unmanaged<ScreenshotHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    manager.onTrigger()
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )

        guard installStatus == noErr else {
            return installStatus
        }

        let hotKeyID = EventHotKeyID(signature: screenshotHotKeySignature, id: screenshotHotKeyID)
        return RegisterEventHotKey(
            UInt32(kVK_ANSI_2),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            eventTarget,
            0,
            &hotKeyRef
        )
    }
}
