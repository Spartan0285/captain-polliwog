// Training workload for a profile-guided build of JavaScriptCore.
//
// Deliberately NOT llint-bench.js, which is what the result is measured on.
// Training and measuring on the same code tells you how well PGO memorised
// one benchmark, which is a number that always looks good and never ships.
//
// What it aims at is the shape of Speedometer's work rather than its exact
// code: building and tearing down objects, string and array churn, property
// lookups on polymorphic shapes, closures, JSON, regular expressions, and
// enough class hierarchy to exercise the inline caches. Speedometer itself
// cannot run here -- it needs a DOM, and this is the bare engine -- so the
// engine-level half of it is what gets covered.
//
// Run with: jsc pgo-train.js

var sink = 0;

// --- Object churn with polymorphic shapes. Inline caches earn their keep
// --- or fail to, and either way the profile should record which.
function Item(id, label, done) {
    this.id = id;
    this.label = label;
    this.done = done;
}
Item.prototype.toggle = function () { this.done = !this.done; return this; };
Item.prototype.describe = function () { return this.id + ":" + this.label; };

function LabelledItem(id, label, done, tag) {
    Item.call(this, id, label, done);
    this.tag = tag;
}
LabelledItem.prototype = Object.create(Item.prototype);
LabelledItem.prototype.describe = function () {
    return Item.prototype.describe.call(this) + "#" + this.tag;
};

function objectChurn(n) {
    var items = [], i;
    for (i = 0; i < n; i++) {
        items.push(i % 3 === 0
            ? new LabelledItem(i, "item" + i, false, "t" + (i % 7))
            : new Item(i, "item" + i, false));
    }
    for (i = 0; i < items.length; i++)
        if (i % 2) items[i].toggle();
    var total = 0;
    for (i = 0; i < items.length; i++)
        total += items[i].describe().length;
    return total;
}

// --- Array and string work: the two things every framework does between
// --- the model and the page.
function arrayWork(n) {
    var a = [], i;
    for (i = 0; i < n; i++) a.push((i * 2654435761) % 1000);
    a.sort(function (x, y) { return x - y; });
    var mapped = a.map(function (x) { return x * 2 + 1; });
    var kept = mapped.filter(function (x) { return x % 3 !== 0; });
    return kept.reduce(function (acc, x) { return (acc + x) | 0; }, 0);
}

function stringWork(n) {
    var parts = [], i;
    for (i = 0; i < n; i++) parts.push("<li class='row'>" + i + "</li>");
    var joined = parts.join("");
    var count = joined.split("<li").length;
    var upper = joined.toUpperCase();
    return count + upper.length;
}

// --- Property access through a plain dictionary, which is what most
// --- framework state actually is.
function mapWork(n) {
    var o = {}, i, k;
    for (i = 0; i < n; i++) o["key" + (i % 500)] = i;
    var sum = 0;
    for (k in o) if (o.hasOwnProperty(k)) sum += o[k];
    return sum;
}

// --- JSON and regular expressions, both heavily used and both with their
// --- own engine subsystems that nothing else here reaches.
function jsonWork(n) {
    var rows = [], i;
    for (i = 0; i < n; i++)
        rows.push({ id: i, name: "row " + i, tags: ["a", "b"], ok: i % 2 === 0 });
    var text = JSON.stringify(rows);
    var back = JSON.parse(text);
    return back.length + text.length;
}

function regexpWork(n) {
    var re = /(\w+)\s+(\d+)/g;
    var word = /^[a-z]+$/;
    var total = 0, i, m;
    for (i = 0; i < n; i++) {
        var s = "field" + i + " " + (i * 7);
        re.lastIndex = 0;
        m = re.exec(s);
        if (m) total += m[1].length + m[2].length;
        if (word.test("abcdef")) total++;
    }
    return total;
}

// --- Closures and higher-order functions, which is how the frameworks
// --- wire everything together.
function closureWork(n) {
    var fns = [], i;
    for (i = 0; i < n; i++) {
        (function (captured) {
            fns.push(function (x) { return x + captured; });
        })(i);
    }
    var total = 0;
    for (i = 0; i < fns.length; i++) total = (total + fns[i](i)) | 0;
    return total;
}

// Several passes, so that functions get hot enough to be worth a profile
// and tier up the way they would in a real page.
var PASSES = 6;
for (var pass = 0; pass < PASSES; pass++) {
    sink += objectChurn(4000);
    sink += arrayWork(6000);
    sink += stringWork(5000);
    sink += mapWork(8000);
    sink += jsonWork(1500);
    sink += regexpWork(8000);
    sink += closureWork(6000);
}

print("pgo-train done, checksum " + sink);
