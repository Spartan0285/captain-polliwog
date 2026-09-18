// Class static blocks (ES2022) as Captain Polliwog adds them to
// JavaScriptCore 604. Run with jsc: prints "PASS n" or the failures.

var failures = [];
var count = 0;
function check(name, actual, expected) {
    count++;
    if (actual !== expected)
        failures.push(name + ": got " + String(actual) + ", expected " + String(expected));
}

var order = [];
class Config {
    static a = order.push("field a");
    static {
        order.push("block 1");
        this.fromBlock = this.a * 10;
    }
    static b = order.push("field b");
    static {
        order.push("block 2");
        var local = "block-local";
        Config.local = local;
    }
}
check("runs in order with static fields", order.join(" / "), "field a / block 1 / field b / block 2");
check("this is the class", Config.fromBlock, 10);
check("var stays in the block", typeof local, "undefined");
check("class binding visible", Config.local, "block-local");

// Private names and super in a static block.
class Base { static greet() { return "hi"; } }
class Derived extends Base {
    static #secret = 42;
    static {
        this.revealed = Derived.#secret;
        this.greeting = super.greet();
    }
}
check("private static in block", Derived.revealed, 42);
check("super in block", Derived.greeting, "hi");

// Closures over outer variables, and a class with only a block.
var outer = "outer";
var seen;
class OnlyBlock { static { seen = outer + "!"; } }
check("closure in block", seen, "outer!");

// A method named static still works.
class Named { static() { return "method"; } }
check("method named static", new Named().static(), "method");

print(failures.length ? "FAIL\n" + failures.join("\n") : "PASS " + count);
