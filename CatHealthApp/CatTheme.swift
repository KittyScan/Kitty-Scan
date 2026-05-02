import SwiftUI

struct CatTheme: Identifiable, Hashable {
    let id: String
    let pattern: String
    let nameZh: String
    let nameEn: String
    let defZh: String
    let defEn: String
    let moodZh: String
    let moodEn: String
    let descZh: String
    let descEn: String
    let bg: Color
    let card: Color
    let light: Color
    let main: Color
    let deep: Color
    let accent: Color
    let eye: Color
    let eyeSecondary: Color?   // only meaningful for odd-eye
    let nose: Color

    func name(zh: Bool) -> String { zh ? nameZh : nameEn }
    func def(zh: Bool) -> String { zh ? defZh : defEn }
    func mood(zh: Bool) -> String { zh ? moodZh : moodEn }
    func desc(zh: Bool) -> String { zh ? descZh : descEn }

    var swatches: [Color] { [bg, card, light, main, deep] }
}

extension CatTheme {
    /// String-based convenience init. The big inline theme-array literal blows
    /// past Swift's type-checker time limit when each entry contains 9
    /// `Color(hex:)` calls — pushing the conversion into this init keeps each
    /// entry expression lightweight (just plain string params).
    init(id: String, pattern: String,
         nameZh: String, nameEn: String,
         defZh: String, defEn: String,
         moodZh: String, moodEn: String,
         descZh: String, descEn: String,
         bg: String, card: String, light: String,
         main: String, deep: String, accent: String,
         eye: String, eyeSecondary: String?, nose: String) {
        self.init(
            id: id, pattern: pattern,
            nameZh: nameZh, nameEn: nameEn,
            defZh: defZh, defEn: defEn,
            moodZh: moodZh, moodEn: moodEn,
            descZh: descZh, descEn: descEn,
            bg: Color(hex: bg), card: Color(hex: card), light: Color(hex: light),
            main: Color(hex: main), deep: Color(hex: deep), accent: Color(hex: accent),
            eye: Color(hex: eye),
            eyeSecondary: eyeSecondary.map { Color(hex: $0) },
            nose: Color(hex: nose)
        )
    }
}

