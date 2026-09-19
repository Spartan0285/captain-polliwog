// Several dynamic imports at once that share a module, as GitHub's page
// does. 604's loader linked some before their dependencies were ready.
// Run with jsc from this directory: prints five "ok" results.
var results = [];
var specs = ["./a.js", "./b.js", "./shared.js", "./c.js", "./a.js"];
var pending = specs.length;
specs.forEach(function (spec) {
    import(spec).then(function (m) { results.push("ok " + spec); }, function (e) { results.push("FAIL " + spec + ": " + e); })
        .then(function () { if (--pending === 0) print(results.join(" | ")); });
});
