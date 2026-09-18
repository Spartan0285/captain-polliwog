// import.meta (ES2020). Run as a module: jsc -m import-meta.js
import * as self from "./import-meta.js";

var failures = [];
function check(name, actual, expected) {
    if (actual !== expected)
        failures.push(name + ": got " + String(actual) + ", expected " + String(expected));
}
check("url is a string", typeof import.meta.url, "string");
check("url names this module", import.meta.url.slice(-14), "import-meta.js");
check("same object each time", import.meta, import.meta);
check("null prototype", Object.getPrototypeOf(import.meta), null);
function inner() { return import.meta; }
check("inside functions", inner(), import.meta);
import.meta.extra = 1;
check("writable", import.meta.extra, 1);
print(failures.length ? "FAIL\n" + failures.join("\n") : "PASS 6");
