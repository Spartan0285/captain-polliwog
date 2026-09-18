// Public class fields (ES2022) as Captain Polliwog adds them to
// JavaScriptCore 604. Run with jsc: prints "PASS n" or the failures.

var failures = [];
var count = 0;
function check(name, actual, expected) {
    count++;
    if (actual !== expected)
        failures.push(name + ": got " + String(actual) + ", expected " + String(expected));
}

// Instance fields on a base class, with and without initializers.
class Point {
    x = 1;
    y = this.x + 1;
    z;
    "quoted" = 4;
    5 = "five";
    static = "a field named static";
    get = "a field named get";
}
var p = new Point();
check("field", p.x, 1);
check("field uses earlier field", p.y, 2);
check("field without initializer", p.z, undefined);
check("field without initializer is own", p.hasOwnProperty("z"), true);
check("string-named field", p.quoted, 4);
check("numeric field", p[5], "five");
check("field named static", p.static, "a field named static");
check("field named get", p.get, "a field named get");
check("fields are enumerable", Object.keys(p).join(","), "5,x,y,z,quoted,static,get");
check("each instance gets its own", new Point().x === 1 && new Point() !== new Point(), true);

// Fields run before the constructor body, and after super() in subclasses.
var order = [];
class Base {
    baseField = order.push("base field");
    constructor() { order.push("base constructor"); }
}
class Derived extends Base {
    derivedField = order.push("derived field");
    constructor() {
        order.push("before super");
        super();
        order.push("after super");
    }
}
new Derived();
check("initialization order", order.join(" / "),
    "before super / base field / base constructor / derived field / after super");

// A subclass without its own constructor.
class Child extends Point { w = this.x * 10; }
var c = new Child();
check("default derived constructor", c.w, 10);
check("inherited fields", c.y, 2);

// Arrow functions keep the instance as |this|, as in React components.
class Button {
    label = "OK";
    onClick = () => this.label;
}
var b = new Button();
var detached = b.onClick;
check("arrow field keeps this", detached(), "OK");
check("arrow field is named", b.onClick.name, "onClick");

// Closures over surrounding variables.
function makeClass(start) {
    var step = 5;
    return class { value = start + step; };
}
check("captures outer variables", new (makeClass(10))().value, 15);

// super.method() in an initializer.
class A { greet() { return "hi"; } }
class B extends A { greeting = super.greet() + "!"; }
check("super property in field", new B().greeting, "hi!");

// Static fields.
var staticOrder = [];
class Config {
    static defaults = { size: 3 };
    static self = Config;
    static twice = this.defaults.size * 2;
    static counter;
    static bump() { return ++Config.bump.calls; }
}
check("static field", Config.defaults.size, 3);
check("static field sees class binding", Config.self, Config);
check("static field this is the class", Config.twice, 6);
check("static field without initializer", Config.hasOwnProperty("counter"), true);
check("static fields stay off instances", new Config().defaults, undefined);

// Define, not assign: a setter on the prototype is not called.
var setterCalls = 0;
class WithSetter { set value(v) { setterCalls++; } }
class Shadow extends WithSetter { value = 1; }
var s = new Shadow();
check("define semantics", setterCalls, 0);
check("defined own property", s.value, 1);

// Automatic semicolons between fields.
class NoSemicolons {
    a = 1
    b = 2
    method() { return this.a + this.b; }
}
check("automatic semicolons", new NoSemicolons().method(), 3);

// Class expressions and anonymous classes.
var Anon = class { f = "anonymous"; };
check("class expression", new Anon().f, "anonymous");

// Errors thrown in an initializer reach the caller of new.
class Throws { f = (function () { throw new Error("boom"); })(); }
var message = "";
try { new Throws(); } catch (e) { message = e.message; }
check("initializer errors propagate", message, "boom");

// Syntax that must still be rejected.
var syntaxErrors = ["class X { constructor = 1 }", "class X { static prototype = 1 }", "class X { a b }"];
for (var i = 0; i < syntaxErrors.length; i++) {
    var threw = false;
    try { eval(syntaxErrors[i]); } catch (e) { threw = e instanceof SyntaxError; }
    check("rejects " + syntaxErrors[i], threw, true);
}

// A class inside a function that is compiled lazily.
function lazyFactory() {
    class Lazy { n = 42; static s = "static"; }
    return new Lazy().n + Lazy.s;
}
check("lazily compiled class", lazyFactory(), "42static");

// Methods keep working next to fields.
class Mixed {
    count = 0;
    increment() { return ++this.count; }
    static make() { return new Mixed(); }
}
var m = Mixed.make();
m.increment();
check("methods with fields", m.increment(), 2);

// super() called from an arrow function in the constructor.
class ArrowSuper extends Base {
    tag = "arrow";
    constructor() {
        var callSuper = () => super();
        callSuper();
    }
}
check("super() in arrow function", new ArrowSuper().tag, "arrow");

// A named class expression sees its own name.
var Outer = class Inner { self = Inner; };
check("named class expression", new Outer().self, Outer);

// Plain functions in an initializer have their own |this|.
class OwnThis { f = function () { return this; }; }
check("function field has its own this", new OwnThis().f.call(7) == 7, true);

// Fields next to generators, async methods and accessors.
class Kinds {
    async = "async field";
    await = "await field";
    items = [1, 2];
    *[Symbol.iterator]() { yield* this.items; }
    async load() { return 1; }
    get size() { return this.items.length; }
}
var k = new Kinds();
check("field named async", k.async, "async field");
check("field named await", k.await, "await field");
check("generator method with fields", Array.from(k).join(","), "1,2");
check("getter with fields", k.size, 2);

// Each evaluation of a class body makes a new class.
var made = [];
for (var n = 0; n < 3; n++)
    made.push(class { v = n; });
check("classes made in a loop", new made[0]().v + new made[2]().v, 6);

// A class expression as a field's value.
class Holder { Inner = class { x = 9; }; }
check("class-valued field", new (new Holder().Inner)().x, 9);
check("class-valued field is named", new Holder().Inner.name, "Inner");

print(failures.length ? "FAIL\n" + failures.join("\n") : "PASS " + count);
