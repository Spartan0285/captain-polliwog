// Async generators and for await (ES2018) as Captain Polliwog adds them to
// JavaScriptCore 604. Run with jsc: prints "PASS n" or the failures once the
// promise jobs have run.

var failures = [];
var count = 0;
function check(name, actual, expected) {
    count++;
    if (actual !== expected)
        failures.push(name + ": got " + String(actual) + ", expected " + String(expected));
}

function delay(value) {
    return new Promise(function (resolve) { resolve(value); });
}

async function* counter(limit) {
    for (var i = 0; i < limit; i++)
        yield await delay(i);
    return "end";
}

async function* withFinally(log) {
    try {
        yield 1;
        yield 2;
    } finally {
        log.push("cleanup");
    }
}

async function* fails() {
    yield 1;
    throw new Error("boom");
}

async function* delegating() {
    yield "a";
    var inner = yield* counter(2);
    yield inner;
    yield* ["x", "y"];
}

var objectWithMethod = {
    async *items() { yield "obj"; }
};

class Store {
    constructor() { this.rows = [3, 4]; }
    async *[Symbol.asyncIterator]() {
        for (var row of this.rows)
            yield row * 10;
    }
    static async *make() { yield "static"; }
}

async function collect(iterable) {
    var out = [];
    for await (var value of iterable)
        out.push(value);
    return out;
}

async function main() {
    // Parsing, as MediaWiki's startup checks it.
    var parses = true;
    try { new Function("try { async function* x() {} } catch {}"); } catch (e) { parses = false; }
    check("MediaWiki compatibility check parses", parses, true);

    var gen = counter(2);
    check("toStringTag", Object.prototype.toString.call(gen), "[object AsyncGenerator]");
    check("next returns a promise", gen.next() instanceof Promise, true);
    var r = await gen.next();
    check("second value", r.value + "/" + r.done, "1/false");
    r = await gen.next();
    check("return value", r.value + "/" + r.done, "end/true");
    r = await gen.next();
    check("after the end", r.value + "/" + r.done, "undefined/true");

    check("for await over async generator", (await collect(counter(3))).join(","), "0,1,2");
    check("for await over array of promises", (await collect([delay(1), 2, delay(3)])).join(","), "1,2,3");
    check("yield*", (await collect(delegating())).join(","), "a,0,1,end,x,y");
    check("object method", (await collect(objectWithMethod.items())).join(","), "obj");
    check("class Symbol.asyncIterator", (await collect(new Store())).join(","), "30,40");
    check("static method", (await collect(Store.make())).join(","), "static");

    var log = [];
    for await (var v of withFinally(log))
        break;
    check("break closes the generator", log.join(","), "cleanup");

    var early = withFinally([]);
    await early.next();
    r = await early.return("stop");
    check("return() mid-way", r.value + "/" + r.done, "stop/true");

    var caught = "";
    try {
        for await (var w of fails()) { }
    } catch (e) {
        caught = e.message;
    }
    check("errors reach for await", caught, "boom");

    // Requests queue up while the body is busy.
    var queued = counter(3);
    var all = await Promise.all([queued.next(), queued.next(), queued.next(), queued.next()]);
    check("queued requests", all.map(function (x) { return x.value; }).join(","), "0,1,2,end");

    // for await inside an async arrow function.
    var arrow = async () => { var s = 0; for await (var n of counter(4)) s += n; return s; };
    check("async arrow for await", await arrow(), 6);

    check("Symbol.asyncIterator", typeof Symbol.asyncIterator, "symbol");
    check("prototype chain", typeof Object.getPrototypeOf(counter.prototype).next, "function");
}

main().then(function () {
    print(failures.length ? "FAIL\n" + failures.join("\n") : "PASS " + count);
}, function (e) {
    print("FAIL (threw) " + e + "\n" + failures.join("\n"));
});
