pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    // guessIcon's fuzzy fallback runs on Fuzzy.go's own normalized score,
    // not this file's Levenshtein-based scoreThreshold -- a different scale
    // entirely. A real match (an exact name, or one truncated like "Firefo")
    // scores 0.8-0.97; an appId that just happens to be a subsequence of some
    // unrelated app's full bundle path (icons here are matched by their
    // absolute path, e.g. "Todoist" against "/System/.../Audio MIDI
    // Setup.app") can still score around 0.2. 0.5 sits well clear of both.
    property real iconGuessThreshold: 0.5
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // Deduped list to fix double icons
    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .filter((app, index, self) => 
            index === self.findIndex((t) => (
                t.id === app.id
            ))
    )
    
    readonly property var preppedNames: list.map(a => ({
        name: Fuzzy.prepare(`${a.name} `),
        entry: a
    }))

    readonly property var preppedIcons: list.map(a => ({
        name: Fuzzy.prepare(`${a.icon} `),
        entry: a
    }))

    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        if (root.sloppySearch) {
            const results = list.map(obj => ({
                entry: obj,
                score: Levendist.computeScore(obj.name.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preppedNames, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry) return entry.icon;

        // Normal substitutions
        if (substitutions[str]) return substitutions[str];
        if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];

        // Regex substitutions
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
        }

        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Search in desktop entries. Fuzzy.go always returns its best
        // candidate, even a coincidental one -- "notion" is a subsequence of
        // plenty of unrelated icon/app names -- and this pick is automatic,
        // with no person looking at the ranked list to reject a bad top
        // result. Below scoreThreshold, a wrong-but-real icon is worse than
        // the "no icon" glyph, so require the same confidence bar sloppy
        // name search already holds candidates to.
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        });
        if (iconSearchResults.length > 0 && iconSearchResults[0].score >= root.iconGuessThreshold) {
            const guess = iconSearchResults[0].obj.entry.icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = Fuzzy.go(str, preppedNames, {
            all: true,
            key: "name"
        });
        if (nameSearchResults.length > 0 && nameSearchResults[0].score >= root.iconGuessThreshold) {
            const guess = nameSearchResults[0].obj.entry.icon
            if (iconExists(guess)) return guess;
        }

        // Quickshell's desktop entry lookup
        const heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry) return heuristicEntry.icon;

        // Give up
        return "application-x-executable";
    }

    /**
     * The desktop entry for a window's appId.
     *
     * heuristicLookup() alone is not enough here: the entries qs-index-apps
     * writes are keyed by bundle id ("org.mozilla.firefox"), while yabai --
     * and so ToplevelManager, and so every pin -- names an app the way macOS
     * displays it ("Firefox"). Nothing matched, so `desktopEntry` was null for
     * every app in the dock and clicking one that was not already running did
     * nothing at all. Fall back to matching on the entry's name.
     */
    function lookup(str: string): var {
        if (!str || str.length == 0) return null;
        return DesktopEntries.heuristicLookup(str)
            ?? list.find(a => a.name.toLowerCase() === str.toLowerCase())
            ?? null;
    }
}
