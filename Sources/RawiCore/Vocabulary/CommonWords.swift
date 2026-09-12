import Foundation

/// Ordinary English, as a fence around automatic learning.
///
/// `TermLearner` refuses any candidate that is, or is one or two edits from, a
/// word on this list. That is the difference between a dictionary that fixes
/// "Sala" into "Salla" and one that quietly rewrites "sale", "salt" and "sails"
/// into it forever.
///
/// The list is deliberately weighted toward the vocabulary people dictate at
/// work — ship, review, report, deadline — because those are the words that
/// recur often enough to look like evidence, and the ones it would hurt most to
/// get wrong.
enum CommonWords {
    static func contains(_ lower: String) -> Bool { all.contains(lower) }

    /// Whether any common word is within `distance` edits of this one.
    static func within(distance: Int, of lower: String) -> Bool {
        for word in all {
            guard abs(word.count - lower.count) <= distance else { continue }
            if editDistance(word, lower, cap: distance) <= distance { return true }
        }
        return false
    }

    /// Bounded Levenshtein: gives up as soon as every cell exceeds the cap, which
    /// is most of the list for most candidates.
    static func editDistance(_ a: String, _ b: String, cap: Int) -> Int {
        let first = Array(a), second = Array(b)
        if first.isEmpty { return second.count }
        if second.isEmpty { return first.count }
        var previous = Array(0...second.count)
        var current = [Int](repeating: 0, count: second.count + 1)
        for i in 1...first.count {
            current[0] = i
            var rowBest = current[0]
            for j in 1...second.count {
                let cost = first[i - 1] == second[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowBest = min(rowBest, current[j])
            }
            if rowBest > cap { return cap + 1 }
            swap(&previous, &current)
        }
        return previous[second.count]
    }

    static let all: Set<String> = [
        // Everyday function and filler
        "able", "about", "above", "across", "after", "again", "against", "ahead",
        "almost", "alone", "along", "already", "also", "although", "always",
        "among", "another", "answer", "anyone", "anything", "around", "away",
        "back", "because", "become", "been", "before", "began", "begin", "behind",
        "being", "believe", "below", "best", "better", "between", "beyond", "both",
        "bring", "build", "built", "call", "called", "came", "cannot", "care",
        "case", "change", "check", "children", "class", "clear", "close", "come",
        "coming", "could", "course", "cover", "create", "data", "date", "days",
        "deal", "decide", "different", "does", "doing", "done", "down", "during",
        "each", "early", "easy", "either", "else", "email", "end", "enough",
        "even", "ever", "every", "everyone", "everything", "exactly", "example",
        "face", "fact", "fall", "family", "feel", "few", "figure", "fill", "final",
        "find", "fine", "first", "follow", "food", "form", "found", "free", "from",
        "full", "game", "gave", "general", "give", "given", "going", "gone",
        "good", "great", "group", "grow", "guess", "half", "hand", "happen",
        "hard", "have", "having", "head", "hear", "heard", "held", "help", "here",
        "high", "hold", "home", "hope", "hour", "house", "however", "idea",
        "important", "include", "info", "inside", "instead", "into", "issue",
        "item", "just", "keep", "kind", "know", "known", "large", "last", "late",
        "later", "lead", "learn", "least", "leave", "left", "less", "letter",
        "level", "life", "like", "line", "list", "little", "live", "local",
        "long", "look", "lose", "lost", "love", "made", "main", "make", "making",
        "many", "matter", "maybe", "mean", "meant", "meet", "meeting", "might",
        "mind", "minute", "miss", "money", "month", "more", "morning", "most",
        "move", "much", "must", "name", "near", "need", "never", "next", "nice",
        "night", "none", "note", "nothing", "notice", "number", "offer", "office",
        "often", "once", "only", "open", "order", "other", "over", "page", "part",
        "pass", "past", "people", "perhaps", "person", "pick", "place", "plan",
        "play", "please", "point", "possible", "power", "present", "press",
        "pretty", "probably", "problem", "process", "public", "pull", "push",
        "question", "quick", "quite", "rather", "read", "ready", "real", "really",
        "reason", "remember", "right", "room", "rule", "said", "same", "save",
        "saying", "school", "second", "seem", "seen", "sense", "sent", "series",
        "service", "several", "shall", "share", "short", "should", "show", "side",
        "simple", "since", "single", "small", "some", "someone", "something",
        "sometimes", "soon", "sorry", "sort", "sound", "speak", "special", "spend",
        "stand", "start", "state", "stay", "step", "still", "stop", "story",
        "student", "study", "stuff", "such", "sure", "take", "taken", "talk",
        "tell", "than", "thank", "thanks", "that", "their", "them", "then",
        "there", "these", "they", "thing", "think", "this", "those", "though",
        "thought", "three", "through", "time", "today", "together", "told",
        "tomorrow", "took", "toward", "true", "turn", "under", "understand",
        "until", "upon", "used", "using", "usually", "very", "wait", "walk",
        "want", "watch", "water", "week", "well", "went", "were", "what", "when",
        "where", "whether", "which", "while", "white", "whole", "will", "wish",
        "with", "within", "without", "word", "work", "world", "would", "write",
        "wrong", "year", "your",

        // The vocabulary of dictating at work: said constantly, easy to mistake
        // for a name, and expensive to get wrong.
        "account", "action", "agenda", "agree", "align", "amount", "answer",
        "approve", "approved", "asset", "assign", "attach", "audit", "backlog",
        "based", "batch", "block", "blocked", "blocker", "board", "book", "brand",
        "branch", "brief", "budget", "bug", "business", "button", "buy", "cancel",
        "card", "channel", "chart", "client", "close", "closed", "code", "colour",
        "color", "column", "comment", "commit", "company", "compare", "config",
        "confirm", "connect", "content", "context", "contract", "control", "copy",
        "cost", "count", "customer", "cycle", "daily", "dashboard", "deadline",
        "debug", "decision", "deck", "default", "delay", "delete", "deliver",
        "demo", "deploy", "deployed", "design", "detail", "dev", "device",
        "discuss", "docs", "document", "draft", "drive", "drop", "due", "edit",
        "effort", "engineer", "enter", "error", "estimate", "event", "expect",
        "export", "failed", "feature", "feedback", "field", "file", "filter",
        "final", "finish", "fix", "fixed", "flag", "flow", "focus", "folder",
        "force", "forward", "front", "goal", "graph", "growth", "guide", "hire",
        "image", "impact", "import", "improve", "input", "install", "internal",
        "invite", "join", "key", "label", "landing", "launch", "layer", "layout",
        "lead", "learn", "legal", "link", "load", "lock", "login", "logo", "loop",
        "manage", "manager", "mark", "market", "master", "media", "member",
        "memo", "menu", "merge", "message", "method", "metric", "mobile", "mock",
        "model", "module", "monitor", "note", "notes", "object", "onboard",
        "option", "output", "owner", "package", "panel", "parse", "partner",
        "patch", "path", "pattern", "pause", "payment", "phase", "pilot",
        "pipeline", "pitch", "platform", "plugin", "policy", "port", "post",
        "price", "pricing", "priority", "product", "profile", "project",
        "prompt", "proposal", "protect", "provide", "public", "publish", "query",
        "queue", "quote", "range", "rate", "reach", "record", "reduce", "refund",
        "region", "release", "remove", "rename", "render", "repeat", "replace",
        "reply", "report", "request", "require", "research", "reset", "resolve",
        "resource", "response", "result", "return", "revenue", "review",
        "revision", "risk", "roadmap", "role", "rollout", "round", "route", "row",
        "run", "sales", "sale", "salt", "sample", "scale", "scope", "screen",
        "script", "scroll", "search", "section", "secure", "select", "send",
        "server", "session", "setting", "setup", "ship", "shipped", "shipping",
        "sign", "signal", "site", "size", "skip", "skipped", "slide", "slot",
        "solve", "source", "space", "spec", "speed", "spend", "sprint", "stack",
        "staff", "stage", "stakeholder", "standup", "status", "stopped", "store",
        "strategy", "stream", "string", "style", "submit", "support", "survey",
        "sync", "system", "table", "target", "task", "team", "template", "test",
        "testing", "thread", "ticket", "timeline", "title", "token", "tool",
        "topic", "total", "track", "traffic", "train", "transfer", "trend",
        "trial", "trigger", "update", "updated", "upload", "usage", "user",
        "value", "vendor", "version", "video", "view", "volume", "weekly",
        "window", "workflow", "workshop", "wrap", "write", "zone",
    ]
}
