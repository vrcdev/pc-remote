import Foundation

enum StepType: String, Codable, CaseIterable, Identifiable {
    case url, run, kill, hotkey, shell, type, sleep, media, power
    var id: String { rawValue }

    var label: String {
        switch self {
        case .url: return "Open URL / protocol"
        case .run: return "Run program"
        case .kill: return "Kill process"
        case .hotkey: return "Press hotkey"
        case .shell: return "PowerShell"
        case .type: return "Type text"
        case .sleep: return "Wait (ms)"
        case .media: return "Media key"
        case .power: return "Power"
        }
    }

    var hint: String {
        switch self {
        case .url: return "https://… or battlenet://Pro or steam://rungameid/…"
        case .run: return "C:\\Path\\to\\app.exe"
        case .kill: return "Overwatch.exe"
        case .hotkey: return "ctrl+shift+f10"
        case .shell: return "Any PowerShell command"
        case .type: return "Text to type on the PC"
        case .sleep: return "1000"
        case .media: return "play_pause | next | prev | mute | vol_up*5 | vol_down*5"
        case .power: return "lock | sleep | shutdown | restart"
        }
    }
}

struct Step: Codable, Identifiable, Hashable {
    var id = UUID()
    var type: StepType
    var value: String
    var args: [String]? = nil

    enum CodingKeys: String, CodingKey { case type, value, args }
}

struct Command: Identifiable, Hashable {
    var name: String
    var steps: [Step]
    var id: String { name }

    var summary: String {
        steps.map { "\($0.type.rawValue): \($0.value)" }.joined(separator: " → ")
    }
}
