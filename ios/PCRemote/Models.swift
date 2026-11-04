import Foundation

enum StepType: String, Codable, CaseIterable, Identifiable {
    case app, url, run, kill, hotkey, shell, type, sleep, media, power
    var id: String { rawValue }

    var label: String {
        switch self {
        case .app: return "Open installed app"
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
        case .app: return "Choose an app"
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
        steps.map { s in
            s.type == .app ? "open \(s.args?.first ?? s.value)" : "\(s.type.rawValue): \(s.value)"
        }.joined(separator: " → ")
    }
}

struct InstalledApp: Identifiable, Hashable, Decodable {
    let name: String
    let id: String
}

enum Presets {
    private static let librewolf = "C:\\Program Files\\LibreWolf\\librewolf.exe"
    private static let deafen = "ctrl+shift+f10"

    static let all: [Command] = [
        Command(name: "open overwatch", steps: [Step(type: .url, value: "battlenet://Pro")]),
        Command(name: "close overwatch", steps: [Step(type: .kill, value: "Overwatch.exe")]),
        Command(name: "open discord", steps: [Step(type: .run, value: "%LOCALAPPDATA%\\Discord\\Update.exe", args: ["--processStart", "Discord.exe"])]),
        Command(name: "close discord", steps: [Step(type: .kill, value: "Discord.exe")]),
        Command(name: "deafen", steps: [Step(type: .hotkey, value: deafen)]),
        Command(name: "goonmode", steps: [Step(type: .hotkey, value: deafen), Step(type: .run, value: librewolf)]),
        Command(name: "open librewolf", steps: [Step(type: .run, value: librewolf)]),
        Command(name: "close librewolf", steps: [Step(type: .kill, value: "librewolf.exe")]),
        Command(name: "lock pc", steps: [Step(type: .power, value: "lock")]),
        Command(name: "sleep pc", steps: [Step(type: .power, value: "sleep")]),
        Command(name: "mute", steps: [Step(type: .media, value: "mute")]),
        Command(name: "volume up", steps: [Step(type: .media, value: "vol_up*5")]),
        Command(name: "volume down", steps: [Step(type: .media, value: "vol_down*5")]),
        Command(name: "play pause", steps: [Step(type: .media, value: "play_pause")]),
        Command(name: "next track", steps: [Step(type: .media, value: "next")]),
    ]
}
