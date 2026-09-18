// Private class members (ES2022) as Captain Polliwog adds them to
// JavaScriptCore 604. Run with jsc: prints "PASS n" or the failures.
// Known difference: reading a private name an object lacks gives undefined
// instead of throwing a TypeError.

var failures = [];
var count = 0;
function check(name, actual, expected) {
    count++;
    if (actual !== expected)
        failures.push(name + ": got " + String(actual) + ", expected " + String(expected));
}

class Counter {
    #count = 0;
    #step;
    static #instances = 0;

    constructor(step) {
        this.#step = step;
        Counter.#instances++;
    }
    increment() { this.#count += this.#step; return this.#count; }
    get value() { return this.#count; }
    #secret() { return "secret " + this.#count; }
    reveal() { return this.#secret(); }
    get #doubled() { return this.#count * 2; }
    set #doubled(v) { this.#count = v / 2; }
    doubled(v) { if (v !== undefined) this.#doubled = v; return this.#doubled; }
    static instances() { return Counter.#instances; }
    static #helper() { return "static helper"; }
    static callHelper() { return this.#helper(); }
    has(obj) { return #count in obj; }
    equals(other) { return this.#count === other.#count; }
    bump() { this.#count++; ++this.#count; return this.#count; }
}

var c = new Counter(2);
check("private field", c.increment(), 2);
check("getter over private field", c.value, 2);
check("private method", c.reveal(), "secret 2");
check("private accessors", c.doubled(10), 10);
check("private setter wrote", c.value, 5);
check("static private field", (new Counter(1), Counter.instances()), 2);
check("static private method", Counter.callHelper(), "static helper");
check("#x in obj", c.has(c), true);
check("#x in other obj", c.has({}), false);
check("private field of another instance", c.equals(new Counter(3)), false);
check("increment operators", c.bump(), 7);

// Invisible from outside.
check("not a string key", c["#count"], undefined);
check("not in keys", Object.keys(c).length, 0);
check("not in JSON", JSON.stringify(c), "{}");
check("not copied by spread", Object.getOwnPropertySymbols({ ...c }).length, 0);
check("for-in sees nothing", (function () { var n = 0; for (var k in c) n++; return n; })(), 0);

// The same name in two classes is two different names.
class A { #x = "a"; getX() { return this.#x; } static read(o) { return o.#x; } }
class B { #x = "b"; getX() { return this.#x; } }
var a = new A(), b = new B();
check("separate classes", a.getX() + b.getX(), "ab");
check("other class's private name not visible", A.read(b), undefined);

// Nested classes see the outer class's private names.
class Outer {
    #value = 42;
    makeInner() {
        var outer = this;
        return new (class { read() { return outer.#value; } })();
    }
}
check("nested class", new Outer().makeInner().read(), 42);

// Arrow functions and closures.
class Timer {
    #ticks = 0;
    tick = () => ++this.#ticks;
}
var t = new Timer();
var tick = t.tick;
tick(); tick();
check("arrow field with private", tick(), 3);

// Subclasses have their own private names; the base's still work.
class Animal {
    #name;
    constructor(name) { this.#name = name; }
    get name() { return this.#name; }
}
class Dog extends Animal {
    #tricks = [];
    learn(t) { this.#tricks.push(t); return this; }
    describe() { return this.name + " knows " + this.#tricks.join(", "); }
}
check("subclass", new Dog("Rex").learn("sit").learn("stay").describe(), "Rex knows sit, stay");

// Optional chaining.
class Maybe { #inner = { v: 1 }; get(o) { return o?.#inner?.v; } }
check("?.#name", new Maybe().get(null), undefined);
check("?.#name present", new Maybe().get(new Maybe()), 1);

// Each evaluation of a class makes new private names.
function makeClass() { return class { #v = 1; static read(o) { return o.#v; } }; }
var C1 = makeClass(), C2 = makeClass();
check("fresh private names per evaluation", C1.read(new C2()), undefined);
check("same evaluation reads", C1.read(new C1()), 1);

// Syntax errors.
var syntaxErrors = ["#x", "this.#x", "class X { m() { return #x; } }", "class X { # x }"];
for (var i = 0; i < syntaxErrors.length; i++) {
    var threw = false;
    try { eval(syntaxErrors[i]); } catch (e) { threw = e instanceof SyntaxError || e instanceof ReferenceError; }
    check("rejects " + syntaxErrors[i], threw, true);
}

print(failures.length ? "FAIL\n" + failures.join("\n") : "PASS " + count);
