// JSON.stringify on a Proxy keeps only keys it reports as enumerable own
// properties (EnumerableOwnPropertyNames). Run with jsc; expect {"style":"unit"}.
var userScope = { style: "unit" };
var defaults = { style: "decimal", display: true, grid: { color: "gray" } };
var proxy = new Proxy({}, {
    ownKeys: function () { return ["style", "display", "grid"]; },
    getOwnPropertyDescriptor: function (t, p) { var d = Reflect.getOwnPropertyDescriptor(userScope, p); if (d) d.configurable = true; return d; },
    get: function (t, p) { return p in userScope ? userScope[p] : defaults[p]; }
});
print("JSON: " + JSON.stringify(proxy));
print("Object.keys: " + Object.keys(proxy).join(","));
var inKeys = []; for (var k in proxy) inKeys.push(k); print("for-in: " + inKeys.join(","));
print("assign: " + JSON.stringify(Object.assign({}, proxy)));
