/* The optimizing compiler and an array's length, reduced as far as it goes.
 *
 *   jsc --useDFGJIT=false scripts/jit/dfg-array-length.js    every line 2
 *   jsc --useDFGJIT=true --thresholdForOptimizeAfterWarmUp=10 \
 *       --thresholdForOptimizeSoon=10 --thresholdForJITAfterWarmUp=5 \
 *       scripts/jit/dfg-array-length.js                      every line wrong
 *
 * What comes back is 2.121995789e-314, which is a JSValue whose two halves
 * read as 1 and 0 taken for a double - the same shape as the other two
 * big-endian faults found in this tier, and not a number any correct path
 * produces. The elements of the same array read back perfectly; it is only
 * the length. `[1,2].length | 0` answers 0, so the register holds nothing
 * useful before anything boxes it.
 *
 * The driver is kept out of the compiler so that the case being measured is
 * the only thing compiled.
 */
function drive(f)
{
    var last = null;
    for (var i = 0; i < 300; i++)
        last = f(i);
    return String(last);
}
if (typeof noDFG === "function")
    noDFG(drive);

function show(name, f)
{
    var r;
    try { r = drive(f); } catch (e) { r = "THREW " + e.message.substring(0, 40); }
    print(name + "\t" + r);
}

show("[1,2].length",        function () { return [1, 2].length; });
show("[1.5,2.5].length",    function () { return [1.5, 2.5].length; });
show("['a','b'].length",    function () { return ["a", "b"].length; });
show("new Array(2).length", function () { return new Array(2).length; });
show("[1,2].length === 2",  function () { return [1, 2].length === 2; });
show("[1,2].length | 0",    function () { return [1, 2].length | 0; });
show("[1,2][0]",            function () { return [1, 2][0]; });
show("[1,2][1]",            function () { return [1, 2][1]; });
