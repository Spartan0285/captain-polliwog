/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

/*
 * Newer web platform features for older WebKit engines. Captain Polliwog
 * runs this in every frame before the page's own scripts. Each feature is
 * added only where the engine lacks it, so a newer engine runs almost none
 * of it. Written in ES5 so that even Tiger's WebKit can read it.
 */
(function (global) {
    "use strict";

    var hasOwn = Object.prototype.hasOwnProperty;

    function define(object, name, value) {
        if (!object || name in object)
            return;
        try {
            Object.defineProperty(object, name, { value: value, writable: true, configurable: true, enumerable: false });
        } catch (e) {
            object[name] = value;
        }
    }

    function defineGetter(object, name, getter) {
        if (!object || name in object)
            return;
        try {
            Object.defineProperty(object, name, { get: getter, configurable: true, enumerable: false });
        } catch (e) {
        }
    }

    function toInteger(value) {
        var number = Number(value);
        if (number !== number)
            return 0;
        if (number === 0 || !isFinite(number))
            return number;
        return (number > 0 ? 1 : -1) * Math.floor(Math.abs(number));
    }

    function toLength(value) {
        var length = toInteger(value);
        return length <= 0 ? 0 : Math.min(length, 9007199254740991);
    }

    var hasSymbol = typeof Symbol === "function" && typeof Symbol.iterator === "symbol";

    // Turns anything iterable (or array-like, on engines without iterators)
    // into an array.
    function iterableToArray(iterable) {
        if (hasSymbol && iterable != null && typeof iterable[Symbol.iterator] === "function") {
            var result = [];
            var iterator = iterable[Symbol.iterator]();
            for (var step = iterator.next(); !step.done; step = iterator.next())
                result.push(step.value);
            return result;
        }
        return Array.prototype.slice.call(iterable);
    }

    /* ---------------------------------------------------------------- Symbols */

    if (hasSymbol) {
        if (!Symbol.asyncIterator)
            define(Symbol, "asyncIterator", Symbol("Symbol.asyncIterator"));
        defineGetter(Symbol.prototype, "description", function () {
            var text = String(this);
            return text.slice(7, -1);
        });
    }

    /* ---------------------------------------------------------------- Object */

    define(Object, "fromEntries", function fromEntries(entries) {
        var result = {};
        var list = iterableToArray(entries);
        for (var i = 0; i < list.length; i++)
            result[list[i][0]] = list[i][1];
        return result;
    });

    define(Object, "hasOwn", function hasOwnProperty(object, key) {
        if (object == null)
            throw new TypeError("Cannot convert undefined or null to object");
        return hasOwn.call(Object(object), key);
    });

    define(Object, "groupBy", function groupBy(items, callback) {
        var result = Object.create(null);
        var list = iterableToArray(items);
        for (var i = 0; i < list.length; i++) {
            var key = callback(list[i], i);
            if (!hasOwn.call(result, key))
                result[key] = [];
            result[key].push(list[i]);
        }
        return result;
    });

    /* ---------------------------------------------------------------- Arrays */

    function flattenInto(target, source, depth) {
        for (var i = 0; i < source.length; i++) {
            if (!(i in source))
                continue;
            var element = source[i];
            if (depth > 0 && Array.isArray(element))
                flattenInto(target, element, depth - 1);
            else
                target.push(element);
        }
        return target;
    }

    define(Array.prototype, "flat", function flat() {
        var depth = arguments.length && arguments[0] !== undefined ? toInteger(arguments[0]) : 1;
        return flattenInto([], Object(this), depth);
    });

    define(Array.prototype, "flatMap", function flatMap(callback, thisArg) {
        var object = Object(this);
        var length = toLength(object.length);
        var result = [];
        for (var i = 0; i < length; i++) {
            if (!(i in object))
                continue;
            var mapped = callback.call(thisArg, object[i], i, object);
            if (Array.isArray(mapped))
                flattenInto(result, mapped, 0);
            else
                result.push(mapped);
        }
        return result;
    });

    function at(index) {
        var object = Object(this);
        var length = toLength(object.length);
        var relative = toInteger(index);
        var k = relative >= 0 ? relative : length + relative;
        return k < 0 || k >= length ? undefined : object[k];
    }
    define(Array.prototype, "at", at);

    define(Array.prototype, "findLast", function findLast(predicate, thisArg) {
        var object = Object(this);
        for (var i = toLength(object.length) - 1; i >= 0; i--) {
            if (predicate.call(thisArg, object[i], i, object))
                return object[i];
        }
        return undefined;
    });

    define(Array.prototype, "findLastIndex", function findLastIndex(predicate, thisArg) {
        var object = Object(this);
        for (var i = toLength(object.length) - 1; i >= 0; i--) {
            if (predicate.call(thisArg, object[i], i, object))
                return i;
        }
        return -1;
    });

    define(Array.prototype, "toReversed", function toReversed() {
        return Array.prototype.slice.call(this).reverse();
    });

    define(Array.prototype, "toSorted", function toSorted(compare) {
        return Array.prototype.slice.call(this).sort(compare);
    });

    define(Array.prototype, "toSpliced", function toSpliced() {
        var copy = Array.prototype.slice.call(this);
        Array.prototype.splice.apply(copy, arguments);
        return copy;
    });

    define(Array.prototype, "with", function (index, value) {
        var copy = Array.prototype.slice.call(this);
        var relative = toInteger(index);
        var k = relative >= 0 ? relative : copy.length + relative;
        if (k < 0 || k >= copy.length)
            throw new RangeError("Invalid index");
        copy[k] = value;
        return copy;
    });

    // Typed arrays share one prototype.
    if (typeof Uint8Array === "function" && Object.getPrototypeOf) {
        var typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
        define(typedArrayPrototype, "at", at);
    }

    /* ---------------------------------------------------------------- Strings */

    define(String.prototype, "trimStart", String.prototype.trimLeft || function trimStart() {
        return String(this).replace(/^[\s\uFEFF\xA0]+/, "");
    });

    define(String.prototype, "trimEnd", String.prototype.trimRight || function trimEnd() {
        return String(this).replace(/[\s\uFEFF\xA0]+$/, "");
    });

    define(String.prototype, "at", function (index) {
        var string = String(this);
        var relative = toInteger(index);
        var k = relative >= 0 ? relative : string.length + relative;
        return k < 0 || k >= string.length ? undefined : string.charAt(k);
    });

    function escapeRegExp(text) {
        return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }

    define(String.prototype, "replaceAll", function replaceAll(search, replacement) {
        var string = String(this);
        if (search instanceof RegExp) {
            if (search.flags.indexOf("g") < 0)
                throw new TypeError("replaceAll must be called with a global RegExp");
            return string.replace(search, replacement);
        }
        // A pattern with no groups gives replace() the same "$" handling.
        return string.replace(new RegExp(escapeRegExp(String(search)), "g"), replacement);
    });

    if (hasSymbol) {
        define(String.prototype, "matchAll", function matchAll(regexp) {
            var string = String(this);
            var matcher;
            if (regexp instanceof RegExp) {
                if (regexp.flags.indexOf("g") < 0)
                    throw new TypeError("matchAll must be called with a global RegExp");
                matcher = new RegExp(regexp.source, regexp.flags);
                matcher.lastIndex = regexp.lastIndex;
            } else
                matcher = new RegExp(regexp, "g");
            var done = false;
            var iterator = {
                next: function () {
                    if (done)
                        return { value: undefined, done: true };
                    var match = matcher.exec(string);
                    if (!match) {
                        done = true;
                        return { value: undefined, done: true };
                    }
                    if (match[0] === "")
                        matcher.lastIndex++;
                    return { value: match, done: false };
                }
            };
            iterator[Symbol.iterator] = function () { return this; };
            return iterator;
        });
    }

    /* ---------------------------------------------------------------- Promises */

    if (typeof Promise === "function") {
        define(Promise.prototype, "finally", function (onFinally) {
            var constructor = this.constructor || Promise;
            if (typeof onFinally !== "function")
                return this.then(onFinally, onFinally);
            return this.then(function (value) {
                return constructor.resolve(onFinally()).then(function () { return value; });
            }, function (reason) {
                return constructor.resolve(onFinally()).then(function () { throw reason; });
            });
        });

        define(Promise, "allSettled", function allSettled(iterable) {
            var constructor = this;
            return constructor.all(iterableToArray(iterable).map(function (item) {
                return constructor.resolve(item).then(function (value) {
                    return { status: "fulfilled", value: value };
                }, function (reason) {
                    return { status: "rejected", reason: reason };
                });
            }));
        });

        if (typeof global.AggregateError !== "function") {
            var AggregateError = function AggregateError(errors, message) {
                var error = new Error(message);
                if (Object.setPrototypeOf)
                    Object.setPrototypeOf(error, AggregateError.prototype);
                error.errors = iterableToArray(errors);
                return error;
            };
            AggregateError.prototype = Object.create(Error.prototype, {
                constructor: { value: AggregateError, writable: true, configurable: true },
                name: { value: "AggregateError", writable: true, configurable: true }
            });
            define(global, "AggregateError", AggregateError);
        }

        define(Promise, "any", function any(iterable) {
            var constructor = this;
            var items = iterableToArray(iterable);
            return new constructor(function (resolve, reject) {
                var errors = [];
                var remaining = items.length;
                if (!remaining)
                    reject(new global.AggregateError([], "All promises were rejected"));
                items.forEach(function (item, index) {
                    constructor.resolve(item).then(resolve, function (reason) {
                        errors[index] = reason;
                        if (!--remaining)
                            reject(new global.AggregateError(errors, "All promises were rejected"));
                    });
                });
            });
        });

        define(Promise, "withResolvers", function withResolvers() {
            var result = {};
            result.promise = new this(function (resolve, reject) {
                result.resolve = resolve;
                result.reject = reject;
            });
            return result;
        });

        define(global, "queueMicrotask", function queueMicrotask(callback) {
            if (typeof callback !== "function")
                throw new TypeError("queueMicrotask requires a function");
            Promise.resolve().then(callback)["catch"](function (error) {
                setTimeout(function () { throw error; }, 0);
            });
        });
    }

    /* ---------------------------------------------------------------- Weak references */

    if (typeof global.WeakRef !== "function" && typeof WeakMap === "function") {
        // Without the engine's help this holds its target strongly: deref()
        // always answers, which is all most pages rely on.
        var WeakRef = function WeakRef(target) {
            if (Object(target) !== target)
                throw new TypeError("WeakRef: target must be an object");
            this._target = target;
        };
        WeakRef.prototype.deref = function () { return this._target; };
        define(global, "WeakRef", WeakRef);
    }

    if (typeof global.FinalizationRegistry !== "function") {
        var FinalizationRegistry = function FinalizationRegistry(callback) {
            this._callback = callback;
        };
        FinalizationRegistry.prototype.register = function () {};
        FinalizationRegistry.prototype.unregister = function () { return false; };
        define(global, "FinalizationRegistry", FinalizationRegistry);
    }

    /* ---------------------------------------------------------------- Intl */

    if (typeof Intl === "object" && Intl.NumberFormat && !Intl.NumberFormat.prototype.formatToParts) {
        // Splits formatted text into the parts formatToParts would give,
        // using the formatter's own output for the separators it uses.
        define(Intl.NumberFormat.prototype, "formatToParts", function formatToParts(number) {
            var formatted = this.format(number);
            var locale = this.resolvedOptions().locale;
            var probe = new Intl.NumberFormat(locale, { useGrouping: true, minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(11111.5);
            var group = probe.replace(/[0-9]/g, "").charAt(0);
            var decimal = probe.replace(/[0-9]/g, "").slice(-1);
            var parts = [];
            var i = 0;
            var seenDecimal = false;
            function push(type, value) {
                var last = parts[parts.length - 1];
                if (last && last.type === type && type !== "group" && type !== "decimal")
                    last.value += value;
                else
                    parts.push({ type: type, value: value });
            }
            while (i < formatted.length) {
                var ch = formatted.charAt(i);
                if (/[0-9\u0660-\u0669\u06F0-\u06F9]/.test(ch))
                    push(seenDecimal ? "fraction" : "integer", ch);
                else if (ch === decimal && /[0-9]/.test(formatted.charAt(i + 1)) && !seenDecimal) {
                    seenDecimal = true;
                    push("decimal", ch);
                } else if (ch === group && /[0-9]/.test(formatted.charAt(i - 1)) && /[0-9]/.test(formatted.charAt(i + 1)))
                    push("group", ch);
                else if (ch === "-" || ch === "\u2212")
                    push("minusSign", ch);
                else if (ch === "+")
                    push("plusSign", ch);
                else if (ch === "%")
                    push("percentSign", ch);
                else if (/\s/.test(ch))
                    push("literal", ch);
                else
                    push(this.resolvedOptions().style === "currency" ? "currency" : "literal", ch);
                i++;
            }
            return parts;
        });
    }

    if (typeof Intl === "object" && !Intl.PluralRules) {
        // English plural rules, enough for pages that only choose between
        // "one" and "other".
        var PluralRules = function PluralRules(locales, options) {
            this._type = options && options.type || "cardinal";
            this._locale = Array.isArray(locales) ? locales[0] || "en" : locales || "en";
        };
        PluralRules.prototype.select = function (number) {
            number = Number(number);
            if (this._type === "ordinal") {
                var ones = number % 10, tens = number % 100;
                if (ones === 1 && tens !== 11) return "one";
                if (ones === 2 && tens !== 12) return "two";
                if (ones === 3 && tens !== 13) return "few";
                return "other";
            }
            return number === 1 ? "one" : "other";
        };
        PluralRules.prototype.resolvedOptions = function () {
            return { locale: this._locale, type: this._type, pluralCategories: ["one", "other"] };
        };
        PluralRules.supportedLocalesOf = function (locales) { return [].concat(locales || []); };
        define(Intl, "PluralRules", PluralRules);
    }

    if (typeof Intl === "object" && !Intl.RelativeTimeFormat) {
        var RelativeTimeFormat = function RelativeTimeFormat(locales, options) {
            this._numeric = options && options.numeric || "always";
            this._locale = Array.isArray(locales) ? locales[0] || "en" : locales || "en";
        };
        RelativeTimeFormat.prototype.format = function (value, unit) {
            value = Number(value);
            unit = String(unit).replace(/s$/, "");
            if (this._numeric === "auto") {
                if (value === 0 && unit === "day") return "today";
                if (value === 1 && unit === "day") return "tomorrow";
                if (value === -1 && unit === "day") return "yesterday";
                if (value === 0) return "this " + unit;
                if (value === 1) return "next " + unit;
                if (value === -1) return "last " + unit;
            }
            var amount = Math.abs(value);
            var label = amount + " " + unit + (amount === 1 ? "" : "s");
            return value < 0 || (value === 0 && 1 / value < 0) ? label + " ago" : "in " + label;
        };
        RelativeTimeFormat.prototype.formatToParts = function (value, unit) {
            return [{ type: "literal", value: this.format(value, unit) }];
        };
        RelativeTimeFormat.prototype.resolvedOptions = function () {
            return { locale: this._locale, numeric: this._numeric, style: "long" };
        };
        RelativeTimeFormat.supportedLocalesOf = function (locales) { return [].concat(locales || []); };
        define(Intl, "RelativeTimeFormat", RelativeTimeFormat);
    }

    if (typeof Intl === "object" && !Intl.ListFormat) {
        var ListFormat = function ListFormat(locales, options) {
            this._type = options && options.type || "conjunction";
        };
        ListFormat.prototype.format = function (list) {
            var items = iterableToArray(list).map(String);
            var word = this._type === "disjunction" ? "or" : "and";
            if (items.length < 2)
                return items.join("");
            if (items.length === 2)
                return items[0] + " " + word + " " + items[1];
            return items.slice(0, -1).join(", ") + ", " + word + " " + items[items.length - 1];
        };
        ListFormat.supportedLocalesOf = function (locales) { return [].concat(locales || []); };
        define(Intl, "ListFormat", ListFormat);
    }

    /* ---------------------------------------------------------------- DOM */

    if (typeof document === "undefined")
        return;

    var ElementPrototype = global.Element && Element.prototype;

    /* AutoFill: the last password typed on this page, with the username
       before it, kept so Captain Polliwog can offer to save the login even
       when the page clears or replaces the field before it moves on (as
       Google's sign-in does). The page's own data, kept in the page. */
    (function () {
        function record(event) {
            var target = event.target;
            if (!target || target.tagName !== "INPUT" || String(target.type).toLowerCase() !== "password" || !target.value)
                return;
            var username = "", inputs = document.getElementsByTagName("input");
            for (var i = 0; i < inputs.length && inputs[i] !== target; i++) {
                var type = String(inputs[i].type).toLowerCase();
                if ((type === "email" || type === "text" || type === "hidden") && inputs[i].value
                    && (type !== "hidden" || /mail|user|login|identifier/i.test(inputs[i].name || "")))
                    username = inputs[i].value;
            }
            try {
                Object.defineProperty(global, "__polliwogTypedLogin", {
                    value: { password: target.value, username: username }, configurable: true, writable: true
                });
            } catch (e) {
            }
        }
        document.addEventListener("change", record, true);
        document.addEventListener("input", record, true);
    })();

    define(ElementPrototype, "toggleAttribute", function toggleAttribute(name, force) {
        var has = this.hasAttribute(name);
        if (force === undefined ? has : !force) {
            this.removeAttribute(name);
            return false;
        }
        if (!has)
            this.setAttribute(name, "");
        return true;
    });

    function replaceChildren() {
        while (this.lastChild)
            this.removeChild(this.lastChild);
        if (this.append)
            this.append.apply(this, arguments);
        else {
            for (var i = 0; i < arguments.length; i++) {
                var node = arguments[i];
                this.appendChild(typeof node === "string" ? document.createTextNode(node) : node);
            }
        }
    }
    define(ElementPrototype, "replaceChildren", replaceChildren);
    if (global.DocumentFragment)
        define(DocumentFragment.prototype, "replaceChildren", replaceChildren);
    if (global.Document)
        define(Document.prototype, "replaceChildren", replaceChildren);

    if (global.HTMLFormElement)
        define(HTMLFormElement.prototype, "requestSubmit", function requestSubmit(submitter) {
            if (submitter) {
                submitter.click();
                return;
            }
            var button = document.createElement("input");
            button.type = "submit";
            button.hidden = true;
            this.appendChild(button);
            button.click();
            this.removeChild(button);
        });

    if (global.crypto && crypto.getRandomValues)
        define(crypto, "randomUUID", function randomUUID() {
            var bytes = new Uint8Array(16);
            crypto.getRandomValues(bytes);
            bytes[6] = (bytes[6] & 0x0f) | 0x40;
            bytes[8] = (bytes[8] & 0x3f) | 0x80;
            var hex = [];
            for (var i = 0; i < 16; i++)
                hex.push((bytes[i] + 0x100).toString(16).slice(1));
            return hex.slice(0, 4).join("") + "-" + hex.slice(4, 6).join("") + "-" + hex.slice(6, 8).join("") + "-" + hex.slice(8, 10).join("") + "-" + hex.slice(10).join("");
        });

    if (global.Blob) {
        var readBlob = function (blob, method) {
            return new Promise(function (resolve, reject) {
                var reader = new FileReader();
                reader.onload = function () { resolve(reader.result); };
                reader.onerror = function () { reject(reader.error); };
                reader[method](blob);
            });
        };
        define(Blob.prototype, "text", function text() { return readBlob(this, "readAsText"); });
        define(Blob.prototype, "arrayBuffer", function arrayBuffer() { return readBlob(this, "readAsArrayBuffer"); });
    }

    // matchMedia(...).addEventListener("change", ...): older engines have
    // only addListener, whose callback gets the list itself -- which carries
    // the same matches and media an event would.
    (function () {
        var MQL = global.MediaQueryList;
        var proto = MQL ? MQL.prototype : null;
        if (!proto && global.matchMedia) {
            try {
                proto = Object.getPrototypeOf(global.matchMedia("all"));
            } catch (e) {
            }
        }
        if (!proto || typeof proto.addListener !== "function" || typeof proto.addEventListener === "function")
            return;
        define(proto, "addEventListener", function addEventListener(type, listener) {
            if (type === "change" && listener)
                this.addListener(typeof listener === "function" ? listener : listener.__polliwogHandle ||
                    (listener.__polliwogHandle = function (list) { listener.handleEvent(list); }));
        });
        define(proto, "removeEventListener", function removeEventListener(type, listener) {
            if (type === "change" && listener)
                this.removeListener(typeof listener === "function" ? listener : listener.__polliwogHandle);
        });
        define(proto, "dispatchEvent", function dispatchEvent() { return true; });
    })();

    // new EventTarget(), and classes that extend it, for engines where
    // EventTarget is only an interface: listeners live on a hidden
    // DocumentFragment, a real event target.
    (function () {
        var NativeEventTarget = global.EventTarget;
        if (!NativeEventTarget)
            return;
        try {
            new NativeEventTarget();
            return;
        } catch (e) {
        }
        // Code that calls EventTarget.prototype's methods directly (super.
        // addEventListener in a subclass, for one) reaches the delegate too.
        ["addEventListener", "removeEventListener", "dispatchEvent"].forEach(function (name) {
            var native = NativeEventTarget.prototype[name];
            NativeEventTarget.prototype[name] = function () {
                var delegate = this && this.__polliwogEventDelegate;
                return delegate ? delegate[name].apply(delegate, arguments) : native.apply(this, arguments);
            };
        });
        var EventTarget = function EventTarget() {
            var delegate = document.createDocumentFragment();
            var self = this;
            Object.defineProperty(self, "__polliwogEventDelegate", { value: delegate });
            ["addEventListener", "removeEventListener"].forEach(function (name) {
                Object.defineProperty(self, name, { value: function () { return delegate[name].apply(delegate, arguments); }, configurable: true, writable: true });
            });
            Object.defineProperty(self, "dispatchEvent", {
                value: function (event) {
                    // Handlers see this object as the target.
                    var handler = self["on" + event.type];
                    var result = delegate.dispatchEvent(event);
                    if (typeof handler === "function")
                        handler.call(self, event);
                    return result;
                },
                configurable: true,
                writable: true
            });
        };
        EventTarget.prototype = NativeEventTarget.prototype;
        global.EventTarget = EventTarget;
    })();

    /* AbortController and AbortSignal */
    if (typeof global.AbortController !== "function") {
        var AbortSignal = function AbortSignal() {
            throw new TypeError("Illegal constructor");
        };
        AbortSignal.prototype = Object.create(global.EventTarget.prototype, {
            constructor: { value: AbortSignal, writable: true, configurable: true }
        });
        var makeAbortSignal = function () {
            var signal = new global.EventTarget();
            if (Object.setPrototypeOf)
                Object.setPrototypeOf(signal, AbortSignal.prototype);
            signal.aborted = false;
            signal.reason = undefined;
            signal.onabort = null;
            signal.throwIfAborted = function () {
                if (this.aborted)
                    throw this.reason;
            };
            return signal;
        };
        var abortError = function () {
            var error;
            try {
                error = new DOMException("The operation was aborted.", "AbortError");
            } catch (e) {
                error = new Error("The operation was aborted.");
                error.name = "AbortError";
            }
            return error;
        };
        var abortSignal = function (signal, reason) {
            if (signal.aborted)
                return;
            signal.aborted = true;
            signal.reason = reason === undefined ? abortError() : reason;
            var event;
            try {
                event = new Event("abort");
            } catch (e) {
                event = document.createEvent("Event");
                event.initEvent("abort", false, false);
            }
            signal.dispatchEvent(event);
        };
        AbortSignal.abort = function (reason) {
            var signal = makeAbortSignal();
            abortSignal(signal, reason);
            return signal;
        };
        AbortSignal.timeout = function (milliseconds) {
            var signal = makeAbortSignal();
            setTimeout(function () {
                var error;
                try {
                    error = new DOMException("The operation timed out.", "TimeoutError");
                } catch (e) {
                    error = new Error("The operation timed out.");
                }
                abortSignal(signal, error);
            }, milliseconds);
            return signal;
        };
        AbortSignal.any = function (signals) {
            var signal = makeAbortSignal();
            iterableToArray(signals).forEach(function (source) {
                if (source.aborted)
                    abortSignal(signal, source.reason);
                else
                    source.addEventListener("abort", function () { abortSignal(signal, source.reason); });
            });
            return signal;
        };
        var AbortController = function AbortController() {
            this.signal = makeAbortSignal();
        };
        AbortController.prototype.abort = function (reason) {
            abortSignal(this.signal, reason);
        };
        define(global, "AbortSignal", AbortSignal);
        define(global, "AbortController", AbortController);

        // fetch() gives up when its signal aborts.
        if (typeof global.fetch === "function") {
            var nativeFetch = global.fetch;
            global.fetch = function fetch(input, init) {
                var signal = init && init.signal;
                if (!signal)
                    return nativeFetch.apply(this, arguments);
                if (signal.aborted)
                    return Promise.reject(signal.reason);
                var self = this, args = arguments;
                return new Promise(function (resolve, reject) {
                    signal.addEventListener("abort", function () { reject(signal.reason); });
                    nativeFetch.apply(self, args).then(resolve, reject);
                });
            };
        }
    }

    /* customElements.upgrade: elements upgrade anyway once in the document */
    if (global.customElements)
        define(customElements, "upgrade", function upgrade() {});

    /* PerformanceObserver.observe({ type }) as well as { entryTypes } */
    if (typeof global.PerformanceObserver === "function") {
        var nativeObserve = PerformanceObserver.prototype.observe;
        PerformanceObserver.prototype.observe = function observe(options) {
            if (options && options.type && !options.entryTypes) {
                var converted = {};
                for (var key in options) {
                    if (key !== "type" && key !== "buffered")
                        converted[key] = options[key];
                }
                converted.entryTypes = [options.type];
                options = converted;
            }
            try {
                return nativeObserve.call(this, options);
            } catch (e) {
                // An entry type this engine doesn't record: nothing to observe.
            }
        };
        if (!PerformanceObserver.supportedEntryTypes)
            define(PerformanceObserver, "supportedEntryTypes", ["mark", "measure", "navigation", "resource"]);
    }

    /* requestIdleCallback */
    define(global, "requestIdleCallback", function requestIdleCallback(callback, options) {
        var start = Date.now();
        return setTimeout(function () {
            callback({
                didTimeout: false,
                timeRemaining: function () { return Math.max(0, 50 - (Date.now() - start)); }
            });
        }, options && options.timeout ? Math.min(options.timeout, 1) : 1);
    });
    define(global, "cancelIdleCallback", function cancelIdleCallback(id) {
        clearTimeout(id);
    });

    /* structuredClone, for the plain data pages pass it */
    define(global, "structuredClone", function structuredClone(value) {
        function clone(item, seen) {
            if (Object(item) !== item)
                return item;
            if (seen.has(item))
                return seen.get(item);
            var result;
            if (item instanceof Date)
                result = new Date(item.getTime());
            else if (item instanceof RegExp)
                result = new RegExp(item.source, item.flags);
            else if (typeof Map === "function" && item instanceof Map) {
                result = new Map();
                seen.set(item, result);
                item.forEach(function (v, k) { result.set(clone(k, seen), clone(v, seen)); });
                return result;
            } else if (typeof Set === "function" && item instanceof Set) {
                result = new Set();
                seen.set(item, result);
                item.forEach(function (v) { result.add(clone(v, seen)); });
                return result;
            } else if (ArrayBuffer.isView && ArrayBuffer.isView(item))
                result = new item.constructor(item);
            else if (item instanceof ArrayBuffer)
                result = item.slice(0);
            else if (typeof item === "function")
                throw new DOMException("The object can not be cloned.", "DataCloneError");
            else {
                result = Array.isArray(item) ? [] : {};
                seen.set(item, result);
                Object.keys(item).forEach(function (key) { result[key] = clone(item[key], seen); });
                return result;
            }
            seen.set(item, result);
            return result;
        }
        return clone(value, new WeakMap());
    });

    /* ResizeObserver: measured on resize and after layout-changing events */
    if (typeof global.ResizeObserver !== "function") {
        var observers = [];
        var scheduled = false;
        var scheduleCheck = function () {
            if (scheduled)
                return;
            scheduled = true;
            (global.requestAnimationFrame || setTimeout)(function () {
                scheduled = false;
                observers.forEach(function (observer) { observer._check(); });
            });
        };
        var ResizeObserver = function ResizeObserver(callback) {
            this._callback = callback;
            this._targets = [];
        };
        ResizeObserver.prototype.observe = function (target) {
            for (var i = 0; i < this._targets.length; i++) {
                if (this._targets[i].target === target)
                    return;
            }
            this._targets.push({ target: target, width: -1, height: -1 });
            if (observers.indexOf(this) < 0)
                observers.push(this);
            scheduleCheck();
        };
        ResizeObserver.prototype.unobserve = function (target) {
            this._targets = this._targets.filter(function (entry) { return entry.target !== target; });
        };
        ResizeObserver.prototype.disconnect = function () {
            this._targets = [];
            var index = observers.indexOf(this);
            if (index >= 0)
                observers.splice(index, 1);
        };
        ResizeObserver.prototype._check = function () {
            var entries = [];
            this._targets.forEach(function (entry) {
                var rect = entry.target.getBoundingClientRect();
                var width = entry.target.clientWidth || rect.width;
                var height = entry.target.clientHeight || rect.height;
                if (width !== entry.width || height !== entry.height) {
                    entry.width = width;
                    entry.height = height;
                    var size = { inlineSize: width, blockSize: height };
                    entries.push({
                        target: entry.target,
                        contentRect: { x: 0, y: 0, top: 0, left: 0, width: width, height: height, right: width, bottom: height },
                        borderBoxSize: [{ inlineSize: rect.width, blockSize: rect.height }],
                        contentBoxSize: [size],
                        devicePixelContentBoxSize: [size]
                    });
                }
            });
            if (entries.length)
                this._callback(entries, this);
        };
        global.addEventListener("resize", scheduleCheck);
        global.addEventListener("load", scheduleCheck);
        document.addEventListener("DOMContentLoaded", scheduleCheck);
        document.addEventListener("transitionend", scheduleCheck, true);
        document.addEventListener("click", function () { setTimeout(scheduleCheck, 0); }, true);
        setInterval(scheduleCheck, 1500);
        define(global, "ResizeObserver", ResizeObserver);
    }

    /* IntersectionObserver: checked on scroll, resize and a slow timer */
    (function () {
        var native = global.IntersectionObserver;
        // WebKit 604 builds one that is not finished: pages would wait
        // forever for lazy images. Use it only if entries arrive.
        if (typeof native === "function" && global.IntersectionObserverEntry && "isIntersecting" in IntersectionObserverEntry.prototype)
            return;

        var observers = [];
        var scheduled = false;
        var scheduleCheck = function () {
            if (scheduled)
                return;
            scheduled = true;
            (global.requestAnimationFrame || setTimeout)(function () {
                scheduled = false;
                observers.forEach(function (observer) { observer._check(); });
            });
        };

        function parseMargin(margin) {
            var parts = String(margin || "0px").split(/\s+/).map(function (part) {
                return { value: parseFloat(part) || 0, percent: /%$/.test(part) };
            });
            while (parts.length < 4)
                parts.push(parts[parts.length === 3 ? 1 : parts.length === 2 ? 0 : 0]);
            return parts;
        }

        var IntersectionObserver = function IntersectionObserver(callback, options) {
            options = options || {};
            this._callback = callback;
            this._targets = [];
            this.root = options.root || null;
            this.rootMargin = options.rootMargin || "0px";
            this._margin = parseMargin(this.rootMargin);
            var threshold = options.threshold === undefined ? [0] : [].concat(options.threshold);
            this.thresholds = threshold.sort();
        };
        IntersectionObserver.prototype.observe = function (target) {
            for (var i = 0; i < this._targets.length; i++) {
                if (this._targets[i].target === target)
                    return;
            }
            this._targets.push({ target: target, ratio: -1 });
            if (observers.indexOf(this) < 0)
                observers.push(this);
            scheduleCheck();
        };
        IntersectionObserver.prototype.unobserve = function (target) {
            this._targets = this._targets.filter(function (entry) { return entry.target !== target; });
        };
        IntersectionObserver.prototype.disconnect = function () {
            this._targets = [];
            var index = observers.indexOf(this);
            if (index >= 0)
                observers.splice(index, 1);
        };
        IntersectionObserver.prototype.takeRecords = function () { return []; };
        IntersectionObserver.prototype._rootRect = function () {
            var rect;
            if (this.root && this.root.getBoundingClientRect) {
                var r = this.root.getBoundingClientRect();
                rect = { top: r.top, left: r.left, right: r.right, bottom: r.bottom };
            } else {
                var element = document.documentElement;
                rect = { top: 0, left: 0, right: global.innerWidth || element.clientWidth, bottom: global.innerHeight || element.clientHeight };
            }
            var width = rect.right - rect.left, height = rect.bottom - rect.top;
            var m = this._margin;
            function amount(part, size) { return part.percent ? part.value * size / 100 : part.value; }
            rect.top -= amount(m[0], height);
            rect.right += amount(m[1], width);
            rect.bottom += amount(m[2], height);
            rect.left -= amount(m[3], width);
            rect.width = rect.right - rect.left;
            rect.height = rect.bottom - rect.top;
            return rect;
        };
        IntersectionObserver.prototype._check = function () {
            var rootRect = this._rootRect();
            var entries = [];
            var thresholds = this.thresholds;
            this._targets.forEach(function (entry) {
                var target = entry.target;
                var rect = target.getBoundingClientRect();
                var connected = document.documentElement.contains(target);
                var top = Math.max(rect.top, rootRect.top), bottom = Math.min(rect.bottom, rootRect.bottom);
                var left = Math.max(rect.left, rootRect.left), right = Math.min(rect.right, rootRect.right);
                var width = right - left, height = bottom - top;
                var intersecting = connected && width >= 0 && height >= 0 && (rect.width || rect.height || rect.top || rect.left) !== 0;
                var area = rect.width * rect.height;
                var ratio = intersecting ? (area ? Math.max(0, width) * Math.max(0, height) / area : 1) : 0;
                var crossed = entry.ratio < 0;
                for (var i = 0; i < thresholds.length && !crossed; i++) {
                    var t = thresholds[i];
                    if ((entry.ratio >= t) !== (ratio >= t) || (t === 0 && (entry.ratio > 0) !== intersecting))
                        crossed = true;
                }
                if (crossed || (entry.intersecting !== intersecting)) {
                    entry.ratio = ratio;
                    entry.intersecting = intersecting;
                    entries.push({
                        target: target,
                        time: global.performance && performance.now ? performance.now() : Date.now(),
                        rootBounds: rootRect,
                        boundingClientRect: rect,
                        intersectionRect: intersecting ? { top: top, left: left, bottom: bottom, right: right, width: width, height: height, x: left, y: top } : { top: 0, left: 0, bottom: 0, right: 0, width: 0, height: 0, x: 0, y: 0 },
                        intersectionRatio: ratio,
                        isIntersecting: intersecting
                    });
                }
            });
            if (entries.length)
                this._callback(entries, this);
        };

        global.addEventListener("scroll", scheduleCheck, true);
        global.addEventListener("resize", scheduleCheck);
        global.addEventListener("load", scheduleCheck);
        document.addEventListener("DOMContentLoaded", scheduleCheck);
        setInterval(scheduleCheck, 500);
        global.IntersectionObserver = IntersectionObserver;
        global.IntersectionObserverEntry = function IntersectionObserverEntry() {};
        global.IntersectionObserverEntry.prototype.isIntersecting = false;
        global.IntersectionObserverEntry.prototype.intersectionRatio = 0;
    })();
})(typeof globalThis !== "undefined" ? globalThis : typeof window !== "undefined" ? window : this);