enum CatThemes {
    /// First entry is the neutral default — the only theme free users can
    /// use. Matches the app-icon palette (warm cream + coffee brown). All
    /// other themes are gated behind a pack/Pro purchase via
    /// SettingsBreedCard's `locked` logic, which uses
    /// `CatThemes.all.first?.id` as the free allow-list.
    static let all: [CatTheme] = [
        .init(id: "default", pattern: "tabby",
              nameZh: "默认", nameEn: "Default",
              defZh: "小喵", defEn: "Kitty",
              moodZh: "温柔朴素 ♡", moodEn: "Gentle & simple ♡",
              descZh: "暖奶油 + 咖啡棕", descEn: "Cream + coffee brown",
              bg: "FDDC9F", card: "F8E8C2", light: "E0B888",
              main: "A87654", deep: "754628", accent: "EFC084",
              eye: "97C459", eyeSecondary: nil, nose: "F0BCA8"),
        .init(id: "orange-tabby", pattern: "tabby",
              nameZh: "橘虎斑", nameEn: "Orange Tabby",
              defZh: "橘子", defEn: "Tangerine",
              moodZh: "元气满满 ☀", moodEn: "Bright & cheerful ☀",
              descZh: "奶油米 + 虎斑橘", descEn: "Cream + tiger orange",
              bg: "FFF4E6", card: "FAEEDA", light: "FAC775",
              main: "EF9F27", deep: "BA7517", accent: "F0997B",
              eye: "97C459", eyeSecondary: nil, nose: "F0997B"),
        .init(id: "silver-tabby", pattern: "tabby",
              nameZh: "银虎斑", nameEn: "Silver Tabby",
              defZh: "银子", defEn: "Silver",
              moodZh: "优雅沉静 ☁", moodEn: "Elegant & calm ☁",
              descZh: "烟灰 + 银白 + 翠绿眼", descEn: "Smoke + silver + green eyes",
              bg: "F4F4F8", card: "E6E6EC", light: "C4C4CE",
              main: "8A8A95", deep: "4A4A55", accent: "D8C7B8",
              eye: "4CA87C", eyeSecondary: nil, nose: "C08088"),
        .init(id: "ragdoll", pattern: "pointed",
              nameZh: "布偶", nameEn: "Ragdoll",
              defZh: "汤圆", defEn: "Mochi",
              moodZh: "贵气优雅 ♡", moodEn: "Royal & elegant ♡",
              descZh: "云朵白 + 薰衣草紫", descEn: "Cloud white + lavender",
              bg: "FAF9FF", card: "EEEDFE", light: "CECBF6",
              main: "AFA9EC", deep: "3C3489", accent: "F4C0D1",
              eye: "378ADD", eyeSecondary: nil, nose: "F4C0D1"),
            .init(id: "black", pattern: "solid",
              nameZh: "纯黑猫", nameEn: "Black Cat",
              defZh: "墨墨", defEn: "Shadow",
              moodZh: "神秘高冷 🌙", moodEn: "Mysterious & cool 🌙",
              descZh: "月光灰 + 墨黑 + 琥珀", descEn: "Moonlight + ink + amber",
              bg: "F1EFE8", card: "D8D6CD", light: "88867E",
              main: "3A3A36", deep: "1D1D1B", accent: "EF9F27",
              eye: "EF9F27", eyeSecondary: nil, nose: "5A4A3A"),
        .init(id: "calico", pattern: "calico",
              nameZh: "三花", nameEn: "Calico",
              defZh: "花卷", defEn: "Patches",
              moodZh: "俏皮有趣 ✿", moodEn: "Playful & fun ✿",
              descZh: "奶白 + 墨黑 + 橘三拼", descEn: "Milk + ink + coral",
              bg: "FFF8F3", card: "FAECE7", light: "F5C4B3",
              main: "D4642C", deep: "6B2C2C", accent: "F0997B",
              eye: "97C459", eyeSecondary: nil, nose: "F0997B"),
        .init(id: "cow", pattern: "tuxedo",
              nameZh: "奶牛猫", nameEn: "Tuxedo",
              defZh: "欧欧", defEn: "Oreo",
              moodZh: "活力机灵 🐾", moodEn: "Lively & clever 🐾",
              descZh: "纯白 + 墨黑 + 金黄", descEn: "White + ink + gold",
              bg: "F8F6F2", card: "EDE9E0", light: "C9C5BD",
              main: "3A3A36", deep: "1D1D1B", accent: "F5D07A",
              eye: "97C459", eyeSecondary: nil, nose: "F5C4B3"),
        .init(id: "orange-white", pattern: "tuxedo-orange",
              nameZh: "橘白双拼", nameEn: "Orange & White",
              defZh: "豆沙", defEn: "Pumpkin",
              moodZh: "暖暖治愈 🍊", moodEn: "Warm & healing 🍊",
              descZh: "奶白 + 橘顶", descEn: "Cream + orange top",
              bg: "FFFBF5", card: "FFF0DC", light: "FDD8A8",
              main: "F2A03E", deep: "A86820", accent: "F0997B",
              eye: "97C459", eyeSecondary: nil, nose: "F0997B"),
            .init(id: "cream", pattern: "solid",
              nameZh: "奶油色", nameEn: "Cream",
              defZh: "布丁", defEn: "Pudding",
              moodZh: "温柔甜美 🍮", moodEn: "Sweet & gentle 🍮",
              descZh: "奶油 + 焦糖 + 桃粉", descEn: "Cream + caramel + peach",
              bg: "FFFAF2", card: "FAF0DE", light: "F0D9B0",
              main: "C9A571", deep: "8A6A3A", accent: "F8B88A",
              eye: "B8D060", eyeSecondary: nil, nose: "F0B090"),
        .init(id: "tortoiseshell", pattern: "tortie",
              nameZh: "玳瑁", nameEn: "Tortoiseshell",
              defZh: "琥珀", defEn: "Amber",
              moodZh: "野性神秘 🐢", moodEn: "Wild & mysterious 🐢",
              descZh: "深栗 + 火焰橘 + 琥珀", descEn: "Chestnut + flame + amber",
              bg: "F5EFE8", card: "E8DCC8", light: "C89860",
              main: "8A4820", deep: "2C1810", accent: "E8782C",
              eye: "E8A830", eyeSecondary: nil, nose: "8A4820"),
        .init(id: "british-blue", pattern: "solid",
              nameZh: "英短蓝猫", nameEn: "British Shorthair",
              defZh: "雾雾", defEn: "Misty",
              moodZh: "温柔 cozy ☁", moodEn: "Cozy warmth ☁",
              descZh: "晨雾蓝 + 铜铃黄", descEn: "Misty blue + copper bell",
              bg: "F0F6FC", card: "E2EEF9", light: "B5D4F4",
              main: "85A8C8", deep: "254B74", accent: "FAC775",
              eye: "E8A830", eyeSecondary: nil, nose: "D4A090"),
        .init(id: "maine-coon", pattern: "longhair-tabby",
              nameZh: "缅因猫", nameEn: "Maine Coon",
              defZh: "大福", defEn: "Leo",
              moodZh: "森林公爵 🌲", moodEn: "Forest duke 🌲",
              descZh: "森林米 + 栗棕 + 翠绿", descEn: "Forest cream + chestnut + green",
              bg: "FAF4EA", card: "F0E4CF", light: "D4B890",
              main: "8B5A2B", deep: "4A2E14", accent: "E8A05C",
              eye: "7CA85C", eyeSecondary: nil, nose: "D88070"),
        .init(id: "siamese", pattern: "pointed",
              nameZh: "暹罗", nameEn: "Siamese",
              defZh: "麦芽", defEn: "Coco",
              moodZh: "复古贵气 ♔", moodEn: "Retro regal ♔",
              descZh: "米黄 + 可可棕 + 蓝宝石眼", descEn: "Beige + cocoa + sapphire eyes",
              bg: "FAF4E8", card: "F5EBD4", light: "EAD5AE",
              main: "8A6030", deep: "4A3010", accent: "85B7EB",
              eye: "4590D4", eyeSecondary: nil, nose: "C89070"),
        .init(id: "russian-blue", pattern: "solid",
              nameZh: "俄罗斯蓝", nameEn: "Russian Blue",
              defZh: "奶昔", defEn: "Smokey",
              moodZh: "梦幻慵懒 ☽", moodEn: "Dreamy & lazy ☽",
              descZh: "藕粉 + 烟灰蓝 + 琥珀", descEn: "Lotus pink + smoke blue + amber",
              bg: "F5F0FA", card: "EBE0F2", light: "D9C7E8",
              main: "8888A0", deep: "4B3860", accent: "EF9F27",
              eye: "7CA85C", eyeSecondary: nil, nose: "C090A0"),
        .init(id: "scottish-fold", pattern: "fold",
              nameZh: "苏格兰折耳", nameEn: "Scottish Fold",
              defZh: "软糖", defEn: "Caramel",
              moodZh: "软乎乎 🫧", moodEn: "Soft & fluffy 🫧",
              descZh: "奶白 + 焦糖棕", descEn: "Cream + butterscotch",
              bg: "FFF7ED", card: "FAE9CE", light: "EDC989",
              main: "C89155", deep: "6B4423", accent: "F5C4B3",
              eye: "FAC775", eyeSecondary: nil, nose: "F0997B"),
        .init(id: "sphynx", pattern: "sphynx",
              nameZh: "斯芬克斯", nameEn: "Sphynx",
              defZh: "皮蛋", defEn: "Gizmo",
              moodZh: "精灵古怪 ✨", moodEn: "Quirky elf ✨",
              descZh: "粉皮肤 + 琥珀", descEn: "Pink skin + amber",
              bg: "FFF1E8", card: "FFDFCE", light: "F5B594",
              main: "D47851", deep: "8A3D1A", accent: "FAC775",
              eye: "E8A830", eyeSecondary: nil, nose: "C05030"),
            .init(id: "bengal", pattern: "spotted",
              nameZh: "孟加拉豹猫", nameEn: "Bengal",
              defZh: "虎豹", defEn: "Spot",
              moodZh: "野美豹花 🐆", moodEn: "Wild leopard 🐆",
              descZh: "野金 + 豹纹 + 翡翠绿", descEn: "Wild gold + leopard + emerald",
              bg: "FAF2E0", card: "F0DFA8", light: "D4A642",
              main: "8A5820", deep: "3A2410", accent: "4FA880",
              eye: "4FA880", eyeSecondary: nil, nose: "C06040"),
        .init(id: "chinchilla", pattern: "longhair-solid",
              nameZh: "金吉拉", nameEn: "Chinchilla",
              defZh: "棉花糖", defEn: "Pearl",
              moodZh: "仙气飘飘 ✦", moodEn: "Ethereal ✦",
              descZh: "冰白 + 银灰 + 海绿", descEn: "Icy white + silver + sea green",
              bg: "FDFDFF", card: "F0F0F5", light: "D8D8E2",
              main: "B0B0BC", deep: "5A5B6B", accent: "7FB8A6",
              eye: "4FA880", eyeSecondary: nil, nose: "D89098"),
        .init(id: "abyssinian", pattern: "solid",
              nameZh: "阿比西尼亚", nameEn: "Abyssinian",
              defZh: "狸狸", defEn: "Foxy",
              moodZh: "机灵小狐 🦊", moodEn: "Clever little fox 🦊",
              descZh: "赤金 + 铜棕 + 狐橘", descEn: "Ruddy gold + copper + fox",
              bg: "FDF5E8", card: "F5E2C0", light: "E0B880",
              main: "B87434", deep: "6A3A14", accent: "E8782C",
              eye: "97C459", eyeSecondary: nil, nose: "C85030"),
        .init(id: "persian", pattern: "longhair-solid",
              nameZh: "波斯猫", nameEn: "Persian",
              defZh: "玫瑰", defEn: "Rose",
              moodZh: "雍容华贵 🌹", moodEn: "Regal rose 🌹",
              descZh: "玫瑰粉 + 霜灰粉", descEn: "Rose petal + dusty pink",
              bg: "FFF5F0", card: "FADED0", light: "F0B8A0",
              main: "C87058", deep: "7A3824", accent: "D4A5B8",
              eye: "E8A830", eyeSecondary: nil, nose: "C85570"),
        .init(id: "burmese", pattern: "solid",
              nameZh: "缅甸猫", nameEn: "Burmese",
              defZh: "焦糖", defEn: "Toffee",
              moodZh: "暖金丝绒 ☕", moodEn: "Golden velvet ☕",
              descZh: "貂棕 + 金色", descEn: "Sable + gold",
              bg: "F5ECD8", card: "E8D4A8", light: "C8A070",
              main: "8A5828", deep: "3E2410", accent: "EFC050",
              eye: "EFC050", eyeSecondary: nil, nose: "C06040"),
        .init(id: "white-odd-eye", pattern: "odd-eye",
              nameZh: "异瞳纯白", nameEn: "Odd-eyed White",
              defZh: "雪球", defEn: "Snowball",
              moodZh: "天选之子 ✧", moodEn: "Chosen one ✧",
              descZh: "纯白 + 左蓝右金", descEn: "Pure white + blue & gold eyes",
              bg: "FCFCFE", card: "F5F5F8", light: "E0E0E8",
              main: "D8D8E0", deep: "5A5A66", accent: "4A90D9",
              eye: "4A90D9", eyeSecondary: "E8A830", nose: "E8A0B0"),
        .init(id: "chinese-garden", pattern: "tabby",
              nameZh: "中华田园", nameEn: "Chinese Garden Cat",
              defZh: "大橘", defEn: "Ginger",
              moodZh: "接地气 🏮", moodEn: "Down to earth 🏮",
              descZh: "暖陶土 + 国风红", descEn: "Warm terracotta + folk red",
              bg: "FAF0DC", card: "F0DDB0", light: "D8A870",
              main: "A0602A", deep: "4A2810", accent: "D64A3A",
              eye: "97C459", eyeSecondary: nil, nose: "C85030"),
    ]

    static func byId(_ id: String?) -> CatTheme? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    static let defaultTheme = all[0]
}
