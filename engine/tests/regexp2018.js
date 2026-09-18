// Regular expression features from ES2018 that Captain Polliwog adds to
// JavaScriptCore 604: named capture groups and Unicode property escapes.
// Run with jsc: prints "PASS n" or the failures.

var failures = [];
var count = 0;
function check(name, actual, expected) {
    count++;
    if (actual !== expected)
        failures.push(name + ": got " + String(actual) + ", expected " + String(expected));
}

// Named capture groups.
var date = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/.exec("on 2026-09-18.");
check("groups.year", date.groups.year, "2026");
check("groups.day", date.groups.day, "18");
check("numbered too", date[2], "09");
check("groups has no prototype", Object.getPrototypeOf(date.groups), null);
check("no groups without names", /(\d)/.exec("5").groups, undefined);
check("unmatched group is undefined", /(?<a>x)|(?<b>y)/.exec("y").groups.a, undefined);
check("String match", "React error #418".match(/Minified React error #(?<invariant>\d+)|error #(?<n>\d+)/).groups.n, "418");
var matchAll = [];
"a1b2".replace(/(?<letter>[a-z])(?<digit>\d)/g, function () {
    var groups = arguments[arguments.length - 1];
    matchAll.push(groups.letter + groups.digit);
    return "";
});
check("replace function gets groups", matchAll.join(","), "a1,b2");
check("$<name> in replace", "2026-09-18".replace(/(?<y>\d+)-(?<m>\d+)-(?<d>\d+)/, "$<d>/$<m>/$<y>"), "18/09/2026");
check("$<name> global", "a-b c-d".replace(/(?<l>\w)-(?<r>\w)/g, "$<r>$<l>"), "ba dc");
check("$< kept without named groups", "ab".replace(/(a)/, "$<x>"), "$<x>b");
check("\\k<name>", /(?<q>["'])text\k<q>/.test("'text'"), true);
check("\\k<name> mismatch", /(?<q>["'])text\k<q>/.test("'text\""), false);
check("\\k without groups is k", /\k/.test("k"), true);
check("path pattern", /.*:spaces\/(?<spaceId>[^/]+)(?:\/environments\/(?<environmentId>[^/]+))?\/entries\/(?<entityId>[^/]+)$/.exec("x:spaces/s1/entries/e9").groups.entityId, "e9");
var subclassed = new (class extends RegExp {})("(?<w>\\w+)");
check("subclass replace uses builtin path", "hello".replace(subclassed, "[$<w>]"), "[hello]");

// Unicode property escapes.
check("\\p{L}", /^\p{L}+$/u.test("héllo"), true);
check("\\p{L} rejects digits", /^\p{L}+$/u.test("abc1"), false);
check("\\p{N}", /\p{N}/u.test("٣"), true);
check("\\p{Lu}", /^\p{Lu}$/u.test("Ä"), true);
check("\\P{L}", /^\P{L}+$/u.test("123 !"), true);
check("\\p{P}", /\p{P}/u.test("¿"), true);
check("\\p{S}", /\p{S}/u.test("€"), true);
check("Script=Greek", /^\p{Script=Greek}+$/u.test("αβγ"), true);
check("sc=Latn", /^\p{sc=Latn}+$/u.test("abc"), true);
check("gc=Lowercase_Letter", /^\p{gc=Lowercase_Letter}+$/u.test("abc"), true);
check("ID_Start", /^\p{ID_Start}\p{ID_Continue}*$/u.test("_x1"), false);
check("ID_Continue", /^\p{ID_Start}\p{ID_Continue}*$/u.test("x1_é"), true);
check("in a class", /^[\p{L}\d_]+$/u.test("é_9"), true);
check("negated in a class", /^[\P{L}]+$/u.test("12"), true);
check("astral", /^\p{L}$/u.test("𝒜"), true);
check("White_Space", /\p{White_Space}/u.test(" "), true);
check("\\p without u is p", /\p{L}/.test("p{L}"), true);

// The s (dotAll) flag.
check("dotAll matches newline", /a.b/s.test("a\nb"), true);
check("without s no newline", /a.b/.test("a\nb"), false);
check("dotAll getter", /x/s.dotAll, true);
check("dotAll getter off", /x/.dotAll, false);
check("flags string", /x/gims.flags, "gims");
check("RegExp constructor s", new RegExp("^.$", "s").test("\r"), true);
check("dotAll with u", /^.$/su.test("\u2028"), true);

// Emoji properties, newer than the bundled ICU.
check("Extended_Pictographic", /^\p{Extended_Pictographic}$/u.test("\u{1F600}"), true);
check("Emoji_Presentation", /\p{Emoji_Presentation}/u.test("\u00A9"), false);
check("Emoji", /\p{Emoji}/u.test("\u00A9"), true);
check("EPres alias", /\p{EPres}/u.test("\u{1F680}"), true);

// Lookbehind.
check("positive lookbehind", "price: $42".match(/(?<=\$)\d+/)[0], "42");
check("negative lookbehind", "x1 $2 y3".match(/(?<!\$)\b\d/g), null);
check("negative lookbehind finds", "$1 2".replace(/(?<!\$)\d/g, "#"), "$1 #");
check("variable length", "https://a.example/path/x".match(/(?<=https:\/\/[^/]+\/)(.*)/)[1], "path/x");
check("groups after keep numbers", /(?<=(a))(b)/.exec("ab")[2], "b");
check("at the start", /(?<=^)a/.test("a"), true);
check("case-insensitive", /(?<=X)y/i.test("xy"), true);
check("lookbehind in replace", "a1b2".replace(/(?<=[a-z])\d/g, "_"), "a_b_");
check("nested lookbehind", /(?<=(?<!b)a)c/.test("ac") && !/(?<=(?<!b)a)c/.test("bac"), true);

var syntaxErrors = ["/\\p{Nonsense}/u", "/\\p{L/u", "/(?<1a>x)/", "/(?<a>x)\\k<b/u", "/\\p{Script}/u"];
for (var i = 0; i < syntaxErrors.length; i++) {
    var threw = false;
    try { eval(syntaxErrors[i]); } catch (e) { threw = e instanceof SyntaxError; }
    check("rejects " + syntaxErrors[i], threw, true);
}

print(failures.length ? "FAIL\n" + failures.join("\n") : "PASS " + count);
